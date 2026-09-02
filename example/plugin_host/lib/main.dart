import 'dart:async';

import 'package:ai_pos_example_plugin/ai_pos_example_plugin.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const PluginHostApp());
}

/// Development host for compile-time third-party plugins.
class PluginHostApp extends StatefulWidget {
  const PluginHostApp({super.key, this.plugin});

  static const hostReadyKey = Key('ai-pos-plugin-host-ready');
  static const openPluginKey = Key('ai-pos-plugin-host-open');

  /// Tests and development builds can replace the default example plugin.
  final AiPosPlugin? plugin;

  @override
  State<PluginHostApp> createState() => _PluginHostAppState();
}

class _PluginHostAppState extends State<PluginHostApp> {
  final AiPosPluginRegistry _registry = AiPosPluginRegistry(
    apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
  );
  final _PluginHostContext _pluginContext = _PluginHostContext();
  final AiPosPluginSessionHostController _sessionController =
      AiPosPluginSessionHostController();
  late final AiPosPlugin _plugin;
  late final Future<void> _registration;

  @override
  void initState() {
    super.initState();
    _plugin = widget.plugin ?? AiPosExamplePlugin();
    _registration = _registry.register(_plugin, _pluginContext);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AiPosPluginSessionHost(
        controller: _sessionController,
        strings: const AiPosPluginPageShellStrings(floatingLabel: 'Float'),
        child: FutureBuilder<void>(
          future: _registration,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text('Plugin registration failed')),
              );
            }

            return Scaffold(
              body: Center(
                key: PluginHostApp.hostReadyKey,
                child: FilledButton(
                  key: PluginHostApp.openPluginKey,
                  onPressed: _openPlugin,
                  child: const Text('Open example plugin'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<Object?> _openPlugin() {
    final pageBuilder = _registry.pageBuilder(
      _plugin.manifest.id,
      _plugin.manifest.entryPage,
    );
    return _sessionController.open(
      AiPosPluginSessionRequest(
        pluginId: _plugin.manifest.id,
        pluginName: _plugin.manifest.name,
        pluginDescription: _plugin.manifest.description,
        pagePath: _plugin.manifest.entryPage,
        pageBuilder: pageBuilder,
      ),
    );
  }

  @override
  void dispose() {
    schedulePluginHostDisposal(
      closeSessions: _sessionController.dispose,
      disposeRegistry: _registry.disposeAll,
    );
    super.dispose();
  }
}

@visibleForTesting
void schedulePluginHostDisposal({
  required Future<void> Function() closeSessions,
  required Future<List<AiPosPluginException>> Function() disposeRegistry,
}) {
  unawaited(
    disposePluginHostResources(
      closeSessions: closeSessions,
      disposeRegistry: disposeRegistry,
    ).catchError((Object error, StackTrace stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ai_pos_plugin_host',
          context: ErrorDescription('while disposing plugin host resources'),
        ),
      );
    }),
  );
}

@visibleForTesting
Future<void> disposePluginHostResources({
  required Future<void> Function() closeSessions,
  required Future<List<AiPosPluginException>> Function() disposeRegistry,
}) async {
  Object? sessionError;
  StackTrace? sessionStackTrace;
  try {
    await closeSessions();
  } catch (error, stackTrace) {
    sessionError = error;
    sessionStackTrace = stackTrace;
  }
  try {
    final disposalErrors = await disposeRegistry();
    for (final error in disposalErrors) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'ai_pos_plugin_host',
          context: ErrorDescription('while disposing the plugin registry'),
        ),
      );
    }
  } catch (error, stackTrace) {
    if (sessionError == null) {
      rethrow;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ai_pos_plugin_host',
        context: ErrorDescription(
          'while disposing the plugin registry after session cleanup failed',
        ),
      ),
    );
  }
  if (sessionError != null) {
    Error.throwWithStackTrace(sessionError, sessionStackTrace!);
  }
}

final class _PluginHostContext implements AiPosPluginContext {
  @override
  Set<AiPosCapability> get grantedCapabilities => const {};

  @override
  Locale get locale => const Locale('en');
}
