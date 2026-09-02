import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dock is safe, tappable, and expands every card', (tester) async {
    await _pumpOverlay(tester, cardCount: 5);

    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    expect(tester.getSize(dock).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(dock).height, greaterThanOrEqualTo(48));
    expect(tester.getRect(dock).right, lessThanOrEqualTo(800));
    final dockSurface = find.descendant(
      of: dock,
      matching: find.byType(Container),
    );
    expect(dockSurface, findsOneWidget);
    expect(tester.getSize(dockSurface).width, 22);

    await tester.tap(dock);
    await tester.pumpAndSettle();

    for (var index = 1; index <= 5; index += 1) {
      final opacity = tester.widget<Opacity>(
        find.byKey(AiPosPluginFloatingOverlay.cardOpacityKey('plugin-$index')),
      );
      expect(opacity.opacity, 1);
    }
  });

  testWidgets('dock and cards expose named button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpOverlay(tester, cardCount: 1);

    expect(find.bySemanticsLabel('Open floating windows'), findsOneWidget);

    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Open plugin-1'), findsOneWidget);
    expect(find.bySemanticsLabel('Close plugin-1'), findsOneWidget);
    expect(find.text('plugin-1'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('controller notifies only when expanded state changes', (
    tester,
  ) async {
    final controller = AiPosPluginFloatingOverlayController();
    var notificationCount = 0;
    controller.addListener(() => notificationCount += 1);
    await _pumpOverlay(tester, cardCount: 1, controller: controller);

    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.isExpanded, isTrue);
    expect(notificationCount, 1);

    final collapse = controller.collapse();
    await tester.pumpAndSettle();
    await collapse;

    expect(controller.isExpanded, isFalse);
    expect(notificationCount, 2);
  });

  testWidgets('drag distance continuously reveals newest before older cards', (
    tester,
  ) async {
    await _pumpOverlay(tester, cardCount: 3, revealExtent: 320);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    final start = tester.getCenter(dock);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();

    final latestOpacity = tester.widget<Opacity>(
      find.byKey(AiPosPluginFloatingOverlay.cardOpacityKey('plugin-3')),
    );
    final olderOpacity = tester.widget<Opacity>(
      find.byKey(AiPosPluginFloatingOverlay.cardOpacityKey('plugin-1')),
    );
    expect(latestOpacity.opacity, greaterThan(0.5));
    expect(latestOpacity.opacity, lessThan(1));
    expect(olderOpacity.opacity, 0);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dock follows vertical drag without revealing cards', (
    tester,
  ) async {
    await _pumpOverlay(tester, cardCount: 1);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    final initialRect = tester.getRect(dock);

    final gesture = await tester.startGesture(tester.getCenter(dock));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    final movedRect = tester.getRect(dock);
    expect(movedRect.top, closeTo(initialRect.top - 120, 0.1));
    expect(find.byKey(AiPosPluginFloatingOverlay.scrimKey), findsNothing);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('dock stays inside the vertical safe bounds while dragging', (
    tester,
  ) async {
    await _pumpOverlay(tester, cardCount: 1);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    final gesture = await tester.startGesture(tester.getCenter(dock));

    await gesture.moveBy(const Offset(0, -1000));
    await tester.pump();
    expect(tester.getRect(dock).top, 0);

    await gesture.moveBy(const Offset(0, 2000));
    await tester.pump();
    expect(tester.getRect(dock).bottom, 600);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('collapsed card projection follows the moved dock position', (
    tester,
  ) async {
    await _pumpOverlay(tester, cardCount: 1);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    await tester.drag(dock, const Offset(0, -120));
    await tester.pump();

    final dockCenter = tester.getRect(dock).center.dy;
    final collapsedCardCenter = tester
        .getRect(
          find.byKey(AiPosPluginFloatingOverlay.cardTransformKey('plugin-1')),
        )
        .center
        .dy;
    expect(collapsedCardCenter, closeTo(dockCenter, 0.1));
  });

  testWidgets('release uses distance and velocity within bounded settling', (
    tester,
  ) async {
    await _pumpOverlay(tester, cardCount: 1, revealExtent: 320);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);

    final slow = await tester.startGesture(tester.getCenter(dock));
    await slow.moveBy(const Offset(-60, 0));
    await slow.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byKey(AiPosPluginFloatingOverlay.scrimKey), findsNothing);

    await tester.fling(dock, const Offset(-180, 0), 1800);
    await tester.pump(const Duration(milliseconds: 159));
    expect(find.byKey(AiPosPluginFloatingOverlay.scrimKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 161));
    final opacity = tester.widget<Opacity>(
      find.byKey(AiPosPluginFloatingOverlay.cardOpacityKey('plugin-1')),
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('scrim covers the bottom system inset edge to edge', (
    tester,
  ) async {
    await _pumpOverlay(
      tester,
      cardCount: 1,
      mediaPadding: const EdgeInsets.only(bottom: 34),
    );
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    await tester.drag(dock, const Offset(0, 1000));
    await tester.pump();
    expect(tester.getRect(dock).bottom, 566);

    await tester.tap(dock);
    await tester.pumpAndSettle();

    final scrimRect = tester.getRect(
      find.byKey(AiPosPluginFloatingOverlay.scrimKey),
    );
    expect(scrimRect.top, 0);
    expect(scrimRect.bottom, 600);
  });

  testWidgets('scrim, right drag, and back collapse before host navigation', (
    tester,
  ) async {
    await _pumpOverlay(tester, cardCount: 2);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    await tester.tap(dock);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginFloatingOverlay.scrimKey), findsNothing);

    await tester.tap(dock);
    await tester.pumpAndSettle();
    final card = find.byKey(AiPosPluginFloatingOverlay.cardKey('plugin-2'));
    await tester.drag(card, const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginFloatingOverlay.scrimKey), findsNothing);

    await tester.tap(dock);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Host route'), findsOneWidget);
    expect(find.byKey(AiPosPluginFloatingOverlay.scrimKey), findsNothing);
  });

  testWidgets('card restore and close callbacks do not cross-fire', (
    tester,
  ) async {
    final restored = <String>[];
    final closed = <String>[];
    await _pumpOverlay(
      tester,
      cardCount: 2,
      onRestore: restored.add,
      onClose: closed.add,
    );
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(AiPosPluginFloatingOverlay.cardCloseKey('plugin-1')),
    );
    await tester.pump();
    expect(closed, <String>['plugin-1']);
    expect(restored, isEmpty);

    await tester.tap(
      find.byKey(AiPosPluginFloatingOverlay.cardKey('plugin-2')),
    );
    await tester.pump();
    expect(restored, <String>['plugin-2']);
  });

  testWidgets(
    'every card has a small top-right close visual with safe target',
    (tester) async {
      await _pumpOverlay(tester, cardCount: 5);
      await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
      await tester.pumpAndSettle();

      for (var index = 1; index <= 5; index += 1) {
        final id = 'plugin-$index';
        final cardRect = tester.getRect(
          find.byKey(AiPosPluginFloatingOverlay.cardKey(id)),
        );
        final targetRect = tester.getRect(
          find.byKey(AiPosPluginFloatingOverlay.cardCloseKey(id)),
        );
        final surfaceRect = tester.getRect(
          find.byKey(AiPosPluginFloatingOverlay.cardCloseSurfaceKey(id)),
        );
        expect(targetRect.width, greaterThanOrEqualTo(48));
        expect(targetRect.height, greaterThanOrEqualTo(48));
        expect(surfaceRect.width, lessThanOrEqualTo(28));
        expect(surfaceRect.height, lessThanOrEqualTo(28));
        expect(targetRect.center.dx, greaterThan(cardRect.center.dx));
        expect(targetRect.center.dy, lessThan(cardRect.center.dy));
      }
    },
  );

  testWidgets('reduced motion still reveals with a short fade', (tester) async {
    await _pumpOverlay(tester, cardCount: 1, disableAnimations: true);
    await tester.tap(find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final opacity = tester.widget<Opacity>(
      find.byKey(AiPosPluginFloatingOverlay.cardOpacityKey('plugin-1')),
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('reveal transforms stable repaint-boundary card surfaces', (
    tester,
  ) async {
    final builds = ValueNotifier<int>(0);
    final paints = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    addTearDown(paints.dispose);
    await _pumpOverlay(
      tester,
      cardCount: 5,
      snapshotBuildCount: builds,
      snapshotPaintCount: paints,
    );
    await tester.pump();

    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);
    await tester.tap(dock);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    final initialBuilds = builds.value;
    final initialPaints = paints.value;
    final gesture = await tester.startGesture(tester.getCenter(dock));
    for (var step = 0; step < 8; step += 1) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(builds.value, initialBuilds);
    expect(paints.value, initialPaints);
    for (var index = 1; index <= 5; index += 1) {
      expect(
        find.ancestor(
          of: find.byKey(AiPosPluginFloatingOverlay.cardKey('plugin-$index')),
          matching: find.byKey(
            ValueKey<String>(
              'ai-pos-plugin-floating-card-repaint-plugin-$index',
            ),
          ),
        ),
        findsOneWidget,
      );
    }
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('five cards survive repeated interrupted drags', (tester) async {
    await _pumpOverlay(tester, cardCount: 5);
    final dock = find.byKey(AiPosPluginFloatingOverlay.dockHitTargetKey);

    for (var cycle = 0; cycle < 1000; cycle += 1) {
      final gesture = await tester.startGesture(tester.getCenter(dock));
      await gesture.moveBy(Offset(cycle.isEven ? -72 : -24, 0));
      await tester.pump(const Duration(milliseconds: 1));
      if (cycle % 3 == 0) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.takeException(), isNull);
    }

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required int cardCount,
  double revealExtent = 320,
  bool disableAnimations = false,
  EdgeInsets mediaPadding = EdgeInsets.zero,
  ValueChanged<String>? onRestore,
  ValueChanged<String>? onClose,
  AiPosPluginFloatingOverlayController? controller,
  ValueNotifier<int>? snapshotBuildCount,
  ValueNotifier<int>? snapshotPaintCount,
}) {
  final cards = List<AiPosPluginFloatingCard>.generate(cardCount, (index) {
    final id = 'plugin-${index + 1}';
    return AiPosPluginFloatingCard(
      pluginId: id,
      pluginName: id,
      snapshot: AiPosPluginSnapshot(
        width: 320,
        height: 480,
        builder: ({key, required fit}) {
          if (snapshotBuildCount != null) {
            snapshotBuildCount.value += 1;
          }
          final surface = ColoredBox(
            key: key,
            color: Colors.primaries[index % Colors.primaries.length],
          );
          if (snapshotPaintCount == null) {
            return surface;
          }
          return CustomPaint(
            painter: _PaintCounter(snapshotPaintCount),
            child: surface,
          );
        },
        onDispose: () {},
      ),
      onRestore: (_) => onRestore?.call(id),
      onClose: () => onClose?.call(id),
    );
  });
  addTearDown(() {
    for (final card in cards) {
      card.snapshot.dispose();
    }
  });
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          padding: mediaPadding,
        ),
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Center(child: Text('Host route')),
              AiPosPluginFloatingOverlay(
                cards: cards,
                revealExtent: revealExtent,
                controller: controller,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _PaintCounter extends CustomPainter {
  const _PaintCounter(this.counter);

  final ValueNotifier<int> counter;

  @override
  void paint(Canvas canvas, Size size) {
    counter.value += 1;
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => false;
}
