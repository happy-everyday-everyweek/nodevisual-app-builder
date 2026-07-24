# 验证清单 — 节点系统与 UI 引用扩展

## 节点系统
- [ ] `variable_get` 节点已从 `node_kinds.dart` 与执行器移除，画布不显示
- [x] 既有项目含 `variable_get` 节点时，加载不崩溃（降级为未知节点或自动移除）
- [ ] `db_aggregate` 支持 count/sum/avg/min/max 五种聚合
- [ ] `db_insert_rows` 批量插入返回 insertedIds 列表
- [ ] `math_func` 的 round/floor/ceil/abs 返回 int，其余返回 double
- [ ] `string_op` 的 16 种操作均能执行（concat/substring/upper/lower/length/replace/split/trim/contains/startsWith/endsWith/indexOf/format/padLeft/padRight/reverse/repeat）
- [ ] `list_op` 的 13 种操作均能执行
- [ ] `date_op` 的 now/format/add/diff 与 year/month/day 等字段提取正确
- [ ] `compare` 的 between 需要第三参数 c
- [ ] `ternary` 返回 trueValue 或 falseValue
- [ ] UI 控制节点写入 RuntimeUiState 后，UI 渲染层能合并覆盖

## 函数签名
- [ ] `FunctionDef.inputs` / `outputs` 字段存在且可序列化
- [x] 既有无签名函数加载时自动推导签名（入参 = isInput funcVars，出参 = 空）
- [ ] `function_call` 节点选择目标后，参数端口与返回值端口按目标签名动态生成
- [ ] 目标函数签名变更后，已放置的 function_call 节点端口同步更新
- [ ] `return` 节点支持多返回值 map，按名映射到 outputs
- [ ] 调用方通过 `#function_call.<outputName>` 读取各返回值

## 页面触发
- [ ] `EntryKind.pageEvent` 存在，ref 形如 `<pageId>:onLoad`
- [ ] 进入页面时按声明序执行 onLoad 函数
- [ ] 离开页面时执行 onDispose 函数
- [ ] 函数 outputs 缓存到页面作用域供 UI 引用
- [ ] 函数抛错不阻塞后续函数执行
- [ ] onDispose 函数返回值不缓存

## 变量作用域
- [ ] `#` 引用卡片显示四源：项目变量 / 组件上下文 / 函数变量 / 上游节点输出
- [ ] 组件上下文源仅在 UI 侧可见（节点参数侧隐藏该源）
- [ ] `list_vertical` 子组件可 `#item` / `#index` / `#item.<field>` 引用
- [ ] `slider` 提供 `#value`，`switch` 提供 `#value`
- [ ] 引用函数变量时，函数已执行完成返回缓存值
- [ ] 函数未就绪时按加载态策略返回（typeDefault / placeholder / blank）
- [ ] 加载态策略在引用配置面板可选，默认 typeDefault
- [ ] placeholder 策略需用户填占位文字
- [ ] blank 策略下属性渲染为空

## UI 组件
- [ ] 新增 12+ 组件在 ComponentPanel 可见：rich_text / video / list_vertical / list_horizontal / tab_container / slider / switch / checkbox / progress / badge / card / divider / spacer / icon
- [ ] 容器组件（list_vertical/horizontal/tab_container/card）可容纳子节点
- [ ] 容器组件向子节点注入 ComponentContext
- [ ] list_vertical 按 items 长度渲染对应数量子节点
- [ ] tab_container 切换 Tab 仅渲染当前 Tab 子树
- [ ] 任意属性旁有 `#` 按钮可触发引用
- [ ] 引用后属性显示占位 `{源.名}`
- [ ] 运行时渲染显示实际值

## UI 事件
- [ ] 按钮支持 onTap / onLongPress
- [ ] text_field 支持 onChanged / onSubmitted
- [ ] slider 支持 onChanged（注入 value）
- [ ] switch 支持 onToggle（注入 value）
- [ ] onChanged 默认防抖 300ms，可配置
- [ ] 事件触发函数入参按签名注入

## 集成
- [ ] 节点调色板按类别分组可折叠
- [ ] 函数签名编辑面板可 CRUD 入参出参
- [x] 既有项目加载不崩溃（迁移正确）
- [x] 端到端：列表渲染数据 + 滑块联动 + 页面加载函数返回值显示
