import 'package:flutter_test/flutter_test.dart';

import 'package:nodevisual_app_builder/data/models/entry.dart';
import 'package:nodevisual_app_builder/data/models/func_param.dart';
import 'package:nodevisual_app_builder/data/models/function_def.dart';
import 'package:nodevisual_app_builder/data/models/node.dart';
import 'package:nodevisual_app_builder/data/models/page.dart';
import 'package:nodevisual_app_builder/data/models/port.dart';
import 'package:nodevisual_app_builder/data/models/project.dart';
import 'package:nodevisual_app_builder/data/models/ui_tree.dart';
import 'package:nodevisual_app_builder/data/models/variable_ref.dart';

/// 验证既有项目数据在加载新代码时的迁移行为（T28）。
///
/// 覆盖：
/// - 无签名函数（inputs/outputs 为空）经 fromJson 加载后自动推导 inputs；
/// - 已有签名函数保持不变；
/// - 旧版 uiEvent entry ref（仅 componentId）与新格式 `componentId::eventName` 兼容；
/// - pageEvent entry 的 pageId / pageEvent 正确解析；
/// - VariableRef 四源 JSON 往返序列化；
/// - 旧式 Project（无 pages 字段）加载 pages 默认为空。
void main() {
  group('FunctionDef.migrateSignature', () {
    test('无签名 + 无 funcVars：保持空 inputs/outputs', () {
      final fn = FunctionDef.fromJson({
        'id': 'f1',
        'name': 'fn1',
        'funcVars': const [],
      });
      expect(fn.inputs, isEmpty);
      expect(fn.outputs, isEmpty);
    });

    test('无签名 + 含 isInput funcVars：自动推导 inputs', () {
      final fn = FunctionDef.fromJson({
        'id': 'f2',
        'name': 'fn2',
        'funcVars': [
          {'id': 'v1', 'name': 'userId', 'type': 'string', 'isInput': true},
          {'id': 'v2', 'name': 'limit', 'type': 'number', 'isInput': true},
          {'id': 'v3', 'name': 'cache', 'type': 'boolean'},
        ],
      });
      expect(fn.inputs.length, 2);
      expect(fn.inputs[0].name, 'userId');
      expect(fn.inputs[0].type, PortType.string);
      expect(fn.inputs[1].name, 'limit');
      expect(fn.inputs[1].type, PortType.number);
      // outputs 仍为空（沿用 return 节点的 value 单返回）。
      expect(fn.outputs, isEmpty);
    });

    test('已有签名：保持不变（不重新推导）', () {
      final fn = FunctionDef.fromJson({
        'id': 'f3',
        'name': 'fn3',
        'funcVars': [
          {'id': 'v1', 'name': 'old', 'type': 'string', 'isInput': true},
        ],
        'inputs': [
          {'name': 'newParam', 'type': 'number'},
        ],
        'outputs': [
          {'name': 'id', 'type': 'number'},
          {'name': 'name', 'type': 'string'},
        ],
      });
      expect(fn.inputs.length, 1);
      expect(fn.inputs.first.name, 'newParam');
      expect(fn.outputs.length, 2);
      expect(fn.outputs[0].name, 'id');
      expect(fn.outputs[1].name, 'name');
    });
  });

  group('FunctionEntry 解析', () {
    test('pageEvent ref 形如 <pageId>:<event> 正确解析', () {
      final entry = FunctionEntry(
        kind: EntryKind.pageEvent,
        ref: 'page-1:onLoad',
      );
      expect(entry.pageId, 'page-1');
      expect(entry.pageEvent, 'onLoad');
      expect(entry.matchesPageEvent('page-1', 'onLoad'), isTrue);
      expect(entry.matchesPageEvent('page-1', 'onDispose'), isFalse);
    });

    test('pageEvent ref 不合法时 pageId/pageEvent 返回 null', () {
      final entry = FunctionEntry(
        kind: EntryKind.pageEvent,
        ref: 'invalid-no-colon',
      );
      expect(entry.pageId, isNull);
      expect(entry.pageEvent, isNull);
    });

    test('pageEvent ref 含未知事件名：pageEvent 返回 null', () {
      final entry = FunctionEntry(
        kind: EntryKind.pageEvent,
        ref: 'page-1:onUnknown',
      );
      expect(entry.pageId, 'page-1');
      expect(entry.pageEvent, isNull);
    });

    test('uiEvent ref 形如 componentId::eventName（旧版仅 componentId 兼容）', () {
      // 旧版仅 componentId 形式（无 :: 后缀）不应崩溃。
      final oldEntry = FunctionEntry(
        kind: EntryKind.uiEvent,
        ref: 'comp-1',
      );
      expect(oldEntry.kind, EntryKind.uiEvent);

      // 新版 componentId::eventName。
      final newEntry = FunctionEntry(
        kind: EntryKind.uiEvent,
        ref: 'comp-1::onTap',
      );
      expect(newEntry.kind, EntryKind.uiEvent);
      expect(newEntry.ref, 'comp-1::onTap');
    });
  });

  group('VariableRef 四源序列化往返', () {
    test('upstream 源', () {
      final ref = VariableRef.upstream(
        nodeId: 'n1',
        outputName: 'result',
      );
      final json = ref.toJson();
      final restored = VariableRef.fromJson(json);
      expect(restored.source, VariableSource.upstream);
      expect(restored.nodeId, 'n1');
      expect(restored.outputName, 'result');
    });

    test('funcVar 源（当前函数变量）', () {
      final ref = VariableRef.funcVar(varId: 'v1');
      final json = ref.toJson();
      final restored = VariableRef.fromJson(json);
      expect(restored.source, VariableSource.funcVar);
      expect(restored.varId, 'v1');
      expect(restored.isPageFunc, isFalse);
    });

    test('funcVar 源（页面级函数 outputs，含时间线）', () {
      final ref = VariableRef.pageFunc(
        funcId: 'f1',
        outputName: 'userId',
      );
      final json = ref.toJson();
      final restored = VariableRef.fromJson(json);
      expect(restored.source, VariableSource.funcVar);
      expect(restored.funcId, 'f1');
      expect(restored.outputName, 'userId');
      expect(restored.isPageFunc, isTrue);
    });

    test('projVar 源', () {
      final ref = VariableRef.projVar(varId: 'pv1');
      final restored = VariableRef.fromJson(ref.toJson());
      expect(restored.source, VariableSource.projVar);
      expect(restored.varId, 'pv1');
    });

    test('component 源', () {
      final ref = VariableRef.component(
        componentId: 'list1',
        fieldName: 'item.name',
      );
      final restored = VariableRef.fromJson(ref.toJson());
      expect(restored.source, VariableSource.component);
      expect(restored.componentId, 'list1');
      expect(restored.fieldName, 'item.name');
    });
  });

  group('Project 迁移', () {
    test('旧式 IR（无 pages 字段）加载后 pages 默认为空', () {
      final project = Project.fromJson({
        'meta': {
          'id': 'p1',
          'name': '旧项目',
          'createdAt': '2026-01-01',
          'updatedAt': '2026-01-01',
          'version': '1',
        },
        'projectVars': const [],
        'functions': const [],
        'folders': const [],
        'db': const [],
        // 注意：故意不写 pages 字段
        'ui': const [],
      });
      expect(project.pages, isEmpty);
    });

    test('完整 Project 含 pages 序列化往返保持一致', () {
      final project = Project(
        meta: const ProjectMeta(
          id: 'p2',
          name: '测试',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          version: '1',
        ),
        pages: [
          Page(id: 'page-1', name: '首页', rootUiNodeId: 'root1'),
        ],
        functions: [
          FunctionDef(
            id: 'f1',
            name: 'onLoad',
            entry: FunctionEntry.pageEvent(
              pageId: 'page-1',
              event: PageEventName.onLoad,
            ),
            inputs: [
              FuncParam(name: 'q', type: PortType.string),
            ],
            outputs: [
              FuncParam(name: 'id', type: PortType.number),
            ],
          ),
        ],
      );
      final json = project.toJson();
      final restored = Project.fromJson(json);

      expect(restored.pages.length, 1);
      expect(restored.pages.first.id, 'page-1');
      expect(restored.pages.first.name, '首页');

      expect(restored.functions.length, 1);
      final fn = restored.functions.first;
      expect(fn.entry?.kind, EntryKind.pageEvent);
      expect(fn.entry?.pageId, 'page-1');
      expect(fn.entry?.pageEvent, PageEventName.onLoad);
      expect(fn.inputs.length, 1);
      expect(fn.inputs.first.name, 'q');
      expect(fn.outputs.length, 1);
      expect(fn.outputs.first.name, 'id');
      expect(fn.outputs.first.type, PortType.number);
    });

    test('完整 function_call 节点 + 显式签名序列化往返', () {
      // 模拟一个新格式 function_call 节点：选择 f1，并按签名传参。
      final node = Node(
        id: 'n1',
        kind: 'function_call',
        params: {
          'targetFunctionId': 'f1',
          'q': 'hello', // 入参字面值
        },
        position: const NodePosition(x: 0, y: 0),
        controlOutputs: const [ControlOutput(name: 'next')],
        dataOutputs: const [
          DataOutput(name: 'id', type: PortType.number),
        ],
      );
      final fn = FunctionDef(
        id: 'caller',
        name: 'caller',
        nodes: [node],
        inputs: const [FuncParam(name: 'q', type: PortType.string)],
        outputs: const [FuncParam(name: 'id', type: PortType.number)],
      );
      final restored = FunctionDef.fromJson(fn.toJson());

      expect(restored.nodes.length, 1);
      final r = restored.nodes.first;
      expect(r.kind, 'function_call');
      expect(r.params['targetFunctionId'], 'f1');
      expect(r.params['q'], 'hello');
      expect(r.dataOutputs.first.name, 'id');
      expect(r.dataOutputs.first.type, PortType.number);
      // 签名也往返保持。
      expect(restored.inputs.first.name, 'q');
      expect(restored.outputs.first.name, 'id');
    });
  });

  group('旧版节点降级处理', () {
    test('旧版 variable_get 节点加载后保留 kind 但不崩溃', () {
      // variable_get 已从节点调色板移除，但旧 IR 中的节点应能加载
      // （运行时执行器将其作为未知节点处理为 no-op）。
      final node = Node.fromJson({
        'id': 'n1',
        'kind': 'variable_get',
        'params': {'varName': 'v1'},
        'position': {'x': 10, 'y': 20},
      });
      expect(node.kind, 'variable_get');
      expect(node.params['varName'], 'v1');
      expect(node.position.x, 10);
      expect(node.position.y, 20);
    });

    test('旧版 variable_get 节点嵌入函数后整体加载不崩溃', () {
      // 模拟一个旧 IR 函数：含 variable_get 节点 + 无 inputs/outputs 签名。
      final fn = FunctionDef.fromJson({
        'id': 'old-fn',
        'name': 'oldFn',
        'nodes': [
          {
            'id': 'n1',
            'kind': 'variable_get',
            'params': {'varName': 'v1'},
            'position': {'x': 0, 'y': 0},
          },
          {
            'id': 'n2',
            'kind': 'variable_set',
            'params': {'varName': 'v2', 'value': 'hello'},
            'position': {'x': 100, 'y': 0},
          },
        ],
        'controlEdges': [
          {'fromNode': 'n1', 'fromPort': 'next', 'toNode': 'n2'},
        ],
      });
      expect(fn.nodes.length, 2);
      expect(fn.nodes[0].kind, 'variable_get');
      expect(fn.nodes[1].kind, 'variable_set');
      // 旧函数无签名 → inputs/outputs 为空（不崩溃）。
      expect(fn.inputs, isEmpty);
      expect(fn.outputs, isEmpty);
    });

    test('未知节点 kind 加载不崩溃', () {
      // 完全未知的节点 kind 应能加载（运行时降级为 no-op + warn）。
      final node = Node.fromJson({
        'id': 'n1',
        'kind': 'some_future_node_kind',
        'params': {'foo': 'bar'},
        'position': {'x': 0, 'y': 0},
      });
      expect(node.kind, 'some_future_node_kind');
      expect(node.params['foo'], 'bar');
    });
  });

  group('旧版 Binding 升级', () {
    test('旧版 Binding（仅 ref，无 loadingStrategy）加载后默认 typeDefault', () {
      // 旧 Binding 结构：{ref: {source: upstream, nodeId, outputName}}
      // 新代码加载后应补默认 loadingStrategy = typeDefault，placeholderText = null。
      final binding = Binding.fromJson({
        'ref': {
          'source': 'upstream',
          'nodeId': 'n1',
          'outputName': 'result',
        },
      });
      expect(binding.ref.source, VariableSource.upstream);
      expect(binding.ref.nodeId, 'n1');
      expect(binding.ref.outputName, 'result');
      expect(binding.loadingStrategy, LoadingStrategy.typeDefault);
      expect(binding.placeholderText, isNull);
    });

    test('新版 Binding 含 placeholder 策略往返一致', () {
      final binding = const Binding(
        ref: VariableRef.pageFunc(funcId: 'f1', outputName: 'userId'),
        loadingStrategy: LoadingStrategy.placeholder,
        placeholderText: '加载中...',
      );
      final json = binding.toJson();
      // 显式序列化 loadingStrategy / placeholderText。
      expect(json['loadingStrategy'], 'placeholder');
      expect(json['placeholderText'], '加载中...');

      final restored = Binding.fromJson(json);
      expect(restored.loadingStrategy, LoadingStrategy.placeholder);
      expect(restored.placeholderText, '加载中...');
      expect(restored.ref.isPageFunc, isTrue);
      expect(restored.ref.funcId, 'f1');
      expect(restored.ref.outputName, 'userId');
    });

    test('旧版 UiNode（无 pageId）加载后 pageId 为 null', () {
      // 旧 IR UiNode 没有 pageId 字段，新代码加载应默认为 null。
      final node = UiNode.fromJson({
        'id': 'ui-1',
        'type': 'Text',
        'props': {'text': 'hello'},
      });
      expect(node.id, 'ui-1');
      expect(node.type, 'Text');
      expect(node.pageId, isNull);
      expect(node.props['text'], 'hello');
    });

    test('旧版 UiNode 含旧版 Binding 加载后默认策略生效', () {
      // 旧 IR 的 UiNode.bindings 内每个 Binding 仅含 ref，新代码加载后
      // loadingStrategy 应补为 typeDefault。
      final node = UiNode.fromJson({
        'id': 'ui-2',
        'type': 'Text',
        'bindings': {
          'text': {
            'ref': {
              'source': 'projVar',
              'varId': 'pv1',
            },
          },
        },
      });
      expect(node.bindings.length, 1);
      final b = node.bindings['text']!;
      expect(b.ref.source, VariableSource.projVar);
      expect(b.ref.varId, 'pv1');
      expect(b.loadingStrategy, LoadingStrategy.typeDefault);
    });
  });

  group('旧版 VariableRef 兼容', () {
    test('旧版 VariableRef（无 component 源）往返不变', () {
      // 旧 IR 的 VariableRef 仅有 upstream/funcVar/projVar 三源，
      // 新代码加载后 source 字段保持原值。
      final oldRef = VariableRef.fromJson({
        'source': 'upstream',
        'nodeId': 'n1',
        'outputName': 'value',
      });
      expect(oldRef.source, VariableSource.upstream);
      expect(oldRef.componentId, isNull);
      expect(oldRef.fieldName, isNull);
      expect(oldRef.funcId, isNull);
    });

    test('未知 source 字符串降级为 upstream', () {
      // 未来可能新增的 source 在旧客户端加载时应安全降级。
      final ref = VariableRef.fromJson({
        'source': 'some_future_source',
        'varId': 'v1',
      });
      expect(ref.source, VariableSource.upstream);
    });

    test('旧版 funcVar 引用（无 funcId）保持 isPageFunc=false', () {
      // 旧 IR 的 funcVar 引用仅含 varId，不指向页面级函数 outputs。
      final ref = VariableRef.fromJson({
        'source': 'funcVar',
        'varId': 'v1',
      });
      expect(ref.source, VariableSource.funcVar);
      expect(ref.varId, 'v1');
      expect(ref.funcId, isNull);
      expect(ref.isPageFunc, isFalse);
    });
  });
}
