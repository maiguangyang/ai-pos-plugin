import 'dart:async';
import 'dart:ui' as ui;

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens when the session host wraps the app Navigator', (
    tester,
  ) async {
    final controller = AiPosPluginSessionHostController();
    final capture = _FakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AiPosPluginSessionHost(
          controller: controller,
          snapshotCapture: capture.call,
          child: child!,
        ),
        home: const Scaffold(body: Center(child: Text('Host home'))),
      ),
    );

    controller.open(_request('builder-topology'));
    await tester.pumpAndSettle();

    expect(find.text('Plugin builder-topology'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('builder-topology system back closes the foreground session', (
    tester,
  ) async {
    final controller = AiPosPluginSessionHostController();
    final dispatcher = RootBackButtonDispatcher();
    final routerDelegate = _BackTestRouterDelegate();
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: routerDelegate,
        backButtonDispatcher: dispatcher,
        builder: (context, child) => AiPosPluginSessionHost(
          controller: controller,
          backButtonDispatcher: dispatcher,
          snapshotCapture: _FakeCapture().call,
          child: child!,
        ),
      ),
    );

    final launch = controller.open(_request('builder-back'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Plugin builder-back'), findsNothing);
    expect(find.text('Host router'), findsOneWidget);
    expect(routerDelegate.popRouteCount, 0);
    expect(await launch, isNull);
  });

  testWidgets(
    'builder-topology back collapses cards before delegating to the router',
    (tester) async {
      final controller = AiPosPluginSessionHostController();
      final dispatcher = RootBackButtonDispatcher();
      final routerDelegate = _BackTestRouterDelegate(handlePop: true);
      final capture = _FakeCapture();
      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: routerDelegate,
          backButtonDispatcher: dispatcher,
          builder: (context, child) => AiPosPluginSessionHost(
            controller: controller,
            backButtonDispatcher: dispatcher,
            snapshotCapture: capture.call,
            child: child!,
          ),
        ),
      );

      final launch = controller.open(_request('builder-floating-back'));
      var launchCompleted = false;
      unawaited(launch.then((_) => launchCompleted = true));
      await tester.pumpAndSettle();
      await _tapFloat(tester);
      await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiPosPluginSessionHost.scrimKey), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(AiPosPluginSessionHost.scrimKey), findsNothing);
      expect(routerDelegate.popRouteCount, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(routerDelegate.popRouteCount, 1);
      expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);
      expect(launchCompleted, isFalse);

      final closeAll = controller.closeAll();
      await tester.pumpAndSettle();
      await closeAll;
      await launch;
    },
  );

  testWidgets('open renders one foreground fullscreen session', (tester) async {
    final harness = await _pumpHost(tester);
    final observed = <AiPosPluginPageVisibility>[];
    final request = _request(
      'one',
      onContext: (context) => observed.add(context.visibility),
    );

    harness.controller.open(request);
    await tester.pumpAndSettle();

    expect(find.text('Host home'), findsOneWidget);
    expect(
      find.byKey(AiPosPluginSessionHost.foregroundSessionKey(request.pluginId)),
      findsOneWidget,
    );
    expect(find.text('Plugin one'), findsOneWidget);
    expect(observed, <AiPosPluginPageVisibility>[
      AiPosPluginPageVisibility.foreground,
    ]);
  });

  testWidgets('float captures once and returns visual control to the host', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('one');
    harness.controller.open(request);
    await tester.pumpAndSettle();

    await _tapFloat(tester);

    expect(harness.capture.ratios, hasLength(1));
    expect(find.text('Host home'), findsOneWidget);
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);
    expect(
      find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId)),
      findsOneWidget,
    );
    expect(
      find.byKey(AiPosPluginSessionHost.foregroundSessionKey(request.pluginId)),
      findsNothing,
    );
  });

  testWidgets('float projects the page into the right-edge dock', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.controller.open(_request('float-projection'));
    await tester.pumpAndSettle();

    await _tapFloatAndStartCapture(tester);
    expect(
      find.byKey(AiPosPluginSessionHost.floatProjectionKey),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 160));
    final rect = tester.getRect(
      find.byKey(AiPosPluginSessionHost.floatProjectionSurfaceKey),
    );
    expect(rect.width, inExclusiveRange(56, 800));
    expect(rect.height, inExclusiveRange(88, 600));
    expect(rect.center.dx, greaterThan(400));

    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);
  });

  testWidgets('float projection blocks interaction with the host page', (
    tester,
  ) async {
    final controller = AiPosPluginSessionHostController();
    final capture = _FakeCapture();
    var hostTapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AiPosPluginSessionHost(
          controller: controller,
          strings: const AiPosPluginPageShellStrings(floatingLabel: 'Float'),
          snapshotCapture: capture.call,
          child: Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('host-action-during-projection'),
                onPressed: () => hostTapCount += 1,
                child: const Text('Host action'),
              ),
            ),
          ),
        ),
      ),
    );
    controller.open(_request('float-blocks-host'));
    await tester.pumpAndSettle();

    await _tapFloatAndStartCapture(tester);
    expect(
      find.byKey(AiPosPluginSessionHost.floatProjectionKey),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('host-action-during-projection')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(hostTapCount, 0);
    await tester.pumpAndSettle();
    final closeAll = controller.closeAll();
    await tester.pumpAndSettle();
    await closeAll;
  });

  testWidgets('new float projection lands at the moved dock position', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.controller.open(_request('dock-target-first'));
    await tester.pumpAndSettle();
    await _tapFloat(tester);

    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    await tester.drag(dock, const Offset(0, -120));
    await tester.pump();
    final movedDockCenterY = tester.getRect(dock).center.dy;

    harness.controller.open(_request('dock-target-second'));
    await tester.pumpAndSettle();
    await _tapFloatAndStartCapture(tester);
    expect(
      find.byKey(AiPosPluginSessionHost.floatProjectionKey),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 330));
    final projectionCenterY = tester
        .getRect(find.byKey(AiPosPluginSessionHost.floatProjectionSurfaceKey))
        .center
        .dy;
    expect(projectionCenterY, closeTo(movedDockCenterY, 5));

    await tester.pumpAndSettle();
  });

  testWidgets('tapping a thumbnail expands its projection to fullscreen', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('restore-projection');
    harness.controller.open(request);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    final sourceRect = tester.getRect(
      find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId)),
    );

    await tester.tap(
      find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId)),
    );
    await tester.pump();
    expect(
      find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
      findsOneWidget,
    );
    expect(
      tester.getRect(
        find.byKey(AiPosPluginSessionHost.restoreProjectionSurfaceKey),
      ),
      sourceRect,
    );

    await tester.pump(const Duration(milliseconds: 160));
    final middleRect = tester.getRect(
      find.byKey(AiPosPluginSessionHost.restoreProjectionSurfaceKey),
    );
    expect(middleRect.width, greaterThan(sourceRect.width));
    expect(middleRect.width, lessThan(800));

    await tester.pumpAndSettle();
    expect(
      find.byKey(AiPosPluginSessionHost.foregroundSessionKey(request.pluginId)),
      findsOneWidget,
    );
    expect(harness.capture.records.single.disposeCount, 1);
  });

  testWidgets(
    'restore projection consumes system back before the host router',
    (tester) async {
      final controller = AiPosPluginSessionHostController();
      final dispatcher = RootBackButtonDispatcher();
      final routerDelegate = _BackTestRouterDelegate(handlePop: true);
      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: routerDelegate,
          backButtonDispatcher: dispatcher,
          builder: (context, child) => AiPosPluginSessionHost(
            controller: controller,
            backButtonDispatcher: dispatcher,
            snapshotCapture: _FakeCapture().call,
            child: child!,
          ),
        ),
      );
      controller.open(_request('restore-blocks-back'));
      await tester.pumpAndSettle();
      await _tapFloat(tester);
      await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          AiPosPluginSessionHost.cardKey('com.vendor.restore-blocks-back'),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(routerDelegate.popRouteCount, 0);
      expect(
        find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      final closeAll = controller.closeAll();
      await tester.pumpAndSettle();
      await closeAll;
    },
  );

  testWidgets('restoring one of multiple cards collapses the floating layer', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final first = _request('restore-first-card');
    final second = _request('restore-second-card');
    harness.controller.open(first);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    harness.controller.open(second);
    await tester.pumpAndSettle();
    await _tapFloat(tester);

    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginSessionHost.scrimKey), findsOneWidget);

    await tester.tap(
      find.byKey(AiPosPluginSessionHost.cardKey(second.pluginId)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AiPosPluginSessionHost.scrimKey), findsNothing);
    expect(
      find.byKey(AiPosPluginSessionHost.foregroundSessionKey(second.pluginId)),
      findsOneWidget,
    );
    expect(
      find.byKey(AiPosPluginSessionHost.cardKey(first.pluginId)),
      findsOneWidget,
    );
  });

  testWidgets('backgrounding reverts an early float projection', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.controller.open(_request('background-float'));
    await tester.pumpAndSettle();
    await _tapFloatAndStartCapture(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(AiPosPluginSessionHost.floatProjectionKey),
      findsOneWidget,
    );

    final snapshot = harness.capture.records.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(snapshot.disposeCount, 0);
    await tester.pump();

    expect(find.byKey(AiPosPluginSessionHost.floatProjectionKey), findsNothing);
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
    expect(
      find.byKey(
        AiPosPluginSessionHost.foregroundSessionKey(
          'com.vendor.background-float',
        ),
      ),
      findsOneWidget,
    );
    expect(snapshot.disposeCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('backgrounding completes a late float projection', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.controller.open(_request('background-late-float'));
    await tester.pumpAndSettle();
    await _tapFloatAndStartCapture(tester);
    await tester.pump(const Duration(milliseconds: 220));

    final snapshot = harness.capture.records.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(snapshot.disposeCount, 0);
    await tester.pump();

    expect(find.byKey(AiPosPluginSessionHost.floatProjectionKey), findsNothing);
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);
    expect(harness.capture.records.single.disposeCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('backgrounding reverts a restore before visual halfway', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('background-early-restore');
    harness.controller.open(request);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final snapshot = harness.capture.records.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(snapshot.disposeCount, 0);
    await tester.pump();

    expect(
      find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
      findsNothing,
    );
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);
    expect(
      find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId)),
      findsOneWidget,
    );
    expect(harness.capture.records.single.disposeCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('backgrounding completes a restore after visual halfway', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('background-late-restore');
    harness.controller.open(request);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    final card = find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId));
    final sourceWidth = tester.getSize(card).width;
    final fullScreenWidth = tester
        .getSize(find.byType(AiPosPluginSessionHost))
        .width;
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final projectionWidth = tester
        .getSize(find.byKey(AiPosPluginSessionHost.restoreProjectionSurfaceKey))
        .width;
    expect(projectionWidth, greaterThan((sourceWidth + fullScreenWidth) / 2));

    final snapshot = harness.capture.records.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(snapshot.disposeCount, 0);
    await tester.pump();

    expect(
      find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
      findsNothing,
    );
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
    expect(
      find.byKey(AiPosPluginSessionHost.foregroundSessionKey(request.pluginId)),
      findsOneWidget,
    );
    expect(snapshot.disposeCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('backgrounding closes a restore superseded by another card', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final firstRequest = _request('background-superseded-first');
    final secondRequest = _request('background-superseded-second');
    var firstCompleted = false;
    harness.controller.open(firstRequest).then((_) => firstCompleted = true);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    harness.controller.open(secondRequest);
    await tester.pumpAndSettle();
    await _tapFloat(tester);

    harness.controller.open(firstRequest);
    await tester.pump();
    expect(
      find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
      findsOneWidget,
    );
    harness.controller.open(secondRequest);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(firstCompleted, isTrue);
    expect(
      find.byKey(AiPosPluginSessionHost.cardKey(firstRequest.pluginId)),
      findsNothing,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        AiPosPluginSessionHost.foregroundSessionKey(secondRequest.pluginId),
      ),
      findsOneWidget,
    );
    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
  });

  testWidgets('backgrounding settles an active close projection', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launch = harness.controller.open(_request('background-close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.byKey(AiPosPluginSessionHost.closeProjectionKey),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(AiPosPluginSessionHost.closeProjectionKey), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(await launch, isNull);
  });

  testWidgets('backgrounding collapses a reveal below halfway', (tester) async {
    final harness = await _pumpHost(tester);
    harness.controller.open(_request('background-overlay'));
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    final gesture = await tester.startGesture(tester.getCenter(dock));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(find.byKey(AiPosPluginSessionHost.scrimKey), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await gesture.cancel();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final opacity = tester.widget<Opacity>(
      find.byKey(
        AiPosPluginFloatingOverlay.cardOpacityKey(
          'com.vendor.background-overlay',
        ),
      ),
    );
    expect(opacity.opacity, 0.0);
  });

  testWidgets('backgrounding expands a reveal above halfway', (tester) async {
    final harness = await _pumpHost(tester);
    harness.controller.open(_request('background-expanded-overlay'));
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    final gesture = await tester.startGesture(tester.getCenter(dock));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await gesture.cancel();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final opacity = tester.widget<Opacity>(
      find.byKey(
        AiPosPluginFloatingOverlay.cardOpacityKey(
          'com.vendor.background-expanded-overlay',
        ),
      ),
    );
    expect(opacity.opacity, 1.0);
  });

  testWidgets('any repeated host entry restores the same live page state', (
    tester,
  ) async {
    _StatefulPluginPage.reset();
    final harness = await _pumpHost(tester);
    final request = _statefulRequest('one');
    final firstLaunch = harness.controller.open(request);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('increment-one')));
    await tester.pump();
    await _tapFloat(tester);

    final secondLaunch = harness.controller.open(request);
    final thirdLaunch = harness.controller.open(request);
    await tester.pumpAndSettle();

    expect(_StatefulPluginPage.initCounts['one'], 1);
    expect(find.text('count:1'), findsOneWidget);
    expect(
      harness.capture.records.map((record) => record.disposeCount),
      everyElement(1),
    );
    expect(identical(firstLaunch, secondLaunch), isTrue);
    expect(identical(secondLaunch, thirdLaunch), isTrue);
  });

  testWidgets(
    'restart dismisses the sheet, animates close, then opens a fresh session',
    (tester) async {
      _StatefulPluginPage.reset();
      final harness = await _pumpHost(tester);
      var oldSessionCompleted = false;
      harness.controller.open(_statefulRequest('restart')).then((_) {
        oldSessionCompleted = true;
      });
      await tester.pumpAndSettle();

      expect(_StatefulPluginPage.initCounts['restart'], 1);
      expect(_StatefulPluginPage.disposeCounts['restart'], isNull);

      await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiPosPluginPageShell.restartActionKey));

      for (var frame = 0; frame < 30; frame += 1) {
        if (find
            .byKey(AiPosPluginPageShell.actionSheetKey)
            .evaluate()
            .isEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(AiPosPluginSessionHost.closeProjectionKey),
        findsOneWidget,
      );
      expect(oldSessionCompleted, isFalse);
      expect(_StatefulPluginPage.disposeCounts['restart'], isNull);
      expect(_StatefulPluginPage.initCounts['restart'], 1);

      await tester.pumpAndSettle();

      expect(oldSessionCompleted, isTrue);
      expect(_StatefulPluginPage.disposeCounts['restart'], 1);
      expect(_StatefulPluginPage.initCounts['restart'], 2);
      expect(find.text('count:0'), findsOneWidget);
    },
  );

  testWidgets('opening another plugin supersedes an in-flight restart', (
    tester,
  ) async {
    _StatefulPluginPage.reset();
    final harness = await _pumpHost(tester);
    harness.controller.open(_statefulRequest('restart-superseded'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.restartActionKey));
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find
          .byKey(AiPosPluginSessionHost.closeProjectionKey)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.byKey(AiPosPluginSessionHost.closeProjectionKey),
      findsOneWidget,
    );

    final latestLaunch = harness.controller.open(_request('after-restart'));
    await tester.pumpAndSettle();

    expect(find.text('Plugin after-restart'), findsOneWidget);
    expect(find.text('count:0'), findsNothing);
    expect(_StatefulPluginPage.initCounts['restart-superseded'], 1);

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    expect(await latestLaunch, isNull);
  });

  testWidgets('restore paints the live page before releasing its snapshot', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('one');
    harness.controller.open(request);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    final record = harness.capture.records.single;
    record.onDispose = () {
      record.cardWasAbsentAtDispose = find
          .byKey(AiPosPluginSessionHost.cardKey(request.pluginId))
          .evaluate()
          .isEmpty;
      record.foregroundWasAbsentAtDispose = find
          .byKey(AiPosPluginSessionHost.foregroundSessionKey(request.pluginId))
          .evaluate()
          .isEmpty;
      final offstageAncestors = find
          .ancestor(
            of: find.text('Plugin one', skipOffstage: false),
            matching: find.byType(Offstage, skipOffstage: false),
          )
          .evaluate()
          .map((element) => element.widget as Offstage);
      record.livePageWasOffstageAtDispose = offstageAncestors.any(
        (offstage) => offstage.offstage,
      );
    };

    harness.controller.open(request);
    await tester.pumpAndSettle();

    expect(record.disposeCount, 1);
    expect(record.cardWasAbsentAtDispose, isTrue);
    expect(record.foregroundWasAbsentAtDispose, isTrue);
    expect(record.livePageWasOffstageAtDispose, isFalse);
    expect(
      find.byKey(AiPosPluginSessionHost.foregroundSessionKey(request.pluginId)),
      findsOneWidget,
    );
  });

  testWidgets('concurrent restore calls share one disposal operation', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('one');
    harness.controller.open(request);
    await tester.pumpAndSettle();
    await _tapFloat(tester);

    harness.controller.open(request);
    harness.controller.open(request);
    await tester.pumpAndSettle();

    expect(harness.capture.records.single.disposeCount, 1);
    expect(find.text('Plugin one'), findsOneWidget);
  });

  testWidgets(
    'different restore requests serialize without stranding a session',
    (tester) async {
      final harness = await _pumpHost(tester);
      final firstRequest = _request('restore-first');
      final secondRequest = _request('restore-second');
      var firstCompleted = false;
      harness.controller.open(firstRequest).then((_) => firstCompleted = true);
      await tester.pumpAndSettle();
      await _tapFloat(tester);
      harness.controller.open(secondRequest);
      await tester.pumpAndSettle();
      await _tapFloat(tester);

      harness.controller.open(firstRequest);
      await tester.pump();
      expect(
        find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
        findsOneWidget,
      );

      harness.controller.open(secondRequest);
      await tester.pumpAndSettle();

      expect(firstCompleted, isTrue);
      expect(harness.capture.records.first.disposeCount, 1);
      expect(harness.capture.records.last.disposeCount, 1);
      expect(
        find.byKey(
          AiPosPluginSessionHost.foregroundSessionKey(secondRequest.pluginId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          AiPosPluginSessionHost.foregroundSessionKey(firstRequest.pluginId),
        ),
        findsNothing,
      );
      expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening a new plugin during restore keeps the latest plugin foreground',
    (tester) async {
      final harness = await _pumpHost(tester);
      final restoringRequest = _request('restoring-before-latest');
      final latestRequest = _request('latest-during-restore');
      harness.controller.open(restoringRequest);
      await tester.pumpAndSettle();
      await _tapFloat(tester);

      harness.controller.open(restoringRequest);
      await tester.pump();
      expect(
        find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
        findsOneWidget,
      );

      harness.controller.open(latestRequest);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          AiPosPluginSessionHost.foregroundSessionKey(latestRequest.pluginId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          AiPosPluginSessionHost.foregroundSessionKey(
            restoringRequest.pluginId,
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(AiPosPluginSessionHost.cardKey(restoringRequest.pluginId)),
        findsOneWidget,
      );

      final closing = harness.controller.closeAll();
      await tester.pump();
      await closing;
    },
  );

  testWidgets('six floating sessions keep five and close the oldest FIFO', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launches = <Future<Object?>>[];
    final completed = <String>[];

    for (var index = 1; index <= 6; index += 1) {
      final id = 'plugin-$index';
      final launch = harness.controller.open(_request(id));
      launches.add(launch);
      launch.then((_) => completed.add(id));
      await tester.pumpAndSettle();
      await _tapFloat(tester);
    }
    await tester.pumpAndSettle();

    expect(completed, <String>['plugin-1']);
    expect(harness.capture.records.first.disposeCount, 1);
    expect(
      find.byKey(AiPosPluginSessionHost.cardKey('com.vendor.plugin-1')),
      findsNothing,
    );
    for (var index = 2; index <= 6; index += 1) {
      expect(
        find.byKey(AiPosPluginSessionHost.cardKey('com.vendor.plugin-$index')),
        findsOneWidget,
      );
    }
    expect(launches.skip(1), everyElement(isA<Future<Object?>>()));
  });

  testWidgets('closeAll disposes live snapshots including a late capture', (
    tester,
  ) async {
    final lateCapture = Completer<AiPosPluginSnapshot>();
    final harness = await _pumpHost(tester);
    harness.capture.nextCapture = lateCapture.future;
    harness.controller.open(_request('late'));
    await tester.pumpAndSettle();
    await _tapFloatAndStartCapture(tester);

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    final record = _SnapshotRecord();
    lateCapture.complete(record.snapshot(width: 320, height: 480));
    await tester.pumpAndSettle();

    expect(record.disposeCount, 1);
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
    expect(find.text('Plugin late'), findsNothing);
  });

  testWidgets('capture failure leaves the plugin foreground', (tester) async {
    var failureCount = 0;
    final harness = await _pumpHost(
      tester,
      onSnapshotCaptureFailed: () => failureCount += 1,
    );
    final request = _request('failure');
    harness.capture.nextError = StateError('capture failed');
    harness.controller.open(request);
    await tester.pumpAndSettle();

    await _tapFloat(tester);

    expect(find.text('Plugin failure'), findsOneWidget);
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
    expect(failureCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capture timeout restores foreground and disposes a late result',
    (tester) async {
      final lateCapture = Completer<AiPosPluginSnapshot>();
      var failureCount = 0;
      final harness = await _pumpHost(
        tester,
        snapshotCaptureTimeout: const Duration(milliseconds: 50),
        onSnapshotCaptureFailed: () => failureCount += 1,
      );
      harness.capture.nextCapture = lateCapture.future;
      harness.controller.open(_request('timeout'));
      await tester.pumpAndSettle();

      await _tapFloatAndStartCapture(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('Plugin timeout'), findsOneWidget);
      expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
      expect(failureCount, 1);

      final record = _SnapshotRecord();
      lateCapture.complete(record.snapshot(width: 320, height: 480));
      await tester.pump();
      expect(record.disposeCount, 1);
    },
  );

  testWidgets('snapshot capture blocks reopening the action sheet', (
    tester,
  ) async {
    final pendingCapture = Completer<AiPosPluginSnapshot>();
    final harness = await _pumpHost(tester);
    harness.capture.nextCapture = pendingCapture.future;
    harness.controller.open(_request('capture-input-lock'));
    await tester.pumpAndSettle();

    await _tapFloatAndStartCapture(tester);
    await tester.tap(
      find.byKey(AiPosPluginPageShell.moreButtonKey),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);

    final record = _SnapshotRecord();
    pendingCapture.complete(record.snapshot(width: 320, height: 480));
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsOneWidget);
  });

  testWidgets('capture ratio honors 480px width and 12 MiB aggregate budget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await _pumpHost(tester);

    for (var index = 1; index <= 6; index += 1) {
      harness.controller.open(_request('tall-$index'));
      await tester.pumpAndSettle();
      await _tapFloat(tester);
    }

    expect(harness.capture.ratios.first, closeTo(0.6, 0.001));
    expect(harness.capture.ratios.last, lessThan(0.6));
    final retainedBytes = harness.capture.records
        .where((record) => record.disposeCount == 0)
        .fold<int>(0, (sum, record) => sum + record.estimatedBytes);
    expect(retainedBytes, lessThanOrEqualTo(12 * 1024 * 1024));
  });

  testWidgets('page context closes foreground or floating despite PopScope', (
    tester,
  ) async {
    final contexts = <AiPosPluginPageContext>[];
    final harness = await _pumpHost(tester);
    final foregroundFuture = harness.controller.open(
      _request('foreground', onContext: contexts.add, blocksPop: true),
    );
    await tester.pumpAndSettle();
    contexts.single.close(result: 'foreground-result');
    await tester.pumpAndSettle();
    expect(await foregroundFuture, 'foreground-result');

    final floatingFuture = harness.controller.open(
      _request('floating', onContext: contexts.add, blocksPop: true),
    );
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    contexts.last.close(result: 'floating-result');
    await tester.pumpAndSettle();

    expect(await floatingFuture, 'floating-result');
    expect(
      harness.capture.records.map((record) => record.disposeCount),
      everyElement(1),
    );
  });

  testWidgets('system back pops plugin pages before closing the session', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launch = harness.controller.open(
      AiPosPluginSessionRequest(
        pluginId: 'com.vendor.back-stack',
        pluginName: 'back-stack',
        pagePath: '/home',
        pageBuilder: (context, _) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('push-plugin-detail'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('Plugin detail')),
                  ),
                ),
              ),
              child: const Text('Plugin root'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('push-plugin-detail')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);
    expect(find.text('Plugin detail'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Plugin detail'), findsNothing);
    expect(find.text('Plugin root'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Plugin root'), findsNothing);
    expect(find.text('Host home'), findsOneWidget);
    expect(await launch, isNull);
  });

  testWidgets('foreground close projects from top-right toward lower-left', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launch = harness.controller.open(_request('projected-close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(AiPosPluginSessionHost.closeProjectionKey),
      findsOneWidget,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final opacity = tester.widget<Opacity>(
      find.byKey(AiPosPluginSessionHost.closeProjectionOpacityKey),
    );
    final transform = tester.widget<Transform>(
      find.byKey(AiPosPluginSessionHost.closeProjectionTransformKey),
    );
    expect(opacity.opacity, inExclusiveRange(0, 1));
    final progress = 1 - opacity.opacity;
    expect(
      transform.transform.entry(0, 3),
      closeTo(-0.28 * 800 * progress, 0.1),
    );
    expect(
      transform.transform.entry(1, 3),
      closeTo(0.55 * 600 * progress, 0.1),
    );

    await tester.pumpAndSettle();
    expect(await launch, isNull);
    expect(harness.capture.records.single.disposeCount, 1);
  });

  testWidgets('reduced motion close is fade-only', (tester) async {
    final harness = await _pumpHost(tester, disableAnimations: true);
    final launch = harness.controller.open(_request('reduced-close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final transform = tester.widget<Transform>(
      find.byKey(AiPosPluginSessionHost.closeProjectionTransformKey),
    );
    expect(transform.transform.entry(0, 3), 0);
    expect(transform.transform.entry(1, 3), 0);
    expect(transform.transform.entry(0, 0), 1);

    await tester.pumpAndSettle();
    expect(await launch, isNull);
  });

  testWidgets('capture failure degrades close to the current live layer', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.capture.nextError = StateError('platform view');
    final launch = harness.controller.open(_request('fallback-close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(AiPosPluginSessionHost.closeLiveTransformKey),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(await launch, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct close cancels an in-flight close projection', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launch = harness.controller.open(_request('interrupted-close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump();
      if (find
          .byKey(AiPosPluginSessionHost.closeProjectionKey)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.byKey(AiPosPluginSessionHost.closeProjectionKey),
      findsOneWidget,
    );

    final replacementLaunch = harness.controller.open(_request('replacement'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(AiPosPluginSessionHost.closeProjectionKey), findsNothing);
    expect(await launch, isNull);
    expect(harness.capture.records.single.disposeCount, 1);
    expect(tester.takeException(), isNull);

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    expect(await replacementLaunch, isNull);
  });

  testWidgets('opening the same plugin during close starts a fresh session', (
    tester,
  ) async {
    _StatefulPluginPage.reset();
    final harness = await _pumpHost(tester);
    final request = _statefulRequest('reopen-during-close');
    final firstLaunch = harness.controller.open(request);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump();
      if (find
          .byKey(AiPosPluginSessionHost.closeProjectionKey)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.byKey(AiPosPluginSessionHost.closeProjectionKey),
      findsOneWidget,
    );

    final reopenedLaunch = harness.controller.open(request);
    var reopenedCompleted = false;
    unawaited(reopenedLaunch.then((_) => reopenedCompleted = true));
    await tester.pumpAndSettle();

    expect(await firstLaunch, isNull);
    expect(reopenedCompleted, isFalse);
    expect(_StatefulPluginPage.initCounts['reopen-during-close'], 2);
    expect(_StatefulPluginPage.disposeCounts['reopen-during-close'], 1);
    expect(find.text('count:0'), findsOneWidget);

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pumpAndSettle();
    expect(await reopenedLaunch, isNull);
  });

  testWidgets('latest same-plugin request wins while close is in progress', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final initialRequest = _labeledRequest('queued-page', 'initial');
    final firstLaunch = harness.controller.open(initialRequest);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump();
      if (find
          .byKey(AiPosPluginSessionHost.closeProjectionKey)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    final staleReopen = harness.controller.open(
      _labeledRequest('queued-page', 'stale'),
    );
    final latestReopen = harness.controller.open(
      _labeledRequest('queued-page', 'latest'),
    );
    await tester.pumpAndSettle();

    expect(await firstLaunch, isNull);
    expect(staleReopen, same(latestReopen));
    expect(find.text('Plugin page latest'), findsOneWidget);
    expect(find.text('Plugin page stale'), findsNothing);

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    expect(await latestReopen, isNull);
  });

  testWidgets('a later different open supersedes a queued same-plugin reopen', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final firstRequest = _request('queued-first');
    final firstLaunch = harness.controller.open(firstRequest);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump();
      if (find
          .byKey(AiPosPluginSessionHost.closeProjectionKey)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    final queuedReopen = harness.controller.open(firstRequest);
    var queuedReopenCompleted = false;
    unawaited(queuedReopen.then((_) => queuedReopenCompleted = true));
    final latestLaunch = harness.controller.open(_request('latest'));
    await tester.pumpAndSettle();

    expect(await firstLaunch, isNull);
    expect(queuedReopenCompleted, isTrue);
    expect(find.text('Plugin latest'), findsOneWidget);
    expect(find.text('Plugin queued-first'), findsNothing);

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    expect(await queuedReopen, isNull);
    expect(await latestLaunch, isNull);
  });

  testWidgets('closeAll racing projection never double-disposes', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launch = harness.controller.open(_request('racing-close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pump();
    await tester.pump();

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    await tester.pumpAndSettle();

    expect(await launch, isNull);
    expect(harness.capture.records.single.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closeAll racing float projection never double-disposes', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final launch = harness.controller.open(_request('racing-float'));
    await tester.pumpAndSettle();
    await _tapFloatAndStartCapture(tester);
    expect(
      find.byKey(AiPosPluginSessionHost.floatProjectionKey),
      findsOneWidget,
    );

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    await tester.pumpAndSettle();

    expect(await launch, isNull);
    expect(harness.capture.records.single.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closeAll racing restore projection never double-disposes', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final request = _request('racing-restore');
    final launch = harness.controller.open(request);
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(AiPosPluginSessionHost.cardKey(request.pluginId)),
    );
    await tester.pump();
    expect(
      find.byKey(AiPosPluginSessionHost.restoreProjectionKey),
      findsOneWidget,
    );

    final closing = harness.controller.closeAll();
    await tester.pump();
    await closing;
    await tester.pumpAndSettle();

    expect(await launch, isNull);
    expect(harness.capture.records.single.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closeAll releases every session after a snapshot error', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final firstLaunch = harness.controller.open(_request('cleanup-first'));
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    final secondLaunch = harness.controller.open(_request('cleanup-second'));
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    final releaseError = StateError('snapshot release failed');
    harness.capture.records.first.disposeError = releaseError;
    final closing = harness.controller.closeAll();
    await tester.pump();
    Object? closeError;
    try {
      await closing;
    } catch (error) {
      closeError = error;
    }

    expect(closeError, isNull);
    expect(
      harness.capture.records.map((record) => record.disposeCount),
      everyElement(1),
    );
    expect(await firstLaunch, isNull);
    expect(await secondLaunch, isNull);
    expect(tester.takeException(), same(releaseError));
  });

  testWidgets('card close completes its session after a snapshot error', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    var sessionCompleted = false;
    harness.controller.open(_request('card-cleanup')).then((_) {
      sessionCompleted = true;
    });
    await tester.pumpAndSettle();
    await _tapFloat(tester);
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();
    final releaseError = StateError('card snapshot release failed');
    harness.capture.records.single.disposeError = releaseError;

    await tester.tap(
      find.byKey(
        AiPosPluginSessionHost.cardCloseKey('com.vendor.card-cleanup'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(sessionCompleted, isTrue);
    expect(harness.capture.records.single.disposeCount, 1);
    expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
    expect(tester.takeException(), same(releaseError));
  });

  testWidgets('open is rejected while closeAll is in progress', (tester) async {
    final harness = await _pumpHost(tester);
    final firstLaunch = harness.controller.open(_request('closing-first'));
    await tester.pumpAndSettle();

    final closing = harness.controller.closeAll();

    expect(
      () => harness.controller.open(_request('closing-race')),
      throwsStateError,
    );

    await tester.pump();
    await closing;
    expect(await firstLaunch, isNull);
    expect(find.byType(AiPosPluginPageShell), findsNothing);

    harness.controller.open(_request('after-closing'));
    await tester.pumpAndSettle();
    expect(find.text('Plugin after-closing'), findsOneWidget);
  });

  testWidgets('fifty full cycles release every session and snapshot owner', (
    tester,
  ) async {
    _StatefulPluginPage.reset();
    final harness = await _pumpHost(tester);

    for (var cycle = 0; cycle < 50; cycle += 1) {
      final launch = harness.controller.open(_statefulRequest('stress'));
      await tester.pumpAndSettle();
      await _tapFloat(tester);

      harness.controller.open(_statefulRequest('stress'));
      harness.controller.open(_statefulRequest('stress'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
      await tester.pumpAndSettle();
      await launch;

      expect(find.byType(AiPosPluginPageShell), findsNothing);
      expect(find.byKey(AiPosPluginSessionHost.dockKey), findsNothing);
    }

    expect(_StatefulPluginPage.initCounts['stress'], 50);
    expect(_StatefulPluginPage.disposeCounts['stress'], 50);
    expect(harness.capture.records, hasLength(100));
    expect(
      harness.capture.records.map((record) => record.disposeCount),
      everyElement(1),
    );
    expect(tester.takeException(), isNull);
  });

  group('real engine image ownership', () {
    late ui.Image baseImage;

    setUpAll(() async {
      baseImage = await createTestImage(width: 32, height: 48, cache: false);
    });

    tearDownAll(() {
      baseImage.dispose();
      expect(baseImage.debugGetOpenHandleStackTraces(), isEmpty);
    });

    testWidgets('fifty full cycles release every image handle', (tester) async {
      final controller = AiPosPluginSessionHostController();
      final images = <ui.Image>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AiPosPluginSessionHost(
            controller: controller,
            strings: const AiPosPluginPageShellStrings(floatingLabel: 'Float'),
            snapshotCapture: (boundary, pixelRatio) async {
              final image = baseImage.clone();
              images.add(image);
              return AiPosPluginSnapshot.image(image);
            },
            child: const Scaffold(body: Center(child: Text('Host home'))),
          ),
        ),
      );

      for (var cycle = 0; cycle < 50; cycle += 1) {
        final launch = controller.open(_request('real-image-$cycle'));
        await tester.pumpAndSettle();
        await _tapFloat(tester);
        controller.open(_request('real-image-$cycle'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
        await tester.pumpAndSettle();
        await launch;

        expect(
          images.every((image) => image.debugDisposed),
          isTrue,
          reason: 'cycle $cycle retained an engine image handle',
        );
        expect(baseImage.debugGetOpenHandleStackTraces(), hasLength(1));
      }

      expect(images, hasLength(100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.dispose();
    });
  });
}

Future<_Harness> _pumpHost(
  WidgetTester tester, {
  bool disableAnimations = false,
  Duration snapshotCaptureTimeout = const Duration(seconds: 3),
  VoidCallback? onSnapshotCaptureFailed,
}) async {
  final controller = AiPosPluginSessionHostController();
  final capture = _FakeCapture();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: AiPosPluginSessionHost(
            controller: controller,
            strings: const AiPosPluginPageShellStrings(floatingLabel: 'Float'),
            snapshotCapture: capture.call,
            snapshotCaptureTimeout: snapshotCaptureTimeout,
            onSnapshotCaptureFailed: onSnapshotCaptureFailed,
            child: const Scaffold(body: Center(child: Text('Host home'))),
          ),
        ),
      ),
    ),
  );
  return _Harness(controller, capture);
}

Future<void> _tapFloat(WidgetTester tester) async {
  await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AiPosPluginPageShell.floatActionKey));
  await tester.pumpAndSettle();
}

Future<void> _tapFloatAndStartCapture(WidgetTester tester) async {
  await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AiPosPluginPageShell.floatActionKey));
  for (var frame = 0; frame < 30; frame += 1) {
    if (find.byKey(AiPosPluginPageShell.actionSheetKey).evaluate().isEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);
  await tester.pump();
  await tester.pump();
}

AiPosPluginSessionRequest _request(
  String id, {
  ValueChanged<AiPosPluginPageContext>? onContext,
  bool blocksPop = false,
}) {
  return AiPosPluginSessionRequest(
    pluginId: 'com.vendor.$id',
    pluginName: id,
    pagePath: '/home',
    pageBuilder: (_, context) {
      onContext?.call(context);
      final page = Scaffold(body: Center(child: Text('Plugin $id')));
      return blocksPop ? PopScope(canPop: false, child: page) : page;
    },
  );
}

AiPosPluginSessionRequest _statefulRequest(String id) {
  return AiPosPluginSessionRequest(
    pluginId: 'com.vendor.$id',
    pluginName: id,
    pagePath: '/home',
    pageBuilder: (_, _) => _StatefulPluginPage(id: id),
  );
}

AiPosPluginSessionRequest _labeledRequest(String id, String label) {
  return AiPosPluginSessionRequest(
    pluginId: 'com.vendor.$id',
    pluginName: id,
    pagePath: '/$label',
    pageBuilder: (_, _) =>
        Scaffold(body: Center(child: Text('Plugin page $label'))),
  );
}

final class _Harness {
  const _Harness(this.controller, this.capture);

  final AiPosPluginSessionHostController controller;
  final _FakeCapture capture;
}

final class _BackTestRouterDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  _BackTestRouterDelegate({this.handlePop = false});

  final bool handlePop;
  var popRouteCount = 0;

  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: const [
        MaterialPage<void>(
          child: Scaffold(body: Center(child: Text('Host router'))),
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }

  @override
  Future<bool> popRoute() async {
    popRouteCount += 1;
    return handlePop;
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

final class _FakeCapture {
  final List<double> ratios = [];
  final List<_SnapshotRecord> records = [];
  Future<AiPosPluginSnapshot>? nextCapture;
  Object? nextError;

  Future<AiPosPluginSnapshot> call(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    ratios.add(pixelRatio);
    final error = nextError;
    nextError = null;
    if (error != null) {
      throw error;
    }
    final pending = nextCapture;
    nextCapture = null;
    if (pending != null) {
      return pending;
    }
    final record = _SnapshotRecord();
    records.add(record);
    return record.snapshot(
      width: (boundary.size.width * pixelRatio).round().clamp(1, 10000),
      height: (boundary.size.height * pixelRatio).round().clamp(1, 10000),
    );
  }
}

final class _SnapshotRecord {
  int disposeCount = 0;
  int estimatedBytes = 0;
  bool? cardWasAbsentAtDispose;
  bool? foregroundWasAbsentAtDispose;
  bool? livePageWasOffstageAtDispose;
  Object? disposeError;
  VoidCallback? onDispose;

  AiPosPluginSnapshot snapshot({required int width, required int height}) {
    estimatedBytes = width * height * 4;
    return AiPosPluginSnapshot(
      width: width,
      height: height,
      builder: ({key, required fit}) =>
          ColoredBox(key: key, color: Colors.blue),
      onDispose: () {
        disposeCount += 1;
        onDispose?.call();
        if (disposeError case final error?) {
          throw error;
        }
      },
    );
  }
}

final class _StatefulPluginPage extends StatefulWidget {
  const _StatefulPluginPage({required this.id});

  static final Map<String, int> initCounts = {};
  static final Map<String, int> disposeCounts = {};

  static void reset() {
    initCounts.clear();
    disposeCounts.clear();
  }

  final String id;

  @override
  State<_StatefulPluginPage> createState() => _StatefulPluginPageState();
}

final class _StatefulPluginPageState extends State<_StatefulPluginPage> {
  int count = 0;

  @override
  void initState() {
    super.initState();
    _StatefulPluginPage.initCounts.update(
      widget.id,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  void dispose() {
    _StatefulPluginPage.disposeCounts.update(
      widget.id,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: Key('increment-${widget.id}'),
          onPressed: () => setState(() => count += 1),
          child: Text('count:$count'),
        ),
      ),
    );
  }
}
