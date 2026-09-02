import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capsule matches the mini-app visual contract', (tester) async {
    await _pumpShell(tester);

    final capsule = find.byKey(FloatingPageShell.capsuleKey);
    final moreButton = find.byKey(FloatingPageShell.moreButtonKey);
    final closeButton = find.byKey(FloatingPageShell.closeButtonKey);
    final colors = Theme.of(tester.element(capsule)).colorScheme;
    final surface = tester.widget<Ink>(
      find.byKey(FloatingPageShell.capsuleSurfaceKey),
    );
    final decoration = surface.decoration! as BoxDecoration;

    expect(decoration.color, colors.surface.withValues(alpha: 0.78));
    expect(
      (decoration.border! as Border).top.color,
      colors.outlineVariant.withValues(alpha: 0.52),
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.more_horiz_rounded)).size, 22);
    expect(tester.widget<Icon>(find.byIcon(Icons.adjust_rounded)).size, 21);
    expect(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(moreButton)).moreButtonTooltip,
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        MaterialLocalizations.of(
          tester.element(closeButton),
        ).closeButtonTooltip,
      ),
      findsOneWidget,
    );

    final divider = find.descendant(
      of: capsule,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == 1 && widget.height == 16,
      ),
    );
    expect(divider, findsOneWidget);
  });

  testWidgets('capsule remains usable across themes and large text', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await _pumpShell(
        tester,
        brightness: brightness,
        textScaler: TextScaler.linear(3),
      );

      expect(
        tester.getSize(find.byKey(FloatingPageShell.capsuleKey)),
        const Size(96, 48),
      );
      expect(
        tester.getSize(find.byKey(FloatingPageShell.closeButtonKey)),
        const Size(48, 48),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('controller pops nested route before the session closes', (
    tester,
  ) async {
    final controller = FloatingPageShellController();
    late BuildContext pageContext;
    var closeCount = 0;
    await _pumpShell(
      tester,
      controller: controller,
      onClose: () => closeCount += 1,
      pageBuilder: (context) {
        pageContext = context;
        return const Text('entry');
      },
    );
    unawaited(
      Navigator.of(pageContext).push<void>(
        MaterialPageRoute<void>(builder: (_) => const Text('detail')),
      ),
    );
    await tester.pumpAndSettle();

    expect(await controller.maybePopNested(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(closeCount, 0);
  });

  testWidgets('close bypasses a page PopScope', (tester) async {
    var closeCount = 0;
    await _pumpShell(
      tester,
      onClose: () => closeCount += 1,
      pageBuilder: (_) =>
          const PopScope(canPop: false, child: SizedBox.expand()),
    );

    await tester.tap(find.byKey(FloatingPageShell.closeButtonKey));
    await tester.pump();
    expect(closeCount, 1);
  });

  testWidgets('builder and presenter failures preserve the close escape', (
    tester,
  ) async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    var closeCount = 0;
    await _pumpShell(
      tester,
      onClose: () => closeCount += 1,
      pageBuilder: (_) => throw StateError('builder failed'),
      presentActions: (_, _) async => throw StateError('presenter failed'),
    );

    await tester.tap(find.byKey(FloatingPageShell.moreButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(FloatingPageShell.closeButtonKey));
    await tester.pump();

    FlutterError.onError = previous;
    expect(reported.map((error) => error.exception), contains(isStateError));
    expect(closeCount, 1);
  });

  testWidgets('selected action runs only after presenter surface is removed', (
    tester,
  ) async {
    var actionCount = 0;
    var surfaceWasAbsent = false;
    var actionContextHasNavigator = false;
    await _pumpShell(
      tester,
      presentActions: (context, _) async {
        final navigator = Navigator.of(context);
        final route = ModalBottomSheetRoute<String>(
          builder: (context) => TextButton(
            key: const Key('choose-float'),
            onPressed: () => Navigator.of(context).pop('float'),
            child: const Text('Float'),
          ),
          isScrollControlled: false,
        );
        final result = await navigator.push(route);
        await route.completed;
        return result;
      },
      onAction: (context, _) {
        actionCount += 1;
        actionContextHasNavigator = Navigator.maybeOf(context) != null;
        surfaceWasAbsent = find
            .byKey(const Key('choose-float'))
            .evaluate()
            .isEmpty;
      },
    );

    await tester.tap(find.byKey(FloatingPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-float')));
    await tester.pump();
    expect(actionCount, 0);
    await tester.pumpAndSettle();

    expect(actionCount, 1);
    expect(actionContextHasNavigator, isTrue);
    expect(surfaceWasAbsent, isTrue);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  FloatingPageShellController? controller,
  WidgetBuilder? pageBuilder,
  Future<String?> Function(BuildContext, List<FloatingPageAction>)?
  presentActions,
  FutureOr<void> Function(BuildContext context, String id)? onAction,
  VoidCallback? onClose,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          textScaler: textScaler,
        ),
        child: FloatingPageShell(
          title: 'Session',
          pageBuilder: pageBuilder ?? (_) => const SizedBox.expand(),
          actions: const [FloatingPageAction(id: 'float', label: 'Float')],
          presentActions: presentActions ?? (_, _) async => null,
          onAction: onAction ?? (_, _) {},
          onClose: onClose ?? () {},
          controller: controller ?? FloatingPageShellController(),
        ),
      ),
    ),
  );
}
