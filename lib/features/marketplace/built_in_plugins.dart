import '../../data/models/port.dart';
import '../plugins/llm/anthropic_plugin.dart';
import '../plugins/llm/openai_plugin.dart';
import '../plugins/native/native_plugins.dart';
import '../plugins/plugin_spec.dart';
import 'marketplace_entry.dart';
import 'plugin_manifest.dart';

/// 内置插件标识前缀。
///
/// 内置插件（OpenAI / Anthropic）的 [MarketplaceEntry.repoUrl] 使用此前缀
/// 加 pluginId（如 `builtin://llm_openai`），与真实 GitHub 仓库区分。
/// [MarketplaceClient.downloadPluginManifest] 与 [InstalledPluginsNotifier.install]
/// 检测此前缀后直接使用 [builtInPluginManifests] 中的 manifest，无需网络下载。
const String kBuiltInScheme = 'builtin://';

/// 判断 [repoUrl] 是否为内置插件。
bool isBuiltInRepo(String repoUrl) => repoUrl.startsWith(kBuiltInScheme);

/// 从内置 `builtin://<pluginId>` URL 提取 pluginId。
String? pluginIdFromBuiltInRepo(String repoUrl) {
  if (!isBuiltInRepo(repoUrl)) return null;
  return repoUrl.substring(kBuiltInScheme.length);
}

/// 内置市场条目：OpenAI / Anthropic。
///
/// 这些插件以 manifest 形式"发布"到市场，但执行逻辑在客户端二进制内
/// （manifest 的 executorType = 'native'）。用户从市场安装时无需网络下载，
/// 直接使用 [builtInPluginManifests] 中的 manifest。
final List<MarketplaceEntry> builtInMarketplaceEntries = [
  MarketplaceEntry(
    id: 'llm_openai',
    displayName: 'OpenAI LLM',
    description: '调用 OpenAI Chat Completions 接口生成文本，支持流式输出。'
        '需要 API Key。',
    version: '1.0.0',
    author: 'NodeVisual',
    repoUrl: '${kBuiltInScheme}llm_openai',
    tags: const ['AI', 'LLM', 'OpenAI', '文本生成'],
    icon: 'ai',
    downloads: 0,
  ),
  MarketplaceEntry(
    id: 'llm_anthropic',
    displayName: 'Anthropic LLM',
    description: '调用 Anthropic Messages 接口生成文本（Claude 系列模型），'
        '支持流式输出。需要 API Key。',
    version: '1.0.0',
    author: 'NodeVisual',
    repoUrl: '${kBuiltInScheme}llm_anthropic',
    tags: const ['AI', 'LLM', 'Anthropic', 'Claude', '文本生成'],
    icon: 'ai',
    downloads: 0,
  ),
];

