# UI 编辑器 1.0 重构 Spec

## Why

当前 UI 编辑器（0.x）存在根本性架构问题：组件分类混乱（布局/展示/媒体/输入/容器/指示器六类冗余）、布局系统基于 Flex（Column/Row）无法满足精细定位需求、Page 与组件松耦合（组件可脱离页面存在）、属性面板组织零散（属性+绑定+触发三段无布局/样式/动画维度）。

本次为**破坏性重构**，版本号升至 1.0.0，旧 0.x 代码归档到 `legacy/v0` 分支，新代码从零开始。核心目标：建立**页面-组件强绑定**的树模型、**相对布局（9宫格堆叠）+ 绝对布局（PPT式自由移动）**的双模布局系统、**参数/布局/样式/触发**的四段式属性面板，并按**展示/交互/容器**三大类重新设计组件集。

## What Changes

- **BREAKING**：废弃 0.x 全部组件类型（column/row/scaffold/list_view/badge/divider/spacer/progress/rich_text/conditional_container/text/button/text_field/image/video/icon/slider/switch/checkbox/list_vertical/list_horizontal/tab_container/card 等），从零重建组件集
- **BREAKING**：废弃 0.x 的 Flex 布局模型（Column/Row 的 mainAxisAlignment/crossAxisAlignment）
- **BREAKING**：废弃 0.x 的"组件可独立于页面存在"模型，改为**页面-组件强绑定**（不创建页面无法添加组件）
- **BREAKING**：旧项目格式不兼容，仅能在 legacy/v0 版本打开
- **新增**：Page 作为特殊组件类型（type='page'），是 UI 树的最父组件，有自己的参数/布局/样式/触发
- **新增**：双模布局系统——相对布局（9宫格堆叠 + 距最近边距离记录）+ 绝对布局（PPT式自由移动 + x/y坐标）
- **新增**：组件级布局选择（每个组件独立选择相对/绝对布局）
- **新增**：四段式属性面板（参数 / 布局 / 样式 / 触发）
- **新增**：9宫格可视化选择器（相对布局的UX交互方式，3x3小框选择堆叠队列）
- **新增**：长按进入移动模式（相对布局→调整堆叠顺序；绝对布局→自由移动）
- **新增**：动画系统（入场动画/出场动画/触发动画，预设 + 关键帧自定义）
- **新增**：三大类组件集——展示类、交互类、容器类
- **新增**：尺寸规范（%或PX，%可设min/max PX）+ 4方向外间距独立控制
- **保留**：`#` 变量引用四源模型（projVar/funcVar/component/upstream）
- **保留**：加载态占位机制（typeDefault/placeholder/blank）
- **保留**：函数触发模型（uiEvent/pageEvent entry）
- **保留**：组件上下文变量（item/index/value 等）
- **保留**：Riverpod 状态管理、IR 序列化框架、插件系统协议

## Impact

- **数据模型**：`UiNode` 重构（增 layout/style/animations 字段，移除 0.x 的 props 中布局相关字段）；`Page` 升级为特殊 UiNode 类型；`Project.ui` 结构调整（页面作为根，组件树挂载在页面下）
- **UI 编辑器**：`segment_view.dart` 完全重写（约3000行代码废弃）；新建四段式属性面板、9宫格选择器、长按移动交互、动画编辑器
- **状态管理**：`ui_editor_providers.dart` 重构（布局/样式/动画的变更方法）
- **组件注册**：`component_registry.dart` 重构（新组件定义、新分类）
- **运行时**：`RuntimeUiState` / `runtime_scope.dart` 需适配新布局模型（9宫格堆叠渲染、绝对定位渲染）
- **编译**：`web_runtime_template.dart` 等需生成新布局的运行时代码
- **序列化**：`ir_serializer.dart` / `ir_validator.dart` 需适配新 IR 结构
- **关联**：依赖 `extend-node-system-and-ui` spec 的 `#` 引用、组件上下文变量、触发事件等机制（这些保留）

---

## ADDED Requirements

### Requirement: 页面-组件强绑定

系统 SHALL 强制页面与组件的绑定关系：**不创建页面无法添加组件**。Page 是 UI 树的唯一根，所有组件必须挂载在某个 Page 下。

