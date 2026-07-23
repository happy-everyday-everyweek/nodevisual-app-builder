import 'package:uuid/uuid.dart';

import '../../data/models/node.dart';
import '../../data/models/port.dart';

const Uuid _uuid = Uuid();

/// 节点种类大类（用于面板分组与检索）。
enum NodeCategory {
  /// 变量节点。
  variable,

  /// 运算节点。
  operation,

  /// 流程控制节点。
  flow,

  /// 数据库节点。
  database,

  /// 函数调用节点。
  function,

  /// 插件节点。
  plugin,
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

  /// 关联的插件 id（仅 plugin 类节点有效，如 `llm_openai`）。
  ///
  /// 用于节点编辑页打开插件配置面板（[PluginConfigSheet]）。null 表示该
  /// kind 不关联插件。Task 9 的 plugin_* kind 通过此字段与 [PluginRegistry]
  /// 中的插件条目关联。
  final String? pluginId;

  const NodeKindSpec({
    required this.kind,
    required this.displayName,
    required this.category,
    this.paramSchema = const [],
    this.defaultControlOutputs = const [],
    this.defaultDataOutputs = const [],
    this.dynamicOutputs,
    this.pluginId,
  });
}

/// 所有节点 kind 的注册表。
///
/// 提供 [getSpec] 查询单个 kind 规格，[allKinds] 枚举全部已注册规格。
/// Task 5 注册基础节点（变量 / 运算 / 流程控制 / 函数调用 / return）；
/// db_* 与 plugin 由 Task 6 / 9 扩展，当前未在注册表中登记。
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
      // ---- 变量 ----
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
      NodeKindSpec(
        kind: 'variable_get',
        displayName: '读取变量',
        category: NodeCategory.variable,
        paramSchema: const [
          ParamSpec(
            name: 'varName',
            label: '变量名',
            inputType: ParamInputType.text,
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'value', type: PortType.any)],
      ),

      // ---- 运算 ----
      NodeKindSpec(
        kind: 'arithmetic',
        displayName: '算术',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operator',
            label: '运算符',
            inputType: ParamInputType.dropdown,
            options: ['+', '-', '*', '/', '%'],
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
        kind: 'logic',
        displayName: '逻辑',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operator',
            label: '运算符',
            inputType: ParamInputType.dropdown,
            options: ['and', 'or', 'not'],
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
        kind: 'string_op',
        displayName: '字符串',
        category: NodeCategory.operation,
        paramSchema: const [
          ParamSpec(
            name: 'operation',
            label: '操作',
            inputType: ParamInputType.dropdown,
            options: ['concat', 'substring', 'upper', 'lower', 'length'],
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
            label: '字符串 b（可选）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.string)],
        // operation == 'length' 输出 length:number，其余输出 result:string。
        dynamicOutputs: _stringOpOutputs,
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
        // 控制流输出由 dynamicOutputs 按 cases 生成。
        defaultControlOutputs: [],
        defaultDataOutputs: [],
        dynamicOutputs: _ifOutputs,
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

      // ---- 函数调用 / return ----
      NodeKindSpec(
        kind: 'function_call',
        displayName: '调用函数',
        category: NodeCategory.function,
        paramSchema: const [
          ParamSpec(
            name: 'targetFunctionId',
            label: '目标函数',
            inputType: ParamInputType.dropdown,
            // 运行时由节点编辑页按项目函数列表填充。
            options: [],
            defaultValue: '',
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [(name: 'result', type: PortType.any)],
      ),
      NodeKindSpec(
        kind: 'return',
        displayName: '返回',
        category: NodeCategory.flow,
        paramSchema: const [
          ParamSpec(
            name: 'value',
            label: '返回值',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.any,
          ),
        ],
        defaultControlOutputs: [],
        defaultDataOutputs: [],
      ),

      // ---- 数据库 ----
      // table 参数采用 text 输入（v1 最小侵入方案，不改 node_editor_screen；
      // 运行时由用户手动输入表名，项目表名可在数据库段查看）。
      NodeKindSpec(
        kind: 'db_query',
        displayName: '数据库查询',
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
            label: '筛选条件（可选 WHERE）',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.string,
          ),
          ParamSpec(
            name: 'limit',
            label: '限制行数',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.number,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'rows', type: PortType.map),
          (name: 'count', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'db_insert',
        displayName: '数据库插入',
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
            label: '数据',
            inputType: ParamInputType.text,
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
        kind: 'db_update',
        displayName: '数据库更新',
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
            label: '数据',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: PortType.map,
          ),
        ],
        defaultControlOutputs: ['next'],
        defaultDataOutputs: [
          (name: 'affected', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'db_delete',
        displayName: '数据库删除',
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
        defaultDataOutputs: [
          (name: 'affected', type: PortType.number),
        ],
      ),
      NodeKindSpec(
        kind: 'db_create_table',
        displayName: '数据库建表',
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
        defaultDataOutputs: [
          (name: 'success', type: PortType.boolean),
        ],
      ),
      NodeKindSpec(
        kind: 'db_alter_table',
        displayName: '数据库改表',
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
        defaultDataOutputs: [
          (name: 'success', type: PortType.boolean),
        ],
      ),

      // ---- 插件（Task 9 / 10）----
      // plugin_<name> kind 通过 pluginId 关联 [PluginRegistry] 中的插件条目。
      // 参数区上方在节点编辑页展示"插件配置"入口（[PluginConfigSheet]）。
      // messages 参数支持 # 引用（期望 list 类型）；model / temperature / maxTokens
      // 为字面值。数据输出 content(string) + usage_tokens(number) 与 LLM executor
      // 返回的 outputs map 对齐。
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
    final data = op == 'length'
        ? const [DataOutput(name: 'length', type: PortType.number)]
        : const [DataOutput(name: 'result', type: PortType.string)];
    return NodeOutputs(
      controlOutputs: const [ControlOutput(name: 'next')],
      dataOutputs: data,
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
}

/// 按 [ParamInputType] 推导默认值（[ParamSpec.defaultValue] 为 null 时）。
Object? _defaultFor(ParamSpec p) {
  if (p.defaultValue != null) return p.defaultValue;
  switch (p.inputType) {
    case ParamInputType.text:
      // acceptsRef 的文本参数默认 null（表示尚未引用 / 赋值）。
      return p.acceptsRef ? null : '';
    case ParamInputType.number:
      return 0;
    case ParamInputType.bool:
      return false;
    case ParamInputType.dropdown:
      return p.options?.isNotEmpty == true ? p.options!.first : '';
    case ParamInputType.listStrings:
      return const <String>[];
  }
}

/// 由规格与 params 解析最终 outputs。
///
/// 若 spec 配置了 [NodeKindSpec.dynamicOutputs]，则调用其生成；
/// 否则使用 [NodeKindSpec.defaultControlOutputs] /
/// [NodeKindSpec.defaultDataOutputs]。
NodeOutputs resolveOutputs(NodeKindSpec spec, Map<String, dynamic> params) {
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
  final outputs = resolveOutputs(spec, params);
  return Node(
    id: id,
    kind: kind,
    params: params,
    position: const NodePosition(x: 0, y: 0),
    controlOutputs: outputs.controlOutputs,
    dataOutputs: outputs.dataOutputs,
  );
}
