import 'package:easypos_demo_integration/easypos_demo_integration.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(const EasyPosDemoApp());
}

/// Standalone publication entry that reuses the integration package verbatim.
final class EasyPosDemoApp extends StatelessWidget {
  const EasyPosDemoApp({super.key});

  @override
  Widget build(BuildContext context) => const EasyPosDemoStandaloneApp();
}