#### Scenario: 无页面时禁止添加组件
- **WHEN** 项目中尚无任何 Page
- **THEN** 组件添加入口（FAB / 组件面板）禁用或提示"请先创建页面"
- **AND** 不允许通过任何途径（API、拖拽、粘贴）创建游离组件

#### Scenario: Page 作为最父组件
- **WHEN** 用户创建一个 Page
- **THEN** 该 Page 在 UI 树中作为根节点存在，type='page'
- **AND** Page 有自己的参数（背景、安全区等）、布局（页面级布局配置）、样式、触发（页面生命周期事件）
- **AND** Page 不可被删除（除非是项目唯一页面）、不可被移动、不可嵌套
- **AND** 所有其他组件必须以某 Page 为祖先

#### Scenario: Page 的生命周期与路由
- **WHEN** 项目包含多个 Page
- **THEN** 其中一个 Page 标记为首页（isHome），应用启动时进入
- **AND** 每个 Page 有路由路径（route），用于编译产物的路由表
- **AND** Page 间通过导航（ui_navigate 节点）跳转

### Requirement: Page 作为特殊组件类型

系统 SHALL 将 Page 实现为一种特殊的 UiNode（type='page'），它具备普通组件的四段配置（参数/布局/样式/触发），但有特殊约束。

#### Scenario: Page 的参数段
- **WHEN** 用户编辑 Page 的参数
- **THEN** 可配置：页面名（name）、路由路径（route）、是否首页（isHome）、背景色、是否启用安全区（top/bottom）、页面进入/退出转场动画

#### Scenario: Page 的布局段
- **WHEN** 用户编辑 Page 的布局段
- **THEN** Page 自身布局固定为"填充屏幕"（width=100%, height=100%）
- **AND** Page 的子组件按 9宫格堆叠 + 绝对布局组织（Page 作为父组件提供布局容器）

#### Scenario: Page 的样式段
- **WHEN** 用户编辑 Page 的样式段
- **THEN** 可配置页面级样式（背景、主题色覆盖等）+ 页面转场动画

#### Scenario: Page 的触发段
- **WHEN** 用户编辑 Page 的触发段
- **THEN** 可绑定页面生命周期事件：onLoad / onDispose / onResume / onPause
- **AND** 每个事件可绑定一个函数（沿用 0.x 的 pageEvent entry 机制）

### Requirement: 四段式属性面板

系统 SHALL 为每个组件（含 Page）提供四段式属性面板：**参数 / 布局 / 样式 / 触发**，按固定顺序组织。

#### Scenario: 参数段
- **WHEN** 用户打开某组件的属性面板
- **THEN** 第一段为"参数"，展示该组件特有的配置项（如文本的 content、图片的 src、按钮的 label）
- **AND** 参数支持 `#` 变量引用绑定（沿用 0.x 机制）
- **AND** 参数项由各组件自定义声明

#### Scenario: 布局段
- **WHEN** 用户查看属性面板的"布局"段
- **THEN** 展示布局模式选择（相对布局 / 绝对布局）
- **AND** 选择相对布局时，展示9宫格可视化选择器（3x3小框）+ 尺寸配置 + 外间距配置
- **AND** 选择绝对布局时，展示 x/y 坐标配置 + 尺寸配置 + 外间距配置
- **AND** Page 组件的布局段只读（固定填充屏幕）

#### Scenario: 样式段
- **WHEN** 用户查看属性面板的"样式"段
- **THEN** 展示该组件特有的样式项（颜色、字体、边框、圆角等，由组件自定义）
- **AND** **必须**包含动画配置区（入场动画 / 出场动画 / 触发动画）
- **AND** 动画可选择预设或自定义关键帧

#### Scenario: 触发段
- **WHEN** 用户查看属性面板的"触发"段
- **THEN** 展示该组件支持的所有事件（如 onTap / onChanged / onLoad 等）
- **AND** 每个事件可绑定一个函数（沿用 0.x 的 uiEvent entry 机制）
- **AND** Page 组件展示页面生命周期事件

### Requirement: 双模布局系统

系统 SHALL 提供两种布局模式：**相对布局**与**绝对布局**，由每个组件独立选择。布局是组件级别的属性。

