import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';

import 'demo_order.dart';
import 'demo_order_runtime.dart';

typedef EasyPosDemoCompletion = void Function(EasyPosDemoResult result);

const _pageBackground = Color(0xFFFCFCFC);
const _hostCapsuleReservedWidth = 112.0;

/// Shared order list used unchanged by the standalone and embedded shells.
final class EasyPosDemoOrdersPage extends StatefulWidget {
  const EasyPosDemoOrdersPage({
    super.key,
    required this.runtime,
    required this.onComplete,
    this.visibilityListenable,
  });

  final EasyPosDemoRuntime runtime;
  final EasyPosDemoCompletion onComplete;
  final ValueListenable<AiPosPluginPageVisibility>? visibilityListenable;

  @override
  State<EasyPosDemoOrdersPage> createState() => _EasyPosDemoOrdersPageState();
}

final class _EasyPosDemoOrdersPageState extends State<EasyPosDemoOrdersPage> {
  VoidCallback? _unbindVisibility;

  @override
  void initState() {
    super.initState();
    _bindVisibility();
  }

  @override
  void didUpdateWidget(covariant EasyPosDemoOrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.visibilityListenable,
          widget.visibilityListenable,
        ) ||
        !identical(oldWidget.runtime, widget.runtime)) {
      _bindVisibility();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OrdersPageBody(
      runtime: widget.runtime,
      onComplete: widget.onComplete,
    );
  }

  void _bindVisibility() {
    _unbindVisibility?.call();
    final visibility = widget.visibilityListenable;
    _unbindVisibility = visibility == null
        ? null
        : widget.runtime.bindPageVisibility(visibility);
  }

  @override
  void dispose() {
    _unbindVisibility?.call();
    _unbindVisibility = null;
    super.dispose();
  }
}

final class _OrdersPageBody extends StatelessWidget {
  const _OrdersPageBody({required this.runtime, required this.onComplete});

  final EasyPosDemoRuntime runtime;
  final EasyPosDemoCompletion onComplete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('配送订单'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: const [SizedBox(width: _hostCapsuleReservedWidth)],
      ),
      body: StreamBuilder<List<DemoOrder>>(
        stream: runtime.ordersStream,
        initialData: runtime.orders,
        builder: (context, snapshot) {
          final orders = snapshot.data ?? runtime.orders;
          return ListView.separated(
            key: const Key('easypos-demo-orders-ready'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                child: ListTile(
                  key: Key('demo-order-row-${order.id}'),
                  minVerticalPadding: 14,
                  title: Text('${order.id} · ${order.customerName}'),
                  subtitle: Text(order.address),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDetail(context, order),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, DemoOrder order) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            _EasyPosDemoOrderDetailPage(order: order, onComplete: onComplete),
      ),
    );
  }
}

final class _EasyPosDemoOrderDetailPage extends StatelessWidget {
  const _EasyPosDemoOrderDetailPage({
    required this.order,
    required this.onComplete,
  });

  final DemoOrder order;
  final EasyPosDemoCompletion onComplete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('easypos-demo-order-detail'),
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('订单详情'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: const [SizedBox(width: _hostCapsuleReservedWidth)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(order.id, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text('客户：${order.customerName}'),
            const SizedBox(height: 12),
            Text('地址：${order.address}'),
            const Spacer(),
            FilledButton(
              key: const Key('easypos-demo-complete-order'),
              onPressed: () => onComplete(EasyPosDemoResult(orderId: order.id)),
              child: const Text('完成并退出'),
            ),
          ],
        ),
      ),
    );
  }
}
