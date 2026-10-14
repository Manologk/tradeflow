import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';

const purchaseStatusLabels = {
  PurchaseStatus.ordered: 'Ordered',
  PurchaseStatus.shipped: 'Shipped by seller',
  PurchaseStatus.atAgent: 'At agent (China)',
  PurchaseStatus.inTransit: 'On the way to Zambia',
  PurchaseStatus.collected: 'Collected',
  PurchaseStatus.refunded: 'Refunded',
  PurchaseStatus.lost: 'Lost',
};

/// Statuses the user moves through by hand. Collected, refunded and lost are
/// set by their own flows so the costs that go with them get recorded.
const manualPurchaseStatuses = [
  PurchaseStatus.ordered,
  PurchaseStatus.shipped,
  PurchaseStatus.atAgent,
  PurchaseStatus.inTransit,
];

IconData purchaseStatusIcon(PurchaseStatus status) => switch (status) {
  PurchaseStatus.ordered => Icons.receipt_outlined,
  PurchaseStatus.shipped => Icons.local_shipping_outlined,
  PurchaseStatus.atAgent => Icons.warehouse_outlined,
  PurchaseStatus.inTransit => Icons.flight_outlined,
  PurchaseStatus.collected => Icons.inventory_2_outlined,
  PurchaseStatus.refunded => Icons.undo,
  PurchaseStatus.lost => Icons.report_outlined,
};

final shortDate = DateFormat('d MMM yyyy');

/// "K3.70 per ¥1" style label for an effective exchange rate.
String rateLabel(double rate) => 'K${rate.toStringAsFixed(3)} per ¥1';
