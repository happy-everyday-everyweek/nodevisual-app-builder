import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/project.dart';
import '../build_artifact.dart';
import '../build_manifest.dart';
import '../build_progress.dart';
import '../build_target.dart';
import '../platform_builder.dart';

/// Android 平台构建器（v1：生成 `.nvapk` 包 + 运行时说明）。
///
/// v1 设计取舍：
/// 在 Android 设备上无法直接调用 `flutter build` 生成 APK（Flutter SDK
/// 不在端侧）。本构建器采用 **IR bundle 模型**：
/// - 将 IR + manifest + 运行时说明打包为 `.nvapk` 文件（实质为 ZIP）
/// - 该文件可被 **NodeVisual Runner**（同伴应用）打开并执行
/// - 同时生成 README 说明端侧 APK 编译的限制与 v1.1 路线
///
/// v1.1 计划（标记，未实现）：
/// - 预构建 Flutter Android 壳 APK 模板（捆绑在 builder 应用 assets 中）
/// - 注入 IR 到壳 APK 的 assets/
/// - 用端侧实现的 APK 签名器（RSA + SHA256）重签
/// - 输出可直接安装的 APK
///
/// 全程端侧完成，不依赖云服务。
class AndroidBuilder with BuilderUtils implements PlatformBuilder {
  @override
  String get target => 'android';

