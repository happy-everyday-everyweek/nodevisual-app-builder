import '../../data/models/port.dart';
import '../../data/models/ui_tree.dart';
import '../../data/models/variable_ref.dart';
import 'runtime_scope.dart';

/// UI 绑定解析结果。
///
/// 由 [BindingResolver.resolve] 返回，描述 UI 属性最终应渲染的值与状态。
class BindingResolveResult {
  /// 解析后的值（已应用加载态策略）。
  ///
  /// - [ready] == true：实际值。
  /// - [ready] == false：按 [LoadingStrategy] 返回的占位（类型默认值 /
  ///   占位文字 / 空串）。
  final Object? value;

  /// 引用是否已就绪（底层值真实可用）。
  ///
  /// false 表示触发了加载态策略（函数未完成 / 组件上下文未注入）。
  /// UI 可据此显示加载指示器或灰显，但渲染仍使用 [value]。
  final bool ready;

  /// 引用是否应"不渲染"（[LoadingStrategy.blank] 且未就绪时）。
  ///
  /// true 时调用方应跳过该属性渲染（如图片不显示、文本不渲染）。
  final bool blank;

  const BindingResolveResult({
    this.value,
    this.ready = true,
    this.blank = false,
  });

  /// 已就绪：直接返回实际值。
  const BindingResolveResult.ready(Object? value)
      : value = value,
        ready = true,
        blank = false;

  /// 未就绪 + 占位：返回占位值，ready=false。
  const BindingResolveResult.placeholder(Object? value)
      : value = value,
        ready = false,
        blank = false;

  /// 未就绪 + 空白：调用方应跳过渲染。
  const BindingResolveResult.blank()
      : value = null,
        ready = false,
        blank = true;
}

/// UI 绑定解析器（T14 时间线规则）。
///
/// 在 UI 渲染期把 [Binding] 解析为最终值，按"时间线规则"处理未就绪引用：
///
/// - **上游节点输出**：从 [RuntimeScope.nodeOutputs] 取值；缺失视为未就绪。
/// - **项目变量**：从 [RuntimeScope.projVars] 取值；项目变量在应用启动时
///   初始化，通常已就绪（缺失视为未就绪）。
/// - **当前函数局部变量**：从 [RuntimeScope.funcVars] 取值（函数执行中）。
/// - **页面级函数 outputs**：按 [PageFuncEntry.state] 状态机：
///   - `done` → 返回缓存 output 值（就绪）；
///   - `running` / `idle` → 未就绪，按 [LoadingStrategy] 返回占位；
///   - `error` → 未就绪，按 [LoadingStrategy] 返回占位（DevTools 显示错误）。
/// - **组件上下文变量**：从 [RuntimeScope.componentContexts] 取值；
///   容器未渲染对应项时未就绪，按 [LoadingStrategy] 返回占位。
///
/// 加载态策略（[LoadingStrategy]）：
/// - [LoadingStrategy.typeDefault]：按 [expectedType] 返回类型默认值
///   （number→0, string→'', list→[], map→{}, bool→false, any→null）。
/// - [LoadingStrategy.placeholder]：返回 [Binding.placeholderText]。
/// - [LoadingStrategy.blank]：返回 [BindingResolveResult.blank]，
///   调用方应跳过该属性渲染。
class BindingResolver {
  BindingResolver._();

