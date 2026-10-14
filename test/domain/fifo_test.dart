import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/domain/fifo.dart';

StockBatch batch(String id, int day, int qty, int total, {String product = 'p', String? purchase}) =>
    StockBatch(
      id: id,
      productId: product,
      receivedAt: DateTime(2026, 1, day),
      qty: qty,
      totalCostZmw: total,
      purchaseId: purchase,
    );

StockDemand sale(String id, int day, int qty, {String product = 'p', Set<String> reserved = const {}}) =>
    StockDemand(
      id: id,
      productId: product,
      at: DateTime(2026, 2, day),
      qty: qty,
      reservedPurchaseIds: reserved,
    );

void main() {
  test('oldest stock is used first', () {
    final ledger = fifo(
      batches: [batch('new', 10, 5, 5000), batch('old', 1, 5, 3000)],
      demands: [sale('s1', 1, 6)],
    );
    // 5 old @ 600 + 1 new @ 1000.
    expect(ledger.demandCosts['s1']!.costZmw, 3000 + 1000);
    expect(ledger.stockOf('p').qty, 4);
    expect(ledger.stockOf('p').valueZmw, 4000);
    expect(ledger.remainingByBatch, {'old': 0, 'new': 4});
  });

  test('sales are costed in date order regardless of input order', () {
    final ledger = fifo(
      batches: [batch('a', 1, 1, 100), batch('b', 2, 1, 900)],
      demands: [sale('late', 5, 1), sale('early', 1, 1)],
    );
    expect(ledger.demandCosts['early']!.costZmw, 100);
    expect(ledger.demandCosts['late']!.costZmw, 900);
  });

  test('uneven batch costs are never lost to rounding', () {
    final ledger = fifo(
      batches: [batch('a', 1, 3, 1000)],
      demands: [sale('s1', 1, 1), sale('s2', 2, 1), sale('s3', 3, 1)],
    );
    final costs = ['s1', 's2', 's3'].map((s) => ledger.demandCosts[s]!.costZmw).toList();
    expect(costs, [333, 333, 334]);
    expect(ledger.stockOf('p').valueZmw, 0);
  });

  test('selling more than recorded stock is flagged, not hidden', () {
    final ledger = fifo(batches: [batch('a', 1, 2, 200)], demands: [sale('s1', 1, 5)]);
    final cost = ledger.demandCosts['s1']!;
    expect((cost.costZmw, cost.unitsCosted, cost.unitsShort), (200, 2, 3));
    expect(cost.isComplete, isFalse);
    expect(ledger.stockOf('p').qty, 0);
  });

  test('products are costed separately', () {
    final ledger = fifo(
      batches: [
        batch('a', 1, 1, 100, product: 'x'),
        batch('b', 1, 1, 700, product: 'y'),
      ],
      demands: [sale('s', 1, 1, product: 'y')],
    );
    expect(ledger.demandCosts['s']!.costZmw, 700);
    expect(ledger.stockOf('x').qty, 1);
    expect(ledger.stockOf('unknown').qty, 0);
  });

  test('a pre-order takes stock from the purchase made for it', () {
    final ledger = fifo(
      batches: [
        batch('old', 1, 1, 100, purchase: 'p1'),
        batch('mine', 5, 1, 900, purchase: 'p2'),
      ],
      demands: [
        sale('regular', 1, 1),
        sale('pre', 2, 1, reserved: {'p2'}),
      ],
    );
    // The earlier regular sale must not eat the pre-order's unit.
    expect(ledger.demandCosts['pre']!.costZmw, 900);
    expect(ledger.demandCosts['regular']!.costZmw, 100);
  });

  test('a pre-order falls back to general stock if its purchase is short', () {
    final ledger = fifo(
      batches: [
        batch('old', 1, 3, 300, purchase: 'p1'),
        batch('mine', 5, 1, 900, purchase: 'p2'),
      ],
      demands: [
        sale('pre', 2, 2, reserved: {'p2'}),
      ],
    );
    expect(ledger.demandCosts['pre']!.costZmw, 900 + 100);
    expect(ledger.stockOf('p').qty, 2);
  });

  test('average cost of what is left', () {
    final ledger = fifo(batches: [batch('a', 1, 2, 300), batch('b', 2, 1, 600)], demands: []);
    expect(ledger.stockOf('p').unitCostZmw, 300);
    expect(const ProductStock(qty: 0, valueZmw: 0).unitCostZmw, isNull);
  });

  test('records which batches each demand used', () {
    final ledger = fifo(
      batches: [
        batch('a', 1, 1, 100, purchase: 'p1'),
        batch('b', 2, 5, 500, purchase: 'p2'),
      ],
      demands: [sale('s', 1, 3)],
    );
    final uses = ledger.demandCosts['s']!.uses;
    expect(uses.map((u) => (u.batchId, u.units, u.costZmw)), [('a', 1, 100), ('b', 2, 200)]);
  });
}
