# Tasks

## 阶段 0：版本隔离与基础准备

- [ ] Task 0.1: 归档 0.x 代码到 legacy/v0 分支
  - [ ] SubTask 0.1.1: 在 main 分支创建 git tag v0-final 标记最后提交
  - [ ] SubTask 0.1.2: 创建 legacy/v0 分支并推送
  - [ ] SubTask 0.1.3: 在 main 分支将 pubspec.yaml 版本号升至 1.0.0
  - [ ] SubTask 0.1.4: 创建新空目录 lib/features/ui_editor/（清空旧 segment_view.dart 等待重写）

## 阶段 1：数据模型重构

- [ ] Task 1.1: 重构 UiNode 数据模型
  - [ ] SubTask 1.1.1: 定义 LayoutConfig 类（mode/cell/distance/x/y/width/height/margin）
  - [ ] SubTask 1.1.2: 定义 SizeSpec 类（value/unit/minPx/maxPx）
  - [ ] SubTask 1.1.3: 定义 MarginSpec 类（top/bottom/left/right，各含 value+unit）
  - [ ] SubTask 1.1.4: 定义 DistanceSpec 类（edge/value/unit）
  - [ ] SubTask 1.1.5: 定义 AnimationsConfig 类（entrance/exit/triggered[]）
  - [ ] SubTask 1.1.6: 定义 AnimationSpec 类（preset 或 keyframes、duration/delay/easing）
  - [ ] SubTask 1.1.7: 定义 Keyframe 类（time/properties/easing）
  - [ ] SubTask 1.1.8: 重构 UiNode 类，新增 layout/style/animations 字段，移除 props 中布局字段
  - [ ] SubTask 1.1.9: 实现新 UiNode 的 toJson/fromJson（向后不兼容）
- [ ] Task 1.2: 重构 Page 数据模型为特殊 UiNode
  - [ ] SubTask 1.2.1: Page 继承/组合 UiNode，type='page'
  - [ ] SubTask 1.2.2: Page 特有 props：name/route/isHome/背景/安全区/转场动画
  - [ ] SubTask 1.2.3: Page 的 layout 固定为填充屏幕（width=100%, height=100%）
  - [ ] SubTask 1.2.4: 实现 Page 的 toJson/fromJson
- [ ] Task 1.3: 重构 Project.ui 结构
  - [ ] SubTask 1.3.1: Project.ui 改为 List<Page>（Page 作为根节点）
  - [ ] SubTask 1.3.2: 所有组件必须挂载在某 Page 下（pageId 必填）
  - [ ] SubTask 1.3.3: 更新 Project 的 toJson/fromJson
- [ ] Task 1.4: 更新 IR 序列化与校验
  - [ ] SubTask 1.4.1: 更新 ir_serializer.dart 适配新结构
  - [ ] SubTask 1.4.2: 更新 ir_validator.dart 适配新结构（强制 pageId 校验等）

## 阶段 2：布局系统实现

- [ ] Task 2.1: 实现9宫格布局选择器组件
  - [ ] SubTask 2.1.1: 创建 Grid9Selector Flutter Widget（3x3小框，可点击选择）
  - [ ] SubTask 2.1.2: 9宫格视觉反馈（选中态高亮）
  - [ ] SubTask 2.1.3: 悬停/长按显示该格的堆叠方向说明
- [ ] Task 2.2: 实现相对布局渲染引擎
  - [ ] SubTask 2.2.1: 实现9宫格分组算法（按 layout.cell 分9队列）
  - [ ] SubTask 2.2.2: 实现堆叠方向排序（顶行向下、底行向上、左中向右、右中向左、中心双向）
  - [ ] SubTask 2.2.3: 实现距离最近边算法（计算组件位置距哪边最近）
  - [ ] SubTask 2.2.4: 实现相对布局的 Flutter RenderObject（堆叠+对齐+距边定位）
  - [ ] SubTask 2.2.5: 实现尺寸 clamp（% 计算 + minPx/maxPx 限制）
  - [ ] SubTask 2.2.6: 实现4方向外间距渲染
- [ ] Task 2.3: 实现绝对布局渲染引擎
  - [ ] SubTask 2.3.1: 实现绝对布局的 Flutter RenderObject（x/y 定位）
  - [ ] SubTask 2.3.2: 支持 x/y 的 PX 与百分比单位
- [ ] Task 2.4: 实现长按移动模式
  - [ ] SubTask 2.4.1: 长按手势检测，进入移动模式
  - [ ] SubTask 2.4.2: 相对布局组件的拖动排序（调整堆叠队列顺序）
  - [ ] SubTask 2.4.3: 绝对布局组件的 PPT 式自由移动（更新 x/y）
  - [ ] SubTask 2.4.4: 拖动时的可视化反馈（插入位置提示、让位动画）
