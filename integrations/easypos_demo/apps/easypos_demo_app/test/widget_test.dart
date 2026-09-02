import 'package:easypos_demo_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('standalone app runs shared orders UI without host capsule', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPosDemoApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('easypos-demo-orders-ready')), findsOneWidget);
    expect(find.byKey(const Key('ai-pos-plugin-host-close')), findsNothing);
    expect(find.text('配送订单'), findsOneWidget);
  });
}
