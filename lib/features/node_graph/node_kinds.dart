import 'package:flutter/material.dart' show IconData, Icons;
import 'package:uuid/uuid.dart';

import '../../data/models/func_param.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
import '../../data/models/port.dart';

const Uuid _uuid = Uuid();

/// 节点种类大类（用于面板分组与检索）。
enum NodeCategory {
  /// 变量节点（仅 variable_set）。
  variable,

  /// 运算节点（arithmetic / math_func / string_op / list_op / date_op）。
  operation,

  /// 逻辑节点（logic / compare / type_check / ternary）。
  logic,

  /// 流程控制节点（if / loop / return）。
  flow,

  /// 函数调用节点（function_call）。
  function,

  /// 数据库节点（db_*）。
  database,

  /// UI 控制节点（ui_set_text / ui_set_visible 等）。
  uiControl,

  /// 插件节点（plugin_*）。
  plugin,
}

/// 节点展示分组（用户视角的 3 大分类，用于面板分组展示）。
///
/// 将细粒度的 [NodeCategory] 归并为 3 个用户友好分组：
/// 1. [variablesDatabase] — 变量与数据库
/// 2. [logicFlow] — 逻辑与流程
/// 3. [executionFunctions] — 执行与函数（不在前两个分类的节点归入此组）
enum NodeDisplayGroup {
  /// 变量与数据库。
  variablesDatabase,

  /// 逻辑与流程。
  logicFlow,

  /// 执行与函数（兜底分组）。
  executionFunctions,
}

/// 将细粒度 [NodeCategory] 映射到 3 大展示分组。
///
/// 规则：
/// - variable / database → [NodeDisplayGroup.variablesDatabase]
/// - logic / flow → [NodeDisplayGroup.logicFlow]
/// - 其余（operation / function / uiControl / plugin）→ [NodeDisplayGroup.executionFunctions]
NodeDisplayGroup displayGroupOf(NodeCategory category) {
  switch (category) {
    case NodeCategory.variable:
    case NodeCategory.database:
      return NodeDisplayGroup.variablesDatabase;
    case NodeCategory.logic:
    case NodeCategory.flow:
      return NodeDisplayGroup.logicFlow;
    case NodeCategory.operation:
    case NodeCategory.function:
    case NodeCategory.uiControl:
    case NodeCategory.plugin:
      return NodeDisplayGroup.executionFunctions;
  }
}

/// 展示分组的中文名称。
String displayGroupLabel(NodeDisplayGroup group) {
  switch (group) {
    case NodeDisplayGroup.variablesDatabase:
      return '变量与数据库';
    case NodeDisplayGroup.logicFlow:
      return '逻辑与流程';
    case NodeDisplayGroup.executionFunctions:
      return '执行与函数';
  }
}

/// 展示分组的图标。
IconData displayGroupIcon(NodeDisplayGroup group) {
  switch (group) {
    case NodeDisplayGroup.variablesDatabase:
      return Icons.storage_outlined;
    case NodeDisplayGroup.logicFlow:
      return Icons.account_tree_outlined;
    case NodeDisplayGroup.executionFunctions:
      return Icons.play_circle_outline;
  }
}

/// 参数输入控件类型。
enum ParamInputType {
  /// 文本输入。
  text,

  /// 数值输入。
  number,

  /// 布尔开关。
  bool,

  /// 下拉单选。
  dropdown,

  /// 字符串列表（可增删，用于 if 的 cases 等）。
  listStrings,

  /// Map 键值对编辑器（用于 return 多返回值映射 / db_insert data）。
  keyValueMap,
}

/// 单个节点参数的规格定义。
///
/// 描述参数在节点编辑页中如何渲染、是否接受 `#` 引用、以及引用时期望的
/// 原始类型（[expectedType]，仅对 [acceptsRef] 为 true 的参数有意义，
/// 用于 [checkRefType] 的类型校验提示）。
class ParamSpec {
  /// 参数键名（对应 [Node.params] 的 key）。
  final String name;

