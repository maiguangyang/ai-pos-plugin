import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';

import '../plugin_exception.dart';
import 'plugin_lifecycle_controller.dart';
import 'plugin_lifecycle_policy.dart';

final class PluginInitializationResult {
  const PluginInitializationResult.success() : code = null, relatedCode = null;

  const PluginInitializationResult.failure(this.code, {this.relatedCode});

  final AiPosPluginErrorCode? code;
  final AiPosPluginErrorCode? relatedCode;

  bool get isSuccess => code == null;
}

final class PluginRuntimeEntry {
  PluginRuntimeEntry({
    required AiPosPlugin plugin,
    required this.manifest,
    required this.pages,
    required this.policy,
  }) : _plugin = plugin,
       _lifecycle = PluginLifecycleController();

  final AiPosPluginManifest manifest;
  final Map<String, AiPosPluginPageBuilder> pages;
  final AiPosPluginLifecyclePolicy policy;
  AiPosPlugin? _plugin;
  PluginLifecycleController? _lifecycle;
  Future<AiPosPluginException?>? _disposal;

  AiPosPlugin get plugin => _plugin!;

  void cancel() => _lifecycle?.cancel();

  Future<PluginInitializationResult> initialize(
    AiPosPluginContext context,
  ) async {
    final plugin = _plugin!;
    final lifecycle = _lifecycle!;
    final timeout = Completer<_InitializationOutcome>();
    final timer = Timer(
      policy.initializationTimeout,
      () => timeout.complete(_InitializationOutcome.timedOut),
    );
    final source =
        Future<void>.sync(
          () => plugin.initialize(context, lifecycle),
        ).then<_InitializationOutcome>(
          (_) => _InitializationOutcome.succeeded,
          onError: (Object error, StackTrace _) {
            return error is AiPosPluginCancellationException &&
                    lifecycle.isCancellationRequested
                ? _InitializationOutcome.cancelled
                : _InitializationOutcome.failed;
          },
        );
    final cancellation = lifecycle.cancellationRequested.then(
      (_) => _InitializationOutcome.cancelled,
    );

    final _InitializationOutcome outcome;
    try {
      outcome = await Future.any([source, cancellation, timeout.future]);
    } finally {
      timer.cancel();
    }

    if (outcome == _InitializationOutcome.succeeded &&
        !lifecycle.isCancellationRequested) {
      return const PluginInitializationResult.success();
    }
    if (outcome == _InitializationOutcome.timedOut) {
      lifecycle.cancel();
    }

    final cleanup = await dispose();
    final code = switch (outcome) {
      _InitializationOutcome.timedOut =>
        AiPosPluginErrorCode.initializationTimedOut,
      _InitializationOutcome.cancelled || _InitializationOutcome.succeeded =>
        AiPosPluginErrorCode.initializationCancelled,
      _InitializationOutcome.failed =>
        AiPosPluginErrorCode.initializationFailed,
    };
    return PluginInitializationResult.failure(code, relatedCode: cleanup?.code);
  }

  Future<AiPosPluginException?> dispose() {
    final active = _disposal;
    if (active != null) {
      return active;
    }

    _lifecycle?.cancel();
    final plugin = _plugin;
    if (plugin == null) {
      return Future<AiPosPluginException?>.value();
    }

    late final Future<AiPosPluginException?> disposal;
    disposal = _dispose(plugin).whenComplete(() {
      _plugin = null;
      _lifecycle = null;
    });
    _disposal = disposal;
    return disposal;
  }

  Future<AiPosPluginException?> _dispose(AiPosPlugin plugin) async {
    final timeout = Completer<_DisposalOutcome>();
    final timer = Timer(
      policy.disposalTimeout,
      () => timeout.complete(_DisposalOutcome.timedOut),
    );
    final source = Future<void>.sync(plugin.dispose).then<_DisposalOutcome>(
      (_) => _DisposalOutcome.succeeded,
      onError: (Object _, StackTrace _) => _DisposalOutcome.failed,
    );

    final _DisposalOutcome outcome;
    try {
      outcome = await Future.any([source, timeout.future]);
    } finally {
      timer.cancel();
    }

    return switch (outcome) {
      _DisposalOutcome.succeeded => null,
      _DisposalOutcome.failed => _error(AiPosPluginErrorCode.disposalFailed),
      _DisposalOutcome.timedOut => _error(
        AiPosPluginErrorCode.disposalTimedOut,
      ),
    };
  }

  AiPosPluginException _error(AiPosPluginErrorCode code) {
    return AiPosPluginException(
      code: code,
      pluginId: manifest.id,
      pluginVersion: manifest.version,
    );
  }
}

enum _InitializationOutcome { succeeded, failed, timedOut, cancelled }

enum _DisposalOutcome { succeeded, failed, timedOut }
