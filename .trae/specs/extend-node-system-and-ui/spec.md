# 节点系统与 UI 引用扩展 Spec

## Why
当前节点系统覆盖基础变量/运算/流程，但**变量读取节点冗余**（应直接用 `#` 引用），**数据库/运算/逻辑节点能力薄弱**（市面成熟工作流系统已有聚合统计、复杂数学、字符串/列表/日期操作、比较/类型检查/三元等），**缺少 UI 控制节点**（无法在函数中改变 UI 组件状态），且**函数无显式入参/出参签名**导致调用方无法类型安全地传参与消费返回值。

更根本的问题在**变量作用域**：UI 组件属性（如 Text 的 content）当前只能绑定到单一 `upstream` 引用，无法引用**项目变量、组件上下文变量（列表项字段、滑块值）、函数返回值变量**；且函数变量存在**时间线**问题（页面加载函数何时执行、UI 何时能读到返回值），当前把这个问题甩给用户处理，造成心智负担。

本 Spec 统一解决：扩展节点能力、引入显式函数签名、新增页面级触发、重构变量作用域为**四源 + 时间线规则**模型，并把 UI 属性引用统一到 `#` 机制，让"组件读什么变量"与"节点参数引用什么变量"成为同一套心智模型。

## What Changes
- **修改**：变量节点精简为只保留 `variable_set`（读取直接用 `#`）
- **修改**：数据库节点重构为 `db_query_one` / `db_query_rows` / `db_aggregate`（count/sum/avg/min/max）/ `db_insert` / `db_insert_rows`（批量）/ `db_update` / `db_delete` + DDL
- **新增**：运算节点扩展 `math_func`（abs/round/sqrt/sin/.../random）、`list_op`（size/get/slice/sort/unique/...）、`date_op`（now/format/add/diff/...）
- **新增**：逻辑节点扩展 `compare`（==/!=/>/</between）、`type_check`（isNull/isNumber/...）、`ternary`（条件表达式）
- **新增**：UI 控制节点 `ui_set_text` / `ui_set_visible` / `ui_set_enabled` / `ui_set_prop` / `ui_navigate` / `ui_show_toast`
- **新增**：`EntryKind.pageEvent`（onLoad / onDispose / onResume / onPause），ref 形如 `pageId:onLoad`
- **新增**：函数显式签名 `inputs: List<FuncParam>` / `outputs: List<FuncParam>`；`function_call` 节点按目标函数签名动态生成参数端口与返回值端口；`return` 节点按名返回多值
- **新增**：`Page` 概念（UI 树的命名根，承载页面级触发与页面作用域函数变量）
- **新增**：变量作用域四源模型 —— **项目变量 / 组件上下文变量 / 函数变量 / 上游节点输出**，统一通过 `#` 引用
- **新增**：函数变量时间线规则（系统自动处理，不让用户操心）
- **新增**：UI 组件属性 `#` 引用统一（替代独立 Binding，Binding 作为 `#` 引用在 UI 侧的存储形式）
- **新增**：加载态占位机制（引用未就绪时，按用户在引用时选择的策略：类型默认值 / 占位文字 / 占位符组件）
- **新增**：UI 组件扩展（rich_text / video / list_vertical / list_horizontal / tab_container / slider / switch / checkbox / progress / badge / card / divider / spacer / icon）
- **新增**：UI 触发事件扩展（onTap / onLongPress / onChanged / onSubmitted / onToggle / onPress / onSelect 等，事件参数作为函数入参注入）

