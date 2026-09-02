import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
