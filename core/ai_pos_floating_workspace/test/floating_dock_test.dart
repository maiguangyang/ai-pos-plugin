import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dock exposes semantics and restores the selected card', (
    tester,
  ) async {
    final restored = <String>[];
    await _pumpDock(
      tester,
      cards: _cards(1, onRestore: (id, _) => restored.add(id)),
    );
    final semantics = tester.ensureSemantics();

    expect(find.bySemanticsLabel('Open floating windows'), findsOneWidget);
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open Session 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Close Session 1'), findsOneWidget);

    await tester.tap(find.byKey(FloatingDock.cardKey('session-1')));
    await tester.pump();
    expect(restored, <String>['session-1']);
    semantics.dispose();
  });

  testWidgets('collapsed dock stays inside safe vertical bounds', (
    tester,
  ) async {
    await _pumpDock(
      tester,
      cards: _cards(1),
      padding: const EdgeInsets.only(top: 20, bottom: 34),
    );
    final dock = find.byKey(FloatingDock.dockHitTargetKey);
    final gesture = await tester.startGesture(tester.getCenter(dock));

    await gesture.moveBy(const Offset(0, -1000));
    await tester.pump();
    expect(tester.getRect(dock).top, closeTo(20, 0.001));

    await gesture.moveBy(const Offset(0, 2000));
    await tester.pump();
    expect(tester.getRect(dock).bottom, closeTo(566, 0.001));
    await gesture.up();
  });

  testWidgets('five card surfaces stay stable through interrupted drags', (
    tester,
  ) async {
    final builds = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    await _pumpDock(tester, cards: _cards(5, buildCount: builds));
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    final initialBuilds = builds.value;
    final dock = find.byKey(FloatingDock.dockHitTargetKey);

    for (var run = 0; run < 5; run += 1) {
      final gesture = await tester.startGesture(tester.getCenter(dock));
      await gesture.moveBy(const Offset(-140, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.cancel();
      await tester.pumpAndSettle();
    }

    expect(builds.value, initialBuilds);
    for (var index = 1; index <= 5; index += 1) {
      expect(
        find.byKey(FloatingDock.cardRepaintBoundaryKey('session-$index')),
        findsOneWidget,
      );
    }
  });

  testWidgets('all cards enter together and settle into a horizontal track', (
    tester,
  ) async {
    await _pumpDock(tester, cards: _cards(3));

    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final enteringOpacities = [
      for (var index = 1; index <= 3; index += 1)
        tester
            .widget<Opacity>(
              find.byKey(FloatingDock.cardOpacityKey('session-$index')),
            )
            .opacity,
    ];
    expect(enteringOpacities, everyElement(greaterThan(0)));
    expect(enteringOpacities.toSet(), hasLength(1));
    final enteringLatestWidth = tester
        .getRect(find.byKey(FloatingDock.cardKey('session-3')))
        .width;

    await tester.pumpAndSettle();
    final oldest = tester.getRect(
      find.byKey(FloatingDock.cardKey('session-1')),
    );
    final middle = tester.getRect(
      find.byKey(FloatingDock.cardKey('session-2')),
    );
    final latest = tester.getRect(
      find.byKey(FloatingDock.cardKey('session-3')),
    );

    expect(oldest.overlaps(middle), isFalse);
    expect(middle.overlaps(latest), isFalse);
    expect(latest.left, lessThan(middle.left));
    expect(middle.left, lessThan(oldest.left));
    expect(oldest.top, closeTo(middle.top, 0.001));
    expect(middle.top, closeTo(latest.top, 0.001));
    expect(enteringLatestWidth, lessThan(latest.width));
    expect(middle.left - latest.right, closeTo(12, 0.001));
    expect(oldest.left - middle.right, closeTo(12, 0.001));
  });

  testWidgets('each card receives taps from its horizontal slot', (
    tester,
  ) async {
    final restored = <String>[];
    await _pumpDock(
      tester,
      cards: _cards(3, onRestore: (id, _) => restored.add(id)),
    );
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();

    final oldest = tester.getRect(
      find.byKey(FloatingDock.cardKey('session-1')),
    );
    await tester.tapAt(oldest.topLeft + const Offset(20, 80));
    await tester.pump();

    expect(restored, <String>['session-1']);
  });

  testWidgets('close controls remain at the card top right', (tester) async {
    await _pumpDock(tester, cards: _cards(3));
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();

    for (var index = 1; index <= 3; index += 1) {
      final cardRect = tester.getRect(
        find.byKey(FloatingDock.cardKey('session-$index')),
      );
      final closeRect = tester.getRect(
        find.byKey(FloatingDock.cardCloseKey('session-$index')),
      );
      expect(closeRect.top, closeTo(cardRect.top, 0.001));
      expect(closeRect.right, closeTo(cardRect.right, 0.001));
      expect(closeRect.size, const Size.square(48));
    }
  });

  testWidgets('five-card track pans to reveal both edge close controls', (
    tester,
  ) async {
    await _pumpDock(tester, cards: _cards(5), size: const Size(390, 844));
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();

    final oldestClose = find.byKey(FloatingDock.cardCloseKey('session-1'));
    final latestClose = find.byKey(FloatingDock.cardCloseKey('session-5'));
    expect(tester.getCenter(latestClose).dx, lessThan(0));
    expect(tester.getCenter(oldestClose).dx, greaterThan(390));

    final middleCard = find.byKey(FloatingDock.cardKey('session-3'));
    final leftGesture = await tester.startGesture(tester.getCenter(middleCard));
    await leftGesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    await leftGesture.up();
    await tester.pump();
    expect(tester.getCenter(oldestClose).dx, inInclusiveRange(0, 390));

    final rightGesture = await tester.startGesture(
      tester.getCenter(middleCard),
    );
    await rightGesture.moveBy(const Offset(360, 0));
    await tester.pump();
    await rightGesture.up();
    await tester.pump();
    expect(tester.getCenter(latestClose).dx, inInclusiveRange(0, 390));
  });

  testWidgets('panned edge close control closes its own card', (tester) async {
    final closed = <String>[];
    await _pumpDock(
      tester,
      cards: _cards(5, onClose: closed.add),
      size: const Size(390, 844),
    );
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();

    final middleCard = find.byKey(FloatingDock.cardKey('session-3'));
    final gesture = await tester.startGesture(tester.getCenter(middleCard));
    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.tap(
      find.byKey(FloatingDock.cardCloseKey('session-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(closed, ['session-1']);
  });

  testWidgets('an exposed back card close control closes its own card', (
    tester,
  ) async {
    final closed = <String>[];
    await _pumpDock(tester, cards: _cards(3, onClose: closed.add));
    await tester.tap(find.byKey(FloatingDock.dockHitTargetKey));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(FloatingDock.cardCloseKey('session-1'))),
    );
    await tester.pump();

    expect(closed, <String>['session-1']);
  });
}

Future<void> _pumpDock(
  WidgetTester tester, {
  required List<FloatingDockCard> cards,
  EdgeInsets padding = EdgeInsets.zero,
  Size size = const Size(800, 600),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, padding: padding),
        child: Scaffold(body: FloatingDock(cards: cards)),
      ),
    ),
  );
}

List<FloatingDockCard> _cards(
  int count, {
  void Function(String id, Rect rect)? onRestore,
  void Function(String id)? onClose,
  ValueNotifier<int>? buildCount,
}) {
  return List.generate(count, (index) {
    final id = 'session-${index + 1}';
    return FloatingDockCard(
      id: id,
      title: 'Session ${index + 1}',
      snapshot: FloatingSnapshot.memory(
        width: 100,
        height: 160,
        builder: ({key, required fit}) {
          buildCount?.value += 1;
          return ColoredBox(key: key, color: Colors.blue);
        },
        onDispose: () {},
      ),
      onRestore: (rect) => onRestore?.call(id, rect),
      onClose: () => onClose?.call(id),
    );
  });
}