  @override
  Future<BuildArtifact> build({
    required Project project,
    required Directory outDir,
    required BuildManifest manifest,
    required void Function(BuildProgress progress) onProgress,
  }) async {
    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 10,
      message: '准备输出目录...',
    ));

    // 子目录：android/
    final androidDir = Directory(p.join(outDir.path, 'android'));
    if (androidDir.existsSync()) androidDir.deleteSync(recursive: true);
    androidDir.createSync(recursive: true);

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 25,
      message: '序列化 IR JSON...',
    ));
    writeIr(androidDir, project);

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 40,
      message: '写入 manifest...',
    ));
    writeManifest(androidDir, manifest);

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 55,
      message: '生成运行时说明...',
    ));
    final runnerSpecFile = File(p.join(androidDir.path, 'RUNNER_SPEC.md'));
    runnerSpecFile.writeAsStringSync(_runnerSpec(project));

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 70,
      message: '生成 README...',
    ));
    final readmeFile = File(p.join(androidDir.path, 'README.md'));
    readmeFile.writeAsStringSync(_readmeMd(project));

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 85,
      message: '打包 .nvapk...',
    ));

    final nvapkPath = artifactPath(
      outDir,
      project.meta.name,
      'android',
      BuildTarget.android.bundleExtension,
    );
    if (nvapkPath.existsSync()) nvapkPath.deleteSync();

    final archive = Archive();
    for (final entity in androidDir.listSync(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: androidDir.path);
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Android .nvapk 打包失败');
    }
    nvapkPath.writeAsBytesSync(zipBytes);

    onProgress(BuildProgress(
      phase: 'Android',
      percent: 100,
      message: 'Android 构建完成（${(zipBytes.length / 1024).toStringAsFixed(1)} KB）',
      isCompleted: true,
    ));

    androidDir.deleteSync(recursive: true);

    return BuildArtifact(
      target: BuildTarget.android,
      path: nvapkPath.path,
      displayName: '${project.meta.name}-android.nvapk',
      sizeBytes: nvapkPath.lengthSync(),
      builtAt: DateTime.now().toIso8601String(),
    );
  }

  /// 运行时规范（描述 .nvapk 包格式，供 NodeVisual Runner 读取）。
  String _runnerSpec(Project project) {
    return '''# NodeVisual Runner Spec

## 包格式
\`.nvapk\` 文件实质为 ZIP 压缩包，包含：

- \`manifest.json\` - 构建清单（项目元信息 + 构建信息 + 运行时要求）
- \`ir.json\` - 项目中间表示（IR），即运行时格式
- \`RUNNER_SPEC.md\` - 本文件（运行时规范说明）
- \`README.md\` - 用户可读说明

## 运行时要求
- **解释器版本**：v1
- **运行时模式**：interpreter（IR 即运行时格式，Dart 节点解释器执行）
- **目标平台**：Android
- **最低 API**：Android 21（5.0 Lollipop）
- **依赖**：Flutter 运行时（由 Runner 应用提供）

## Runner 应用职责
1. 解压 \`.nvapk\` 文件
2. 读取 \`manifest.json\` 校验版本兼容性
3. 加载 \`ir.json\` 到 [Project] 模型
4. 启动 Flutter 应用，使用 [NodeInterpreter] 执行函数
5. 渲染 \`ir.ui\`（Page 节点数组）为 Flutter UI
6. 处理 UI 事件 → 触发函数 → 更新绑定

## UI 结构（v1.0 重构）

\`ir.ui\` 为 \`List<UiNode>\` 的扁平数组，每个元素是一个 [UiNode]。
**Page 作为根节点**：Page 节点是一种特殊的 [UiNode]（\`type='page'\`），
其 \`id\` 即页面 id，\`children\` 为该页面的 UI 根节点树。

### UiNode 五段结构
每个 [UiNode] 含以下字段：

- \`props\`：静态属性（组件特有参数；Page 节点存 name/route/isHome/background/safeArea 等页面属性）
- \`layout\`：[LayoutConfig] 布局配置（双模布局，见下文）；null 表示沿用默认流式布局
- \`style\`：视觉样式 map（color / fontSize / padding / borderRadius / border / opacity 等，与 props 的功能参数区分）
- \`animations\`：[AnimationsConfig] 动画配置（入场 / 出场 / 触发动画）
- \`triggers\`：事件名 → 函数 id 映射（如 \`onTap\` -> \`func-uuid\`；Page 节点此处存生命周期触发）
- \`bindings\`：属性绑定（属性名 -> [Binding]，运行时按 \`#\` 引用动态解析）
- \`children\`：子节点列表（无限嵌套）

### 双模布局系统
[LayoutConfig] 支持两种模式（\`mode\` 字段）：

- **relative（9 宫格相对布局）**：使用 \`cell\`（1-9 宫格归属）+ \`distance\`（距最近边）定位。
  - cell 1/2/3 从顶部往下堆叠；7/8/9 从底部往上堆叠
  - cell 4 从左往右堆叠；6 从右往左堆叠；cell 5 中心堆叠
  - 同 cell 内按 \`distance.value\` 升序排列
- **absolute（绝对布局）**：使用 \`x\` / \`y\` 坐标定位（支持百分比 / 像素）

两种模式下 \`width\` / \`height\` 必填（[SizeSpec] 支持百分比 + minPx/maxPx 约束），
\`margin\` 为 4 方向外间距。Runner 应使用 [LayoutContainer] + [LayoutChild]
渲染（与编辑器端 RelativeLayoutRenderObject / AbsoluteLayoutRenderObject 对齐）。

### 动画系统
[AnimationsConfig] 含三类动画：

- \`entrance\`：入场动画（节点首次渲染时自动播放）
- \`exit\`：出场动画（节点被移除时播放）
- \`triggered\`：事件触发动画列表（由 UI 事件驱动，每个 [TriggeredAnimation] 绑定一个事件名到 [AnimationSpec]）

[AnimationSpec] 支持两种形式（二选一）：
- \`preset\`：预设动画（fade / slide / scale / bounce / rotate / elastic）
- \`keyframes\`：关键帧动画（time 0-1 归一化时间 + KeyframeProperties 变换状态）

含 \`duration\` / \`delay\`（毫秒）与 \`easing\`（linear / easeIn / easeOut / easeInOut / bounce / elastic）。

### Page 生命周期触发
Page 节点的 \`triggers\` 存生命周期事件 → 函数 id：
- \`onLoad\`：页面加载时触发（进入页面）
- \`onDispose\`：页面销毁时触发（离开页面）
- \`onResume\`：页面恢复时触发（从后台/下级页面返回）
- \`onPause\`：页面暂停时触发（切到后台/跳到下级页面）

Page 节点 \`id\` 用于：
- [PageLifecycleManager] 的 pageId 参数
- 函数入口 [FunctionEntry] 的 pageEvent ref \`<pageId>:<event>\`
- 页面级函数 outputs 缓存的归属（页面卸载时清空，确保跨页面不串扰）

## v1 支持的节点类型
- 变量：variable_set（读取用 `#` 引用，无 variable_get）
- 运算：arithmetic, math_func, string_op, list_op, date_op
- 逻辑：logic, compare, type_check, ternary
- 流程：if, loop, function_call, return（多返回值按 outputs 名映射）
- 数据库：db_query_one, db_query_rows, db_aggregate, db_insert, db_insert_rows, db_update, db_delete, db_create_table, db_alter_table
- UI 控制：ui_set_text, ui_set_visible, ui_set_enabled, ui_set_prop, ui_set_style, ui_set_layout, ui_set_trigger, ui_play_animation, ui_navigate, ui_show_toast
- 插件：plugin_*（按注册的插件 executor 执行）

## 函数签名
- 函数声明 inputs/outputs，`function_call` 节点按目标签名动态生成参数与返回值端口
- `return` 节点按目标函数 outputs 名映射返回多值

## 页面触发
- 函数入口 entry.kind = pageEvent，ref 形如 `<pageId>:<event>`
- 支持事件：onLoad / onDispose / onResume / onPause
- onLoad 函数的 outputs 缓存到页面作用域（[RuntimeScope.pageFuncOutputs]），供同页面 UI 组件 `#` 引用
- 页面卸载时调用 [RuntimeScope.clearPageFuncOutputs] 清空缓存，避免跨页面串扰

## 变量作用域（四源）
- 项目变量：`#projVar`，引用项目级变量
- 组件上下文变量：`#component`，引用容器组件提供的运行时上下文（列表项 item/index、滑块 value 等）
- 函数变量：`#funcVar`，含时间线规则（页面 onLoad 函数 outputs 缓存到页面作用域）
- 上游节点输出：`#upstream`，引用同函数已执行节点的命名数据输出

## 时间线与加载态
- 函数未就绪时（running/idle/error），UI 引用按加载态策略返回：
  - typeDefault（默认值）/ placeholder（占位文字）/ blank（不渲染）

## 运行时 UI 状态覆盖（RuntimeUiState）
\`ui_*\` 控制节点在函数执行期间通过 [RuntimeUiState] 修改 UI 组件运行时表现，
覆盖 [UiNode] 的各段：
- \`props\`：覆盖业务属性（text / value 等）
- \`style\`：覆盖视觉样式（color / fontSize 等）
- \`layout\`：整体替换 [LayoutConfig]
- \`triggers\`：覆盖事件 → 函数 id 映射
- \`visible\` / \`enabled\`：覆盖可见性 / 启用状态
- \`animationRequests\`：运行时动画播放请求（entrance / exit / triggered）

UI 渲染层在渲染对应组件时合并这些覆盖到基础 [UiNode] 值。

## v1 限制
- Web/Windows 端不支持 db_* 与 plugin_* 节点（降级为 no-op）
- Loop 节点在 v1 不支持子图递归执行（仅展开 list 输出 item/index）
- 函数调用深度受 MAX_STEPS=10000 限制
''';
  }

  String _readmeMd(Project project) {
    return '''# ${project.meta.name} - Android 产物

由 NodeVisual App Builder 端侧生成。

## v1 说明
本产物为 \`.nvapk\` 包（IR bundle），需配合 **NodeVisual Runner** 应用运行。

## v1.1 计划
未来版本将支持直接生成可安装的 APK：
- 预构建 Flutter Android 壳 APK 模板
- 端侧注入 IR 到壳 APK
- 端侧 RSA + SHA256 重签
- 输出独立可安装 APK

## 包内容
- \`manifest.json\` - 构建清单
- \`ir.json\` - 项目 IR
- \`RUNNER_SPEC.md\` - 运行时规范
- \`README.md\` - 本文件
''';
  }
}