#### Scenario: 组件级布局选择
- **WHEN** 用户在布局段选择某组件的布局模式
- **THEN** 该组件独立采用所选布局模式（相对或绝对）
- **AND** 同一父组件下的不同子组件可采用不同布局模式
- **AND** 切换布局模式时，系统尽量保留位置信息（如相对→绝对时，按当前渲染位置计算 x/y）

### Requirement: 相对布局（9宫格堆叠）

系统 SHALL 提供基于9宫格堆叠的相对布局模式。每个父组件（Page 或容器类组件）的子组件按9宫格归属组织成9个堆叠队列。

**9宫格选择器UX**：布局段展示一个3x3小框，用户点击某格表示将该组件分配到对应的堆叠队列。

**9宫格堆叠方向与对齐**：

| 宫格位置 | 堆叠方向 | 水平对齐 | 垂直起点 |
|---------|---------|---------|---------|
| 左上(row1,col1) | 从上往下 | 靠左 | 从上开始 |
| 上中(row1,col2) | 从上往下 | 居中 | 从上开始 |
| 右上(row1,col3) | 从上往下 | 靠右 | 从上开始 |
| 左中(row2,col1) | 从左往右 | 从左开始 | 上下居中 |
| 中心(row2,col2) | 往上或往下（取决于用户放置位置） | 居中 | 从中心开始 |
| 右中(row2,col3) | 从右往左 | 从右开始 | 上下居中 |
| 左下(row3,col1) | 从下往上 | 靠左 | 从下开始 |
| 下中(row3,col2) | 从下往上 | 居中 | 从下开始 |
| 右下(row3,col3) | 从下往上 | 靠右 | 从下开始 |

#### Scenario: 选择9宫格
- **WHEN** 用户在布局段点击9宫格选择器的某格（如左上）
- **THEN** 该组件被分配到对应堆叠队列
- **AND** 后续加入同格的组件按堆叠方向追加（如左上格：从上往下追加）
- **AND** 渲染时组件按堆叠方向与对齐方式排列

#### Scenario: 中心格的双向堆叠
- **WHEN** 用户选择中心格(row2,col2)
- **AND** 拖动放置组件到中心上方
- **THEN** 该组件从中心往上堆叠
- **WHEN** 用户拖动放置组件到中心下方
- **THEN** 该组件从中心往下堆叠
- **AND** 系统根据用户放置位置（中心上方/下方）决定堆叠方向

#### Scenario: 距离记录（距最近边）
- **WHEN** 组件处于相对布局模式
- **THEN** 系统记录该组件距离"最近边"的 PX 或百分比（默认百分比）
- **AND** "最近边"由算法判定：组件在画布中的位置距离父组件哪一边最近，即记录距那一边的距离
- **AND** 用户可类似编辑 PPT 一样拖动组件到任意位置，拖动后系统重新计算最近边并更新距离记录
- **AND** 距离单位可在 PX 与百分比间切换（默认百分比）

#### Scenario: 距离记录示例
- **WHEN** 用户将一个文本组件拖动到画布上方
- **AND** 经计算该位置距父组件上边框最近，距离为父组件高度的 1%
- **THEN** 系统记录该组件"距上边 1%"
- **AND** 渲染时该组件定位在距上边 1% 处

### Requirement: 相对布局的尺寸与外间距

系统 SHALL 要求相对布局的组件必须指定长和宽，并支持4方向外间距独立控制。

#### Scenario: 尺寸配置
- **WHEN** 组件处于相对布局模式
- **THEN** 必须配置 width 和 height
- **AND** 单位可选百分比（%）或 PX
- **AND** 当单位为百分比时，可设置最小 PX（minPx）和最大 PX（maxPx）作为上下限
- **AND** 渲染时按百分比计算实际尺寸，但 clamp 到 [minPx, maxPx] 范围

#### Scenario: 外间距配置
- **WHEN** 用户配置组件的外间距（margin）
- **THEN** 4个方向（上/下/左/右）可分别独立配置
- **AND** 每个方向的单位可选 PX 或百分比
- **AND** 默认值为 0

### Requirement: 绝对布局（PPT式自由移动）

系统 SHALL 提供基于 x/y 坐标的绝对布局模式，支持 PPT 式自由移动。

