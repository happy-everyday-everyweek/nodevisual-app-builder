# Tasks

- [x] Task 1: 搭建 Flutter 项目脚手架与基础架构
  - [x] SubTask 1.1: 初始化 Flutter 项目（Android 优先配置）
  - [x] SubTask 1.2: 引入状态管理（Riverpod）、路由、本地存储（SQLite + 文件系统）依赖
  - [x] SubTask 1.3: 建立项目目录结构（features/core/data/presentation 分层）
  - [x] SubTask 1.4: 定义核心数据模型（Project / Function / Database / UI Artifact）

- [ ] Task 2: 实现项目三段式结构与悬浮胶囊 Top 栏
  - [ ] SubTask 2.1: 实现项目创建、打开、保存（本地持久化）
  - [ ] SubTask 2.2: 实现悬浮胶囊状 Top 栏组件（函数 / 数据库 / UI 三段切换）
  - [ ] SubTask 2.3: 三段编辑器状态独立保留，切换不丢失

- [ ] Task 3: 实现函数组织能力
  - [ ] SubTask 3.1: 函数命名、重命名
  - [ ] SubTask 3.2: 函数标签（多标签增删）
  - [ ] SubTask 3.3: 文件夹/子文件夹无限嵌套树结构
  - [ ] SubTask 3.4: 函数侧边栏（按文件夹树、标签、名称检索）

- [ ] Task 4: 实现节点图编辑器核心（控制平面）
  - [ ] SubTask 4.1: 可缩放/平移画布（捏合缩放 + 双指平移，触屏适配）
  - [ ] SubTask 4.2: 节点渲染（自定义 RenderObject / Canvas）
  - [ ] SubTask 4.3: 节点拖拽放置、长按选中
  - [ ] SubTask 4.4: 控制流连线交互（拖拽连线，仅承载执行顺序与分支，无类型校验）
  - [ ] SubTask 4.5: 节点 DAG 校验（防止环、确保可执行）
  - [ ] SubTask 4.6: 节点动态命名输出声明（控制流输出 + 数据输出，按节点配置生成）

- [ ] Task 5: 实现基础节点（变量 / 运算 / 流程控制）
  - [ ] SubTask 5.1: 变量节点（设置变量、读取变量）
  - [ ] SubTask 5.2: 运算节点（算术、逻辑、字符串）
  - [ ] SubTask 5.3: 流程控制节点（If 可配置任意数量 case、Loop body/completed 等命名输出）
  - [ ] SubTask 5.4: 节点编辑页（点击节点进入，配置参数与 `#` 引用）

- [ ] Task 5.5: 实现节点输出值类型系统（数据输出层）
  - [ ] SubTask 5.5.1: 命名数据输出声明原始类型（number/string/bool/any，List/Map 无参容器）
  - [ ] SubTask 5.5.2: `#` 引用类型与目标参数不匹配时在节点编辑页内提示

- [ ] Task 6: 实现数据库节点
  - [ ] SubTask 6.1: 数据库段（Database）编辑器：表结构定义
  - [ ] SubTask 6.2: 数据库节点（增、删、改、查）
  - [ ] SubTask 6.3: 表结构操作节点（建表、改表）

- [ ] Task 7: 实现变量引用系统（数据平面）
  - [ ] SubTask 7.1: 定义变量来源（控制流上游节点输出 = 沿控制连线反向传递闭包 / 函数变量 / 项目变量）与作用域解析；循环体内变量仅循环内可见
  - [ ] SubTask 7.2: 节点编辑页参数输入框中 `#` 触发变量选择卡片（底部 Sheet / 悬浮卡，移动端友好）
  - [ ] SubTask 7.3: 卡片按来源分组、显示类型提示、搜索过滤、两段式选择（节点→输出名）或 `#名称` 直接命中
  - [ ] SubTask 7.4: `#变量名` 输入式快速引用；跨来源冲突时列候选并标注来源

- [ ] Task 8: 实现可视化 UI 编辑器与函数触发绑定
  - [ ] SubTask 8.1: UI 组件面板 + 画布
  - [ ] SubTask 8.2: 拖拽放置组件、调整位置/尺寸/属性
  - [ ] SubTask 8.3: 组件属性 `#` 绑定到函数命名输出或项目变量
  - [ ] SubTask 8.4: 组件触发点面板（点击组件显示其支持的触发点：点击/加载/卸载/列表项滚动到此处等）
  - [ ] SubTask 8.5: 触发点 → 函数绑定；定时器/外部事件/函数调用节点作为函数 entry

- [ ] Task 9: 实现插件系统框架
  - [ ] SubTask 9.1: 插件节点抽象（输入/输出/配置声明）
  - [ ] SubTask 9.2: 插件加载与注册机制
  - [ ] SubTask 9.3: 插件配置面板（如 API Key 输入与本地安全存储）

- [ ] Task 10: 实现 LLM 内置插件
  - [ ] SubTask 10.1: OpenAI SDK 封装节点（对话补全、流式）
  - [ ] SubTask 10.2: Anthropic SDK 封装节点（消息、流式）
  - [ ] SubTask 10.3: 模型 / 参数 / API Key 配置

- [ ] Task 11: 设计中间表示（IR）与代码生成器
  - [ ] SubTask 11.1: 定义项目 IR（JSON schema：函数 DAG + DB schema + UI tree + 变量）
  - [ ] SubTask 11.2: IR → Flutter/Dart 源码生成器
  - [ ] SubTask 11.3: IR 校验（类型、引用完整性）

- [ ] Task 12: 实现端侧编译管线
  - [ ] SubTask 12.1: 嵌入式构建工具链集成（Flutter build 能力端侧化）
  - [ ] SubTask 12.2: 一键编译 Web 产物（HTML/JS 静态包）
  - [ ] SubTask 12.3: 一键编译 Android 产物（APK）
  - [ ] SubTask 12.4: 一键编译 Windows 产物（可执行 / 可运行目录，可作为后续里程碑）
  - [ ] SubTask 12.5: 产物本地导出与分享

- [ ] Task 13: Android 平台兼容性与触屏体验优化
  - [ ] SubTask 13.1: 多 Android 屏幕尺寸/方向适配
  - [ ] SubTask 13.2: 触屏交互打磨（节点拖拽、画布手势、卡片选择）
  - [ ] SubTask 13.3: Android 端功能与性能验证

# Task Dependencies
- Task 2 依赖 Task 1（项目模型与脚手架）
- Task 3 依赖 Task 2（函数段已可切换）
- Task 4 依赖 Task 2（编辑器宿主）
- Task 5 依赖 Task 4（节点图核心）
- Task 6 依赖 Task 4、Task 2（节点核心 + 数据库段）
- Task 7 依赖 Task 5（需基础节点输出可供引用）
- Task 8 依赖 Task 2（UI 段已可切换）
- Task 9 依赖 Task 4（插件作为节点类型）
- Task 10 依赖 Task 9
- Task 11 依赖 Task 4–10（IR 需覆盖所有节点与段）
- Task 12 依赖 Task 11（需 IR 与代码生成）
- Task 13 贯穿全程，最后集中验证