## Impact
- **数据模型**：`FunctionDef` 增 `inputs` / `outputs`；`EntryKind` 增 `pageEvent`；新增 `Page` 模型；`VariableRef` 增 `component` 源；`Binding` 重构为 `#` 引用的 UI 存储形式
- **节点系统**：`node_kinds.dart` 大幅重写（移除 variable_get，重构 db_*，新增 math/list/date/compare/type_check/ternary/ui_*）；`node_executors.dart` 同步重写
- **变量作用域**：`ScopeResolver` 重构为四源解析；新增 `ComponentContext`（列表项字段、滑块值等运行时上下文）
- **UI 编辑器**：`segment_view.dart` 新增 12+ 组件；属性面板支持 `#` 引用；事件面板扩展
- **函数编辑器**：`function_editor_screen.dart` 增加函数签名编辑入口；`function_call` 节点动态生成参数端口
- **运行时**：`RuntimeScope` 增页面级函数变量缓存与时间线状态；`RuntimeUiState` 已实现 UI 控制节点覆盖层
- **风险**：变量作用域重构影响所有 `#` 引用解析路径，需保证向后兼容（旧引用仍能解析）；函数签名迁移需为既有函数提供默认签名推导
- **关联分支**：`feat/node-system-expansion` 已实现节点扩展与 UI 控制节点执行器基础；本 Spec 在其上补完函数签名、页面触发、变量作用域、UI 属性引用统一

---

## ADDED Requirements

### Requirement: 页面级触发
系统 SHALL 支持 `EntryKind.pageEvent`，ref 形如 `<pageId>:<eventName>`，eventName ∈ `onLoad` / `onDispose` / `onResume` / `onPause`。一个页面可挂多个函数到同一事件（按声明序执行）。

#### Scenario: 页面加载触发函数
- **WHEN** 运行时进入某 Page
- **THEN** 系统按声明序执行该 Page 下所有 `entry.kind == pageEvent && ref == '<pageId>:onLoad'` 的函数
- **AND** 函数的 `outputs` 在执行完成后缓存到页面作用域，供该页面内 UI 组件的 `#` 引用读取
- **AND** 若函数抛错，记录错误但不阻塞后续函数执行

#### Scenario: 页面卸载触发函数
- **WHEN** 运行时离开某 Page
- **THEN** 系统按声明序执行该 Page 下所有 `entry.kind == pageEvent && ref == '<pageId>:onDispose'` 的函数
- **AND** 卸载函数的返回值不缓存（页面已销毁）

### Requirement: 函数显式签名
系统 SHALL 为每个函数提供显式 `inputs: List<FuncParam>` 与 `outputs: List<FuncParam>` 声明。`FuncParam` 包含 `name` / `type: PortType` / `defaultValue` / `description`。

#### Scenario: 函数签名编辑
- **WHEN** 用户在函数编辑器打开"签名"面板
- **THEN** 可增删改入参与出参，每项含名称、类型、默认值、描述
- **AND** 既有无签名函数迁移时，系统自动推导：入参 = funcVars 中 `isInput==true` 项，出参 = 空（沿用 return 的 value）

#### Scenario: 函数调用节点动态端口
- **WHEN** 用户在 `function_call` 节点选择目标函数
- **THEN** 节点按目标函数 `inputs` 动态生成参数 `ParamSpec`（每个入参一个 `#` 可引用参数）
- **AND** 节点按目标函数 `outputs` 动态生成命名数据输出端口
- **AND** 目标函数签名变更时，已放置的 `function_call` 节点在下次编辑时同步端口

#### Scenario: 多返回值
- **WHEN** 函数声明 `outputs: [{name:'id', type:number}, {name:'name', type:string}]`
- **AND** 函数体内 `return` 节点配置返回 `{id: #..., name: #...}`（按名映射）
- **THEN** 调用方通过 `#function_call.id` / `#function_call.name` 读取各返回值

### Requirement: 变量作用域四源模型
系统 SHALL 统一变量引用为四源：**项目变量** / **组件上下文变量** / **函数变量** / **上游节点输出**。所有源通过同一 `#` 引用机制访问。

#### Scenario: 项目变量引用
- **WHEN** 任意节点参数或 UI 组件属性使用 `#` 引用
- **THEN** 可选择项目变量（`VariableSource.projVar`），值来自 `RuntimeScope.projVars`

#### Scenario: 组件上下文变量引用
- **WHEN** UI 组件位于 `list_vertical` / `list_horizontal` / `tab_container` 等容器内
- **THEN** 组件可引用容器提供的上下文变量：
  - 列表项：`item`（当前项）、`index`（索引）、`item.<field>`（项字段，若 item 为 Map）
  - Tab：`tab`（当前 Tab 索引）、`tab.<field>`
