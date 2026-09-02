import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';

import 'demo_order.dart';

/// Owns all long-lived demo resources shared by both application shells.
final class EasyPosDemoRuntime {
  StreamController<List<DemoOrder>>? _ordersController;
  Timer? _timer;
  var _disposed = false;
  final _orders = const <DemoOrder>[
    DemoOrder(
      id: 'ORDER-1001',
      customerName: '陈女士',
      address: '浦东新区世纪大道 100 号',
      status: DemoOrderStatus.waiting,
    ),
    DemoOrder(
      id: 'ORDER-1002',
      customerName: '林先生',
      address: '徐汇区漕溪北路 88 号',
      status: DemoOrderStatus.delivering,
    ),
    DemoOrder(
      id: 'ORDER-1003',
      customerName: '王女士',
      address: '静安区南京西路 66 号',
      status: DemoOrderStatus.completed,
    ),
  ];
  var _emissionCount = 0;
  var _producerStartCount = 0;

  bool get isDisposed => _disposed;
  bool get isRunning => _ordersController != null && !_disposed;
  bool get hasActiveTimer => _timer?.isActive ?? false;
  int get emissionCount => _emissionCount;
  int get producerStartCount => _producerStartCount;
  List<DemoOrder> get orders => List<DemoOrder>.unmodifiable(_orders);
  Stream<List<DemoOrder>> get ordersStream =>
      _ordersController?.stream ?? const Stream<List<DemoOrder>>.empty();

  /// Starts one controller and one periodic local update producer.
  Future<void> start() async {
    if (_disposed) {
      throw StateError('A disposed demo runtime cannot be restarted.');
    }
    if (_ordersController != null) {
      return;
    }

    final controller = StreamController<List<DemoOrder>>.broadcast(sync: true);
    _ordersController = controller;
    _producerStartCount += 1;
    _emit(controller);
    _startTimer();
  }

  VoidCallback bindPageVisibility(
    ValueListenable<AiPosPluginPageVisibility> visibility,
  ) {
    if (_disposed) {
      throw StateError('A disposed demo runtime cannot bind page visibility.');
    }
    var bound = true;
    void handleVisibility() {
      if (!bound || _disposed) {
        return;
      }
      switch (visibility.value) {
        case AiPosPluginPageVisibility.foreground:
          _startTimer();
        case AiPosPluginPageVisibility.floating:
        case AiPosPluginPageVisibility.closing:
          _stopTimer();
      }
    }

    visibility.addListener(handleVisibility);
    handleVisibility();
    return () {
      if (!bound) {
        return;
      }
      bound = false;
      visibility.removeListener(handleVisibility);
      _stopTimer();
    };
  }

  void _startTimer() {
    final controller = _ordersController;
    if (_disposed ||
        controller == null ||
        controller.isClosed ||
        hasActiveTimer) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_disposed && !controller.isClosed) {
        _emit(controller);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit(StreamController<List<DemoOrder>> controller) {
    _emissionCount += 1;
    controller.add(orders);
  }

  /// Stops production before closing the stream; repeated calls are safe.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopTimer();
    final controller = _ordersController;
    _ordersController = null;
    await controller?.close();
  }
}
