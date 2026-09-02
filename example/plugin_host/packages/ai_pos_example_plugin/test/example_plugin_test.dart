import 'dart:async';

import 'package:ai_pos_example_plugin/ai_pos_example_plugin.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example plugin exposes a valid API 0.3 contract', () {
    final plugin = AiPosExamplePlugin();

    expect(plugin.manifest.id, 'com.sjfood.example');
    expect(
      plugin.manifest.requiredApiVersion,
      const AiPosPluginApiVersion(major: 0, minor: 3),
    );
    expect(AiPosPluginContractValidator.validate(plugin), isEmpty);
  });

  test(
    'initialization observes cancellation and disposal is idempotent',
    () async {
      final plugin = AiPosExamplePlugin();
      final lifecycle = _Lifecycle();

      await plugin.initialize(_Context(), lifecycle);
      await plugin.dispose();
      await plugin.dispose();

      lifecycle.cancel();
      await expectLater(
        plugin.initialize(_Context(), lifecycle),
        throwsA(isA<AiPosPluginCancellationException>()),
      );
    },
  );

  testWidgets('entry page accepts page context and renders its marker', (
    tester,
  ) async {
    final plugin = AiPosExamplePlugin();
    final pageContext = _PageContext();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => plugin.pages['/home']!(context, pageContext),
        ),
      ),
    );

    expect(
      find.byKey(const Key('ai-pos-example-plugin-ready')),
      findsOneWidget,
    );
    expect(find.text('Example integration ready'), findsOneWidget);
    pageContext.close(result: 'done');
    expect(pageContext.result, 'done');
  });
}

final class _Context implements AiPosPluginContext {
  @override
  Set<AiPosCapability> get grantedCapabilities => const {};

  @override
  Locale get locale => const Locale('en');
}

final class _Lifecycle implements AiPosPluginLifecycle {
  final _cancellation = Completer<void>();

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

final class _PageContext implements AiPosPluginPageContext {
  Object? result;

  @override
  AiPosPluginPageVisibility get visibility =>
      AiPosPluginPageVisibility.foreground;

  @override
  ValueListenable<AiPosPluginPageVisibility> get visibilityListenable =>
      const _ForegroundVisibility();

  @override
  void close({Object? result}) {
    this.result = result;
  }
}

final class _ForegroundVisibility
    implements ValueListenable<AiPosPluginPageVisibility> {
  const _ForegroundVisibility();

  @override
  AiPosPluginPageVisibility get value => AiPosPluginPageVisibility.foreground;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
