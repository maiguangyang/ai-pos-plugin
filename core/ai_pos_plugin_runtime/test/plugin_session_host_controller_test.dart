import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:ai_pos_plugin_runtime/src/presentation/plugin_session_host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final request = AiPosPluginSessionRequest(
    pluginId: 'com.vendor.delivery',
    pluginName: 'Delivery',
    pagePath: '/orders',
    pageBuilder: (_, _) => const SizedBox.shrink(),
  );

  test('controller requires one attached live host', () async {
    final controller = AiPosPluginSessionHostController();
    final first = _FakeHostDelegate();
    final second = _FakeHostDelegate();

    expect(() => controller.open(request), throwsStateError);
    controller.attachHost(first);
    expect(await controller.open(request), 'result');
    expect(first.requests, <AiPosPluginSessionRequest>[request]);
    expect(() => controller.attachHost(second), throwsStateError);

    controller.detachHost(first);
    expect(() => controller.open(request), throwsStateError);
    await controller.dispose();
  });

  test('dispose closes the attached host exactly once', () async {
    final controller = AiPosPluginSessionHostController();
    final host = _FakeHostDelegate();
    controller.attachHost(host);

    await controller.dispose();
    await controller.dispose();

    expect(host.closeAllCount, 1);
    expect(() => controller.open(request), throwsStateError);
  });
}

final class _FakeHostDelegate implements AiPosPluginSessionHostDelegate {
  final List<AiPosPluginSessionRequest> requests = [];
  int closeAllCount = 0;

  @override
  Future<Object?> open(AiPosPluginSessionRequest request) async {
    requests.add(request);
    return 'result';
  }

  @override
  Future<void> closeAll() async {
    closeAllCount += 1;
  }
}