  /// 中文展示名。
  final String label;

  /// 输入控件类型。
  final ParamInputType inputType;

  /// 下拉选项（仅 [ParamInputType.dropdown] 有效）。
  ///
  /// 静态选项；动态选项（如 function_call 的 targetFunctionId 取项目内函数）
  /// 由节点编辑页按 kind + name 特殊处理，运行时覆盖此处。
  final List<String>? options;

  /// 是否可被 `#` 引用赋值（true 时编辑页显示 # 按钮）。
  final bool acceptsRef;

  /// 默认值（缺省时按 [inputType] 推导）。
  final Object? defaultValue;

  /// 引用时期望的原始类型（null 视为 [PortType.any]，不约束）。
  final PortType? expectedType;

  const ParamSpec({
    required this.name,
    required this.label,
    required this.inputType,
    this.options,
    this.acceptsRef = false,
    this.defaultValue,
    this.expectedType,
  });
}

/// 节点动态输出的解析结果（控制流输出 + 数据输出）。
class NodeOutputs {
  /// 控制流输出端口列表。
  final List<ControlOutput> controlOutputs;

  /// 数据输出端口列表。
  final List<DataOutput> dataOutputs;

  const NodeOutputs({
    this.controlOutputs = const [],
    this.dataOutputs = const [],
  });
}

/// 根据 [Node.params] 动态生成 outputs 的函数签名。
///
/// 返回值应为完整 outputs（同时包含控制流与数据输出）。
typedef DynamicOutputsFn = NodeOutputs Function(Map<String, dynamic> params);

/// 根据 [Node.params] + 项目上下文动态生成 outputs（用于 function_call
/// 按目标函数签名生成命名数据输出端口）。
///
/// [project] 提供函数列表（查找目标函数的 inputs/outputs）。
typedef ProjectOutputsFn = NodeOutputs Function(
  Map<String, dynamic> params,
  List<FunctionDef> functions,
);

/// 一种节点 kind 的元数据规格。
///
/// 集中描述该 kind 的参数 schema 与默认 / 动态输出，作为节点编辑页
/// 渲染、节点工厂创建、类型校验提示的统一来源。
class NodeKindSpec {
  /// kind 标识。
  final String kind;

  /// 中文展示名。
  final String displayName;

  /// 大类。
  final NodeCategory category;

  /// 参数 schema。
  final List<ParamSpec> paramSchema;

  /// 默认控制流输出名（[dynamicOutputs] 为 null 时使用）。
  final List<String> defaultControlOutputs;

  /// 默认数据输出（[dynamicOutputs] 为 null 时使用）。
  final List<({String name, PortType type})> defaultDataOutputs;

  /// 动态输出生成器（非 null 时优先使用，覆盖默认输出）。
  final DynamicOutputsFn? dynamicOutputs;

  /// 项目上下文动态输出生成器（仅 function_call 使用）。
  ///
  /// 优先于 [dynamicOutputs]：按目标函数签名生成命名数据输出。
  final ProjectOutputsFn? projectOutputs;

  /// 关联的插件 id（仅 plugin 类节点有效，如 `llm_openai`）。
  final String? pluginId;

  const NodeKindSpec({
    required this.kind,
    required this.displayName,
    required this.category,
    this.paramSchema = const [],
    this.defaultControlOutputs = const [],
    this.defaultDataOutputs = const [],
    this.dynamicOutputs,
    this.projectOutputs,
    this.pluginId,
  });
}

/// 所有节点 kind 的注册表。
///
/// 提供 [getSpec] 查询单个 kind 规格，[allKinds] 枚举全部已注册规格。
class NodeKindRegistry {
  NodeKindRegistry._();

  static final Map<String, NodeKindSpec> _specs = _buildSpecs();