  /// 解析 [binding] 为最终渲染值。
  ///
  /// [scope] 为当前运行时作用域（UI 渲染期共享）。
  /// [expectedType] 用于 [LoadingStrategy.typeDefault] 推导默认值；
  /// 为 null 视为 [PortType.any]（默认值 null）。
  static BindingResolveResult resolve(
    Binding binding,
    RuntimeScope scope, {
    PortType? expectedType,
  }) {
    final ref = binding.ref;
    final strategy = binding.loadingStrategy;
    switch (ref.source) {
      case VariableSource.upstream:
        final v = _resolveUpstream(ref, scope);
        if (v == null) {
          return _applyStrategy(strategy, expectedType, binding.placeholderText);
        }
        return BindingResolveResult.ready(v);
      case VariableSource.projVar:
        final v = _resolveProjVar(ref, scope);
        if (v == null && !_projVarExists(ref, scope)) {
          return _applyStrategy(strategy, expectedType, binding.placeholderText);
        }
        return BindingResolveResult.ready(v);
      case VariableSource.funcVar:
        if (ref.isPageFunc) {
          return _resolvePageFunc(ref, scope, strategy, expectedType,
              binding.placeholderText);
        }
        // 当前函数局部变量：执行中函数的 funcVars 总是就绪（缺失视为 null 值）。
        if (ref.varId == null) {
          return _applyStrategy(strategy, expectedType, binding.placeholderText);
        }
        return BindingResolveResult.ready(scope.getFuncVar(ref.varId!));
      case VariableSource.component:
        if (ref.componentId == null || ref.fieldName == null) {
          return _applyStrategy(strategy, expectedType, binding.placeholderText);
        }
        final ctx = scope.getComponentContext(ref.componentId!);
        if (ctx == null) {
          // 容器未注入上下文（未渲染对应项）→ 未就绪。
          return _applyStrategy(strategy, expectedType, binding.placeholderText);
        }
        return BindingResolveResult.ready(ctx.get(ref.fieldName!));
    }
  }

  /// 解析上游节点输出。
  static Object? _resolveUpstream(VariableRef ref, RuntimeScope scope) {
    if (ref.nodeId == null || ref.outputName == null) return null;
    return scope.getNodeOutput(ref.nodeId!, ref.outputName!);
  }

  /// 解析项目变量。
  static Object? _resolveProjVar(VariableRef ref, RuntimeScope scope) {
    if (ref.varId == null) return null;
    return scope.getProjVar(ref.varId!);
  }

  /// 项目变量是否已初始化（区分"值为 null"与"变量不存在"）。
  static bool _projVarExists(VariableRef ref, RuntimeScope scope) {
    if (ref.varId == null) return false;
    return scope.projVars.containsKey(ref.varId!);
  }

  /// 解析页面级函数 outputs，按状态机返回值或加载态占位。
  static BindingResolveResult _resolvePageFunc(
    VariableRef ref,
    RuntimeScope scope,
    LoadingStrategy strategy,
    PortType? expectedType,
    String? placeholderText,
  ) {
    final funcId = ref.funcId!;
    final outputName = ref.outputName!;
    final entry = scope.getPageFuncEntry(funcId);
    if (entry == null) {
      // 函数未挂到任何页面事件 → 视为未就绪。
      return _applyStrategy(strategy, expectedType, placeholderText);
    }
    switch (entry.state) {
      case PageFuncState.done:
        return BindingResolveResult.ready(entry.outputs[outputName]);
      case PageFuncState.running:
      case PageFuncState.idle:
      case PageFuncState.error:
        // 未就绪：按策略返回占位（error 状态 UI 可额外显示错误标记，
        // 但渲染仍用占位避免破坏布局）。
        return _applyStrategy(strategy, expectedType, placeholderText);
    }
  }

  /// 应用加载态策略返回占位值。
  static BindingResolveResult _applyStrategy(
    LoadingStrategy strategy,
    PortType? expectedType,
    String? placeholderText,
  ) {
    switch (strategy) {
      case LoadingStrategy.typeDefault:
        return BindingResolveResult.placeholder(_typeDefault(expectedType));
      case LoadingStrategy.placeholder:
        return BindingResolveResult.placeholder(placeholderText ?? '');
      case LoadingStrategy.blank:
        return const BindingResolveResult.blank();
    }
  }

  /// 按 [PortType] 推导类型默认值。
  static Object? _typeDefault(PortType? type) {
    final t = type ?? PortType.any;
    switch (t) {
      case PortType.number:
        return 0;
      case PortType.string:
        return '';
      case PortType.boolean:
        return false;
      case PortType.list:
        return <dynamic>[];
      case PortType.map:
        return <String, dynamic>{};
      case PortType.any:
        return null;
    }
  }
}
