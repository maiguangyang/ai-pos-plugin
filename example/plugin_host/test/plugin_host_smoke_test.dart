import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_host/main.dart';
import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'host cleanup always disposes the registry after a session failure',
    () async {
      var registryDisposed = false;

      await expectLater(
        disposePluginHostResources(
          closeSessions: () => Future<void>.error(StateError('close failed')),
          disposeRegistry: () async {
            registryDisposed = true;
            return const <AiPosPluginException>[];
          },
        ),
        throwsStateError,
      );

      expect(registryDisposed, isTrue);
    },
  );

  test(
    'scheduled host cleanup reports failures without an uncaught error',
    () async {
      final reportedErrors = <FlutterErrorDetails>[];
      final uncaughtErrors = <Object>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = reportedErrors.add;
      addTearDown(() => FlutterError.onError = originalOnError);

      await runZonedGuarded(() async {
        schedulePluginHostDisposal(
          closeSessions: () => Future<void>.error(StateError('close failed')),
          disposeRegistry: () async => const <AiPosPluginException>[],
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaughtErrors.add(error));

      expect(uncaughtErrors, isEmpty);
      expect(reportedErrors, hasLength(1));
      expect(reportedErrors.single.exception, isA<StateError>());
    },
  );

  test('host cleanup preserves session and registry failures', () async {
    final sessionError = StateError('close failed');
    final registryError = StateError('registry failed');
    final reportedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    Object? thrownError;
    try {
      await disposePluginHostResources(
        closeSessions: () => Future<void>.error(sessionError),
        disposeRegistry: () =>
            Future<List<AiPosPluginException>>.error(registryError),
      );
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError, same(sessionError));
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, same(registryError));
  });

  test('scheduled host cleanup reports registry disposal results', () async {
    final registry = AiPosPluginRegistry(
      apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
    );
    await registry.register(
      _SlowPlugin(
        Future<void>.value(),
        disposeError: StateError('private-disposal-detail'),
      ),
      const _TestPluginContext(),
    );
    final reportedErrors = <FlutterErrorDetails>[];
    final uncaughtErrors = <Object>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    await runZonedGuarded(() async {
      schedulePluginHostDisposal(
        closeSessions: () async {},
        disposeRegistry: registry.disposeAll,
      );
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => uncaughtErrors.add(error));

    expect(uncaughtErrors, isEmpty);
    expect(reportedErrors, hasLength(1));
    final exception = reportedErrors.single.exception;
    expect(exception, isA<AiPosPluginException>());
    expect(
      (exception as AiPosPluginException).code,
      AiPosPluginErrorCode.disposalFailed,
    );
    expect(exception.toString(), isNot(contains('private-disposal-detail')));
  });

  testWidgets('host opens, floats, restores, and closes one live session', (
    tester,
  ) async {
    await tester.pumpWidget(const PluginHostApp());
    await tester.pumpAndSettle();

    expect(find.byKey(PluginHostApp.hostReadyKey), findsOneWidget);
    expect(find.byKey(const Key('ai-pos-example-plugin-ready')), findsNothing);

    await tester.tap(find.byKey(PluginHostApp.openPluginKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ai-pos-example-plugin-ready')),
      findsOneWidget,
    );
    expect(find.byKey(AiPosPluginPageShell.closeButtonKey), findsOneWidget);
    expect(find.byKey(PluginHostApp.hostReadyKey), findsOneWidget);
    expect(find.byKey(PluginHostApp.openPluginKey).hitTestable(), findsNothing);

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.floatActionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(PluginHostApp.hostReadyKey), findsOneWidget);
    expect(
      find.byKey(PluginHostApp.openPluginKey).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);

    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(AiPosPluginSessionHost.cardKey('com.sjfood.example')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('ai-pos-example-plugin-ready')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(PluginHostApp.hostReadyKey), findsOneWidget);
    expect(find.byKey(const Key('ai-pos-example-plugin-ready')), findsNothing);
  });

  testWidgets('unmount cancels and disposes a plugin initializing late', (
    tester,
  ) async {
    final initialization = Completer<void>();
    final plugin = _SlowPlugin(initialization.future);
    await tester.pumpWidget(PluginHostApp(plugin: plugin));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(plugin.cancellationObserved, isTrue);
    expect(plugin.disposeCount, 1);
  });
}

final class _SlowPlugin implements AiPosPlugin {
  _SlowPlugin(this.initialization, {this.disposeError});

  final Future<void> initialization;
  final Object? disposeError;
  bool cancellationObserved = false;
  int disposeCount = 0;

  @override
  final AiPosPluginManifest manifest = AiPosPluginManifest(
    id: 'com.sjfood.slow',
    name: 'Slow',
    version: '0.3.0',
    requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
    entryPage: '/home',
    capabilities: const {},
  );

  @override
  Map<String, AiPosPluginPageBuilder> get pages => {
    '/home': (_, _) => const SizedBox.shrink(),
  };

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {
    await Future.any([initialization, lifecycle.cancellationRequested]);
    cancellationObserved = lifecycle.isCancellationRequested;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    if (disposeError case final error?) {
      throw error;
    }
  }
}

final class _TestPluginContext implements AiPosPluginContext {
  const _TestPluginContext();

  @override
  Set<AiPosCapability> get grantedCapabilities => const {};

  @override
  Locale get locale => const Locale('en');
}
