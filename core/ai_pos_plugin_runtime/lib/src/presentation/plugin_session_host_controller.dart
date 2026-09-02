import 'package:flutter/foundation.dart';

import 'plugin_session_request.dart';

/// Internal host boundary used by [AiPosPluginSessionHostController].
@internal
abstract interface class AiPosPluginSessionHostDelegate {
  Future<Object?> open(AiPosPluginSessionRequest request);

  Future<void> closeAll();
}

/// Host-app handle that never retains a BuildContext.
final class AiPosPluginSessionHostController {
  AiPosPluginSessionHostDelegate? _delegate;
  Future<void>? _disposeFuture;
  bool _isDisposed = false;

  Future<Object?> open(AiPosPluginSessionRequest request) {
    if (_isDisposed) {
      throw StateError('The session host controller is disposed.');
    }
    final delegate = _delegate;
    if (delegate == null) {
      throw StateError('No plugin session host is attached.');
    }
    return delegate.open(request);
  }

  Future<void> closeAll() {
    if (_isDisposed) {
      return _disposeFuture ?? Future<void>.value();
    }
    return _delegate?.closeAll() ?? Future<void>.value();
  }

  @internal
  void attachHost(AiPosPluginSessionHostDelegate delegate) {
    if (_isDisposed) {
      throw StateError('The session host controller is disposed.');
    }
    final current = _delegate;
    if (current != null && !identical(current, delegate)) {
      throw StateError('A plugin session host is already attached.');
    }
    _delegate = delegate;
  }

  @internal
  void detachHost(AiPosPluginSessionHostDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    _isDisposed = true;
    final delegate = _delegate;
    _delegate = null;
    if (delegate != null) {
      await delegate.closeAll();
    }
  }
}
