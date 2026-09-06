import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('interactive dismiss follows raw drag progress', (tester) async {
    const sourceRect = Rect.fromLTWH(24, 80, 72, 72);
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          launchOrigin: const FloatingSessionLaunchOrigin(
            sourceRect: sourceRect,
            viewportSize: Size(800, 600),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final begin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'a',
      keepForegroundAsFloating: false,
    );
    await tester.pump();
    final handle = (await begin)!;
    handle.updateProgress(0.35);
    await tester.pump();

    final snapshot = find.descendant(
      of: find.byKey(
        const Key('ai-pos-floating-workspace-interactive-dismiss-projection'),
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.blue,
      ),
    );
    expect(snapshot, findsOneWidget);
    final viewport =
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    _expectRectClose(
      tester.getRect(snapshot),
      Rect.lerp(viewport, sourceRect, 0.35)!,
      epsilon: 0.01,
    );
    expect(handle.progress, 0.35);

    final cancel = handle.cancel();
    await tester.pumpAndSettle();
    await cancel;
  });

  testWidgets('interactive dismiss completion closes the foreground', (
    tester,
  ) async {
    var closed = 0;
    var disposed = 0;
    final harness = await _pumpHost(
      tester,
      capture: (_, _) async => FloatingSnapshot.memory(
        width: 100,
        height: 160,
        builder: ({key, required fit}) =>
            ColoredBox(key: key, color: Colors.blue),
        onDispose: () => disposed += 1,
      ),
    );
    unawaited(
      harness.agent.open(_request('agent', 'a', onClosed: (_) => closed += 1)),
    );
    await tester.pumpAndSettle();

    final begin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'a',
      keepForegroundAsFloating: false,
    );
    await tester.pump();
    final handle = (await begin)!..updateProgress(0.75);
    final settle = handle.settle(velocityX: 0);
    await tester.pumpAndSettle();

    expect(await settle, FloatingSessionSwitchOutcome.completed);
    expect(closed, 1);
    expect(disposed, 1);
    expect(harness.agent.sessionCount, 0);
    expect(find.text('agent-a'), findsNothing);
  });

  testWidgets('interactive dismiss completion retains a floating foreground', (
    tester,
  ) async {
    var disposed = 0;
    final visibility = <FloatingSessionVisibility>[];
    final harness = await _pumpHost(
      tester,
      capture: (_, _) async => FloatingSnapshot.memory(
        width: 100,
        height: 160,
        builder: ({key, required fit}) =>
            ColoredBox(key: key, color: Colors.blue),
        onDispose: () => disposed += 1,
      ),
    );
    unawaited(
      harness.agent.open(
        _request('agent', 'a', onVisibilityChanged: visibility.add),
      ),
    );
    await tester.pumpAndSettle();

    final begin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'a',
      keepForegroundAsFloating: true,
    );
    await tester.pump();
    final handle = (await begin)!..updateProgress(0.75);
    final settle = handle.settle(velocityX: 0);
    await tester.pumpAndSettle();

    expect(await settle, FloatingSessionSwitchOutcome.completed);
    expect(visibility, [
      FloatingSessionVisibility.foreground,
      FloatingSessionVisibility.floating,
    ]);
    expect(disposed, 0);
    expect(harness.agent.sessionCount, 1);
    const key = FloatingSessionKey(domainId: 'agent', sessionId: 'a');
    expect(
      find.byKey(FloatingWorkspaceHost.foregroundSessionKey(key)),
      findsNothing,
    );
    expect(find.byKey(FloatingDock.cardKey(key)), findsOneWidget);

    final cleanup = harness.agent.closeAll();
    await tester.pumpAndSettle();
    await cleanup;
    expect(disposed, 1);
  });

  testWidgets('closeAll cancels interactive dismiss before cleanup', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    final begin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'a',
      keepForegroundAsFloating: false,
    );
    await tester.pump();
    (await begin)!.updateProgress(0.35);
    await tester.pump();
    expect(
      find.byKey(FloatingWorkspaceHost.interactiveDismissProjectionKey),
      findsOneWidget,
    );

    final cleanup = harness.agent.closeAll();
    await tester.pumpAndSettle();
    await cleanup;

    expect(harness.agent.sessionCount, 0);
    expect(
      find.byKey(FloatingWorkspaceHost.interactiveDismissProjectionKey),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive dismiss blocks overlapping opens', (tester) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    final begin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'a',
      keepForegroundAsFloating: false,
    );
    await tester.pump();
    final handle = (await begin)!;

    expect(() => harness.agent.open(_request('agent', 'b')), throwsStateError);

    final cancel = handle.cancel();
    await tester.pumpAndSettle();
    await cancel;
  });

  testWidgets('interactive switch rejects an active dismiss', (tester) async {
    final harness = await _pumpHost(tester);
    await _openFloatingThenForeground(tester, harness.agent);

    final dismissBegin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'b',
      keepForegroundAsFloating: false,
    );
    await tester.pump();
    final dismiss = (await dismissBegin)!;

    final interactiveSwitch = await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.right,
      keepForegroundAsFloating: false,
    );

    expect(interactiveSwitch, isNull);
    final cancel = dismiss.cancel();
    await tester.pumpAndSettle();
    await cancel;
  });

  testWidgets('float action is ignored during interactive dismiss', (
    tester,
  ) async {
    late FloatingSessionActions actions;
    final visibility = <FloatingSessionVisibility>[];
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        FloatingSessionRequest(
          key: const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
          title: 'agent-a',
          pageBuilder: (_, value) {
            actions = value;
            return const Material(child: Text('agent-a'));
          },
          maybePopNested: () async => false,
          onVisibilityChanged: visibility.add,
          onClosed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final begin = harness.agent.beginInteractiveDismiss(
      foregroundSessionId: 'a',
      keepForegroundAsFloating: false,
    );
    await tester.pump();
    final dismiss = (await begin)!;

    final floatAttempt = actions.float();
    await tester.pump();
    await tester.pump();

    expect(visibility, [FloatingSessionVisibility.foreground]);
    expect(
      find.byKey(FloatingWorkspaceHost.interactiveDismissProjectionKey),
      findsOneWidget,
    );
    final cancel = dismiss.cancel();
    await tester.pumpAndSettle();
    await floatAttempt;
    await cancel;
  });

  testWidgets('interactive restore follows raw progress without recapture', (
    tester,
  ) async {
    var captureCount = 0;
    final harness = await _pumpHost(
      tester,
      capture: (boundary, pixelRatio) async {
        captureCount += 1;
        return _capture(boundary, pixelRatio);
      },
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();
    unawaited(harness.agent.open(_request('agent', 'b')));
    await tester.pumpAndSettle();
    final targetKey = const FloatingSessionKey(
      domainId: 'agent',
      sessionId: 'a',
    );
    final targetRect = tester.getRect(
      find.byKey(FloatingDock.cardTransformKey(targetKey)),
    );
    final capturesBeforeDrag = captureCount;

    final handle = await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: false,
    );
    expect(handle, isNotNull);
    handle!.updateProgress(0.35);
    await tester.pump();

    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final expected = Rect.lerp(targetRect, Offset.zero & viewport, 0.35)!;
    _expectRectClose(
      tester.getRect(
        find.byKey(FloatingWorkspaceHost.interactiveSwitchProjectionKey),
      ),
      expected,
      epsilon: 0.01,
    );
    expect(find.byKey(FloatingDock.cardKey(targetKey)), findsNothing);
    expect(handle.progress, 0.35);
    expect(captureCount, capturesBeforeDrag);

    handle.updateProgress(-1);
    expect(handle.progress, 0);
    handle.updateProgress(2);
    expect(handle.progress, 1);
    expect(captureCount, capturesBeforeDrag);

    final cancel = handle.cancel();
    await tester.pumpAndSettle();
    await cancel;
    expect(
      find.byKey(
        FloatingWorkspaceHost.foregroundSessionKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'b'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(FloatingDock.cardKey(targetKey)), findsOneWidget);
  });

  testWidgets('interactive completion closes an empty foreground', (
    tester,
  ) async {
    var disposedSnapshots = 0;
    var closedForeground = 0;
    final harness = await _pumpHost(
      tester,
      capture: (boundary, pixelRatio) async => FloatingSnapshot.memory(
        width: 100,
        height: 160,
        builder: ({key, required fit}) =>
            ColoredBox(key: key, color: Colors.blue),
        onDispose: () => disposedSnapshots += 1,
      ),
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();
    unawaited(
      harness.agent.open(
        _request('agent', 'b', onClosed: (_) => closedForeground += 1),
      ),
    );
    await tester.pumpAndSettle();

    final handle = (await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: false,
    ))!;
    handle.updateProgress(0.75);
    final settle = handle.settle(velocityX: 0);
    expect(handle.settle(velocityX: -3000), same(settle));
    await tester.pumpAndSettle();

    expect(await settle, FloatingSessionSwitchOutcome.completed);
    expect(closedForeground, 1);
    expect(disposedSnapshots, 1);
    expect(harness.agent.sessionCount, 1);
    expect(
      find.byKey(
        FloatingWorkspaceHost.foregroundSessionKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'interactive completion retains a conversed foreground as newest',
    (tester) async {
      final disposedCaptureIndexes = <int>[];
      var captureIndex = 0;
      final harness = await _pumpHost(
        tester,
        capture: (boundary, pixelRatio) async {
          final index = captureIndex++;
          return FloatingSnapshot.memory(
            width: 100,
            height: 160,
            builder: ({key, required fit}) =>
                ColoredBox(key: key, color: Colors.blue),
            onDispose: () => disposedCaptureIndexes.add(index),
          );
        },
      );
      unawaited(harness.agent.open(_request('agent', 'a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pumpAndSettle();
      unawaited(harness.agent.open(_request('agent', 'b')));
      await tester.pumpAndSettle();

      final begin = harness.agent.beginInteractiveSwitch(
        foregroundSessionId: 'b',
        targetSessionId: 'a',
        direction: FloatingSessionSwitchDirection.right,
        keepForegroundAsFloating: true,
      );
      await tester.pump();
      final handle = (await begin)!;
      expect(captureIndex, 2);
      handle.updateProgress(0.75);
      final settle = handle.settle(velocityX: 0);
      await tester.pumpAndSettle();

      expect(await settle, FloatingSessionSwitchOutcome.completed);
      expect(disposedCaptureIndexes, [0]);
      expect(harness.agent.sessionCount, 2);
      expect(
        tester
            .widget<FloatingDock>(find.byType(FloatingDock))
            .cards
            .map((card) => card.id),
        [const FloatingSessionKey(domainId: 'agent', sessionId: 'b')],
      );
      expect(
        find.byKey(
          FloatingWorkspaceHost.foregroundSessionKey(
            const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('interactive switch rejects invalid and overlapping starts', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    await _openFloatingThenForeground(tester, harness.agent);

    expect(
      await harness.agent.beginInteractiveSwitch(
        foregroundSessionId: 'a',
        targetSessionId: 'b',
        direction: FloatingSessionSwitchDirection.left,
        keepForegroundAsFloating: false,
      ),
      isNull,
    );
    expect(
      await harness.agent.beginInteractiveSwitch(
        foregroundSessionId: 'b',
        targetSessionId: 'missing',
        direction: FloatingSessionSwitchDirection.left,
        keepForegroundAsFloating: false,
      ),
      isNull,
    );

    final handle = await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: false,
    );
    expect(handle, isNotNull);
    expect(
      await harness.agent.beginInteractiveSwitch(
        foregroundSessionId: 'b',
        targetSessionId: 'a',
        direction: FloatingSessionSwitchDirection.right,
        keepForegroundAsFloating: false,
      ),
      isNull,
    );
    final cancel = handle!.cancel();
    await tester.pumpAndSettle();
    await cancel;
    expect(harness.agent.sessionCount, 2);
  });

  testWidgets('direction-normalized velocity completes a short restore', (
    tester,
  ) async {
    for (final direction in FloatingSessionSwitchDirection.values) {
      final harness = await _pumpHost(tester);
      await _openFloatingThenForeground(tester, harness.agent);
      final handle = (await harness.agent.beginInteractiveSwitch(
        foregroundSessionId: 'b',
        targetSessionId: 'a',
        direction: direction,
        keepForegroundAsFloating: false,
      ))!;
      handle.updateProgress(0.2);
      final settle = handle.settle(
        velocityX: direction == FloatingSessionSwitchDirection.left
            ? -2000
            : 2000,
      );
      await tester.pumpAndSettle();
      expect(await settle, FloatingSessionSwitchOutcome.completed);
      final closeAll = harness.agent.closeAll();
      await tester.pumpAndSettle();
      await closeAll;
    }
  });

  testWidgets('closeAll cancels an interactive switch before cleanup', (
    tester,
  ) async {
    var captureIndex = 0;
    final disposedCaptureIndexes = <int>[];
    final harness = await _pumpHost(
      tester,
      capture: (boundary, pixelRatio) async {
        final index = captureIndex++;
        return FloatingSnapshot.memory(
          width: 100,
          height: 160,
          builder: ({key, required fit}) =>
              ColoredBox(key: key, color: Colors.blue),
          onDispose: () => disposedCaptureIndexes.add(index),
        );
      },
    );
    await _openFloatingThenForeground(tester, harness.agent);
    final begin = harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: true,
    );
    await tester.pump();
    final handle = (await begin)!..updateProgress(0.4);

    final closeAll = harness.agent.closeAll();
    await tester.pumpAndSettle();
    await closeAll;

    expect(harness.agent.sessionCount, 0);
    expect(
      find.byKey(FloatingWorkspaceHost.interactiveSwitchProjectionKey),
      findsNothing,
    );
    expect(disposedCaptureIndexes, unorderedEquals([0, 1, 2]));
    expect(disposedCaptureIndexes.toSet(), hasLength(3));
    expect(
      await handle.settle(velocityX: -2000),
      FloatingSessionSwitchOutcome.cancelled,
    );
  });

  testWidgets('slow release below threshold returns target to its card', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    await _openFloatingThenForeground(tester, harness.agent);
    final handle = (await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: false,
    ))!;
    handle.updateProgress(0.49);

    final settle = handle.settle(velocityX: 0);
    await tester.pumpAndSettle();

    expect(await settle, FloatingSessionSwitchOutcome.cancelled);
    expect(harness.agent.sessionCount, 2);
    expect(
      find.byKey(
        FloatingWorkspaceHost.foregroundSessionKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'b'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        FloatingDock.cardKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('closing during an interactive switch cancels it first', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    await _openFloatingThenForeground(tester, harness.agent);
    final handle = (await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: false,
    ))!..updateProgress(0.4);

    final close = harness.agent.close('b');
    await tester.pumpAndSettle();
    await close;

    expect(harness.agent.sessionCount, 1);
    expect(
      await handle.settle(velocityX: -2000),
      FloatingSessionSwitchOutcome.cancelled,
    );
    expect(
      find.byKey(FloatingWorkspaceHost.interactiveSwitchProjectionKey),
      findsNothing,
    );
    expect(
      find.byKey(
        FloatingDock.cardKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('reduced motion maps progress to full-screen opacity', (
    tester,
  ) async {
    final harness = await _pumpHost(tester, disableAnimations: true);
    await _openFloatingThenForeground(tester, harness.agent);
    final handle = (await harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: false,
    ))!..updateProgress(0.4);
    await tester.pump();

    final projection = find.byKey(
      FloatingWorkspaceHost.interactiveSwitchProjectionKey,
    );
    expect(
      tester.getRect(projection),
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio),
    );
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: projection, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0.4);

    final cancel = handle.cancel();
    await tester.pumpAndSettle();
    await cancel;
  });

  testWidgets('timed out interactive capture disposes its late snapshot', (
    tester,
  ) async {
    final lateCapture = Completer<FloatingSnapshot>();
    final captureFailures = <FloatingSessionKey>[];
    var captureCount = 0;
    var lateDisposeCount = 0;
    final harness = await _pumpHost(
      tester,
      captureTimeout: const Duration(milliseconds: 10),
      onCaptureFailed: captureFailures.add,
      capture: (boundary, pixelRatio) {
        captureCount += 1;
        if (captureCount == 1) {
          return _capture(boundary, pixelRatio);
        }
        return lateCapture.future;
      },
    );
    await _openFloatingThenForeground(tester, harness.agent);

    final begin = harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 11));
    expect(await begin, isNull);
    lateCapture.complete(
      FloatingSnapshot.memory(
        width: 100,
        height: 160,
        builder: ({key, required fit}) =>
            ColoredBox(key: key, color: Colors.blue),
        onDispose: () => lateDisposeCount += 1,
      ),
    );
    await tester.pump();

    expect(lateDisposeCount, 1);
    expect(captureFailures, [
      const FloatingSessionKey(domainId: 'agent', sessionId: 'b'),
    ]);
    expect(harness.agent.sessionCount, 2);
  });

  testWidgets(
    'system back cancels interactive restore without closing source',
    (tester) async {
      final harness = await _pumpHost(tester);
      await _openFloatingThenForeground(tester, harness.agent);
      final handle = (await harness.agent.beginInteractiveSwitch(
        foregroundSessionId: 'b',
        targetSessionId: 'a',
        direction: FloatingSessionSwitchDirection.left,
        keepForegroundAsFloating: false,
      ))!..updateProgress(0.4);

      final handled = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(await handled, isTrue);
      expect(harness.agent.sessionCount, 2);
      expect(
        await handle.settle(velocityX: -2000),
        FloatingSessionSwitchOutcome.cancelled,
      );
      expect(
        find.byKey(
          FloatingWorkspaceHost.foregroundSessionKey(
            const FloatingSessionKey(domainId: 'agent', sessionId: 'b'),
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('disposing host releases interactive snapshots exactly once', (
    tester,
  ) async {
    var captureIndex = 0;
    final disposedCaptureIndexes = <int>[];
    final harness = await _pumpHost(
      tester,
      capture: (boundary, pixelRatio) async {
        final index = captureIndex++;
        return FloatingSnapshot.memory(
          width: 100,
          height: 160,
          builder: ({key, required fit}) =>
              ColoredBox(key: key, color: Colors.blue),
          onDispose: () => disposedCaptureIndexes.add(index),
        );
      },
    );
    await _openFloatingThenForeground(tester, harness.agent);
    final begin = harness.agent.beginInteractiveSwitch(
      foregroundSessionId: 'b',
      targetSessionId: 'a',
      direction: FloatingSessionSwitchDirection.left,
      keepForegroundAsFloating: true,
    );
    await tester.pump();
    final handle = (await begin)!..updateProgress(0.4);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(disposedCaptureIndexes, unorderedEquals([0, 1]));
    expect(disposedCaptureIndexes.toSet(), hasLength(2));
    expect(
      await handle.settle(velocityX: -2000),
      FloatingSessionSwitchOutcome.cancelled,
    );
  });

  testWidgets('default request opens immediately without initial projection', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);

    unawaited(harness.plugin.open(_request('plugin', 'p')));
    await tester.pump();

    expect(find.byKey(FloatingWorkspaceHost.openProjectionKey), findsNothing);
    expect(find.text('plugin-p'), findsOneWidget);
  });

  testWidgets(
    'new session projects from a valid launch origin before admission',
    (tester) async {
      final visibility = <FloatingSessionVisibility>[];
      final harness = await _pumpHost(tester);

      unawaited(
        harness.agent.open(
          _request(
            'agent',
            'a',
            animateInitialPresentation: true,
            launchOrigin: const FloatingSessionLaunchOrigin(
              sourceRect: Rect.fromLTWH(24, 80, 72, 72),
              viewportSize: Size(800, 600),
            ),
            onVisibilityChanged: visibility.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(FloatingWorkspaceHost.openProjectionKey),
        findsOneWidget,
      );
      final openingSnapshot = find.descendant(
        of: find.byKey(FloatingWorkspaceHost.openProjectionKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.blue,
        ),
      );
      expect(openingSnapshot, findsOneWidget);
      _expectRectClose(
        tester.getRect(openingSnapshot),
        const Rect.fromLTWH(24, 80, 72, 72),
      );
      expect(visibility, isEmpty);

      await tester.pumpAndSettle();

      expect(visibility, [FloatingSessionVisibility.foreground]);
      expect(find.text('agent-a'), findsOneWidget);
    },
  );

  testWidgets('opted-in session without an origin uses centered fallback', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);

    unawaited(
      harness.agent.open(
        _request('agent', 'a', animateInitialPresentation: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    final openingSnapshot = find.descendant(
      of: find.byKey(FloatingWorkspaceHost.openProjectionKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.blue,
      ),
    );
    expect(openingSnapshot, findsOneWidget);
    _expectRectClose(
      tester.getRect(openingSnapshot),
      const Rect.fromLTWH(16, 12, 768, 576),
    );

    await tester.pumpAndSettle();
  });

  testWidgets(
    'latest same-domain request cancels opening before foreground admission',
    (tester) async {
      final firstVisibility = <FloatingSessionVisibility>[];
      final secondVisibility = <FloatingSessionVisibility>[];
      final harness = await _pumpHost(tester);
      final firstCompletion = harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          onVisibilityChanged: firstVisibility.add,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(FloatingWorkspaceHost.openProjectionKey),
        findsOneWidget,
      );

      unawaited(
        harness.agent.open(
          _request(
            'agent',
            'b',
            animateInitialPresentation: true,
            onVisibilityChanged: secondVisibility.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await firstCompletion;

      expect(firstVisibility, [FloatingSessionVisibility.closing]);
      expect(secondVisibility, [FloatingSessionVisibility.foreground]);
      expect(harness.agent.sessionCount, 1);
      expect(find.text('agent-a'), findsNothing);
      expect(find.text('agent-b'), findsOneWidget);
    },
  );

  testWidgets('separate domains keep five cards each in one Dock', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);

    for (final domain in [harness.plugin, harness.agent]) {
      for (var index = 1; index <= 5; index += 1) {
        unawaited(domain.open(_request(domain.domainId, '$index')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('float-session')));
        await tester.pumpAndSettle();
      }
    }

    expect(find.byKey(FloatingWorkspaceHost.dockKey), findsOneWidget);
    expect(harness.plugin.sessionCount, 5);
    expect(harness.agent.sessionCount, 5);
    for (final domain in ['plugin', 'agent']) {
      for (var index = 1; index <= 5; index += 1) {
        expect(
          find.byKey(
            FloatingDock.cardKey(
              FloatingSessionKey(domainId: domain, sessionId: '$index'),
            ),
          ),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('Dock cards follow interleaved global float chronology', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    for (final (domain, id) in [
      (harness.plugin, 'p1'),
      (harness.agent, 'a1'),
      (harness.plugin, 'p2'),
    ]) {
      unawaited(domain.open(_request(domain.domainId, id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pumpAndSettle();
    }

    final dock = tester.widget<FloatingDock>(find.byType(FloatingDock));
    expect(dock.cards.map((card) => card.id), [
      const FloatingSessionKey(domainId: 'plugin', sessionId: 'p1'),
      const FloatingSessionKey(domainId: 'agent', sessionId: 'a1'),
      const FloatingSessionKey(domainId: 'plugin', sessionId: 'p2'),
    ]);
  });

  testWidgets(
    'existing Dock receives a new card before float projection ends',
    (tester) async {
      final harness = await _pumpHost(tester);
      unawaited(harness.agent.open(_request('agent', 'a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pumpAndSettle();
      final originalDockState = tester.state(find.byType(FloatingDock));

      unawaited(harness.agent.open(_request('agent', 'b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(FloatingWorkspaceHost.floatProjectionKey),
        findsOneWidget,
      );
      expect(tester.state(find.byType(FloatingDock)), same(originalDockState));
      expect(
        tester
            .widget<FloatingDock>(find.byType(FloatingDock))
            .cards
            .map((card) => card.id),
        [
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
          const FloatingSessionKey(domainId: 'agent', sessionId: 'b'),
        ],
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets('closing a back card keeps the remaining Dock stack expanded', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    for (final id in ['a', 'b', 'c']) {
      unawaited(harness.agent.open(_request('agent', id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        FloatingDock.cardCloseKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.agent.sessionCount, 2);
    expect(find.byKey(FloatingDock.scrimKey), findsOneWidget);
    for (final id in ['b', 'c']) {
      expect(
        tester
            .widget<Opacity>(
              find.byKey(
                FloatingDock.cardOpacityKey(
                  FloatingSessionKey(domainId: 'agent', sessionId: id),
                ),
              ),
            )
            .opacity,
        1,
      );
    }
  });

  testWidgets('same key restores while cross-domain foreground is busy', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final first = harness.agent.open(_request('agent', 'a'));
    await tester.pumpAndSettle();

    expect(
      () => harness.plugin.open(_request('plugin', 'p')),
      throwsA(isA<FloatingWorkspaceBusyException>()),
    );

    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();
    final second = harness.agent.open(_request('agent', 'a'));
    await tester.pumpAndSettle();

    expect(second, same(first));
    expect(find.text('agent-a'), findsOneWidget);
    expect(harness.agent.sessionCount, 1);
  });

  testWidgets('same-domain restore replaces the foreground session', (
    tester,
  ) async {
    final closed = <String>[];
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        _request('agent', 'a', onClosed: (_) => closed.add('a')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();

    unawaited(
      harness.agent.open(
        _request('agent', 'b', onClosed: (_) => closed.add('b')),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    expect(find.text('agent-a'), findsOneWidget);
    expect(find.text('agent-b'), findsNothing);
    expect(closed, ['b']);
    expect(harness.agent.sessionCount, 1);
  });

  testWidgets('float and restore retain the snapshot projection motion', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('ai-pos-floating-workspace-float-projection')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        FloatingDock.cardKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('ai-pos-floating-workspace-restore-projection')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('agent-a'), findsOneWidget);
  });

  testWidgets('foreground close retains its snapshot projection motion', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('close-session')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('ai-pos-floating-workspace-close-projection')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(harness.agent.sessionCount, 0);
    expect(find.text('agent-a'), findsNothing);
  });

  testWidgets('direct close projects back to the valid launch origin', (
    tester,
  ) async {
    const sourceRect = Rect.fromLTWH(24, 80, 72, 72);
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          launchOrigin: const FloatingSessionLaunchOrigin(
            sourceRect: sourceRect,
            viewportSize: Size(800, 600),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('close-session')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));

    final snapshot = find.descendant(
      of: find.byKey(FloatingWorkspaceHost.closeProjectionKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.blue,
      ),
    );
    expect(snapshot, findsOneWidget);
    _expectRectClose(tester.getRect(snapshot), sourceRect);

    await tester.pumpAndSettle();
    expect(harness.agent.sessionCount, 0);
  });

  testWidgets('floating permanently invalidates the initial launch origin', (
    tester,
  ) async {
    const sourceRect = Rect.fromLTWH(24, 80, 72, 72);
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          launchOrigin: const FloatingSessionLaunchOrigin(
            sourceRect: sourceRect,
            viewportSize: Size(800, 600),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        FloatingDock.cardKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('close-session')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));

    final snapshot = find.descendant(
      of: find.byKey(FloatingWorkspaceHost.closeProjectionKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.blue,
      ),
    );
    expect(snapshot, findsOneWidget);
    expect(_rectIsClose(tester.getRect(snapshot), sourceRect), isFalse);
  });

  testWidgets(
    'initial capture timeout admits live session and disposes late snapshot',
    (tester) async {
      final capture = Completer<FloatingSnapshot>();
      final disposed = Completer<void>();
      final visibility = <FloatingSessionVisibility>[];
      var disposeCount = 0;
      final harness = await _pumpHost(
        tester,
        capture: (_, _) => capture.future,
        captureTimeout: const Duration(milliseconds: 1),
      );

      unawaited(
        harness.agent.open(
          _request(
            'agent',
            'a',
            animateInitialPresentation: true,
            onVisibilityChanged: visibility.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2));

      expect(visibility, [FloatingSessionVisibility.foreground]);
      expect(find.text('agent-a'), findsOneWidget);
      expect(find.byKey(FloatingWorkspaceHost.openProjectionKey), findsNothing);

      await tester.runAsync(() async {
        capture.complete(
          FloatingSnapshot.memory(
            width: 10,
            height: 10,
            builder: ({key, required fit}) => const SizedBox(),
            onDispose: () {
              disposeCount += 1;
              disposed.complete();
            },
          ),
        );
        await disposed.future;
      });
      expect(disposeCount, 1);
    },
  );

  testWidgets(
    'closeAll cancels initial capture without admitting the session',
    (tester) async {
      final capture = Completer<FloatingSnapshot>();
      final visibility = <FloatingSessionVisibility>[];
      var disposeCount = 0;
      final harness = await _pumpHost(
        tester,
        capture: (_, _) => capture.future,
      );
      final completion = harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          onVisibilityChanged: visibility.add,
        ),
      );
      await tester.pump();
      await tester.pump();

      var closeCompleted = false;
      unawaited(harness.agent.closeAll().then((_) => closeCompleted = true));
      await tester.pump();
      await tester.pump();
      final completedBeforeCaptureReturned = closeCompleted;

      capture.complete(
        FloatingSnapshot.memory(
          width: 10,
          height: 10,
          builder: ({key, required fit}) => const SizedBox(),
          onDispose: () => disposeCount += 1,
        ),
      );
      await tester.pumpAndSettle();
      await completion;

      expect(completedBeforeCaptureReturned, isTrue);
      expect(visibility, [FloatingSessionVisibility.closing]);
      expect(harness.agent.sessionCount, 0);
      expect(disposeCount, 1);
    },
  );

  testWidgets(
    'close cancels an opening projection without foreground admission',
    (tester) async {
      final visibility = <FloatingSessionVisibility>[];
      final harness = await _pumpHost(tester);
      final completion = harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          launchOrigin: const FloatingSessionLaunchOrigin(
            sourceRect: Rect.fromLTWH(24, 80, 72, 72),
            viewportSize: Size(800, 600),
          ),
          onVisibilityChanged: visibility.add,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(FloatingWorkspaceHost.openProjectionKey),
        findsOneWidget,
      );

      var closeCompleted = false;
      unawaited(harness.agent.close('a').then((_) => closeCompleted = true));
      await tester.pump();
      await tester.pump();
      final completedBeforeOpeningAnimationEnded = closeCompleted;
      await tester.pumpAndSettle();
      await completion;

      expect(completedBeforeOpeningAnimationEnded, isTrue);
      expect(visibility, [FloatingSessionVisibility.closing]);
      expect(harness.agent.sessionCount, 0);
      expect(find.byKey(FloatingWorkspaceHost.openProjectionKey), findsNothing);
    },
  );

  testWidgets('disposing the host cancels an opening projection safely', (
    tester,
  ) async {
    var disposeCount = 0;
    final harness = await _pumpHost(
      tester,
      capture: (_, _) async => FloatingSnapshot.memory(
        width: 10,
        height: 10,
        builder: ({key, required fit}) => const SizedBox(),
        onDispose: () => disposeCount += 1,
      ),
    );
    unawaited(
      harness.agent.open(
        _request('agent', 'a', animateInitialPresentation: true),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(FloatingWorkspaceHost.openProjectionKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(disposeCount, 1);
  });

  testWidgets('reduced motion skips distant launch geometry', (tester) async {
    const sourceRect = Rect.fromLTWH(24, 80, 72, 72);
    final harness = await _pumpHost(tester, disableAnimations: true);
    unawaited(
      harness.agent.open(
        _request(
          'agent',
          'a',
          animateInitialPresentation: true,
          launchOrigin: const FloatingSessionLaunchOrigin(
            sourceRect: sourceRect,
            viewportSize: Size(800, 600),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final snapshot = find.descendant(
      of: find.byKey(FloatingWorkspaceHost.openProjectionKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.blue,
      ),
    );
    expect(snapshot, findsOneWidget);
    expect(tester.getRect(snapshot), const Rect.fromLTWH(0, 0, 800, 600));

    await tester.pumpAndSettle();
  });

  testWidgets('timed out close capture disposes its late snapshot', (
    tester,
  ) async {
    final capture = Completer<FloatingSnapshot>();
    var disposeCount = 0;
    final harness = await _pumpHost(
      tester,
      capture: (_, _) => capture.future,
      captureTimeout: const Duration(milliseconds: 1),
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('close-session')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));
    capture.complete(
      FloatingSnapshot.memory(
        width: 10,
        height: 10,
        builder: ({key, required fit}) => const SizedBox(),
        onDispose: () => disposeCount += 1,
      ),
    );
    await tester.pump();

    expect(disposeCount, 1);
    expect(harness.agent.sessionCount, 0);
  });

  testWidgets('closeAll waits for and safely follows a float projection', (
    tester,
  ) async {
    var disposeCount = 0;
    final harness = await _pumpHost(
      tester,
      capture: (_, _) async => FloatingSnapshot.memory(
        width: 10,
        height: 10,
        builder: ({key, required fit}) => const SizedBox(),
        onDispose: () => disposeCount += 1,
      ),
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(FloatingWorkspaceHost.floatProjectionKey),
      findsOneWidget,
    );
    var cleanupCompleted = false;
    final cleanup = harness.agent.closeAll().whenComplete(
      () => cleanupCompleted = true,
    );
    await tester.pump();
    expect(cleanupCompleted, isFalse);

    await tester.pumpAndSettle();
    await cleanup;
    expect(harness.agent.sessionCount, 0);
    expect(disposeCount, 1);
    expect(find.byKey(FloatingWorkspaceHost.floatProjectionKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closeAll safely follows a restore projection', (tester) async {
    var disposeCount = 0;
    final harness = await _pumpHost(
      tester,
      capture: (_, _) async => FloatingSnapshot.memory(
        width: 10,
        height: 10,
        builder: ({key, required fit}) => const SizedBox(),
        onDispose: () => disposeCount += 1,
      ),
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        FloatingDock.cardKey(
          const FloatingSessionKey(domainId: 'agent', sessionId: 'a'),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(FloatingWorkspaceHost.restoreProjectionKey),
      findsOneWidget,
    );

    final cleanup = harness.agent.closeAll();
    await tester.pumpAndSettle();
    await cleanup;
    expect(harness.agent.sessionCount, 0);
    expect(disposeCount, 2);
    expect(
      find.byKey(FloatingWorkspaceHost.restoreProjectionKey),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closeAll includes a foreground close already in progress', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-session')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(FloatingWorkspaceHost.closeProjectionKey),
      findsOneWidget,
    );

    var cleanupCompleted = false;
    final cleanup = harness.agent.closeAll().whenComplete(
      () => cleanupCompleted = true,
    );
    await tester.pump();
    expect(cleanupCompleted, isFalse);
    await tester.pumpAndSettle();
    await cleanup;
    expect(harness.agent.sessionCount, 0);
  });

  testWidgets('latest same-domain request wins while projection owns screen', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pump();
    await tester.pump();

    final superseded = harness.agent.open(
      _request('agent', 'b', content: 'superseded-b'),
    );
    unawaited(harness.agent.open(_request('agent', 'c', content: 'latest-c')));
    await tester.pumpAndSettle();

    expect(await superseded, isNull);
    expect(find.text('latest-c'), findsOneWidget);
    expect(find.text('superseded-b'), findsNothing);
    expect(harness.agent.sessionCount, 2);
  });

  testWidgets('cross-domain request stays busy during projection', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pump();
    await tester.pump();

    expect(
      () => harness.plugin.open(_request('plugin', 'p')),
      throwsA(isA<FloatingWorkspaceBusyException>()),
    );
  });

  testWidgets('latest same-key request wins while close is in progress', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    unawaited(harness.agent.open(_request('agent', 'a', content: 'original')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-session')));
    await tester.pump();
    await tester.pump();

    var staleCompleted = false;
    var latestCompleted = false;
    final stale = harness.agent.open(
      _request('agent', 'a', content: 'stale-reopen'),
    )..whenComplete(() => staleCompleted = true);
    final latest = harness.agent.open(
      _request('agent', 'a', content: 'latest-reopen'),
    )..whenComplete(() => latestCompleted = true);
    await tester.pumpAndSettle();

    expect(staleCompleted, isTrue);
    expect(await stale, isNull);
    expect(latestCompleted, isFalse);
    expect(find.text('latest-reopen'), findsOneWidget);
    expect(find.text('stale-reopen'), findsNothing);
    expect(harness.agent.sessionCount, 1);

    final close = harness.agent.close('a');
    await tester.pumpAndSettle();
    await close;
    expect(latestCompleted, isTrue);
    expect(await latest, isNull);
  });

  testWidgets('domain closeAll and overflow never cross ownership', (
    tester,
  ) async {
    final closed = <String>[];
    final harness = await _pumpHost(tester);
    for (var index = 1; index <= 6; index += 1) {
      unawaited(
        harness.agent.open(
          _request('agent', '$index', onClosed: (_) => closed.add('$index')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pumpAndSettle();
    }
    unawaited(harness.plugin.open(_request('plugin', 'p')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();

    expect(closed, contains('1'));
    expect(harness.agent.sessionCount, 5);
    expect(harness.plugin.sessionCount, 1);

    final closeAgent = harness.agent.closeAll();
    await tester.pumpAndSettle();
    await closeAgent;
    expect(harness.agent.sessionCount, 0);
    expect(harness.plugin.sessionCount, 1);
  });

  testWidgets('capture failure leaves the session foreground', (tester) async {
    final harness = await _pumpHost(
      tester,
      capture: (_, _) async => throw StateError('capture failed'),
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pumpAndSettle();

    expect(find.text('agent-a'), findsOneWidget);
    expect(find.byKey(FloatingWorkspaceHost.dockKey), findsNothing);
  });

  testWidgets('timed out capture disposes its late snapshot exactly once', (
    tester,
  ) async {
    final capture = Completer<FloatingSnapshot>();
    final disposed = Completer<void>();
    var disposeCount = 0;
    var failureCount = 0;
    final harness = await _pumpHost(
      tester,
      capture: (_, _) => capture.future,
      captureTimeout: const Duration(milliseconds: 1),
      onCaptureFailed: (_) => failureCount += 1,
    );
    unawaited(harness.agent.open(_request('agent', 'a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('float-session')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));
    expect(failureCount, 1);
    expect(find.text('agent-a'), findsOneWidget);

    await tester.runAsync(() async {
      capture.complete(
        FloatingSnapshot.memory(
          width: 10,
          height: 10,
          builder: ({key, required fit}) => const SizedBox(),
          onDispose: () {
            disposeCount += 1;
            disposed.complete();
          },
        ),
      );
      await disposed.future;
    });
    expect(disposeCount, 1);
  });

  testWidgets('closeAll is idempotent during an active cleanup', (
    tester,
  ) async {
    final closed = Completer<void>();
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        _request('agent', 'a', onClosed: (_) => closed.future),
      ),
    );
    await tester.pumpAndSettle();

    final first = harness.agent.closeAll();
    final second = harness.agent.closeAll();
    expect(second, same(first));
    closed.complete();
    await tester.pumpAndSettle();
    await first;
    expect(harness.agent.sessionCount, 0);
  });

  testWidgets('disposing the host closes every live session', (tester) async {
    final closed = Completer<void>();
    final harness = await _pumpHost(tester);
    unawaited(
      harness.agent.open(
        _request('agent', 'a', onClosed: (_) => closed.complete()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await closed.future;

    expect(closed.isCompleted, isTrue);
  });

  testWidgets(
    'adding or removing an empty domain preserves another domain sessions',
    (tester) async {
      final plugin = FloatingDomainController(
        policy: const FloatingDomainPolicy(
          domainId: 'plugin',
          maxFloatingSessions: 5,
          maxSnapshotBytes: 12 * 1024 * 1024,
        ),
      );
      final agent = FloatingDomainController(
        policy: const FloatingDomainPolicy(
          domainId: 'agent',
          maxFloatingSessions: 5,
          maxSnapshotBytes: 12 * 1024 * 1024,
        ),
      );

      Future<void> pump(List<FloatingDomainController> domains) async {
        await tester.pumpWidget(
          MaterialApp(
            home: FloatingWorkspaceHost(
              domains: domains,
              snapshotCapture: _capture,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        );
      }

      await pump([plugin, agent]);
      unawaited(plugin.open(_request('plugin', 'p')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('float-session')));
      await tester.pumpAndSettle();

      await pump([plugin]);
      expect(plugin.sessionCount, 1);
      expect(agent.sessionCount, 0);
      expect(find.byKey(FloatingWorkspaceHost.dockKey), findsOneWidget);

      await pump([plugin, agent]);
      expect(plugin.sessionCount, 1);
      expect(agent.sessionCount, 0);
      expect(find.byKey(FloatingWorkspaceHost.dockKey), findsOneWidget);
    },
  );
}

FloatingSessionRequest _request(
  String domain,
  String id, {
  FutureOr<void> Function(Object? result)? onClosed,
  FutureOr<void> Function(FloatingSessionVisibility visibility)?
  onVisibilityChanged,
  String? content,
  bool animateInitialPresentation = false,
  FloatingSessionLaunchOrigin? launchOrigin,
}) {
  return FloatingSessionRequest(
    key: FloatingSessionKey(domainId: domain, sessionId: id),
    title: '$domain-$id',
    pageBuilder: (_, actions) => Material(
      child: Stack(
        children: [
          Center(child: Text(content ?? '$domain-$id')),
          TextButton(
            key: const Key('float-session'),
            onPressed: actions.float,
            child: const Text('Float'),
          ),
          Align(
            alignment: Alignment.topRight,
            child: TextButton(
              key: const Key('close-session'),
              onPressed: actions.close,
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
    maybePopNested: () async => false,
    onVisibilityChanged: onVisibilityChanged ?? (_) {},
    onClosed: onClosed ?? (_) {},
    animateInitialPresentation: animateInitialPresentation,
    launchOrigin: launchOrigin,
  );
}

Future<_Harness> _pumpHost(
  WidgetTester tester, {
  FloatingSnapshotCapture? capture,
  Duration captureTimeout = const Duration(seconds: 3),
  ValueChanged<FloatingSessionKey>? onCaptureFailed,
  bool disableAnimations = false,
}) async {
  final plugin = FloatingDomainController(
    policy: const FloatingDomainPolicy(
      domainId: 'plugin',
      maxFloatingSessions: 5,
      maxSnapshotBytes: 12 * 1024 * 1024,
    ),
  );
  final agent = FloatingDomainController(
    policy: const FloatingDomainPolicy(
      domainId: 'agent',
      maxFloatingSessions: 5,
      maxSnapshotBytes: 12 * 1024 * 1024,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: FloatingWorkspaceHost(
        domains: [plugin, agent],
        snapshotCapture: capture ?? _capture,
        snapshotCaptureTimeout: captureTimeout,
        onSnapshotCaptureFailed: onCaptureFailed,
        child: const ColoredBox(color: Colors.white),
      ),
    ),
  );
  return _Harness(plugin, agent);
}

Future<FloatingSnapshot> _capture(
  RenderRepaintBoundary boundary,
  double pixelRatio,
) async {
  return FloatingSnapshot.memory(
    width: 100,
    height: 160,
    builder: ({key, required fit}) => ColoredBox(key: key, color: Colors.blue),
    onDispose: () {},
  );
}

Future<void> _openFloatingThenForeground(
  WidgetTester tester,
  FloatingDomainController controller,
) async {
  unawaited(controller.open(_request(controller.domainId, 'a')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('float-session')));
  await tester.pumpAndSettle();
  unawaited(controller.open(_request(controller.domainId, 'b')));
  await tester.pumpAndSettle();
}

void _expectRectClose(Rect actual, Rect expected, {double epsilon = 1}) {
  expect(actual.left, closeTo(expected.left, epsilon));
  expect(actual.top, closeTo(expected.top, epsilon));
  expect(actual.width, closeTo(expected.width, epsilon));
  expect(actual.height, closeTo(expected.height, epsilon));
}

bool _rectIsClose(Rect actual, Rect expected, {double epsilon = 1}) {
  return (actual.left - expected.left).abs() <= epsilon &&
      (actual.top - expected.top).abs() <= epsilon &&
      (actual.width - expected.width).abs() <= epsilon &&
      (actual.height - expected.height).abs() <= epsilon;
}

final class _Harness {
  const _Harness(this.plugin, this.agent);
  final FloatingDomainController plugin;
  final FloatingDomainController agent;
}
