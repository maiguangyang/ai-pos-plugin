import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders fullscreen content under a transparent host layer and mini-app capsule',
    (tester) async {
      await _pumpHost(
        tester,
        pageBuilder: (_, _) =>
            const ColoredBox(key: Key('plugin-content'), color: Colors.blue),
        mediaPadding: const EdgeInsets.only(top: 32),
      );
      await tester.tap(find.byKey(_HostHarness.launchKey));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('plugin-content')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('plugin-content'))),
        const Size(800, 600),
      );

      final capsule = find.byKey(AiPosPluginPageShell.capsuleKey);
      final more = find.byKey(AiPosPluginPageShell.moreButtonKey);
      final close = find.byKey(AiPosPluginPageShell.closeButtonKey);
      expect(capsule, findsOneWidget);
      expect(find.byType(FloatingPageCapsule), findsOneWidget);
      expect(tester.getSize(capsule), const Size(96, 48));
      expect(more, findsOneWidget);
      expect(close, findsOneWidget);
      expect(tester.getSize(more), const Size(48, 48));
      final closeRect = tester.getRect(close);
      expect(closeRect.size, const Size(48, 48));
      expect(closeRect.top, 36);
      expect(800 - closeRect.right, greaterThanOrEqualTo(12));
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      expect(find.byIcon(Icons.adjust_rounded), findsOneWidget);
      expect(
        find.byTooltip(
          MaterialLocalizations.of(tester.element(close)).closeButtonTooltip,
        ),
        findsOneWidget,
      );

      final capsuleSurface = tester.widget<Ink>(
        find.byKey(AiPosPluginPageShell.capsuleSurfaceKey),
      );
      final decoration = capsuleSurface.decoration! as BoxDecoration;
      expect(decoration.color?.a, inExclusiveRange(0, 1));
      expect(
        tester
            .widgetList<Material>(
              find.ancestor(of: capsule, matching: find.byType(Material)),
            )
            .every((material) => material.elevation == 0),
        isTrue,
      );
      expect(
        tester.getSize(find.byKey(AiPosPluginPageShell.capsuleSurfaceKey)),
        const Size(88, 36),
      );
    },
  );

  testWidgets('capsule surface is vertically centered in a standard app bar', (
    tester,
  ) async {
    const appBarTitleKey = Key('plugin-app-bar-title');
    await _pumpHost(
      tester,
      mediaPadding: const EdgeInsets.only(top: 32),
      pageBuilder: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Plugin page', key: appBarTitleKey)),
      ),
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    final appBarTitleRect = tester.getRect(find.byKey(appBarTitleKey));
    final capsuleSurfaceRect = tester.getRect(
      find.byKey(AiPosPluginPageShell.capsuleSurfaceKey),
    );

    expect(capsuleSurfaceRect.center.dy, appBarTitleRect.center.dy);
  });

  testWidgets('host more opens an app introduction action sheet', (
    tester,
  ) async {
    var floatCount = 0;
    await _pumpHost(
      tester,
      pluginName: 'Partner Delivery',
      pluginDescription: 'Independent delivery order workspace',
      onRequestFloat: () => floatCount += 1,
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().startsWith(
          'FloatingActionSheetContent<',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(AiPosPluginPageShell.appIntroductionKey), findsOneWidget);
    expect(find.text('Partner Delivery'), findsOneWidget);
    expect(find.text('Independent delivery order workspace'), findsOneWidget);
    final pluginTitle = tester.widget<Text>(find.text('Partner Delivery'));
    final pluginDescription = tester.widget<Text>(
      find.text('Independent delivery order workspace'),
    );
    expect(pluginTitle.maxLines, 1);
    expect(pluginTitle.overflow, TextOverflow.ellipsis);
    expect(pluginDescription.maxLines, 2);
    expect(pluginDescription.overflow, TextOverflow.ellipsis);
    expect(pluginTitle.style?.fontSize, 16);
    expect(pluginTitle.style?.fontWeight, FontWeight.w600);
    expect(pluginDescription.style?.fontSize, 12);
    expect(pluginDescription.style?.fontWeight, FontWeight.w400);
    expect(pluginDescription.style?.height, 1.4);
    final sheetSurface = tester.widget<Material>(
      find.byKey(AiPosPluginPageShell.actionSheetKey),
    );
    expect(
      sheetSurface.color,
      Theme.of(
        tester.element(find.byKey(AiPosPluginPageShell.actionSheetKey)),
      ).colorScheme.surfaceContainerLow,
    );
    expect(find.byKey(AiPosPluginPageShell.floatActionKey), findsOneWidget);
    expect(find.byKey(AiPosPluginPageShell.restartActionKey), findsOneWidget);
    expect(find.text('Float'), findsOneWidget);
    expect(find.text('Restart mini app'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    final floatRect = tester.getRect(
      find.byKey(AiPosPluginPageShell.floatActionKey),
    );
    final restartRect = tester.getRect(
      find.byKey(AiPosPluginPageShell.restartActionKey),
    );
    expect(floatRect.width, floatRect.height);
    expect(floatRect.width, greaterThanOrEqualTo(64));
    expect(restartRect.width, restartRect.height);
    expect(restartRect.width, greaterThanOrEqualTo(64));
    expect(restartRect.top, floatRect.top);
    expect(restartRect.left, greaterThan(floatRect.right));

    final floatLabelRect = tester.getRect(find.text('Float'));
    final restartLabelRect = tester.getRect(find.text('Restart mini app'));
    expect(floatLabelRect.top, greaterThan(floatRect.bottom));
    expect(restartLabelRect.top, greaterThan(restartRect.bottom));

    await tester.tap(find.byKey(AiPosPluginPageShell.floatActionKey));
    await tester.pumpAndSettle();
    expect(floatCount, 1);
    expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);
  });

  testWidgets('reports action sheet presenter failures through FlutterError', (
    tester,
  ) async {
    final error = StateError('presenter failed');
    final reportedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);
    await _pumpHost(tester, actionSheetPresenter: (_, _) async => throw error);
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pump();

    FlutterError.onError = originalOnError;
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, same(error));
  });

  testWidgets('reports async float request failures through FlutterError', (
    tester,
  ) async {
    final error = StateError('float failed');
    final reportedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);
    await _pumpHost(tester, onRequestFloat: () async => throw error);
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.floatActionKey));
    await tester.pumpAndSettle();

    FlutterError.onError = originalOnError;
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, same(error));
  });

  testWidgets('reports async restart request failures through FlutterError', (
    tester,
  ) async {
    final error = StateError('restart failed');
    final reportedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);
    await _pumpHost(tester, onRequestRestart: () async => throw error);
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.restartActionKey));
    await tester.pumpAndSettle();

    FlutterError.onError = originalOnError;
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, same(error));
  });

  testWidgets('floating waits until the action sheet is fully removed', (
    tester,
  ) async {
    var floatCount = 0;
    var sheetWasAbsent = false;
    await _pumpHost(
      tester,
      onRequestFloat: () {
        floatCount += 1;
        sheetWasAbsent = find
            .byKey(AiPosPluginPageShell.actionSheetKey)
            .evaluate()
            .isEmpty;
      },
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.floatActionKey));
    await tester.pump();
    expect(floatCount, 0);

    await tester.pumpAndSettle();
    expect(floatCount, 1);
    expect(sheetWasAbsent, isTrue);
  });

  testWidgets(
    'action sheet dismisses on scrim and on back without closing plugin',
    (tester) async {
      await _pumpHost(tester, onRequestFloat: () {});
      await tester.tap(find.byKey(_HostHarness.launchKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(40, 80));
      await tester.pumpAndSettle();
      expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);

      await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsNothing);
      expect(find.byKey(AiPosPluginPageShell.closeButtonKey), findsOneWidget);
    },
  );

  testWidgets('restart action recreates entry page and clears nested routes', (
    tester,
  ) async {
    var buildCount = 0;
    late BuildContext pluginContext;
    await _pumpHost(
      tester,
      pageBuilder: (context, _) {
        pluginContext = context;
        buildCount += 1;
        return Text('entry generation $buildCount');
      },
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    final firstBuildCount = buildCount;
    unawaited(
      Navigator.of(pluginContext).push<void>(
        MaterialPageRoute<void>(builder: (_) => const Text('nested detail')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiPosPluginPageShell.restartActionKey));
    await tester.pumpAndSettle();

    expect(find.text('nested detail'), findsNothing);
    expect(buildCount, greaterThan(firstBuildCount));
    expect(find.text('entry generation $buildCount'), findsOneWidget);
  });

  testWidgets('page context follows host visibility transitions', (
    tester,
  ) async {
    final visibility = ValueNotifier<AiPosPluginPageVisibility>(
      AiPosPluginPageVisibility.foreground,
    );
    late AiPosPluginPageContext pageContext;
    await _pumpHost(
      tester,
      visibilityListenable: visibility,
      pageBuilder: (_, context) {
        pageContext = context;
        return const SizedBox.expand();
      },
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    expect(pageContext.visibility, AiPosPluginPageVisibility.foreground);
    visibility.value = AiPosPluginPageVisibility.floating;
    expect(pageContext.visibility, AiPosPluginPageVisibility.floating);
    expect(pageContext.visibilityListenable, same(visibility));

    visibility.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('capsule surface is visible in ${brightness.name} theme', (
      tester,
    ) async {
      await _pumpHost(
        tester,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
      );
      await tester.tap(find.byKey(_HostHarness.launchKey));
      await tester.pumpAndSettle();

      final surface = tester.widget<Ink>(
        find.byKey(AiPosPluginPageShell.capsuleSurfaceKey),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.color?.a, greaterThan(0));
      expect(decoration.border, isNotNull);

      await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('close capsule remains usable with large text scaling', (
    tester,
  ) async {
    await _pumpHost(tester, textScaler: TextScaler.linear(3));
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    final close = find.byKey(AiPosPluginPageShell.closeButtonKey);
    expect(close, findsOneWidget);
    expect(tester.getSize(close), const Size(48, 48));
    expect(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(close)).closeButtonTooltip,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginPageShell.actionSheetKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(AiPosPluginPageShell.floatActionKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(40, 80));
    await tester.pumpAndSettle();

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
  });

  testWidgets('page context closes the outer route with a result', (
    tester,
  ) async {
    late AiPosPluginPageContext pageContext;
    Object? result;
    await _pumpHost(
      tester,
      pageBuilder: (_, context) {
        pageContext = context;
        return const SizedBox.expand();
      },
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    pageContext.close(result: 'done');
    await tester.pumpAndSettle();

    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
    expect(result, 'done');
  });

  testWidgets('capsule forcibly closes despite a nested PopScope', (
    tester,
  ) async {
    Object? result = 'unchanged';
    await _pumpHost(
      tester,
      pageBuilder: (_, _) =>
          const PopScope(canPop: false, child: SizedBox.expand()),
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('retained page context is invalid after its route closes', (
    tester,
  ) async {
    late AiPosPluginPageContext pageContext;
    final results = <Object?>[];
    await _pumpHost(
      tester,
      pageBuilder: (_, context) {
        pageContext = context;
        return const SizedBox.expand();
      },
      onResult: results.add,
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    pageContext.close(result: 'first');
    await tester.pumpAndSettle();

    pageContext.close(result: Object());
    await tester.pump();

    expect(results, <Object?>['first']);
    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
  });

  testWidgets('system back pops nested routes before returning to host', (
    tester,
  ) async {
    late BuildContext pluginContext;
    await _pumpHost(
      tester,
      pageBuilder: (context, _) {
        pluginContext = context;
        return const ColoredBox(key: Key('entry-page'), color: Colors.green);
      },
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(pluginContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const ColoredBox(key: Key('nested-page'), color: Colors.orange),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nested-page')), findsNothing);
    expect(find.byKey(const Key('entry-page')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
  });

  testWidgets('shell controller pops only the nested navigator', (
    tester,
  ) async {
    final controller = AiPosPluginPageShellController();
    late BuildContext pluginContext;
    await _pumpHost(
      tester,
      controller: controller,
      pageBuilder: (context, _) {
        pluginContext = context;
        return const ColoredBox(key: Key('entry-page'), color: Colors.green);
      },
    );
    expect(await controller.maybePopNested(), isFalse);
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(pluginContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const ColoredBox(key: Key('nested-page'), color: Colors.orange),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await controller.maybePopNested(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nested-page')), findsNothing);
    expect(find.byKey(const Key('entry-page')), findsOneWidget);
  });

  testWidgets('page context from a nested page closes the whole plugin route', (
    tester,
  ) async {
    late BuildContext pluginContext;
    late AiPosPluginPageContext pageContext;
    Object? result;
    await _pumpHost(
      tester,
      pageBuilder: (context, routeContext) {
        pluginContext = context;
        pageContext = routeContext;
        return const SizedBox.expand();
      },
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(pluginContext).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();

    pageContext.close(result: 42);
    await tester.pumpAndSettle();

    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
    expect(result, 42);
  });

  testWidgets('builder failure remains below the host escape capsule', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      pageBuilder: (_, _) => throw StateError('third-party build failed'),
    );
    await tester.tap(find.byKey(_HostHarness.launchKey));
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
    await tester.pumpAndSettle();
    expect(find.byKey(AiPosPluginPageShell.closeButtonKey), findsOneWidget);
    await tester.tap(find.byKey(AiPosPluginPageShell.closeButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_HostHarness.launchKey), findsOneWidget);
  });
}

Future<void> _pumpHost(
  WidgetTester tester, {
  AiPosPluginPageBuilder? pageBuilder,
  ThemeMode themeMode = ThemeMode.light,
  EdgeInsets mediaPadding = EdgeInsets.zero,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<Object?>? onResult,
  AiPosPluginPageFloatCallback? onRequestFloat,
  AiPosPluginPageRestartCallback? onRequestRestart,
  AiPosPluginActionSheetPresenter? actionSheetPresenter,
  String pluginName = 'Plugin',
  String pluginDescription = 'Third-party application',
  ValueListenable<AiPosPluginPageVisibility>? visibilityListenable,
  AiPosPluginPageShellController? controller,
}) {
  return tester.pumpWidget(
    _HostHarness(
      pageBuilder: pageBuilder ?? (_, _) => const SizedBox.expand(),
      themeMode: themeMode,
      mediaPadding: mediaPadding,
      textScaler: textScaler,
      onResult: onResult,
      onRequestFloat: onRequestFloat,
      onRequestRestart: onRequestRestart,
      actionSheetPresenter: actionSheetPresenter,
      pluginName: pluginName,
      pluginDescription: pluginDescription,
      visibilityListenable: visibilityListenable,
      controller: controller,
    ),
  );
}

final class _HostHarness extends StatelessWidget {
  const _HostHarness({
    required this.pageBuilder,
    required this.themeMode,
    required this.mediaPadding,
    required this.textScaler,
    this.onResult,
    this.onRequestFloat,
    this.onRequestRestart,
    this.actionSheetPresenter,
    required this.pluginName,
    required this.pluginDescription,
    this.visibilityListenable,
    this.controller,
  });

  static const launchKey = Key('launch-plugin');

  final AiPosPluginPageBuilder pageBuilder;
  final ThemeMode themeMode;
  final EdgeInsets mediaPadding;
  final TextScaler textScaler;
  final ValueChanged<Object?>? onResult;
  final AiPosPluginPageFloatCallback? onRequestFloat;
  final AiPosPluginPageRestartCallback? onRequestRestart;
  final AiPosPluginActionSheetPresenter? actionSheetPresenter;
  final String pluginName;
  final String pluginDescription;
  final ValueListenable<AiPosPluginPageVisibility>? visibilityListenable;
  final AiPosPluginPageShellController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(padding: mediaPadding, textScaler: textScaler),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: launchKey,
              onPressed: () async {
                final result = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute<Object?>(
                    builder: (_) => AiPosPluginPageShell(
                      pluginName: pluginName,
                      pluginDescription: pluginDescription,
                      pageBuilder: pageBuilder,
                      strings: const AiPosPluginPageShellStrings(
                        floatingLabel: 'Float',
                        restartLabel: 'Restart mini app',
                      ),
                      visibilityListenable: visibilityListenable,
                      controller: controller,
                      actionSheetPresenter: actionSheetPresenter,
                      onRequestFloat: onRequestFloat,
                      onRequestRestart: onRequestRestart,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Open plugin'),
            ),
          ),
        ),
      ),
    );
  }
}
