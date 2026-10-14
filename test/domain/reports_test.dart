import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/domain/fifo.dart';
import 'package:tradeflow/domain/reports.dart';

DateTime d(int day) => DateTime(2026, 10, day);

void main() {
  // Two batches: opening stock (no platform) and a Taobao purchase.
  final batches = [
    StockBatch(id: 'open', productId: 'buds', receivedAt: DateTime(1970), qty: 1, totalCostZmw: 10000),
    StockBatch(id: 'tb', productId: 'buds', receivedAt: d(2), qty: 4, totalCostZmw: 60000, purchaseId: 'p1'),
    StockBatch(id: 'w', productId: 'watch', receivedAt: d(2), qty: 1, totalCostZmw: 40000, purchaseId: 'p2'),
  ];
  final platformByBatch = {'open': null, 'tb': 'taobao', 'w': '1688'};

  final sales = [
    SaleFact(
      id: 's1',
      at: d(5),
      channelId: 'whatsapp',
      items: const [SaleItemFact(id: 'i1', productId: 'buds', qty: 2, revenueZmw: 50000)],
    ),
    SaleFact(
      id: 's2',
      at: d(6),
      items: const [SaleItemFact(id: 'i2', productId: 'watch', qty: 1, revenueZmw: 65000)],
    ),
    // Outside the period.
    SaleFact(
      id: 's3',
      at: DateTime(2026, 11, 1),
      items: const [SaleItemFact(id: 'i3', productId: 'buds', qty: 1, revenueZmw: 25000)],
    ),
  ];
  final ledger = fifo(
    batches: batches,
    demands: [
      for (final s in sales)
        for (final i in s.items) StockDemand(id: i.id, productId: i.productId, at: s.at, qty: i.qty),
    ],
  );

  ProfitReport report({
    List<ExpenseFact> expenses = const [],
    List<OtherCostFact> other = const [],
    List<LossFact> losses = const [],
    List<ReturnFact> returns = const [],
  }) => profitReport(
    from: d(1),
    to: DateTime(2026, 11, 1),
    sales: sales,
    ledger: ledger,
    platformByBatch: platformByBatch,
    expenses: expenses,
    otherCosts: other,
    losses: losses,
    returns: returns,
  );

  test('revenue and FIFO cost of sales in the period', () {
    final r = report();
    // Buds: 1 opening @100 + 1 Taobao @150 = 250; watch 400.
    expect(r.totals.revenueZmw, 115000);
    expect(r.totals.costZmw, 25000 + 40000);
    expect(r.grossProfitZmw, 50000);
    expect(r.missingCostUnits, 0);
  });

  test('net profit takes off expenses, fees, forgotten expenses and losses', () {
    final r = report(
      expenses: [
        ExpenseFact(at: d(7), amountZmw: 3000, categoryId: 'transport'),
        ExpenseFact(at: d(8), amountZmw: 2000, categoryId: 'delivery'),
        ExpenseFact(at: DateTime(2026, 9, 30), amountZmw: 99999, categoryId: 'transport'),
      ],
      other: [OtherCostFact(at: d(9), amountZmw: 500)],
      losses: [LossFact(kind: LossKind.refund, at: d(9), amountZmw: 1500, label: 'Refund')],
      returns: [ReturnFact(at: d(10), paidZmw: 20000, refundedZmw: 15000)],
    );
    expect(r.expensesByCategory, {'transport': 3000, 'delivery': 2000});
    expect(r.netProfitZmw, 50000 - 5000 - 500 - 1500 + 5000);
  });

  test('profit by product and channel', () {
    final r = report();
    expect(r.byProduct['buds']!.profitZmw, 25000);
    expect(r.byProduct['watch']!.profitZmw, 25000);
    expect(r.byChannel['whatsapp']!.revenueZmw, 50000);
    expect(r.byChannel[null]!.revenueZmw, 65000);
  });

  test('profit by platform follows the batches units came from', () {
    final r = report();
    expect(r.byPlatform[null]!.units, 1, reason: 'opening stock');
    expect(r.byPlatform[null]!.revenueZmw, 25000);
    expect(r.byPlatform['taobao']!.costZmw, 15000);
    expect(r.byPlatform['1688']!.profitZmw, 25000);
    final total = r.byPlatform.values.fold(const ProfitLine(), (a, b) => a + b);
    expect(total.revenueZmw, r.totals.revenueZmw);
  });

  test('units without stock count as missing and land in the unknown platform', () {
    final shortLedger = fifo(
      batches: const [],
      demands: [StockDemand(id: 'x', productId: 'p', at: d(5), qty: 2)],
    );
    final r = profitReport(
      from: d(1),
      to: d(30),
      sales: [
        SaleFact(
          id: 's',
          at: d(5),
          items: const [SaleItemFact(id: 'x', productId: 'p', qty: 2, revenueZmw: 1000)],
        ),
      ],
      ledger: shortLedger,
      platformByBatch: const {},
    );
    expect(r.missingCostUnits, 2);
    expect(r.byPlatform[null]!.revenueZmw, 1000);
  });

  test('margin', () {
    expect(const ProfitLine(revenueZmw: 1000, costZmw: 600).margin, closeTo(0.4, 1e-9));
    expect(const ProfitLine().margin, isNull);
  });

  test('rate summary', () {
    final s = RateSummary(
      points: [
        RatePoint(at: d(1), rate: 3.7),
        RatePoint(at: d(9), rate: 3.6),
        RatePoint(at: d(5), rate: 3.8),
      ],
    );
    expect(s.latest!.rate, 3.6);
    expect(s.best, 3.6);
    expect(s.worst, 3.8);
    expect(s.average, closeTo(3.7, 1e-9));
    expect(const RateSummary(points: []).latest, isNull);
  });

  test('month helpers roll over the year', () {
    expect(monthStart(DateTime(2026, 12, 15, 10)), DateTime(2026, 12));
    expect(nextMonth(DateTime(2026, 12, 15)), DateTime(2027, 1));
  });
}
