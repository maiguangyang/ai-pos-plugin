import 'dart:async';

import 'package:flutter/material.dart';

import '../orders/demo_order.dart';
import '../orders/demo_order_home_page.dart';
import '../orders/demo_order_runtime.dart';

/// Independently runnable shell owned by the integration developer.
final class EasyPosDemoStandaloneApp extends StatefulWidget {
  const EasyPosDemoStandaloneApp({super.key, this.runtime});

  final EasyPosDemoRuntime? runtime;

  @override
  State<EasyPosDemoStandaloneApp> createState() =>
      _EasyPosDemoStandaloneAppState();
}

final class _EasyPosDemoStandaloneAppState
    extends State<EasyPosDemoStandaloneApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final EasyPosDemoRuntime _runtime;
  late final Future<void> _start;

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime ?? EasyPosDemoRuntime();
    _start = _runtime.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyPOS Demo',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: FutureBuilder<void>(
        future: _start,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text('启动失败')));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return EasyPosDemoOrdersPage(
            runtime: _runtime,
            onComplete: _showCompleted,
          );
        },
      ),
    );
  }

  void _showCompleted(EasyPosDemoResult result) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('订单 ${result.orderId} 已完成')),
    );
  }

  @override
  void dispose() {
    unawaited(_runtime.dispose());
    super.dispose();
  }
}
