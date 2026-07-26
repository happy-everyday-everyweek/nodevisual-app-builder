# 架构说明

本文档补充 [README](../README.md) 中未展开的实现细节，适合希望深入理解或贡献代码的开发者阅读。

## 目录结构

```
lib/
├── core/                 # 主题、常量、导航过渡
├── data/
│   ├── models/           # 数据模型（Project, Node, Port, ...）
│   ├── ir/               # IR 序列化与校验
│   ├── local/            # 本地存储
│   └── repositories/     # 仓储层
├── features/
│   ├── node_graph/       # 节点图编辑器（控制平面）
│   ├── variables/        # 变量引用系统（数据平面）
│   ├── database/         # 数据库段
│   ├── ui_editor/        # UI 可视化编辑器
│   ├── plugins/          # 插件系统（LLM + HTTP 插件）
│   ├── marketplace/      # 插件市场（浏览/安装）
│   ├── compiler/         # 节点解释器（IR 即运行时）
│   ├── build_pipeline/   # 端侧编译管线
│   ├── functions/        # 函数组织（命名/标签/文件夹）
│   ├── project/          # 项目管理
│   └── ...
└── presentation/
    ├── screens/          # 屏幕（主页/编辑器/编译/市场）
    └── widgets/          # 通用组件
```

## 控制平面与数据平面

- **控制平面**：画布上的连线只表达执行顺序与分支，不传递参数。
- **数据平面**：节点内部通过 `#` 引用表达式获取数据，来源包括设备变量、组件变量、项目变量、函数变量和上游节点输出。

## 子母节点设计

多输出母节点（如 `if`、`loop`）的每个输出端口会自动生成一个 `branch` 子节点；连线起点必须点击子节点，从而保证控制流语义清晰。

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

## 技术栈

- **Flutter** / **Dart**（跨端：Web / Android / Windows）
- **Riverpod** 状态管理
- **GoRouter** 声明式路由
- **SQLite** 本地数据库
- **flutter_secure_storage** 敏感配置存储