  /// 查询 kind 规格；未注册返回 null。
  static NodeKindSpec? getSpec(String kind) => _specs[kind];

  /// 全部已注册规格（按注册顺序）。
  static List<NodeKindSpec> allKinds() =>
      _specs.values.toList(growable: false);

  /// 是否已注册。
  static bool isRegistered(String kind) => _specs.containsKey(kind);

  static Map<String, NodeKindSpec> _buildSpecs() {
    final specs = <NodeKindSpec>[
      // ---- 变量（精简：仅 variable_set，读取用 # 引用）----
      NodeKindSpec(
        kind: 'variable_set',
        displayName: '设置变量',
        category: NodeCategory.variable,
        paramSchema: const [
          ParamSpec(
            name: 'varName',
            label: '变量名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'value',
            label: '值',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
      ),

      // ---- 运算 ----
      NodeKindSpec(
        kind: 'arithmetic',
        displayName: '算术运算',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operator',
            label: '运算符',
            inputType: ParamInputType.dropdown,
            options: ['+', '-', '*', '/', '%', '//', '^'],
            defaultValue: '+',
          ),
          ParamSpec(
            name: 'a',
            label: '操作数 a',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
          ParamSpec(
            name: 'b',
            label: '操作数 b',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.number)],
      ),
      NodeKindSpec(
        kind: 'math_func',
        displayName: '数学函数',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'func',
            label: '函数',
            inputType: ParamInputType.dropdown,
            options: [
              'abs', 'round', 'floor', 'ceil', 'sqrt', 'log',
              'sin', 'cos', 'tan', 'min', 'max', 'random',
            ],
            defaultValue: 'abs',
          ),
          ParamSpec(
            name: 'a',
            label: '操作数 a',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
          ParamSpec(
            name: 'b',
            label: '操作数 b（min/max 用）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.number)],
      ),
      NodeKindSpec(
        kind: 'string_op',
        displayName: '字符串操作',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operation',
            label: '操作',
            inputType: ParamInputType.dropdown,
            options: [
              'concat', 'substring', 'upper', 'lower', 'length',
              'replace', 'split', 'trim', 'contains', 'startsWith',
              'endsWith', 'indexOf', 'format', 'padLeft', 'padRight',
              'reverse', 'repeat',
            ],
            defaultValue: 'concat',
          ),
          ParamSpec(
            name: 'a',
            label: '字符串 a',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'b',
            label: '字符串 b / 参数',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'c',
            label: '参数 c（替换目标 / 填充字符）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.string)],
        dynamicOutputs: _stringOpOutputs,
      ),
      NodeKindSpec(
        kind: 'list_op',
        displayName: '列表操作',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operation',
            label: '操作',
            inputType: ParamInputType.dropdown,
            options: [
              'size', 'get', 'contains', 'append', 'removeAt', 'slice',
              'reverse', 'sort', 'unique', 'join', 'concat', 'indexOf',
              'map', 'filter',
            ],
            defaultValue: 'size',
          ),
          ParamSpec(
            name: 'a',
            label: '列表',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.list,
          ),
          ParamSpec(
            name: 'b',
            label: '参数 b（index / 元素 / 连接符）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.any)],
        dynamicOutputs: _listOpOutputs,
      ),
      NodeKindSpec(
        kind: 'date_op',
        displayName: '日期操作',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operation',
            label: '操作',
            inputType: ParamInputType.dropdown,
            options: ['now', 'parse', 'format', 'year', 'month', 'day', 'add', 'diff'],
            defaultValue: 'now',
          ),
          ParamSpec(
            name: 'a',
            label: '时间戳/日期字符串',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
          ParamSpec(
            name: 'b',
            label: '参数 b（格式 / 增量值）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'c',
            label: '参数 c（增量单位 / 比较时间戳）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.any)],
        dynamicOutputs: _dateOpOutputs,
      ),

      // ---- 逻辑 ----
      NodeKindSpec(
        kind: 'logic',
        displayName: '逻辑运算',
        category: NodeCategory.logic,
        paramSchema: const [
          ParamSpec(
            name: 'operator',
            label: '运算符',
            inputType: ParamInputType.dropdown,
            options: ['and', 'or', 'not', 'xor', 'nand', 'nor'],
            defaultValue: 'and',
          ),
          ParamSpec(
            name: 'a',
            label: '操作数 a',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
          ParamSpec(
            name: 'b',
            label: '操作数 b（可选）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.boolean)],
      ),
      NodeKindSpec(
        kind: 'compare',
        displayName: '比较',
        category: NodeCategory.logic,
        paramSchema: const [
          ParamSpec(
            name: 'operator',
            label: '运算符',
            inputType: ParamInputType.dropdown,
            options: ['==', '!=', '>', '<', '>=', '<=', 'between'],
            defaultValue: '==',
          ),
          ParamSpec(
            name: 'a',
            label: '操作数 a',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
          ParamSpec(
            name: 'b',
            label: '操作数 b',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
          ParamSpec(
            name: 'c',
            label: '操作数 c（between 时为上界）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.boolean)],
      ),
      NodeKindSpec(
        kind: 'type_check',
        displayName: '类型检查',
        category: NodeCategory.logic,
        paramSchema: const [
          ParamSpec(
            name: 'check',
            label: '检查类型',
            inputType: ParamInputType.dropdown,
            options: [
              'isNull', 'isNotNull', 'isNumber', 'isString',
              'isBool', 'isList', 'isMap',
            ],
            defaultValue: 'isNull',
          ),
          ParamSpec(
            name: 'a',
            label: '操作数',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.boolean)],
      ),
      NodeKindSpec(
        kind: 'ternary',
        displayName: '三元表达式',
        category: NodeCategory.logic,
        paramSchema: const [
          ParamSpec(
            name: 'condition',
            label: '条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
          ParamSpec(
            name: 'trueValue',
            label: '为真时的值',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
          ParamSpec(
            name: 'falseValue',
            label: '为假时的值',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.any)],
      ),

      // ---- 流程控制 ----
      NodeKindSpec(
        kind: 'if',
        displayName: '条件分支',
        category: NodeCategory.flow,
        paramSchema: const [
          ParamSpec(
            name: 'condition',
            label: '条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
          ParamSpec(
            name: 'cases',
            label: '分支',
            inputType: ParamInputType.listStrings,
            defaultValue: ['true', 'false'],
          ),
          ParamSpec(
            name: 'includeDefault',
            label: '包含 default 分支',
            inputType: ParamInputType.bool,
            defaultValue: false,
          ),
        ],
        defaultControlOutputs: [],
        defaultDataOutputs: [],
        dynamicOutputs: _ifOutputs,
      ),
      // ---- if 分支子节点（子母节点设计：插入 if 时自动生成的子节点）----
      NodeKindSpec(
        kind: 'if_branch',
        displayName: '条件分支出口',
        category: NodeCategory.flow,
        paramSchema: const [
          ParamSpec(
            name: 'parentId',
            label: '所属条件节点',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'caseName',
            label: '分支名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [],
      ),
      NodeKindSpec(
        kind: 'loop',
        displayName: '循环',
        category: NodeCategory.flow,
        paramSchema: const [
          ParamSpec(
            name: 'mode',
            label: '模式',
            inputType: ParamInputType.dropdown,
            options: ['count', 'condition'],
            defaultValue: 'count',
          ),
          ParamSpec(
            name: 'count',
            label: '循环次数',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
          ParamSpec(
            name: 'condition',
            label: '循环条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
        ],
        defaultControlOutputs: ['body', 'completed'],
        defaultDataOutputs: [(name: 'index', type: PortType.number)],
      ),
      NodeKindSpec(
        kind: 'return',
        displayName: '返回',
        category: NodeCategory.flow,
        paramSchema: const [
          // 单返回值（向后兼容）：value 字段为旧式单返回值。
          // 多返回值（新）：values 为 map<name, ref>，按函数 outputs 名映射。
          ParamSpec(
            name: 'value',
            label: '返回值（单返回，向后兼容）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
          ParamSpec(
            name: 'values',
            label: '多返回值映射（按函数 outputs 名）',
            inputType: ParamInputType.keyValueMap,
            acceptsRef: true,
            expectedType: PortType.map,
          ),
        ],
        defaultControlOutputs: [],
        defaultDataOutputs: [],
      ),

      // ---- 函数调用（按目标函数签名动态生成端口）----
      NodeKindSpec(
        kind: 'function_call',
        displayName: '调用函数',
        category: NodeCategory.function,
        paramSchema: const [
          ParamSpec(
            name: 'targetFunctionId',
            label: '目标函数',
            inputType: ParamInputType.dropdown,
            options: [],
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.any)],
        // 按目标函数 outputs 动态生成命名数据输出端口。
        projectOutputs: _functionCallOutputs,
      ),

      // ---- 数据库 ----
      NodeKindSpec(
        kind: 'db_query_one',
        displayName: '查询单行',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'filter',
            label: '筛选条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'select',
            label: '选择列（逗号分隔）',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'row', type: PortType.map)],
      ),
      NodeKindSpec(
        kind: 'db_query_rows',
        displayName: '查询多行',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'filter',
            label: '筛选条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'orderBy',
            label: '排序（如 name ASC, age DESC）',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'limit',
            label: '限制行数',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
          ParamSpec(
            name: 'offset',
            label: '偏移量',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'rows', type: PortType.list),
          (name: 'count', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'db_aggregate',
        displayName: '聚合统计',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'func',
            label: '聚合函数',
            inputType: ParamInputType.dropdown,
            options: ['count', 'sum', 'avg', 'min', 'max'],
            defaultValue: 'count',
          ),
          ParamSpec(
            name: 'column',
            label: '列名（count 时可空）',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'filter',
            label: '筛选条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.number)],
      ),
      NodeKindSpec(
        kind: 'db_insert',
        displayName: '插入单行',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'data',
            label: '数据（列名 -> 值）',
            inputType: ParamInputType.keyValueMap,
            acceptsRef: true,
            expectedType: PortType.map,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'insertedId', type: PortType.number),
          (name: 'affected', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'db_insert_rows',
        displayName: '批量插入',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'rows',
            label: '行列表',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.list,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'insertedIds', type: PortType.list),
          (name: 'affected', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'db_update',
        displayName: '更新',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'filter',
            label: '筛选条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'data',
            label: '更新数据（列名 -> 值）',
            inputType: ParamInputType.keyValueMap,
            acceptsRef: true,
            expectedType: PortType.map,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'affected', type: PortType.number)],
      ),
      NodeKindSpec(
        kind: 'db_delete',
        displayName: '删除',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'filter',
            label: '筛选条件',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'affected', type: PortType.number)],
      ),
      NodeKindSpec(
        kind: 'db_create_table',
        displayName: '建表',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'columnsSpec',
            label: '列定义',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'success', type: PortType.boolean)],
      ),
      NodeKindSpec(
        kind: 'db_alter_table',
        displayName: '改表',
        category: NodeCategory.database,
        paramSchema: const [
          ParamSpec(
            name: 'table',
            label: '表名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'action',
            label: '操作',
            inputType: ParamInputType.dropdown,
            options: ['add', 'drop', 'rename'],
            defaultValue: 'add',
          ),
          ParamSpec(
            name: 'columnName',
            label: '列名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'newType',
            label: '新类型（可选）',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'success', type: PortType.boolean)],
      ),

      // ---- UI 控制 ----
      NodeKindSpec(
        kind: 'ui_set_text',
        displayName: '设置文本',
        category: NodeCategory.uiControl,
        paramSchema: const [
          ParamSpec(
            name: 'componentId',
            label: '目标组件',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'text',
            label: '文本',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
        ],
        defaultControlOutputs: ['next'],
      ),
      NodeKindSpec(
        kind: 'ui_set_visible',
        displayName: '设置可见性',
        category: NodeCategory.uiControl,
        paramSchema: const [
          ParamSpec(
            name: 'componentId',
            label: '目标组件',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'visible',
            label: '是否可见',
            inputType: ParamInputType.bool,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
        ],
        defaultControlOutputs: ['next'],
      ),
      NodeKindSpec(
        kind: 'ui_set_enabled',
        displayName: '设置启用状态',
        category: NodeCategory.uiControl,
        paramSchema: const [
          ParamSpec(
            name: 'componentId',
            label: '目标组件',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'enabled',
            label: '是否启用',
            inputType: ParamInputType.bool,
            acceptsRef: true,
            expectedType: PortType.boolean,
          ),
        ],
        defaultControlOutputs: ['next'],
      ),
      NodeKindSpec(
        kind: 'ui_set_prop',
        displayName: '设置属性',
        category: NodeCategory.uiControl,
        paramSchema: const [
          ParamSpec(
            name: 'componentId',
            label: '目标组件',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'propName',
            label: '属性名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'value',
            label: '属性值',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: ['next'],
      ),
      NodeKindSpec(
        kind: 'ui_navigate',
        displayName: '导航',
        category: NodeCategory.uiControl,
        paramSchema: const [
          ParamSpec(
            name: 'route',
            label: '路由',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
          ParamSpec(
            name: 'params',
            label: '参数',
            inputType: ParamInputType.keyValueMap,
            acceptsRef: true,
            expectedType: PortType.map,
          ),
        ],
        defaultControlOutputs: ['next'],
      ),
      NodeKindSpec(
        kind: 'ui_show_toast',
        displayName: '显示提示',
        category: NodeCategory.uiControl,
        paramSchema: const [
          ParamSpec(
            name: 'message',
            label: '消息内容',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'type',
            label: '类型',
            inputType: ParamInputType.dropdown,
            options: ['info', 'success', 'error', 'warning'],
            defaultValue: 'info',
          ),
        ],
        defaultControlOutputs: ['next'],
      ),

      // ---- 内置插件 ----
      NodeKindSpec(
        kind: 'plugin_openai',
        displayName: 'OpenAI 插件',
        category: NodeCategory.plugin,
        pluginId: 'llm_openai',
        paramSchema: const [
          ParamSpec(
            name: 'messages',
            label: '消息列表',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.list,
          ),
          ParamSpec(
            name: 'model',
            label: '模型',
            inputType: ParamInputType.text,
            defaultValue: 'gpt-4o-mini',
          ),
          ParamSpec(
            name: 'temperature',
            label: '温度',
            inputType: ParamInputType.number,
            defaultValue: 0.7,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'content', type: PortType.string),
          (name: 'usage_tokens', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'plugin_anthropic',
        displayName: 'Anthropic 插件',
        category: NodeCategory.plugin,
        pluginId: 'llm_anthropic',
        paramSchema: const [
          ParamSpec(
            name: 'messages',
            label: '消息列表',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.list,
          ),
          ParamSpec(
            name: 'model',
            label: '模型',
            inputType: ParamInputType.text,
            defaultValue: 'claude-3-5-sonnet-20240612',
          ),
          ParamSpec(
            name: 'maxTokens',
            label: '最大 token 数',
            inputType: ParamInputType.number,
            defaultValue: 1024,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'content', type: PortType.string),
          (name: 'usage_tokens', type: PortType.number),
        ],
      ),
    ];

    final map = <String, NodeKindSpec>{};
    for (final s in specs) {
      map[s.kind] = s;
    }
    return map;
  }

  // ---- 动态 outputs 生成器 ----

  static NodeOutputs _stringOpOutputs(Map<String, dynamic> params) {
    final op = params['operation']?.toString() ?? 'concat';
    // length 输出 number 类型 result；split 输出 list 类型 result。
    if (op == 'length') {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.number)],
      );
    }
    if (op == 'split') {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.list)],
      );
    }
    return const NodeOutputs(
      controlOutputs: [ControlOutput(name: 'next')],
      dataOutputs: [DataOutput(name: 'result', type: PortType.string)],
    );
  }

  static NodeOutputs _listOpOutputs(Map<String, dynamic> params) {
    final op = params['operation']?.toString() ?? 'size';
    // size / indexOf 返回 number；其余操作返回 any（可能为 list / element）。
    if (op == 'size' || op == 'indexOf') {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.number)],
      );
    }
    if (op == 'contains') {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.boolean)],
      );
    }
    return const NodeOutputs(
      controlOutputs: [ControlOutput(name: 'next')],
      dataOutputs: [DataOutput(name: 'result', type: PortType.any)],
    );
  }

  static NodeOutputs _dateOpOutputs(Map<String, dynamic> params) {
    final op = params['operation']?.toString() ?? 'now';
    // year/month/day 返回 number；now/parse/format 返回 number（时间戳）。
    if (op == 'year' || op == 'month' || op == 'day' || op == 'now' ||
        op == 'parse' || op == 'add' || op == 'diff') {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.number)],
      );
    }
    // format 返回 string。
    return const NodeOutputs(
      controlOutputs: [ControlOutput(name: 'next')],
      dataOutputs: [DataOutput(name: 'result', type: PortType.string)],
    );
  }

  static NodeOutputs _ifOutputs(Map<String, dynamic> params) {
    final rawCases = params['cases'];
    List<String> cases;
    if (rawCases is List) {
      cases = rawCases.map((e) => e.toString()).toList(growable: false);
    } else {
      cases = const ['true', 'false'];
    }
    if (cases.isEmpty) {
      cases = const ['true'];
    }
    final includeDefault = params['includeDefault'] == true;
    final outs = <ControlOutput>[
      for (final c in cases) ControlOutput(name: c),
    ];
    if (includeDefault) {
      outs.add(const ControlOutput(name: 'default'));
    }
    return NodeOutputs(controlOutputs: outs);
  }

  /// function_call 按目标函数签名动态生成命名数据输出端口。
  ///
  /// 查找目标函数 [FunctionDef.outputs]：
  /// - 有 outputs：按每个 FuncParam.name 生成命名数据输出（type 来自 FuncParam）。
  /// - 无 outputs：退化到单返回 `result:any`（向后兼容）。
  static NodeOutputs _functionCallOutputs(
    Map<String, dynamic> params,
    List<FunctionDef> functions,
  ) {
    final targetId = params['targetFunctionId']?.toString() ?? '';
    if (targetId.isEmpty) {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.any)],
      );
    }
    FunctionDef? target;
    for (final f in functions) {
      if (f.id == targetId) {
        target = f;
        break;
      }
    }
    if (target == null || target.outputs.isEmpty) {
      return const NodeOutputs(
        controlOutputs: [ControlOutput(name: 'next')],
        dataOutputs: [DataOutput(name: 'result', type: PortType.any)],
      );
    }
    return NodeOutputs(
      controlOutputs: const [ControlOutput(name: 'next')],
      dataOutputs: [
        for (final p in target.outputs) DataOutput(name: p.name, type: p.type),
      ],
    );
  }
}

