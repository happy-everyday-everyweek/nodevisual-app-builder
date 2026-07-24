# 任务分解 — 节点系统与 UI 引用扩展

> 关联分支：`feat/node-system-expansion`（已实现节点执行器基础）→ 本 Spec 任务在其上补完数据模型/UI/作用域

## 阶段 1：数据模型与签名（前置）

- [ ] **T1** `EntryKind` 增 `pageEvent`；`entry.dart` ref 解析支持 `<pageId>:<event>`
- [ ] **T2** 新增 `Page` 模型（id / name / rootUiNodeId / eventBindings）；`Project` 增 `pages: List<Page>`；`UiNode` 增 `pageId` 字段（标记所属页面）
- [ ] **T3** 新增 `FuncParam`（name / type / defaultValue / description）；`FunctionDef` 增 `inputs: List<FuncParam>` / `outputs: List<FuncParam>`；为既有函数提供默认签名推导（`_migrateSignature`）
- [ ] **T4** `VariableRef` 增 `VariableSource.component` 源 + `componentId` / `fieldName` 字段；`VariableRef.fromJson/toJson` 同步
- [ ] **T5** 新增 `ComponentContext`（componentId / fields: Map）；运行时由容器组件注入；持久化时不存储（纯运行时）
- [ ] **T6** `Binding` 重构：内部存储为 `VariableRef` + 加载态策略（`typeDefault` / `placeholder` / `blank`）+ 占位文字；`UiNode.bindings` 含义不变但值结构升级

## 阶段 2：节点规格与执行器（部分已实现）

- [x] **T7** 节点执行器扩展（math_func / list_op / date_op / compare / type_check / ternary / db_*重构 / ui_*）— `feat/node-system-expansion` 已完成
- [ ] **T8** `node_kinds.dart` 同步规格：移除 variable_get，重构 db_* 规格，新增 math_func / list_op / date_op / compare / type_check / ternary / ui_* 规格与参数 schema
- [ ] **T9** `function_call` 节点规格改造：`dynamicOutputs` 改为按目标函数 `outputs` 动态生成；`paramSchema` 按 `inputs` 动态生成
- [ ] **T10** `return` 节点支持多返回值：参数改为 `values: Map<name, ref>`；按 `outputs` 名映射
- [ ] **T11** 节点调色板分类分组（变量/运算/逻辑/流程/函数/数据库/UI控制/插件），可折叠

## 阶段 3：变量作用域与时间线

- [ ] **T12** `ScopeResolver` 重构为四源解析：projVar / component / funcVar / upstream；`matchByName` 支持组件上下文（如 `item.name` 解析为 `component.item.field:name`）
- [ ] **T13** `RuntimeScope` 增页面级函数变量缓存：`pageFuncOutputs: Map<funcId, Map<outputName, value>>` + 状态机（idle / running / done / error）
- [ ] **T14** 时间线规则实现：解析 `#funcVar` 引用时检查目标函数状态，未就绪按加载态策略返回默认值
- [ ] **T15** `VariablePickerSheet` 扩展：四源展示；选中 component 源时显示组件上下文可用字段；引用配置面板含"加载态策略"

## 阶段 4：UI 组件扩展

- [ ] **T16** `segment_view.dart` 新增组件渲染：rich_text / video / list_vertical / list_horizontal / tab_container / slider / switch / checkbox / progress / badge / card / divider / spacer / icon
- [ ] **T17** 容器组件注入 `ComponentContext`：list_vertical/horizontal 注入 item/index；tab_container 注入 tab；slider/switch 注入 value
- [ ] **T18** 属性面板支持 `#` 引用：任意属性旁加 `#` 按钮，复用 `VariablePickerSheet`；选中后属性显示占位 `{源.名}`
- [ ] **T19** 事件面板扩展：每个组件支持配置 onTap/onLongPress/onChanged/onSubmitted/onToggle 等事件 → 绑定函数 + 防抖配置
- [ ] **T20** `ComponentPanel` 新增 12+ 组件卡片；按类别分组（基础/容器/输入/展示）

## 阶段 5：页面与触发

- [ ] **T21** UI 编辑器新增"页面"概念：根 UiNode 可标记为 Page；页面列表 UI
- [ ] **T22** 页面事件绑定 UI：在页面属性面板配置 onLoad/onDispose 等绑定函数（多选 + 顺序）
- [ ] **T23** 运行时页面生命周期：进入页面触发 onLoad，离开触发 onDispose；函数 outputs 缓存到页面作用域
- [ ] **T24** 事件触发函数入参注入：onChanged 注入 value、onTap 注入 event map 等

## 阶段 6：集成与验证

- [ ] **T25** `node_editor_screen.dart` 适配新参数类型（function_call 动态端口、return 多值 map）
- [ ] **T26** `function_editor_screen.dart` 函数签名编辑面板（入参/出参 CRUD）
- [ ] **T27** 编译管线（codegen / interpreter）适配函数签名与页面触发
- [x] **T28** 既有项目数据迁移测试：无签名函数自动推导签名；旧 Binding 升级为新结构
- [x] **T29** 端到端验证：列表渲染数据 + 滑块联动文本 + 页面加载函数返回值显示