- **AND** 滑块 `slider` 提供 `value`（当前值）、开关 `switch` 提供 `value`
- **AND** 这些变量由 `ComponentContext` 在渲染时按组件树位置注入

#### Scenario: 函数变量引用（含时间线）
- **WHEN** UI 组件引用页面 onLoad 函数的 outputs
- **THEN** 系统按时间线规则解析：
  - 函数**已执行完成**：返回缓存的 output 值
  - 函数**执行中**：返回用户在引用时选择的加载态策略（见"加载态占位"）
  - 函数**尚未执行**：返回加载态策略
  - 函数**执行失败**：返回加载态策略，并在 DevTools 显示错误标记（不影响渲染）

#### Scenario: 上游节点输出引用
- **WHEN** 节点参数引用 `#upstream`
- **THEN** 值来自 `RuntimeScope.nodeOutputs`（保持现有行为）

### Requirement: 加载态占位机制
系统 SHALL 在 `#` 引用时允许用户选择"加载态策略"，适用于**函数变量**（时间线未就绪）与**组件上下文变量**（容器未渲染对应项）场景。

策略 ∈ `typeDefault`（按类型默认值）/ `placeholder`（占位文字）/ `blank`（不渲染该属性）。

#### Scenario: 引用时选择加载态
- **WHEN** 用户在 UI 组件属性或节点参数上 `#` 引用一个函数变量
- **THEN** 引用配置面板提供"加载态策略"选项
- **AND** 默认策略为 `typeDefault`（number→0, string→'', list→[], map→{}, bool→false）
- **AND** `placeholder` 策略需用户填占位文字（如"加载中..."）
- **AND** `blank` 策略下属性渲染为空（文本类显示空串，图片类不渲染）

### Requirement: UI 组件属性统一 # 引用
系统 SHALL 让 UI 组件的任意属性（text / src / value / color / visible / enabled 等）通过 `#` 引用变量，与节点参数引用体验一致。

#### Scenario: 文本组件引用函数返回值
- **WHEN** 用户在 `text` 组件的 `content` 属性点 `#` 按钮
- **THEN** 弹出变量选择卡片，可选项目/组件/函数/上游变量
- **AND** 选中后属性显示为 `{函数名.输出名}` 占位（编辑态）或实际值（运行态）
- **AND** 引用配置包含"加载态策略"

#### Scenario: 列表项组件引用 item 字段
- **WHEN** `list_vertical` 的子组件为 `text`，其 `content` 引用 `#item.name`
- **THEN** 运行时渲染时，每个列表项的 `text` 显示对应 `item['name']` 字段值
- **AND** item 为 null 时按加载态策略处理

### Requirement: UI 触发事件扩展
系统 SHALL 支持组件级事件触发函数，事件参数作为函数入参注入。事件 ∈ `onTap` / `onLongPress` / `onChanged` / `onSubmitted` / `onToggle` / `onPress` / `onRelease` / `onSelect`。

#### Scenario: 按钮点击触发函数
- **WHEN** `button` 组件配置 `onTap` 事件绑定到函数 F
- **AND** F 声明入参 `[{name:'event', type:map}]`
- **THEN** 点击按钮时执行 F，注入 `event = {type:'tap', timestamp:..., componentId:...}`
- **AND** F 的 outputs 不自动缓存（事件触发函数的返回值不进页面作用域，除非显式用 `ui_set_*` 节点写入）

#### Scenario: 输入框内容变化触发函数
- **WHEN** `text_field` 配置 `onChanged` 绑定函数 F
- **AND** F 入参含 `[{name:'value', type:string}]`
- **THEN** 每次内容变化执行 F，注入 `value = 当前输入内容`
- **AND** 默认防抖 300ms（用户可在事件配置中调整）

#### Scenario: 滑块值变化触发函数
- **WHEN** `slider` 配置 `onChanged` 绑定函数 F
- **AND** F 入参含 `[{name:'value', type:number}]`
- **THEN** 滑动时执行 F，注入 `value = 当前滑块值`
- **AND** 滑块同时通过组件上下文变量 `value` 供同容器内其他组件 `#` 引用

### Requirement: 节点系统扩展（已在 feat/node-system-expansion 实现基础）
系统 SHALL 提供以下节点类别（执行器已实现，节点规格与 UI 集成待补完）：

