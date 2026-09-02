import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart';
import 'package:easypos_demo_integration/easypos_demo_integration.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page visibility unbind stops the periodic producer', () async {
    final runtime = EasyPosDemoRuntime();
    final pageContext = FakeAiPosPluginPageContext();
    await runtime.start();
    final unbind = runtime.bindPageVisibility(pageContext.visibilityListenable);

    pageContext.setVisibility(AiPosPluginPageVisibility.floating);
    expect(runtime.hasActiveTimer, isFalse);
    expect(runtime.isRunning, isTrue);
    pageContext.setVisibility(AiPosPluginPageVisibility.foreground);
    expect(runtime.hasActiveTimer, isTrue);
    expect(runtime.producerStartCount, 1);

    unbind();
    expect(runtime.hasActiveTimer, isFalse);
    pageContext.setVisibility(AiPosPluginPageVisibility.foreground);
    expect(runtime.hasActiveTimer, isFalse);
    await runtime.dispose();
    pageContext.invalidate();
  });

  test(
    'shared runtime starts once and disposes every resource idempotently',
    () async {
      final runtime = EasyPosDemoRuntime();

      await runtime.start();
      await runtime.start();

      expect(runtime.isRunning, isTrue);
      expect(runtime.hasActiveTimer, isTrue);
      expect(runtime.emissionCount, 1);
      expect(runtime.orders, hasLength(3));

      await runtime.dispose();
      await runtime.dispose();

      expect(runtime.isDisposed, isTrue);
      expect(runtime.isRunning, isFalse);
      expect(runtime.hasActiveTimer, isFalse);
      expect(runtime.emissionCount, 1);
    },
  );

  test(
    'plugin cancellation releases a partially initialized runtime',
    () async {
      final runtime = EasyPosDemoRuntime();
      final plugin = EasyPosDemoPlugin(runtime: runtime);
      final lifecycle = FakeAiPosPluginLifecycle()..cancel();

      await expectLater(
        plugin.initialize(
          FakeAiPosPluginContext(locale: const Locale('zh', 'CN')),
          lifecycle,
        ),
        throwsA(isA<AiPosPluginCancellationException>()),
      );

      expect(runtime.isDisposed, isTrue);
      expect(runtime.hasActiveTimer, isFalse);
    },
  );
}
