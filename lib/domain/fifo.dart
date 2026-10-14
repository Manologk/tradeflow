// FIFO stock costing, docs/PRODUCT_SPEC.md §4.4–4.5. Pure functions.

/// Units received into stock with a known total landed cost.
class StockBatch {
  const StockBatch({
    required this.id,
    required this.productId,
    required this.receivedAt,
    required this.qty,
    required this.totalCostZmw,
    this.purchaseId,
  });

  final String id;
  final String productId;
  final DateTime receivedAt;
  final int qty;
  final int totalCostZmw;

  /// The purchase it came from; null for opening stock.
  final String? purchaseId;
}

/// Units handed to a customer.
class StockDemand {
  const StockDemand({
    required this.id,
    required this.productId,
    required this.at,
    required this.qty,
    this.reservedPurchaseIds = const {},
  });

  /// Sale item id.
  final String id;
  final String productId;
  final DateTime at;
  final int qty;

  /// Purchases made for this pre-order; their stock is used first.
  final Set<String> reservedPurchaseIds;
}

class DemandCost {
  const DemandCost({required this.costZmw, required this.unitsCosted, required this.unitsShort});

  final int costZmw;
  final int unitsCosted;

  /// Units sold with no stock recorded to cost them against.
  final int unitsShort;

  bool get isComplete => unitsShort == 0;
}

class ProductStock {
  const ProductStock({required this.qty, required this.valueZmw});

  final int qty;
  final int valueZmw;

  /// Average cost of what's left, rounded; null when none left.
  int? get unitCostZmw => qty == 0 ? null : (valueZmw / qty).round();
}

class StockLedger {
  const StockLedger({required this.demandCosts, required this.stock, required this.remainingByBatch});

  final Map<String, DemandCost> demandCosts;
  final Map<String, ProductStock> stock;
  final Map<String, int> remainingByBatch;

  ProductStock stockOf(String productId) => stock[productId] ?? const ProductStock(qty: 0, valueZmw: 0);
}

class _Remaining {
  _Remaining(this.batch) : qty = batch.qty, value = batch.totalCostZmw;

  final StockBatch batch;
  int qty;
  int value;

  /// Takes up to [wanted] units; returns (units taken, their cost). Cost is
  /// proportional, and the last unit out takes whatever value is left, so a
  /// batch's cost is always fully used.
  (int, int) take(int wanted) {
    final units = wanted < qty ? wanted : qty;
    if (units == 0) return (0, 0);
    final cost = units == qty ? value : value * units ~/ qty;
    qty -= units;
    value -= cost;
    return (units, cost);
  }
}

/// Costs every demand against stock batches.
///
/// Demand for a pre-order first takes from the purchases made for it. All
/// other units come oldest batch first, demands processed in date order.
StockLedger fifo({required List<StockBatch> batches, required List<StockDemand> demands}) {
  final ordered = [...batches]
    ..sort((a, b) {
      final byDate = a.receivedAt.compareTo(b.receivedAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  final byProduct = <String, List<_Remaining>>{};
  for (final b in ordered) {
    byProduct.putIfAbsent(b.productId, () => []).add(_Remaining(b));
  }

  final costed = <String, (int units, int cost)>{};

  // Pass 1: pre-orders take from the purchases bought for them.
  for (final d in demands.where((d) => d.reservedPurchaseIds.isNotEmpty)) {
    var units = 0, cost = 0;
    for (final r in byProduct[d.productId] ?? const <_Remaining>[]) {
      if (units == d.qty) break;
      if (!d.reservedPurchaseIds.contains(r.batch.purchaseId)) continue;
      final (u, c) = r.take(d.qty - units);
      units += u;
      cost += c;
    }
    costed[d.id] = (units, cost);
  }

  // Pass 2: everything still needed, oldest stock first, in sale order.
  final chronological = [...demands]
    ..sort((a, b) {
      final byDate = a.at.compareTo(b.at);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  for (final d in chronological) {
    var (units, cost) = costed[d.id] ?? (0, 0);
    for (final r in byProduct[d.productId] ?? const <_Remaining>[]) {
      if (units == d.qty) break;
      final (u, c) = r.take(d.qty - units);
      units += u;
      cost += c;
    }
    costed[d.id] = (units, cost);
  }

  final stock = <String, ProductStock>{};
  final remaining = <String, int>{};
  for (final MapEntry(key: productId, value: list) in byProduct.entries) {
    var qty = 0, value = 0;
    for (final r in list) {
      qty += r.qty;
      value += r.value;
      remaining[r.batch.id] = r.qty;
    }
    stock[productId] = ProductStock(qty: qty, valueZmw: value);
  }

  return StockLedger(
    demandCosts: {
      for (final d in demands)
        d.id: DemandCost(
          costZmw: costed[d.id]!.$2,
          unitsCosted: costed[d.id]!.$1,
          unitsShort: d.qty - costed[d.id]!.$1,
        ),
    },
    stock: stock,
    remainingByBatch: remaining,
  );
}