#### Scenario: 绝对布局配置
- **WHEN** 组件选择绝对布局模式
- **THEN** 系统记录该组件的 x、y 坐标（相对于父组件左上角）
- **AND** 坐标单位可选 PX 或百分比（默认百分比）
- **AND** 组件尺寸配置同相对布局（width/height + 单位 + min/max Px）

#### Scenario: PPT式自由移动
- **WHEN** 用户拖动绝对布局的组件
- **THEN** 组件跟随手指/指针自由移动（类似编辑 PPT）
- **AND** 移动后系统更新组件的 x/y 坐标
- **AND** 不进行最近边吸附（与相对布局的区别）

### Requirement: 长按进入移动模式

系统 SHALL 通过长按手势让组件进入移动模式，移动模式的行为取决于组件自身的布局方式。

#### Scenario: 相对布局组件的长按移动
- **WHEN** 用户长按一个相对布局的组件
- **THEN** 组件进入移动模式
- **AND** 用户可拖动该组件调整其在堆叠队列中的顺序
- **AND** 拖动时可视化提示插入位置（如其他组件让位动画）
- **AND** 松手后组件停留在新的顺序位置

#### Scenario: 绝对布局组件的长按移动
- **WHEN** 用户长按一个绝对布局的组件
- **THEN** 组件进入移动模式
- **AND** 用户可像编辑 PPT 一样自由移动该组件
- **AND** 松手后组件停留在拖动到达的 x/y 坐标

### Requirement: 概念模型与实现分离

系统 SHALL 在概念上理解"每个父组件有10层（9相对层+1绝对层）"，但在实现时**不**使用10个独立列表存储，而采用字段标记方式。

#### Scenario: 实现方式
- **WHEN** 系统存储父组件的子组件列表
- **THEN** 子组件存储为单一列表（children）
- **AND** 每个子组件的 layout 配置中包含 mode（relative/absolute）和 cell（9宫格之一，仅相对布局）
- **AND** 渲染时按 mode + cell 分组并按堆叠方向排序
- **AND** 不在数据模型中创建10个独立的层列表

### Requirement: 动画系统

系统 SHALL 为每个组件提供动画配置能力，包含入场动画、出场动画、触发动画三类。动画支持预设与关键帧自定义两种编辑方式。

#### Scenario: 入场动画
- **WHEN** 组件首次出现在屏幕上（页面加载、条件渲染显示、列表项渲染等）
- **THEN** 播放配置的入场动画
- **AND** 可选择预设（淡入 fade、滑入 slide、缩放 scale、弹跳 bounce、旋转 rotate、弹性 elastic 等）
- **AND** 可调整时长（duration）、延迟（delay）、缓动曲线（easing）

#### Scenario: 出场动画
- **WHEN** 组件从屏幕上消失（页面卸载、条件渲染隐藏、列表项移除等）
- **THEN** 播放配置的出场动画
- **AND** 可选择预设与调整参数（同入场动画）

#### Scenario: 触发动画
- **WHEN** 用户为组件配置触发动画
- **THEN** 可绑定到某个事件（如 onTap、onChanged、自定义条件）
- **AND** 事件触发时播放配置的动画
- **AND** 一个组件可配置多个触发动画（不同事件触发不同动画）

#### Scenario: 预设动画
- **WHEN** 用户选择预设动画
- **THEN** 从预设库选择（fade / slide / scale / bounce / rotate / elastic 等）
- **AND** 可调参数：时长、延迟、缓动曲线、初始/最终值（如 slide 的方向与距离）

#### Scenario: 关键帧自定义动画
- **WHEN** 用户选择关键帧自定义
- **THEN** 提供时间轴编辑器
- **AND** 可在时间轴上添加关键帧
- **AND** 每个关键帧可设置属性值：位置(x/y)、透明度(opacity)、缩放(scale)、旋转(rotation)
- **AND** 关键帧间支持缓动曲线配置
- **AND** 时间轴支持预览播放

### Requirement: 展示类组件

系统 SHALL 提供以下展示类组件，每个组件有自定义参数/样式，但都必须支持动画配置。

#### Scenario: 文本组件
- **WHEN** 用户添加文本组件
- **THEN** 支持三种模式：单行文本（single line）、多行文本（multi line）、富文本（rich text）
- **AND** 参数：内容（content，支持 `#` 引用）、模式选择
- **AND** 样式：字体、字号、颜色、粗细、对齐、行高、字间距等