- [ ] Task 2.5: 实现布局段属性面板
  - [ ] SubTask 2.5.1: 布局模式切换（相对/绝对）
  - [ ] SubTask 2.5.2: 相对布局时展示9宫格选择器
  - [ ] SubTask 2.5.3: 尺寸配置 UI（width/height + 单位 + min/max Px）
  - [ ] SubTask 2.5.4: 外间距配置 UI（4方向独立）
  - [ ] SubTask 2.5.5: 距离配置 UI（显示计算结果，可手动覆盖）

## 阶段 3：组件注册与定义

- [ ] Task 3.1: 重构组件注册系统
  - [ ] SubTask 3.1.1: 定义新 ComponentDef 接口（type/category/propsSpec/styleSpec/events）
  - [ ] SubTask 3.1.2: 定义三大分类枚举（display/interactive/container）
  - [ ] SubTask 3.1.3: 实现组件注册表（替代旧 _componentDefs）
- [ ] Task 3.2: 实现展示类组件定义
  - [ ] SubTask 3.2.1: 文本组件（单行/多行/富文本模式）
  - [ ] SubTask 3.2.2: 图片组件（本地上传/base64/URL，object-fit）
  - [ ] SubTask 3.2.3: 视频组件（进度条/控制栏/手势/自动播放等）
  - [ ] SubTask 3.2.4: 图标组件（上传/SVG代码/Material+Lucide库）
  - [ ] SubTask 3.2.5: 图表组件（基于 fl_chart，多图表类型）
- [ ] Task 3.3: 实现交互类组件定义
  - [ ] SubTask 3.3.1: 按钮（primary/secondary/outline/text/danger）+ 图标按钮 + 按钮组 + FAB
  - [ ] SubTask 3.3.2: 开关 + 单选按钮 Radio
  - [ ] SubTask 3.3.3: 下拉选择框 + 级联选择框
  - [ ] SubTask 3.3.4: 文本输入框（单行/多行/数字/密码 + 一键清空）
  - [ ] SubTask 3.3.5: 滑块（单值/范围双滑块）
  - [ ] SubTask 3.3.6: 日期选择器（精度配置）+ 日期范围选择器
  - [ ] SubTask 3.3.7: 颜色选择器
  - [ ] SubTask 3.3.8: 文件上传组件
  - [ ] SubTask 3.3.9: 富文本编辑器
  - [ ] SubTask 3.3.10: 链接 + Tabs + 分页器
- [ ] Task 3.4: 实现容器类组件定义
  - [ ] SubTask 3.4.1: 通用容器组件
  - [ ] SubTask 3.4.2: 条件渲染容器（Visible When）
  - [ ] SubTask 3.4.3: 循环渲染容器（Repeat/For-Each）
  - [ ] SubTask 3.4.4: 列表组件（横向/纵向，静态可滚动）
  - [ ] SubTask 3.4.5: 查询容器（Query Container）

## 阶段 4：UI 编辑器主界面重构

- [ ] Task 4.1: 重写 UI 编辑器主视图
  - [ ] SubTask 4.1.1: 画布区域（渲染 Page + 组件树）
  - [ ] SubTask 4.1.2: 9宫格堆叠的可视化渲染（所见即所得）
  - [ ] SubTask 4.1.3: 组件选中态、长按移动态
- [ ] Task 4.2: 实现页面管理面板
  - [ ] SubTask 4.2.1: 页面列表（新建/重命名/删除/设为首页）
  - [ ] SubTask 4.2.2: 无页面时的引导提示（"请先创建页面"）
  - [ ] SubTask 4.2.3: 组件添加入口在无页面时禁用
- [ ] Task 4.3: 实现组件面板
  - [ ] SubTask 4.3.1: 按三大类分组展示（展示/交互/容器）
  - [ ] SubTask 4.3.2: 每类可折叠
  - [ ] SubTask 4.3.3: 支持搜索过滤
- [ ] Task 4.4: 实现四段式属性面板
  - [ ] SubTask 4.4.1: 参数段（动态渲染组件特有 props）
  - [ ] SubTask 4.4.2: 布局段（复用 Task 2.5）
  - [ ] SubTask 4.4.3: 样式段（动态渲染组件特有 style + 动画配置区）
  - [ ] SubTask 4.4.4: 触发段（事件→函数绑定，沿用 0.x 机制）

## 阶段 5：动画系统实现

- [ ] Task 5.1: 实现动画数据模型与存储
  - [ ] SubTask 5.1.1: AnimationsConfig 的持久化（toJson/fromJson）
  - [ ] SubTask 5.1.2: 预设动画库定义（fade/slide/scale/bounce/rotate/elastic）
