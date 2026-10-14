import 'dart:math';

import 'models.dart';
import 'money.dart';

class CartTotals {
  const CartTotals({
    required this.itemsZmw,
    required this.deliveryZmw,
    required this.depositZmw,
    required this.units,
  });

  final int itemsZmw;
  final int deliveryZmw;
  final int depositZmw;
  final int units;

  int get totalZmw => itemsZmw + deliveryZmw;
}

/// Prices the cart against the current catalog. Lines for products that are
/// gone or sold out are left out.
List<OrderLine> priceLines(List<CartLine> cart, Catalog catalog) => [
  for (final line in cart)
    if (catalog.product(line.productId) case final p? when p.canOrder)
      OrderLine(
        productId: p.id,
        name: p.name,
        size: line.size,
        color: line.color,
        qty: line.qty,
        unitPriceZmw: p.priceZmw,
        preOrder: p.isPreOrder,
        leadTimeWeeks: p.leadTimeWeeks,
      ),
];

/// Deposit on pre-order items, rounded up to whole kwacha.
int depositFor(List<OrderLine> lines, int percent) {
  final preOrderValue = lines.where((l) => l.preOrder).fold(0, (sum, l) => sum + l.totalZmw);
  if (preOrderValue == 0 || percent <= 0) return 0;
  final deposit = (preOrderValue * percent / 100).ceil();
  return ((deposit + 99) ~/ 100) * 100;
}

CartTotals totalsFor(List<OrderLine> lines, ShopSettings settings, {String? areaId}) {
  final area = settings.deliveryAreas.where((a) => a.id == areaId).firstOrNull;
  return CartTotals(
    itemsZmw: lines.fold(0, (sum, l) => sum + l.totalZmw),
    deliveryZmw: area?.feeZmw ?? 0,
    depositZmw: depositFor(lines, settings.depositPercent),
    units: lines.fold(0, (sum, l) => sum + l.qty),
  );
}

const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Short code customers quote on WhatsApp, e.g. "TF-7K3Q". No 0/O or 1/I.
String newOrderCode([Random? random]) {
  final r = random ?? Random.secure();
  return 'TF-${List.generate(4, (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)]).join()}';
}

/// Normalises a Zambian phone number to international digits:
/// "097 123 4567" / "+260971234567" -> "260971234567". Null if not valid.
String? normalisePhone(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^0[79]\d{8}$').hasMatch(digits)) return '260${digits.substring(1)}';
  if (RegExp(r'^260[79]\d{8}$').hasMatch(digits)) return digits;
  if (RegExp(r'^[79]\d{8}$').hasMatch(digits)) return '260$digits';
  return null;
}

Order buildOrder({
  required String code,
  required DateTime now,
  required Customer customer,
  required List<OrderLine> lines,
  required ShopSettings settings,
}) {
  final totals = totalsFor(lines, settings, areaId: customer.areaId);
  return Order(
    code: code,
    createdAt: now,
    customer: customer,
    areaName: settings.deliveryAreas.where((a) => a.id == customer.areaId).firstOrNull?.name,
    lines: lines,
    itemsZmw: totals.itemsZmw,
    deliveryZmw: totals.deliveryZmw,
    depositZmw: totals.depositZmw,
  );
}

/// The message the customer sends the shop on WhatsApp.
String whatsappMessage(Order order, ShopSettings settings) {
  final b = StringBuffer()
    ..writeln("Hi ${settings.name}! I'd like to order (${order.code}):")
    ..writeln();
  for (final l in order.lines) {
    final options = [if (l.size != null) 'Size ${l.size}', if (l.color != null) l.color!].join(', ');
    final pre = l.preOrder
        ? ' [Pre-order${l.leadTimeWeeks == null ? '' : ' ~${l.leadTimeWeeks} weeks'}]'
        : '';
    b.writeln('• ${l.qty} × ${l.name}${options.isEmpty ? '' : ' ($options)'}$pre: ${kwacha(l.totalZmw)}');
  }
  b
    ..writeln()
    ..writeln('Items: ${kwacha(order.itemsZmw)}');
  if (order.areaName != null) b.writeln('Delivery (${order.areaName}): ${kwacha(order.deliveryZmw)}');
  b.writeln('Total: ${kwacha(order.totalZmw)}');
  if (order.depositZmw > 0) {
    b.writeln('Pre-order deposit (${settings.depositPercent}%): ${kwacha(order.depositZmw)}');
  }
  b
    ..writeln()
    ..writeln('Name: ${order.customer.name}')
    ..writeln('Phone: +${order.customer.phone}');
  if (order.customer.notes.trim().isNotEmpty) b.writeln('Notes: ${order.customer.notes.trim()}');
  return b.toString().trimRight();
}

Uri whatsappLink(Order order, ShopSettings settings) =>
    Uri.https('wa.me', '/${settings.whatsappNumber}', {'text': whatsappMessage(order, settings)});