#### Scenario: 图片组件
- **WHEN** 用户添加图片组件
- **THEN** 支持三种图片来源：本地上传（封装到应用中）、Base64、URL
- **AND** 参数：图片来源（src，支持 `#` 引用）
- **AND** 样式：object-fit 属性切换（cover / contain / fill / none）、圆角、边框等
- **AND** 本地上传的图片资源随项目保存

#### Scenario: 视频组件
- **WHEN** 用户添加视频组件
- **THEN** 支持三种视频来源：本地上传、Base64、URL
- **AND** 参数：视频来源（src，支持 `#` 引用）
- **AND** 样式：丰富的播放选项——是否展示进度条、是否展示控制栏、是否支持手势（如双击全屏、滑动调整音量/进度）、自动播放、循环播放、静音等
- **AND** object-fit 属性切换（cover / contain / fill / none）

#### Scenario: 图标组件
- **WHEN** 用户添加图标组件
- **THEN** 支持三种图标来源：用户上传、粘贴 SVG 代码、从内置图标库选择
- **AND** 内置图标库包含两套：Material Icons + Lucide（开源、风格简洁现代）
- **AND** 用户可在两套图标库间切换选择
- **AND** 参数：图标来源、所选图标
- **AND** 样式：尺寸、颜色

#### Scenario: 图表组件
- **WHEN** 用户添加图表组件
- **THEN** 支持多种图表类型：柱状图（bar）、面积图（area）、饼图（pie）、散点图（scatter）、雷达图（radar）、热力图（heatmap）、漏斗图（funnel）等（不限于列举的类型）
- **AND** 基于 fl_chart 库实现
- **AND** 参数：图表类型、数据源（`#` 引用绑定数组数据）
- **AND** 样式：配色、坐标轴、图例、tooltip 等图表特有样式

### Requirement: 交互类组件

系统 SHALL 提供以下交互类组件。

#### Scenario: 按钮组件
- **WHEN** 用户添加按钮组件
- **THEN** 支持样式变体：primary / secondary / outline / text / danger 等
- **AND** 参数：标签（label，支持 `#` 引用）、变体（variant）
- **AND** 触发：onTap / onLongPress

#### Scenario: 图标按钮、按钮组、FAB
- **WHEN** 用户添加图标按钮 / 按钮组 / 浮动操作按钮（FAB）
- **THEN** 图标按钮：仅图标，无标签
- **AND** 按钮组：多个按钮横向排列，支持互斥选择
- **AND** FAB：悬浮于内容之上的圆形按钮
- **AND** 触发：onTap / onLongPress

#### Scenario: 开关与单选
- **WHEN** 用户添加开关（switch）/ 单选按钮（radio）
- **THEN** 开关：二元状态切换
- **AND** 单选按钮：多个圆圈选项中选一个（如性别选择），点击圆圈选中
- **AND** 参数：当前值（value，支持 `#` 引用）、选项列表
- **AND** 触发：onToggle / onChanged

#### Scenario: 下拉选择与级联选择
- **WHEN** 用户添加下拉选择框（dropdown）/ 级联选择框（cascader）
- **THEN** 下拉选择：点击展开选项列表，选一项
- **AND** 级联选择：多级联动选择（如省→市→区）
- **AND** 参数：当前值、选项数据（支持 `#` 引用）
- **AND** 触发：onSelect

#### Scenario: 文本输入框
- **WHEN** 用户添加文本输入框
- **THEN** 支持四种模式：单行输入、多行输入、数字输入、密码输入
- **AND** 可选是否带一键清空按钮
- **AND** 参数：当前值（value，支持 `#` 引用）、占位提示（hint）、模式
- **AND** 触发：onChanged / onSubmitted / onFocus / onBlur

#### Scenario: 滑块
- **WHEN** 用户添加滑块
- **THEN** 支持两种模式：单值滑块、范围双滑块（range slider）
- **AND** 参数：当前值（value，支持 `#` 引用）、最小值、最大值、步长、模式
- **AND** 触发：onChanged / onChangeEnd

