import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'interactive dismiss forwards normalized id and retention option to host',
    () async {
      final controller = _controller();
      final delegate = _RecordingDomainHost();
      controller.attachHost(delegate);

      final result = await controller.beginInteractiveDismiss(
        foregroundSessionId: '  agent-c  ',
        keepForegroundAsFloating: true,
      );

      expect(delegate.dismissController, same(controller));
      expect(delegate.dismissForegroundSessionId, 'agent-c');
      expect(delegate.dismissKeepForegroundAsFloating, isTrue);
      expect(result, same(delegate.handle));
    },
  );

  test(
    'interactive dismiss fails closed while detached and rejects empty ids',
    () {
      final controller = _controller();

      expect(
        controller.beginInteractiveDismiss(
          foregroundSessionId: 'agent-c',
          keepForegroundAsFloating: false,
        ),
        completion(isNull),
      );
      expect(
        () => controller.beginInteractiveDismiss(
          foregroundSessionId: ' ',
          keepForegroundAsFloating: false,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'interactive switch forwards normalized ids and options to host',
    () async {
      final controller = _controller();
      final delegate = _RecordingDomainHost();
      controller.attachHost(delegate);

      final result = await controller.beginInteractiveSwitch(
        foregroundSessionId: '  agent-c  ',
        targetSessionId: ' agent-b ',
        direction: FloatingSessionSwitchDirection.right,
        keepForegroundAsFloating: true,
      );

      expect(delegate.controller, same(controller));
      expect(delegate.foregroundSessionId, 'agent-c');
      expect(delegate.targetSessionId, 'agent-b');
      expect(delegate.direction, FloatingSessionSwitchDirection.right);
      expect(delegate.keepForegroundAsFloating, isTrue);
      expect(result, same(delegate.handle));
    },
  );

  test(
    'interactive switch returns null while controller is detached',
    () async {
      final result = await _controller().beginInteractiveSwitch(
        foregroundSessionId: 'agent-c',
        targetSessionId: 'agent-b',
        direction: FloatingSessionSwitchDirection.left,
        keepForegroundAsFloating: false,
      );

      expect(result, isNull);
    },
  );

  test('interactive switch rejects empty or identical session ids', () {
    final controller = _controller();

    expect(
      () => controller.beginInteractiveSwitch(
        foregroundSessionId: ' ',
        targetSessionId: 'agent-b',
        direction: FloatingSessionSwitchDirection.left,
        keepForegroundAsFloating: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.beginInteractiveSwitch(
        foregroundSessionId: 'agent-a',
        targetSessionId: ' agent-a ',
        direction: FloatingSessionSwitchDirection.right,
        keepForegroundAsFloating: true,
      ),
      throwsArgumentError,
    );
  });

  test('controller rejects another domain and detaches cleanly', () {
    final controller = FloatingDomainController(
      policy: const FloatingDomainPolicy(
        domainId: 'agent',
        maxFloatingSessions: 5,
        maxSnapshotBytes: 1024,
      ),
    );
    final request = FloatingSessionRequest(
      key: const FloatingSessionKey(domainId: 'plugin', sessionId: 'one'),
      title: 'One',
      pageBuilder: (_, _) => throw UnimplementedError(),
      maybePopNested: () async => false,
      onVisibilityChanged: (_) {},
      onClosed: (_) {},
    );

    expect(() => controller.open(request), throwsArgumentError);
    expect(controller.closeAll(), completes);
  });

  test('session keys use value equality', () {
    expect(
      const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
      const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
    );
    expect(
      const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
      isNot(const FloatingSessionKey(domainId: 'plugin', sessionId: 'a')),
    );
  });
}

FloatingDomainController _controller() {
  return FloatingDomainController(
    policy: const FloatingDomainPolicy(
      domainId: 'agent',
      maxFloatingSessions: 5,
      maxSnapshotBytes: 1024,
    ),
  );
}

final class _RecordingDomainHost implements FloatingDomainHostDelegate {
  final handle = _FakeSwitchHandle();
  FloatingDomainController? controller;
  FloatingDomainController? dismissController;
  String? foregroundSessionId;
  String? dismissForegroundSessionId;
  String? targetSessionId;
  FloatingSessionSwitchDirection? direction;
  bool? keepForegroundAsFloating;
  bool? dismissKeepForegroundAsFloating;

  @override
  Future<FloatingSessionSwitchHandle?> beginInteractiveDismiss(
    FloatingDomainController controller, {
    required String foregroundSessionId,
    required bool keepForegroundAsFloating,
  }) async {
    dismissController = controller;
    dismissForegroundSessionId = foregroundSessionId;
    dismissKeepForegroundAsFloating = keepForegroundAsFloating;
    return handle;
  }

  @override
  Future<FloatingSessionSwitchHandle?> beginInteractiveSwitch(
    FloatingDomainController controller, {
    required String foregroundSessionId,
    required String targetSessionId,
    required FloatingSessionSwitchDirection direction,
    required bool keepForegroundAsFloating,
  }) async {
    this.controller = controller;
    this.foregroundSessionId = foregroundSessionId;
    this.targetSessionId = targetSessionId;
    this.direction = direction;
    this.keepForegroundAsFloating = keepForegroundAsFloating;
    return handle;
  }

  @override
  Future<void> close(
    FloatingDomainController controller,
    String sessionId,
  ) async {}

  @override
  Future<void> closeAll(FloatingDomainController controller) async {}

  @override
  Future<Object?> open(
    FloatingDomainController controller,
    FloatingSessionRequest request,
  ) async => null;

  @override
  int sessionCount(FloatingDomainController controller) => 0;
}

final class _FakeSwitchHandle implements FloatingSessionSwitchHandle {
  @override
  double progress = 0;

  @override
  Future<void> cancel() async {}

  @override
  Future<FloatingSessionSwitchOutcome> settle({
    required double velocityX,
  }) async {
    return FloatingSessionSwitchOutcome.completed;
  }

  @override
  void updateProgress(double value) {
    progress = value;
  }
}
