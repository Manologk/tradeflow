import '../core/allocation.dart';

// Landed-cost rules from docs/PRODUCT_SPEC.md §4. Pure functions so they can
// be tested exhaustively; repositories feed them rows from the database.

/// §4.1 — Splits the ZMW actually charged for a purchase across its items by
/// their CNY value. Seller delivery and card fees ride along proportionally.
List<int> itemPurchaseCosts({required int paidZmw, required List<int> itemValuesCny}) =>
    allocate(paidZmw, itemValuesCny);

/// Kwacha per yuan actually achieved on a payment, or null if nothing in CNY.
double? effectiveRate({required int paidZmw, required int totalCny}) =>
    totalCny == 0 ? null : paidZmw / totalCny;

/// A purchase line as the costing engine sees it.
class CostItem {
  const CostItem({
    required this.id,
    required this.purchaseId,
    required this.cargoTypeId,
    required this.qty,
    required this.purchaseCostZmw,
  });

  final String id;
  final String purchaseId;
  final String cargoTypeId;
  final int qty;

  /// The item's share of what was paid for its purchase (§4.1).
  final int purchaseCostZmw;
}

class CostShippingLine {
  const CostShippingLine({
    required this.id,
    required this.cargoTypeId,
    required this.costZmw,
    required this.purchaseIds,
  });

  final String id;
  final String cargoTypeId;

  /// The line's share of the ZMW actually paid for its bill.
  final int costZmw;
  final List<String> purchaseIds;
}

class CostCollection {
  const CostCollection({required this.id, required this.costZmw, required this.purchaseIds});

  final String id;

  /// Transport plus storage.
  final int costZmw;
  final List<String> purchaseIds;
}

class ItemLandedCost {
  const ItemLandedCost({
    required this.qty,
    required this.purchaseZmw,
    this.shippingZmw = 0,
    this.collectionZmw = 0,
  });

  final int qty;
  final int purchaseZmw;
  final int shippingZmw;
  final int collectionZmw;

  int get totalZmw => purchaseZmw + shippingZmw + collectionZmw;

  /// Rounded per-unit cost, for display. Use [totalZmw] for sums.
  int get unitZmw => qty == 0 ? 0 : (totalZmw / qty).round();

  ItemLandedCost _with({int? shippingZmw, int? collectionZmw}) => ItemLandedCost(
    qty: qty,
    purchaseZmw: purchaseZmw,
    shippingZmw: shippingZmw ?? this.shippingZmw,
    collectionZmw: collectionZmw ?? this.collectionZmw,
  );
}

/// §4.2 — Splits a shipping bill's ZMW payment across its lines by their USD
/// amounts.
List<int> billLineCosts({required int paidZmw, required List<int> lineAmountsUsd}) =>
    allocate(paidZmw, lineAmountsUsd);

/// §4.2–4.4 — Landed cost of every item, keyed by item id.
///
/// * Each shipping line is spread over the items of its cargo type in the
///   purchases it covers, by purchase cost. If none of those items has the
///   line's cargo type, it is spread over all of them.
/// * Each collection's transport and storage is spread over every item in
///   the purchases collected, by purchase cost plus shipping share.
/// * Lines or collections that cover no (remaining) items are ignored.
Map<String, ItemLandedCost> landedCosts({
  required List<CostItem> items,
  List<CostShippingLine> shippingLines = const [],
  List<CostCollection> collections = const [],
}) {
  final result = {
    for (final item in items) item.id: ItemLandedCost(qty: item.qty, purchaseZmw: item.purchaseCostZmw),
  };
  final byPurchase = <String, List<CostItem>>{};
  for (final item in items) {
    byPurchase.putIfAbsent(item.purchaseId, () => []).add(item);
  }
  List<CostItem> itemsIn(Iterable<String> purchaseIds) => [
    for (final id in purchaseIds.toSet()) ...?byPurchase[id],
  ];

  for (final line in shippingLines) {
    final covered = itemsIn(line.purchaseIds);
    if (covered.isEmpty) continue;
    final sameCargo = covered.where((i) => i.cargoTypeId == line.cargoTypeId).toList();
    final targets = sameCargo.isEmpty ? covered : sameCargo;
    final shares = allocate(line.costZmw, [for (final t in targets) t.purchaseCostZmw]);
    for (final (i, target) in targets.indexed) {
      final current = result[target.id]!;
      result[target.id] = current._with(shippingZmw: current.shippingZmw + shares[i]);
    }
  }

  for (final collection in collections) {
    final targets = itemsIn(collection.purchaseIds);
    if (targets.isEmpty) continue;
    final shares = allocate(collection.costZmw, [
      for (final t in targets) result[t.id]!.purchaseZmw + result[t.id]!.shippingZmw,
    ]);
    for (final (i, target) in targets.indexed) {
      final current = result[target.id]!;
      result[target.id] = current._with(collectionZmw: current.collectionZmw + shares[i]);
    }
  }
  return result;
}