#### Scenario: 日期选择器与日期范围选择器
- **WHEN** 用户添加日期选择器 / 日期范围选择器
- **THEN** 日期选择器：用户可选择精度——到年 / 到月 / 到日 / 到时 / 到分 / 到秒
- **AND** 日期范围选择器：选择起止日期，同样支持精度配置
- **AND** 参数：当前值（value，支持 `#` 引用）、精度（precision）
- **AND** 触发：onSelect

#### Scenario: 颜色选择器
- **WHEN** 用户添加颜色选择器
- **THEN** 提供颜色面板（色相/饱和度/亮度）或色板选择
- **AND** 参数：当前颜色值（value，支持 `#` 引用）
- **AND** 触发：onChanged

#### Scenario: 文件上传组件
- **WHEN** 用户添加文件上传组件
- **THEN** 支持选择文件类型过滤（图片/视频/文档/任意）
- **AND** 支持多选
- **AND** 参数：已选文件列表（value，支持 `#` 引用）、文件类型过滤、是否多选
- **AND** 触发：onFileSelected

#### Scenario: 富文本编辑器
- **WHEN** 用户添加富文本编辑器
- **THEN** 提供所见即所得的富文本编辑（加粗、斜体、下划线、列表、链接等）
- **AND** 参数：内容（content，支持 `#` 引用）
- **AND** 触发：onChanged

#### Scenario: 链接、Tabs、分页器
- **WHEN** 用户添加链接 / Tabs / 分页器
- **THEN** 链接：可点击的文本链接，支持跳转
- **AND** Tabs：标签页切换器，多个 Tab 选项，选中态高亮
- **AND** 分页器：页码导航，支持上一页/下一页/跳页
- **AND** 触发：onTap（链接）/ onTabChange（Tabs）/ onPageChange（分页器）

### Requirement: 容器类组件

系统 SHALL 提供以下容器类组件，每个容器可容纳子组件并提供布局上下文（9宫格堆叠 + 绝对布局）。

#### Scenario: 容器组件（通用）
- **WHEN** 用户添加容器组件
- **THEN** 该容器可容纳子组件
- **AND** 子组件按9宫格堆叠 + 绝对布局组织（容器作为父组件提供布局上下文）
- **AND** 参数：无特有参数（通用容器）
- **AND** 样式：背景色、边框、圆角、内间距（padding）等

#### Scenario: 条件渲染容器（Visible When）
- **WHEN** 用户添加条件渲染容器
- **THEN** 通过表达式控制显示哪个子容器
- **AND** 参数：条件表达式（condition，支持 `#` 引用）、匹配模式（single / firstMatch）
- **AND** 子组件通过 case 属性标识分支名
- **AND** 渲染时仅展示匹配 case 的子组件
- **AND** 触发：onCaseChange

#### Scenario: 循环渲染容器（Repeat / For-Each）
- **WHEN** 用户添加循环渲染容器
- **THEN** 绑定数组数据，自动循环渲染子组件模板
- **AND** 参数：数据源（items，`#` 引用数组）
- **AND** 子组件可引用循环上下文变量：item（当前项）、index（索引）、item.<field>（项字段）
- **AND** 非滚动渲染（全部内联渲染，不同于列表的可滚动）
- **AND** 触发：onItemTap

#### Scenario: 列表组件（横向 / 纵向）
- **WHEN** 用户添加列表组件
- **THEN** 支持两种方向：横向列表（horizontal）、纵向列表（vertical）
- **AND** 为静态可滚动列表（用户手动添加子项，非数据绑定循环）
- **AND** 参数：方向（direction）
- **AND** 子组件在列表中按顺序排列，支持滚动浏览
- **AND** 触发：onItemTap / onScroll

#### Scenario: 查询容器（Query Container）
- **WHEN** 用户添加查询容器
- **THEN** 挂载数据源（查询），每条数据对应一个子容器
- **AND** 子组件可引用查询结果（item、index、item.<field>）
- **AND** 与循环渲染容器的区别：查询容器直接挂载数据源（内置查询能力），循环容器仅绑定数组
- **AND** 参数：数据源配置、查询条件（支持 `#` 引用）
- **AND** 触发：onItemTap / onScroll / onLoad

---

## MODIFIED Requirements

### Requirement: 变量引用（沿用 0.x，无修改）