/// 按 [ParamInputType] 推导默认值（[ParamSpec.defaultValue] 为 null 时）。
Object? _defaultFor(ParamSpec p) {
  if (p.defaultValue != null) return p.defaultValue;
  switch (p.inputType) {
    case ParamInputType.text:
      return p.acceptsRef ? null : '';
    case ParamInputType.number:
      return 0;
    case ParamInputType.bool:
      return false;
    case ParamInputType.dropdown:
      return p.options?.isNotEmpty == true ? p.options!.first : '';
    case ParamInputType.listStrings:
      return const <String>[];
    case ParamInputType.keyValueMap:
      return const <String, dynamic>{};
  }
}

/// 由规格与 params 解析最终 outputs。
///
/// 优先级：[NodeKindSpec.projectOutputs] > [NodeKindSpec.dynamicOutputs] >
/// 默认 outputs。
NodeOutputs resolveOutputs(NodeKindSpec spec, Map<String, dynamic> params) {
  return resolveOutputsInProject(spec, params, const []);
}

/// 由规格 + params + 项目函数列表解析最终 outputs。
///
/// 用于 function_call 节点按目标函数签名动态生成端口。
NodeOutputs resolveOutputsInProject(
  NodeKindSpec spec,
  Map<String, dynamic> params,
  List<FunctionDef> functions,
) {
  final projectFn = spec.projectOutputs;
  if (projectFn != null) {
    return projectFn(params, functions);
  }
  final dyn = spec.dynamicOutputs;
  if (dyn != null) {
    return dyn(params);
  }
  return NodeOutputs(
    controlOutputs: [
      for (final n in spec.defaultControlOutputs) ControlOutput(name: n),
    ],
    dataOutputs: [
      for (final d in spec.defaultDataOutputs)
        DataOutput(name: d.name, type: d.type),
    ],
  );
}

