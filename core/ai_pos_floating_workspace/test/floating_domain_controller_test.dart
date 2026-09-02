import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