系统 SHALL 保留 0.x 的 `#` 变量引用四源模型：项目变量 / 组件上下文变量 / 函数变量 / 上游节点输出。所有源通过同一 `#` 引用机制访问，UI 组件属性与节点参数引用体验一致。

（本 Spec 不修改该机制，仅在新组件属性中沿用。）

### Requirement: 加载态占位（沿用 0.x，无修改）

系统 SHALL 保留 0.x 的加载态占位机制（typeDefault / placeholder / blank），适用于函数变量（时间线未就绪）与组件上下文变量（容器未渲染对应项）场景。

（本 Spec 不修改该机制，仅在新组件属性引用中沿用。）

### Requirement: 函数触发模型（沿用 0.x，无修改）

系统 SHALL 保留 0.x 的函数触发模型：组件事件 → 触发函数（uiEvent entry）；页面生命周期事件 → 触发函数（pageEvent entry）。函数声明其入口点（entry），自身不关心触发来源。

（本 Spec 不修改该机制，仅在新组件触发段中沿用。）

---

## Technical Notes（技术说明，非强制约束）

### 版本隔离策略

- 0.x 代码归档到 `legacy/v0` 分支（git tag v0-final）
- 主分支版本号升至 1.0.0
- 旧项目（0.x 格式）仅能在 legacy/v0 版本打开，1.0 不做向后兼容迁移
- 新代码组织：数据模型放 `lib/data/models/`（替换 0.x 同名文件），UI 编辑器放 `lib/features/ui_editor/`（完全重写）

### 数据模型（IR 结构）

```
project: { meta, projectVars[], functions[], db{tables[]}, ui{pages[]} }
page (特殊 UiNode): { id, name, route, isHome, type:'page',
                     props, layout, style, animations,
                     children: UiNode[], bindings, triggers }
uiNode: { id, type, pageId,
          props,         // 组件特有参数
          layout: {      // 布局配置
            mode: 'relative' | 'absolute',
            cell: 1..9 | null,     // 相对布局的9宫格归属（1=左上,...,9=右下）
            distance: { edge: 'top'|'bottom'|'left'|'right'|'center', value, unit } | null,  // 相对布局距最近边
            x: { value, unit } | null,  // 绝对布局 x
            y: { value, unit } | null,  // 绝对布局 y
            width: { value, unit: '%'|'px', minPx?, maxPx? },
            height: { value, unit: '%'|'px', minPx?, maxPx? },
            margin: { top, bottom, left, right }  // 每项 { value, unit }
          },
          style,         // 组件特有样式 + animations
          animations: { entrance?, exit?, triggered: [{ event, animation }] },
          children: UiNode[],  // 仅容器类有
          bindings,      // props → Binding (# 引用)
          triggers }     // eventName → funcId
```

### 9宫格编号约定

```
1 2 3
4 5 6
7 8 9
```
- 1=左上, 2=上中, 3=右上
- 4=左中, 5=中心, 6=右中
- 7=左下, 8=下中, 9=右下

### 9宫格堆叠渲染算法

每个父组件渲染子组件时：
1. 按 layout.mode 分组：relative 组 + absolute 组
2. relative 组按 layout.cell 分成9个队列
3. 每个队列按堆叠方向（顶行向下、底行向上、左中向右、右中向左、中心双向）排序
4. 按对齐方式（水平靠左/居中/靠右、垂直从上/居中/从下）定位
5. absolute 组按 x/y 坐标直接定位

### 第三方依赖

- **图表**：`fl_chart`（MIT 许可，Flutter 生态主流）
- **图标库**：Material Icons（Flutter 内置）+ `lucide_icons`（开源 ISC 许可）
- **富文本编辑**：`flutter_quill` 或类似（待技术调研）
- **日期选择器**：基于 Flutter DatePicker 扩展，支持精度配置

### 复用 0.x 的部分

- `#` 变量引用四源模型（`VariableRef` / `ScopeResolver`）
- 加载态占位（`LoadingStrategy` / `Binding`）
- 函数触发模型（`FunctionEntry` / `EntryKind`）
- 组件上下文变量（`ComponentContext`）
- Riverpod 状态管理模式（`Notifier` + provider）
- IR 序列化框架（`toJson` / `fromJson`）
- 插件系统协议（`UiComponentDef`）
