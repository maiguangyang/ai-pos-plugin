import 'package:flutter/foundation.dart';

/// Local order states used by the self-contained feasibility demo.
enum DemoOrderStatus { waiting, delivering, completed }

/// One immutable local delivery order shared by standalone and plugin modes.
@immutable
final class DemoOrder {
  const DemoOrder({
    required this.id,
    required this.customerName,
    required this.address,
    required this.status,
  });

  final String id;
  final String customerName;
  final String address;
  final DemoOrderStatus status;

  DemoOrder copyWith({DemoOrderStatus? status}) => DemoOrder(
    id: id,
    customerName: customerName,
    address: address,
    status: status ?? this.status,
  );
}

/// Safe diagnostic result returned to the host after completing an order.
@immutable
final class EasyPosDemoResult {
  const EasyPosDemoResult({required this.orderId});

  final String orderId;
}
