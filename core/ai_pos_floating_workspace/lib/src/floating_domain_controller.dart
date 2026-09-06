import 'floating_session.dart';

abstract interface class FloatingDomainHostDelegate {
  Future<Object?> open(
    FloatingDomainController controller,
    FloatingSessionRequest request,
  );

  Future<void> close(FloatingDomainController controller, String sessionId);

  Future<void> closeAll(FloatingDomainController controller);

  Future<FloatingSessionSwitchHandle?> beginInteractiveSwitch(
    FloatingDomainController controller, {
    required String foregroundSessionId,
    required String targetSessionId,
    required FloatingSessionSwitchDirection direction,
    required bool keepForegroundAsFloating,
  });

  int sessionCount(FloatingDomainController controller);
}

final class FloatingDomainController {
  FloatingDomainController({required this.policy});

  final FloatingDomainPolicy policy;
  FloatingDomainHostDelegate? _delegate;

  String get domainId => policy.domainId;
  int get sessionCount => _delegate?.sessionCount(this) ?? 0;

  Future<Object?> open(FloatingSessionRequest request) {
    if (request.key.domainId != domainId) {
      throw ArgumentError.value(
        request.key.domainId,
        'request.key.domainId',
        'must match controller domain $domainId',
      );
    }
    final delegate = _delegate;
    if (delegate == null) {
      throw StateError('No floating workspace host is attached.');
    }
    return delegate.open(this, request);
  }

  Future<void> close(String sessionId) {
    return _delegate?.close(this, sessionId) ?? Future<void>.value();
  }

  Future<void> closeAll() {
    return _delegate?.closeAll(this) ?? Future<void>.value();
  }

  Future<FloatingSessionSwitchHandle?> beginInteractiveSwitch({
    required String foregroundSessionId,
    required String targetSessionId,
    required FloatingSessionSwitchDirection direction,
    required bool keepForegroundAsFloating,
  }) {
    final normalizedForegroundId = foregroundSessionId.trim();
    final normalizedTargetId = targetSessionId.trim();
    if (normalizedForegroundId.isEmpty) {
      throw ArgumentError.value(
        foregroundSessionId,
        'foregroundSessionId',
        'must not be empty',
      );
    }
    if (normalizedTargetId.isEmpty) {
      throw ArgumentError.value(
        targetSessionId,
        'targetSessionId',
        'must not be empty',
      );
    }
    if (normalizedForegroundId == normalizedTargetId) {
      throw ArgumentError.value(
        targetSessionId,
        'targetSessionId',
        'must differ from foregroundSessionId',
      );
    }
    final delegate = _delegate;
    if (delegate == null) {
      return Future<FloatingSessionSwitchHandle?>.value();
    }
    return delegate.beginInteractiveSwitch(
      this,
      foregroundSessionId: normalizedForegroundId,
      targetSessionId: normalizedTargetId,
      direction: direction,
      keepForegroundAsFloating: keepForegroundAsFloating,
    );
  }

  void attachHost(FloatingDomainHostDelegate delegate) {
    final current = _delegate;
    if (current != null && !identical(current, delegate)) {
      throw StateError('A floating workspace host is already attached.');
    }
    _delegate = delegate;
  }

  void detachHost(FloatingDomainHostDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }
}
