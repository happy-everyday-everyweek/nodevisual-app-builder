# NodeVisual App Builder

跨端可视化节点编程工具——通过连接节点形成函数，可视化 UI 编辑器，一键编译打包为 Web / Android / Windows 多端应用。

## 功能

- **节点图编辑器**：拖拽连接节点，控制流连线表达执行顺序与分支
- **双平面模型**：控制平面（画布连线）与数据平面（节点编辑页 `#` 引用）分离
- **可视化 UI 编辑器**：拖拽组件生成界面，属性绑定到函数输出
- **多端编译打包**：端侧完成，输出 Web（HTML/JS）、Android（.nvapk）、Windows（.nvexe）
- **插件系统**：内置 OpenAI / Anthropic LLM 插件，支持从插件市场安装 HTTP 插件
- **插件市场**：浏览、搜索、安装社区插件（[插件市场仓库](https://github.com/happy-everyday-everyweek/nodevisual-plugin-marketplace)）

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