- **变量**：`variable_set`（仅写入，读取用 `#`）
- **运算**：`arithmetic`（+−×÷%//^）、`math_func`（abs/round/floor/ceil/sqrt/log/sin/cos/tan/min/max/random）、`string_op`（concat/substring/upper/lower/length/replace/split/trim/contains/startsWith/endsWith/indexOf/format/padLeft/padRight/reverse/repeat）、`list_op`（size/get/contains/append/removeAt/slice/reverse/sort/unique/join/concat/indexOf）、`date_op`（now/parse/format/year/month/day/add/diff）
- **逻辑**：`logic`（and/or/not/xor/nand/nor）、`compare`（==/!=/>/</>=/<=/between）、`type_check`（isNull/isNotNull/isNumber/isString/isBool/isList/isMap）、`ternary`
- **流程**：`if`、`loop`、`return`（多返回值按名映射）
- **函数**：`function_call`（按目标签名动态端口）
- **数据库**：`db_query_one`、`db_query_rows`、`db_aggregate`、`db_insert`、`db_insert_rows`、`db_update`、`db_delete`、`db_create_table`、`db_alter_table`
- **UI 控制**：`ui_set_text`、`ui_set_visible`、`ui_set_enabled`、`ui_set_prop`、`ui_navigate`、`ui_show_toast`
- **插件**：`plugin_openai`、`plugin_anthropic`、`plugin_<id>`（市场）

#### Scenario: 节点调色板分类
- **WHEN** 用户在函数编辑器查看调色板
- **THEN** 节点按类别分组展示：变量 / 运算 / 逻辑 / 流程 / 函数 / 数据库 / UI 控制 / 插件
- **AND** 每类可折叠，避免一次性展示过多节点

### Requirement: UI 组件扩展
系统 SHALL 提供 12+ 新组件：`rich_text` / `video` / `list_vertical` / `list_horizontal` / `tab_container` / `slider` / `switch` / `checkbox` / `progress` / `badge` / `card` / `divider` / `spacer` / `icon`。

容器类（`list_vertical` / `list_horizontal` / `tab_container` / `card`）可容纳子节点并向子节点提供组件上下文变量。

#### Scenario: 列表组件渲染数据
- **WHEN** `list_vertical` 的 `items` 属性 `#` 引用一个 list 数据
- **AND** 子组件为 `card`，内含 `text` 引用 `#item.name`
- **THEN** 运行时按 items 长度渲染对应数量 card，每个 card 的 text 显示对应项的 name 字段

#### Scenario: Tab 容器切换
- **WHEN** `tab_container` 配置多个 Tab 子节点
- **THEN** 切换 Tab 时仅渲染当前 Tab 子树
- **AND** 子组件可 `#` 引用 `tab`（当前索引）与 `tab.<field>`

---

## MODIFIED Requirements

### Requirement: 变量引用（修改）
系统 SHALL 统一变量引用为四源：**项目变量 / 组件上下文变量 / 函数变量 / 上游节点输出**。引用通过 `#` 触发卡片选择或 `#名称` 快速输入。

（原 spec 仅支持 upstream + funcVar + projVar 三源，本次新增 component 源，并把 UI 属性引用统一到本机制。）

#### Scenario: 引用来源扩展
- **WHEN** 用户在节点参数或 UI 属性触发 `#` 引用
- **THEN** 卡片显示四类来源：项目变量、组件上下文变量（仅 UI 侧可见）、函数变量、上游节点输出
- **AND** 选中后存为 `VariableRef`，`source` 字段标识来源

### Requirement: 节点系统（修改）
系统 SHALL 精简变量节点（移除 `variable_get`，读取统一用 `#`），并扩展运算/逻辑/数据库/UI 控制节点类别如"ADDED Requirements"所述。

（原 spec 的 variable_get / 简单 arithmetic / logic / string_op / db_query 等被替换或扩展。）

---

## REMOVED Requirements

### Requirement: variable_get 节点
**理由**：变量读取用 `#` 引用即可，无需独立节点。已从 `node_kinds.dart` 与执行器移除。
