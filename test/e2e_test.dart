import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nodevisual_app_builder/data/models/entry.dart';
import 'package:nodevisual_app_builder/data/models/func_param.dart';
import 'package:nodevisual_app_builder/data/models/function_def.dart';
import 'package:nodevisual_app_builder/data/models/node.dart';
import 'package:nodevisual_app_builder/data/models/page.dart';
import 'package:nodevisual_app_builder/data/models/port.dart';
import 'package:nodevisual_app_builder/data/models/project.dart';
import 'package:nodevisual_app_builder/data/models/project_variable.dart';
import 'package:nodevisual_app_builder/data/models/ui_tree.dart';
import 'package:nodevisual_app_builder/data/models/variable_ref.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/build_manifest.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/builders/web_builder.dart';

/// 端到端验证（T29）。
///
/// 验证三类集成场景的 IR 构造、序列化与 Web 运行时产物：
/// 1. 列表渲染数据：页面 onLoad 函数返回 list，list_vertical 绑定 items，
///    子 card 引用 #item.name；
/// 2. 滑块联动文本：slider 提供 value 组件上下文，子 text 引用 #value；
/// 3. 页面加载函数返回值显示：text 引用 #pageFunc:<funcId>.<outputName>。
///
/// 由于沙箱环境无 flutter/dart 运行时，测试聚焦于：
/// - IR 结构能正确构造并往返序列化；
/// - WebBuilder 产物 runtime.js 含渲染所需的关键标识与逻辑。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nv_e2e_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  BuildManifest buildManifest(String target, Project project) {
    return BuildManifest(
      target: target,
      project: ProjectInfo(
        id: project.meta.id,
        name: project.meta.name,
        irVersion: project.meta.version,
      ),
      build: const BuildInfo(
        builderVersion: '0.1.0',
        builtAt: '2026-01-01T00:00:00',
        builtOn: 'test',
      ),
      runtime: const RuntimeInfo(),
    );
  }

  Future<String> buildWebRuntime(Project project) async {
    final builder = WebBuilder();
    final artifact = await builder.build(
      project: project,
      outDir: tempDir,
      manifest: buildManifest('web', project),
      onProgress: (_) {},
    );
    final bytes = artifact.file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final runtimeFile = archive.files.firstWhere((f) => f.name == 'runtime.js');
    return utf8.decode(runtimeFile.content as List<int>);
  }

  group('场景 1：列表渲染数据', () {
    test('页面 onLoad 函数返回 list → list_vertical 绑定 items → 子 card 引用 #item.name', () async {
      // IR 构造：
      // - 函数 onLoad：return 节点返回 list literal
      // - list_vertical：items 绑定到 #pageFunc:onLoad.items
      // - 子 card → text：content 绑定到 #component:<listId>.item.name
      final returnNode = Node(
        id: 'ret-1',
        kind: 'return',
        params: {
          'values': {
            'items': [
              {'name': 'Alice', 'age': 30},
              {'name': 'Bob', 'age': 25},
            ],
          },
        },
        position: const NodePosition(x: 0, y: 0),
      );
      final onLoadFn = FunctionDef(
        id: 'fn-onload',
        name: 'onLoad',
        entry: const FunctionEntry(
          kind: EntryKind.pageEvent,
          ref: 'page-1:onLoad',
        ),
        nodes: [returnNode],
        outputs: const [FuncParam(name: 'items', type: PortType.list)],
      );
      // 子 card 内含 text，text 的 content 绑定到 component 源 item.name。
      final textInCard = UiNode(
        id: 'text-1',
        type: 'Text',
        pageId: 'page-1',
        bindings: {
          'text': Binding(
            ref: const VariableRef.component(
              componentId: 'list-1',
              fieldName: 'item.name',
            ),
          ),
        },
      );
      final cardTemplate = UiNode(
        id: 'card-tpl',
        type: 'card',
        pageId: 'page-1',
        children: [textInCard],
      );
      final listNode = UiNode(
        id: 'list-1',
        type: 'list_vertical',
        pageId: 'page-1',
        bindings: {
          'items': Binding(
            ref: const VariableRef.pageFunc(
              funcId: 'fn-onload',
              outputName: 'items',
            ),
          ),
        },
        children: [cardTemplate],
      );
      final rootUi = UiNode(
        id: 'root-1',
        type: 'Column',
        pageId: 'page-1',
        children: [listNode],
      );
      // Page 作为特殊 UiNode（type='page'），其 children 为该页面的 UI 根节点树。
      final pageNode = createPageNode(
        id: 'page-1',
        name: '首页',
        isHome: true,
        children: [rootUi],
      );

      final project = Project(
        meta: const ProjectMeta(
          id: 'p-e2e-1',
          name: '列表渲染',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          version: '1',
        ),
        functions: [onLoadFn],
        ui: [pageNode],
      );

      // 序列化往返验证
      final json = project.toJson();
      final restored = Project.fromJson(json);
      expect(restored.ui.first.id, 'page-1');
      expect(restored.ui.first.isPage, isTrue);
      expect(restored.functions.first.id, 'fn-onload');
      expect(restored.functions.first.outputs.first.name, 'items');
      // ui.first 是 Page 节点；其 children.first 才是 UI 根（Column）。
      expect(restored.ui.first.children.first.type, 'Column');
      expect(
        restored.ui.first.children.first.children.first.type,
        'list_vertical',
      );

      final listBinding = restored
          .ui.first.children.first.children.first.bindings['items']!;
      expect(listBinding.ref.isPageFunc, isTrue);
      expect(listBinding.ref.funcId, 'fn-onload');
      expect(listBinding.ref.outputName, 'items');

      final textBinding = restored.ui.first.children.first.children.first
          .children.first.children.first.bindings['text']!;
      expect(textBinding.ref.source, VariableSource.component);
      expect(textBinding.ref.componentId, 'list-1');
      expect(textBinding.ref.fieldName, 'item.name');

      // WebBuilder 产物验证：runtime.js 含列表渲染与组件上下文逻辑
      final runtime = await buildWebRuntime(project);
      expect(runtime, contains('list_vertical'));
      expect(runtime, contains('renderListChildren'));
      expect(runtime, contains('COMPONENT_CONTEXT_STACK'));
      expect(runtime, contains('readComponentField'));
      expect(runtime, contains('item.name'));
      expect(runtime, contains('PAGE_FUNC_OUTPUTS'));
      expect(runtime, contains('LIST_REGISTRY'));
    });
  });

  group('场景 2：滑块联动文本', () {
    test('slider 提供 value 组件上下文 → 子 text 引用 #value', () async {
      // IR 构造：
      // - slider：作为容器，提供 value 上下文
      // - 子 text：content 绑定到 #component:<sliderId>.value
      final textBelowSlider = UiNode(
        id: 'text-2',
        type: 'Text',
        pageId: 'page-2',
        bindings: {
          'text': Binding(
            ref: const VariableRef.component(
              componentId: 'slider-1',
              fieldName: 'value',
            ),
          ),
        },
      );
      final sliderNode = UiNode(
        id: 'slider-1',
        type: 'slider',
        pageId: 'page-2',
        props: {'min': 0, 'max': 100, 'value': 50},
        children: [textBelowSlider],
      );
      final rootUi = UiNode(
        id: 'root-2',
        type: 'Column',
        pageId: 'page-2',
        children: [sliderNode],
      );
      final pageNode = createPageNode(
        id: 'page-2',
        name: '滑块页',
        isHome: true,
        children: [rootUi],
      );

      final project = Project(
        meta: const ProjectMeta(
          id: 'p-e2e-2',
          name: '滑块联动',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          version: '1',
        ),
        ui: [pageNode],
      );

      // 序列化往返验证
      final restored = Project.fromJson(project.toJson());
      // ui.first 是 Page 节点；其 children.first 是 UI 根（Column），
      // 再下一层才是 slider。
      final slider = restored.ui.first.children.first.children.first;
      expect(slider.type, 'slider');
      expect(slider.props['value'], 50);

      final textBinding = slider.children.first.bindings['text']!;
      expect(textBinding.ref.source, VariableSource.component);
      expect(textBinding.ref.componentId, 'slider-1');
      expect(textBinding.ref.fieldName, 'value');

      // WebBuilder 产物验证：runtime.js 含 slider 渲染与 value 上下文注入
      final runtime = await buildWebRuntime(project);
      expect(runtime, contains('slider'));
      expect(runtime, contains('_componentContext'));
      expect(runtime, contains('pushComponentContext'));
      expect(runtime, contains('readComponentField'));
    });
  });

  group('场景 3：页面加载函数返回值显示', () {
    test('页面 onLoad 函数返回值 → text 引用 #pageFunc:<funcId>.<outputName>', () async {
      // IR 构造：
      // - 函数 onLoad：return 节点返回 { userId: 'u-123' }
      // - text：content 绑定到 #pageFunc:fn-onload.userId
      final returnNode = Node(
        id: 'ret-2',
        kind: 'return',
        params: {
          'values': {
            'userId': 'u-123',
          },
        },
        position: const NodePosition(x: 0, y: 0),
      );
      final onLoadFn = FunctionDef(
        id: 'fn-onload-3',
        name: 'fetchUser',
        entry: const FunctionEntry(
          kind: EntryKind.pageEvent,
          ref: 'page-3:onLoad',
        ),
        nodes: [returnNode],
        outputs: const [FuncParam(name: 'userId', type: PortType.string)],
      );
      final page = createPageNode(
        id: 'page-3',
        name: '用户页',
        isHome: true,
      );

      final textNode = UiNode(
        id: 'text-3',
        type: 'Text',
        pageId: 'page-3',
        bindings: {
          'text': Binding(
            ref: const VariableRef.pageFunc(
              funcId: 'fn-onload-3',
              outputName: 'userId',
            ),
            loadingStrategy: LoadingStrategy.placeholder,
            placeholderText: '加载中...',
          ),
        },
      );
      final rootUi = UiNode(
        id: 'root-3',
        type: 'Column',
        pageId: 'page-3',
        children: [textNode],
      );
      // 将 UI 根挂到 Page 节点下。
      final pageNode = page.copyWith(children: [rootUi]);

      final project = Project(
        meta: const ProjectMeta(
          id: 'p-e2e-3',
          name: '函数返回值',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          version: '1',
        ),
        functions: [onLoadFn],
        ui: [pageNode],
      );

      // 序列化往返验证
      final restored = Project.fromJson(project.toJson());
      final fn = restored.functions.first;
      expect(fn.entry?.kind, EntryKind.pageEvent);
      expect(fn.entry?.pageId, 'page-3');
      expect(fn.entry?.pageEvent, PageEventName.onLoad);
      expect(fn.outputs.first.name, 'userId');

      // ui.first 是 Page 节点；其 children.first 是 UI 根（Column），
      // 再下一层才是 text。
      final textBinding = restored
          .ui.first.children.first.children.first.bindings['text']!;
      expect(textBinding.ref.isPageFunc, isTrue);
      expect(textBinding.ref.funcId, 'fn-onload-3');
      expect(textBinding.ref.outputName, 'userId');
      expect(textBinding.loadingStrategy, LoadingStrategy.placeholder);
      expect(textBinding.placeholderText, '加载中...');

      // WebBuilder 产物验证：runtime.js 含页面函数触发与 outputs 缓存逻辑
      final runtime = await buildWebRuntime(project);
      expect(runtime, contains('PAGE_FUNC_OUTPUTS'));
      expect(runtime, contains('triggerPageFunction'));
      expect(runtime, contains('refreshBindingsForPageFunc'));
      expect(runtime, contains('isPageFunc'));
      expect(runtime, contains('pageEvent'));
    });
  });

  group('场景 4：综合 — 项目变量绑定', () {
    test('text 引用 #projVar → 运行时读项目变量默认值', () async {
      // 验证项目变量作为第四源的基础引用路径。
      final projVar = ProjectVariable(
        id: 'pv-greeting',
        name: 'greeting',
        type: PortType.string,
        defaultValue: 'Hello, NodeVisual!',
      );
      final textNode = UiNode(
        id: 'text-4',
        type: 'Text',
        pageId: 'page-4',
        bindings: {
          'text': Binding(
            ref: const VariableRef.projVar(varId: 'pv-greeting'),
          ),
        },
      );
      final rootUi = UiNode(
        id: 'root-4',
        type: 'Column',
        pageId: 'page-4',
        children: [textNode],
      );
      final pageNode = createPageNode(
        id: 'page-4',
        name: '项目变量页',
        isHome: true,
        children: [rootUi],
      );
      final project = Project(
        meta: const ProjectMeta(
          id: 'p-e2e-4',
          name: '项目变量',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          version: '1',
        ),
        projectVars: [projVar],
        ui: [pageNode],
      );

      final restored = Project.fromJson(project.toJson());
      expect(restored.projectVars.first.id, 'pv-greeting');
      expect(restored.projectVars.first.defaultValue, 'Hello, NodeVisual!');

      // ui.first 是 Page 节点；其 children.first 是 UI 根（Column），
      // 再下一层才是 text。
      final textBinding = restored
          .ui.first.children.first.children.first.bindings['text']!;
      expect(textBinding.ref.source, VariableSource.projVar);
      expect(textBinding.ref.varId, 'pv-greeting');

      final runtime = await buildWebRuntime(project);
      expect(runtime, contains('projVar'));
      expect(runtime, contains('projectVars'));
    });
  });

  group('场景 5：UI 事件触发函数', () {
    test('button onTap 绑定函数 → 运行时含事件触发逻辑', () async {
      // 验证 UI 事件入口（uiEvent）的端到端 IR 与运行时。
      final buttonFn = FunctionDef(
        id: 'fn-tap',
        name: 'onTapHandler',
        entry: const FunctionEntry(
          kind: EntryKind.uiEvent,
          ref: 'btn-1::onTap',
        ),
        nodes: [
          Node(
            id: 'ret-3',
            kind: 'return',
            params: {'value': null},
            position: const NodePosition(x: 0, y: 0),
          ),
        ],
      );
      final buttonNode = UiNode(
        id: 'btn-1',
        type: 'ElevatedButton',
        pageId: 'page-5',
        props: {'label': '点我', 'onTap': 'fn-tap'},
      );
      final rootUi = UiNode(
        id: 'root-5',
        type: 'Column',
        pageId: 'page-5',
        children: [buttonNode],
      );
      final pageNode = createPageNode(
        id: 'page-5',
        name: '事件触发页',
        isHome: true,
        children: [rootUi],
      );
      final project = Project(
        meta: const ProjectMeta(
          id: 'p-e2e-5',
          name: '事件触发',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          version: '1',
        ),
        functions: [buttonFn],
        ui: [pageNode],
      );

      final restored = Project.fromJson(project.toJson());
      final fn = restored.functions.first;
      expect(fn.entry?.kind, EntryKind.uiEvent);
      expect(fn.entry?.ref, 'btn-1::onTap');

      final runtime = await buildWebRuntime(project);
      expect(runtime, contains('triggerFunction'));
      expect(runtime, contains('onTap'));
    });
  });
}