/// 根据 kind 创建默认 [Node]（生成 id、默认 params、解析默认 outputs）。
///
/// position 默认 (0, 0)，由调用方覆盖。未注册的 kind 退化为通用节点
/// （单 `next` 控制流输出），保证画布始终可用。
Node createNodeForKind(String kind) {
  final id = _uuid.v4();
  final spec = NodeKindRegistry.getSpec(kind);
  if (spec == null) {
    return Node(
      id: id,
      kind: kind,
      params: const {},
      position: const NodePosition(x: 0, y: 0),
      controlOutputs: const [ControlOutput(name: 'next')],
    );
  }
  final params = <String, dynamic>{
    for (final p in spec.paramSchema) p.name: _defaultFor(p),
  };
  final outputs = resolveOutputsInProject(spec, params, const []);
  return Node(
    id: id,
    kind: kind,
    params: params,
    position: const NodePosition(x: 0, y: 0),
    controlOutputs: outputs.controlOutputs,
    dataOutputs: outputs.dataOutputs,
  );
}

/// 按 kind + 项目函数列表创建默认 [Node]（function_call 节点支持
/// 按目标函数签名动态生成 outputs）。
Node createNodeForKindInProject(
  String kind,
  List<FunctionDef> functions,
) {
  final id = _uuid.v4();
  final spec = NodeKindRegistry.getSpec(kind);
  if (spec == null) {
    return Node(
      id: id,
      kind: kind,
      params: const {},
      position: const NodePosition(x: 0, y: 0),
      controlOutputs: const [ControlOutput(name: 'next')],
    );
  }
  final params = <String, dynamic>{
    for (final p in spec.paramSchema) p.name: _defaultFor(p),
  };
  final outputs = resolveOutputsInProject(spec, params, functions);
  return Node(
    id: id,
    kind: kind,
    params: params,
    position: const NodePosition(x: 0, y: 0),
    controlOutputs: outputs.controlOutputs,
    dataOutputs: outputs.dataOutputs,
  );
}

/// 按 [FuncParam] 列表构造 [Node.dataOutputs]（供 return 节点 / function_call
/// 节点在签名变更时同步 outputs 用）。
List<DataOutput> dataOutputsFromParams(List<FuncParam> params) {
  return [for (final p in params) DataOutput(name: p.name, type: p.type)];
}