/// 内置插件 manifest 映射（pluginId → PluginManifest）。
///
/// 这些 manifest 标记 executorType = 'native'，安装时直接持久化 manifest，
/// 运行时通过 [nativePluginExecutors] 查找执行器实例。
final Map<String, PluginManifest> builtInPluginManifests = {
  'llm_openai': PluginManifest(
    id: 'llm_openai',
    displayName: 'OpenAI LLM',
    description: '调用 OpenAI Chat Completions 接口生成文本，支持流式输出。',
    version: '1.0.0',
    author: 'NodeVisual',
    category: 'ai',
    inputs: const [
      ManifestInput(
        name: 'messages',
        type: PortType.list,
        required: true,
        description: '消息列表，形如 [{"role":"user","content":"你好"}]',
      ),
      ManifestInput(
        name: 'model',
        type: PortType.string,
        required: true,
        description: '模型名，如 gpt-4o-mini',
      ),
      ManifestInput(
        name: 'temperature',
        type: PortType.number,
        required: false,
        description: '采样温度，0~2，默认 0.7',
      ),
    ],
    outputs: const [
      ManifestOutput(name: 'content', type: PortType.string, description: '生成的文本'),
      ManifestOutput(
          name: 'usage_tokens', type: PortType.number, description: '总 token 数'),
    ],
    configSchema: const [
      ManifestConfigField(
        key: 'apiKey',
        label: 'API Key',
        fieldType: ConfigFieldType.secret,
        required: true,
      ),
      ManifestConfigField(
        key: 'baseUrl',
        label: 'Base URL',
        fieldType: ConfigFieldType.text,
        required: false,
        defaultValue: 'https://api.openai.com',
      ),
    ],
    executor: const HttpExecutorDef(method: 'POST', url: ''),
    executorType: 'native',
    sourceRepoUrl: '${kBuiltInScheme}llm_openai',
    installedAt: '',
  ),
  'llm_anthropic': PluginManifest(
    id: 'llm_anthropic',
    displayName: 'Anthropic LLM',
    description: '调用 Anthropic Messages 接口生成文本，支持流式输出。',
    version: '1.0.0',
    author: 'NodeVisual',
    category: 'ai',
    inputs: const [
      ManifestInput(
        name: 'messages',
        type: PortType.list,
        required: true,
        description: '消息列表，形如 [{"role":"user","content":"你好"}]',
      ),
      ManifestInput(
        name: 'model',
        type: PortType.string,
        required: true,
        description: '模型名，如 claude-3-5-sonnet-20240612',
      ),
      ManifestInput(
        name: 'maxTokens',
        type: PortType.number,
        required: true,
        description: '最大输出 token 数',
      ),
    ],
    outputs: const [
      ManifestOutput(name: 'content', type: PortType.string, description: '生成的文本'),
      ManifestOutput(
          name: 'usage_tokens',
          type: PortType.number,
          description: '输入+输出 token 数'),
    ],
    configSchema: const [
      ManifestConfigField(
        key: 'apiKey',
        label: 'API Key',
        fieldType: ConfigFieldType.secret,
        required: true,
      ),
      ManifestConfigField(
        key: 'baseUrl',
        label: 'Base URL',
        fieldType: ConfigFieldType.text,
        required: false,
        defaultValue: 'https://api.anthropic.com',
      ),
    ],
    executor: const HttpExecutorDef(method: 'POST', url: ''),
    executorType: 'native',
    sourceRepoUrl: '${kBuiltInScheme}llm_anthropic',
    installedAt: '',
  ),
};

/// 内置 native 执行器映射（pluginId → PluginExecutor 实例）。
///
/// 用于 executorType == 'native' 的插件：安装时直接从本表查找执行器实例
/// 注册到 [PluginRegistry]，无需 HTTP 模板。
///
/// 包含：
/// - OpenAI / Anthropic：通过市场安装后注册（用户主动安装）。
/// - clipboard / haptic / share：始终内置预注册（无需用户安装），
///   此处仅供 [InstalledPluginsNotifier._registerOne] 在 native 类型时查找。
final Map<String, PluginExecutor> nativePluginExecutors = {
  'llm_openai': OpenAiExecutor(),
  'llm_anthropic': AnthropicExecutor(),
  'native_clipboard': const ClipboardExecutor(),
  'native_haptic': const HapticExecutor(),
  'native_share': const ShareExecutor(),
};

/// 始终内置预注册的插件 spec 列表（clipboard / haptic / share）。
///
/// 这些插件代表各端原生能力，由 [PluginRegistry.withBuiltins] 在启动时
/// 直接注册，无需用户从市场安装。对应的 NodeKindSpec 也保留在
/// [NodeKindRegistry] 中作为内置节点。
final List<PluginSpec> builtInPreRegisteredSpecs = [
  clipboardPluginSpec,
  hapticPluginSpec,
  sharePluginSpec,
];

/// 获取内置插件的 manifest（若 [pluginId] 是内置插件）。
PluginManifest? getBuiltInManifest(String pluginId) =>
    builtInPluginManifests[pluginId];