- [ ] Task 5.2: 实现预设动画编辑器
  - [ ] SubTask 5.2.1: 预设选择 UI
  - [ ] SubTask 5.2.2: 参数调整 UI（duration/delay/easing/初始值/最终值）
- [ ] Task 5.3: 实现关键帧动画编辑器
  - [ ] SubTask 5.3.1: 时间轴 UI（横向时间轴 + 关键帧标记）
  - [ ] SubTask 5.3.2: 关键帧添加/删除/编辑
  - [ ] SubTask 5.3.3: 关键帧属性编辑（x/y/opacity/scale/rotation）
  - [ ] SubTask 5.3.4: 缓动曲线配置
  - [ ] SubTask 5.3.5: 预览播放
- [ ] Task 5.4: 实现动画运行时执行
  - [ ] SubTask 5.4.1: 入场动画触发（组件首次出现）
  - [ ] SubTask 5.4.2: 出场动画触发（组件消失）
  - [ ] SubTask 5.4.3: 触发动画执行（事件→动画）

## 阶段 6：状态管理重构

- [ ] Task 6.1: 重构 UiMutator
  - [ ] SubTask 6.1.1: 新增布局变更方法（updateLayout/setCell/setDistance/setSize/setMargin）
  - [ ] SubTask 6.1.2: 新增样式变更方法（updateStyle）
  - [ ] SubTask 6.1.3: 新增动画变更方法（setEntrance/setExit/addTriggeredAnimation等）
  - [ ] SubTask 6.1.4: 强制 pageId 校验（addComponent 必须传 pageId）
- [ ] Task 6.2: 适配 `#` 引用与触发模型
  - [ ] SubTask 6.2.1: 复用 0.x 的 setBinding 机制
  - [ ] SubTask 6.2.2: 复用 0.x 的 setTrigger 机制
  - [ ] SubTask 6.2.3: 复用 0.x 的 setPageEventFunction 机制

## 阶段 7：运行时与编译适配

- [ ] Task 7.1: 适配运行时渲染
  - [ ] SubTask 7.1.1: RuntimeUiState 适配新 UiNode 结构
  - [ ] SubTask 7.1.2: runtime_scope.dart 适配 Page 作为根节点
  - [ ] SubTask 7.1.3: 实现9宫格堆叠的运行时渲染
  - [ ] SubTask 7.1.4: 实现绝对布局的运行时渲染
- [ ] Task 7.2: 适配编译产物
  - [ ] SubTask 7.2.1: web_runtime_template.dart 生成新布局运行时代码
  - [ ] SubTask 7.2.2: android_builder.dart 适配新结构
  - [ ] SubTask 7.2.3: windows_builder.dart 适配新结构

## 阶段 8：测试与验证

- [ ] Task 8.1: 单元测试
  - [ ] SubTask 8.1.1: 数据模型序列化/反序列化测试
  - [ ] SubTask 8.1.2: 9宫格堆叠算法测试（各宫格方向、中心双向）
  - [ ] SubTask 8.1.3: 距离最近边算法测试
  - [ ] SubTask 8.1.4: 尺寸 clamp 测试（% + minPx/maxPx）
- [ ] Task 8.2: 集成测试
  - [ ] SubTask 8.2.1: 页面-组件强绑定场景测试（无页面时禁止添加）
  - [ ] SubTask 8.2.2: 相对布局完整流程测试（选格→堆叠→拖动→距边记录）
  - [ ] SubTask 8.2.3: 绝对布局完整流程测试（自由移动→x/y更新）
  - [ ] SubTask 8.2.4: 长按移动模式测试（相对→排序；绝对→自由移动）
  - [ ] SubTask 8.2.5: 动画系统测试（入场/出场/触发）
- [ ] Task 8.3: E2E 测试
  - [ ] SubTask 8.3.1: 完整搭建一个含多页面、多组件的 UI 项目
  - [ ] SubSub 8.3.2: 编译为 Web 产物并验证渲染

# Task Dependencies

- [Task 1.*]（数据模型）是所有后续任务的基础，最先完成
- [Task 2.*]（布局系统）依赖 Task 1
- [Task 3.*]（组件定义）依赖 Task 1
- [Task 4.*]（编辑器主界面）依赖 Task 2 + Task 3
- [Task 5.*]（动画系统）依赖 Task 1，可与 Task 2/3 并行
- [Task 6.*]（状态管理）依赖 Task 1，可与 Task 2/3 并行
- [Task 7.*]（运行时编译）依赖 Task 1 + Task 2
- [Task 8.*]（测试）依赖所有前置任务
- 可并行：Task 2 与 Task 3；Task 5 与 Task 2/3；Task 6 与 Task 2/3
