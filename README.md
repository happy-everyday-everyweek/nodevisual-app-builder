# NodeVisual App Builder

跨端可视化节点编程工具——通过连接节点形成函数，可视化 UI 编辑器，一键编译打包为 Web / Android / Windows 多端应用。

## 功能

- **节点图编辑器**：两步点击式连线（先点起始节点，再点终止节点），控制流连线仅表达执行顺序与分支，与参数传递无关
- **双平面模型**：控制平面（画布连线）与数据平面（节点编辑页 `#` 引用）解耦——连线只管执行顺序，参数通过 `#` 引用独立完成
- **子母节点设计**：多输出母节点（if / loop 等）的每个输出端口自动对应一个 `branch` 子节点，连线起点必须点击子节点
- **变量系统**：`#` 引用统一表达五源——设备变量 / 组件变量 / 项目变量 / 函数变量 / 上游节点输出
- **可视化 UI 编辑器**：拖拽组件生成界面，属性绑定到函数输出
- **多端编译打包**：端侧完成，输出 Web（HTML/JS）、Android（.nvapk）、Windows（.nvexe）
- **插件系统**：内置 OpenAI / Anthropic LLM 插件，支持从插件市场安装 HTTP 插件
- **插件市场**：浏览、搜索、安装社区插件（[插件市场仓库](https://github.com/happy-everyday-everyweek/nodevisual-plugin-marketplace)）

## 平台可用性

### 节点（函数编辑器）

节点面板会在仅特定端可用的节点上显示平台标签（如 `Android` / `Android / Windows`），全平台可用节点无标签。

| 节点 | 可用平台 | 说明 |
|------|---------|------|
| `plugin_openai` / `plugin_anthropic` | 全平台 | LLM 走 HTTP API |
| `plugin_clipboard` | 全平台 | Flutter Clipboard 跨端可用 |
| `plugin_haptic` | Android | `HapticFeedback` 仅移动端有效，Web/Windows 上为空操作 |
| `plugin_share` | Android / Windows | `share_plus` 在桌面/移动端调用系统分享面板；Web 端兼容性差 |
| 其他节点 | 全平台 | 数据库 / 运算 / 逻辑 / 流程 / UI 控制等 |

### UI 组件

UI 编辑器中所有内置组件（布局 / 展示 / 媒体 / 输入 / 容器 / 指示器）均基于 Flutter 跨端能力实现，在 Web / Android / Windows 上行为一致，无平台限制。


## 架构

```
lib/
├── core/                 # 主题、常量
├── data/
│   ├── models/           # 数据模型（Project, Node, Port, ...）
│   ├── ir/               # IR 序列化与校验
│   ├── local/            # 本地存储
│   └── repositories/      # 仓储层
├── features/
│   ├── node_graph/        # 节点图编辑器（控制平面）
│   ├── variables/         # 变量引用系统（数据平面）
│   ├── database/          # 数据库段
│   ├── ui_editor/         # UI 可视化编辑器
│   ├── plugins/           # 插件系统（LLM + HTTP 插件）
│   ├── marketplace/       # 插件市场（浏览/安装）
│   ├── compiler/          # 节点解释器（IR 即运行时）
│   ├── build_pipeline/    # 端侧编译管线
│   ├── functions/         # 函数组织（命名/标签/文件夹）
│   ├── project/           # 项目管理
│   └── ...
└── presentation/
    ├── screens/           # 屏幕（主页/编辑器/编译/市场）
    └── widgets/           # 通用组件
```

## 技术栈

- **Flutter** / **Dart**（跨端：Web / Android / Windows）
- **Riverpod** 状态管理
- **GoRouter** 声明式路由
- **SQLite** 本地数据库
- **flutter_secure_storage** 敏感配置存储

## 构建

```bash
flutter pub get
flutter run
```

## 许可证

MIT
