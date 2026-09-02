import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';

import 'lifecycle/plugin_lifecycle_policy.dart';
import 'lifecycle/plugin_runtime_entry.dart';
import 'plugin_exception.dart';

enum _RegistryState { open, closing, closed }

/// 宿主侧编译期插件注册表。
final class AiPosPluginRegistry {
  AiPosPluginRegistry({
    required this.apiVersion,
    this.lifecyclePolicy = const AiPosPluginLifecyclePolicy(),
  }) {
    if (lifecyclePolicy.initializationTimeout <= Duration.zero ||
        lifecyclePolicy.disposalTimeout <= Duration.zero) {
      throw ArgumentError('Plugin lifecycle timeouts must be positive.');
    }
  }

  final AiPosPluginApiVersion apiVersion;
  final AiPosPluginLifecyclePolicy lifecyclePolicy;
  final Map<String, PluginRuntimeEntry> _plugins = {};
  final Map<String, PluginRuntimeEntry> _initializing = {};
  Future<List<AiPosPluginException>>? _disposal;
  _RegistryState _state = _RegistryState.open;

  /// 按注册顺序返回当前插件的只读快照。
  Iterable<AiPosPlugin> get plugins => List<AiPosPlugin>.unmodifiable(
    _plugins.values.map((entry) => entry.plugin),
  );

  /// 校验并初始化插件；只有初始化成功后才会登记。
  Future<void> register(AiPosPlugin plugin, AiPosPluginContext context) {
    if (_state != _RegistryState.open) {
      return Future<void>.error(
        const AiPosPluginException(
          code: AiPosPluginErrorCode.registryClosed,
          pluginId: '',
          pluginVersion: '',
        ),
      );
    }

    AiPosPluginManifest? manifest;
    late final Map<String, AiPosPluginPageBuilder> pages;
    late final List<AiPosPluginContractIssue> issues;
    try {
      manifest = plugin.manifest;
      pages = Map<String, AiPosPluginPageBuilder>.unmodifiable(plugin.pages);
      issues = AiPosPluginContractValidator.validate(
        _PluginContractView(manifest: manifest, pages: pages),
      );
    } catch (_) {
      return Future<void>.error(
        AiPosPluginException(
          code: AiPosPluginErrorCode.invalidManifest,
          pluginId: manifest?.id ?? '',
          pluginVersion: manifest?.version ?? '',
        ),
      );
    }
    if (issues.isNotEmpty) {
      return Future<void>.error(
        _error(AiPosPluginErrorCode.invalidManifest, manifest),
      );
    }
    if (_plugins.containsKey(manifest.id) ||
        _initializing.containsKey(manifest.id)) {
      return Future<void>.error(
        _error(AiPosPluginErrorCode.duplicatePluginId, manifest),
      );
    }
    if (!apiVersion.supports(manifest.requiredApiVersion)) {
      return Future<void>.error(
        _error(AiPosPluginErrorCode.incompatibleApiVersion, manifest),
      );
    }
    if (!context.grantedCapabilities.containsAll(manifest.capabilities)) {
      return Future<void>.error(
        _error(AiPosPluginErrorCode.capabilityDenied, manifest),
      );
    }

    final entry = PluginRuntimeEntry(
      plugin: plugin,
      manifest: manifest,
      pages: pages,
      policy: lifecyclePolicy,
    );
    _initializing[manifest.id] = entry;
    return _initialize(entry, context);
  }

  Future<void> _initialize(
    PluginRuntimeEntry entry,
    AiPosPluginContext context,
  ) async {
    try {
      final result = await entry.initialize(context);
      if (!result.isSuccess) {
        throw _error(
          result.code!,
          entry.manifest,
          relatedCode: result.relatedCode,
        );
      }
      if (_state != _RegistryState.open ||
          !identical(_initializing[entry.manifest.id], entry)) {
        entry.cancel();
        final cleanup = await entry.dispose();
        throw _error(
          AiPosPluginErrorCode.initializationCancelled,
          entry.manifest,
          relatedCode: cleanup?.code,
        );
      }
      _plugins[entry.manifest.id] = entry;
    } finally {
      if (identical(_initializing[entry.manifest.id], entry)) {
        _initializing.remove(entry.manifest.id);
      }
    }
  }

  /// 按 ID 获取插件，否则抛出稳定的 [AiPosPluginException]。
  AiPosPlugin plugin(String pluginId) {
    return _entry(pluginId).plugin;
  }

  /// Returns the immutable manifest snapshot validated during registration.
  AiPosPluginManifest manifest(String pluginId) {
    return _entry(pluginId).manifest;
  }

  PluginRuntimeEntry _entry(String pluginId) {
    final entry = _plugins[pluginId];
    if (entry == null) {
      throw AiPosPluginException(
        code: AiPosPluginErrorCode.pluginNotFound,
        pluginId: pluginId,
        pluginVersion: '',
      );
    }
    return entry;
  }

  /// 获取插件声明的页面构建器。
  AiPosPluginPageBuilder pageBuilder(String pluginId, String pagePath) {
    final entry = _entry(pluginId);
    final builder = entry.pages[pagePath];
    if (builder == null) {
      throw _error(AiPosPluginErrorCode.pageNotFound, entry.manifest);
    }
    return builder;
  }

  /// 关闭注册表并逆序执行有界释放；重复调用共享同一个结果。
  Future<List<AiPosPluginException>> disposeAll() {
    final active = _disposal;
    if (active != null) {
      return active;
    }

    _state = _RegistryState.closing;
    final initializing = _initializing.values.toList(growable: false);
    final registered = _plugins.values
        .toList(growable: false)
        .reversed
        .toList();
    _initializing.clear();
    _plugins.clear();
    for (final entry in initializing) {
      entry.cancel();
    }

    late final Future<List<AiPosPluginException>> disposal;
    disposal = _disposeEntries([...initializing, ...registered]).whenComplete(
      () {
        _state = _RegistryState.closed;
      },
    );
    _disposal = disposal;
    return disposal;
  }

  Future<List<AiPosPluginException>> _disposeEntries(
    List<PluginRuntimeEntry> entries,
  ) async {
    final errors = <AiPosPluginException>[];
    for (final entry in entries) {
      final error = await entry.dispose();
      if (error != null) {
        errors.add(error);
      }
    }
    return List<AiPosPluginException>.unmodifiable(errors);
  }

  static AiPosPluginException _error(
    AiPosPluginErrorCode code,
    AiPosPluginManifest manifest, {
    AiPosPluginErrorCode? relatedCode,
  }) {
    return AiPosPluginException(
      code: code,
      pluginId: manifest.id,
      pluginVersion: manifest.version,
      relatedCode: relatedCode,
    );
  }
}

final class _PluginContractView implements AiPosPlugin {
  const _PluginContractView({required this.manifest, required this.pages});

  @override
  final AiPosPluginManifest manifest;

  @override
  final Map<String, AiPosPluginPageBuilder> pages;

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) {
    throw UnsupportedError('Contract views cannot be initialized.');
  }

  @override
  Future<void> dispose() {
    throw UnsupportedError('Contract views cannot be disposed.');
  }
}
