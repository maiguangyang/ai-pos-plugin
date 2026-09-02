import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';

final class PluginLifecycleController implements AiPosPluginLifecycle {
  final Completer<void> _cancellation = Completer<void>();

  @override
  bool get isCancellationRequested => _cancellation.isCompleted;

  @override
  Future<void> get cancellationRequested => _cancellation.future;

  void cancel() {
    if (!_cancellation.isCompleted) {
      _cancellation.complete();
    }
  }

  @override
  void throwIfCancellationRequested() {
    if (isCancellationRequested) {
      throw const AiPosPluginCancellationException();
    }
  }
}
