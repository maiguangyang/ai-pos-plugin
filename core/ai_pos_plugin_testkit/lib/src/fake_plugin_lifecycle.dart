import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';

/// Controllable cooperative-cancellation lifecycle for plugin tests.
final class FakeAiPosPluginLifecycle implements AiPosPluginLifecycle {
  final _cancellation = Completer<void>();

  /// Requests cancellation once. Repeated calls are no-ops.
  void cancel() {
    if (!_cancellation.isCompleted) {
      _cancellation.complete();
    }
  }

  @override
  Future<void> get cancellationRequested => _cancellation.future;

  @override
  bool get isCancellationRequested => _cancellation.isCompleted;

  @override
  void throwIfCancellationRequested() {
    if (isCancellationRequested) {
      throw const AiPosPluginCancellationException();
    }
  }
}
