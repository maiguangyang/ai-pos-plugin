import 'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart';
import 'package:easypos_demo_integration/easypos_demo_integration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared orders page navigates to detail and back', (
    tester,
  ) async {
    final runtime = EasyPosDemoRuntime();
    await runtime.start();

    await tester.pumpWidget(
      MaterialApp(
        home: EasyPosDemoOrdersPage(runtime: runtime, onComplete: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('easypos-demo-orders-ready')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(scaffold.backgroundColor, const Color(0xFFFCFCFC));
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.elevation, 0);
    expect(appBar.scrolledUnderElevation, 0);
    await tester.tap(find.byKey(const Key('demo-order-row-ORDER-1001')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('easypos-demo-order-detail')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('easypos-demo-orders-ready')), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('plugin page completion returns a bounded result to the host', (
    tester,
  ) async {
    final runtime = EasyPosDemoRuntime();
    final plugin = EasyPosDemoPlugin(runtime: runtime);
    final pageContext = FakeAiPosPluginPageContext();
    await runtime.start();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => plugin.pages['/orders']!(context, pageContext),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('demo-order-row-ORDER-1001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('easypos-demo-complete-order')));
    await tester.pump();

    expect(pageContext.closeCount, 1);
    expect(pageContext.closeResults.single, isA<EasyPosDemoResult>());
    expect(
      (pageContext.closeResults.single! as EasyPosDemoResult).orderId,
      'ORDER-1001',
    );
    await plugin.dispose();
  });
}
