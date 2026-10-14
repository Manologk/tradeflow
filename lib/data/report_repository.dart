import 'package:drift/drift.dart';

import '../core/streams.dart';
import '../domain/fifo.dart';
import '../domain/reports.dart';
import 'database.dart';
import 'money_repository.dart';
import 'problems_repository.dart';
import 'sales_repository.dart';
import 'shipping_repository.dart';
import 'stock_repository.dart';

/// Everything Home and Reports show, gathered in one pass.
class BusinessSnapshot {
  const BusinessSnapshot({
    required this.sales,
    required this.returns,
    required this.expenses,
    required this.otherCosts,
    required this.losses,
    required this.ledger,
    required this.platformByBatch,
    required this.transitZmw,
    required this.transitPurchases,
    required this.oldestTransit,
    required this.owedZmw,
    required this.oldestDebt,
    required this.slowMovers,
    required this.balances,
    required this.cnyRates,
    required this.usdRates,
    required this.names,
  });

  final List<SaleFact> sales;
  final List<ReturnFact> returns;
  final List<ExpenseFact> expenses;
  final List<OtherCostFact> otherCosts;
  final List<LossFact> losses;
  final StockLedger ledger;
  final Map<String, String?> platformByBatch;

  /// Paid so far for purchases not yet collected (purchase + shipping).
  final int transitZmw;
  final int transitPurchases;
  final DateTime? oldestTransit;
  final int owedZmw;
  final DateTime? oldestDebt;

  /// Products with stock and no sale (or arrival) for 60+ days.
  final List<String> slowMovers;
  final List<PlaceBalance> balances;
  final RateSummary cnyRates;
  final RateSummary usdRates;

  /// Display names for products and lookups (platforms, channels, categories).
  final Map<String, String> names;

  int get stockValueZmw => ledger.stock.values.fold(0, (a, s) => a + s.valueZmw);
  int get stockUnits => ledger.stock.values.fold(0, (a, s) => a + s.qty);
  int get moneyNowZmw => balances.where((b) => !b.place.archived).fold(0, (a, b) => a + b.balanceZmw);

  ProfitReport report(DateTime from, DateTime to) => profitReport(
    from: from,
    to: to,
    sales: sales,
    ledger: ledger,
    platformByBatch: platformByBatch,
    returns: returns,
    expenses: expenses,
    otherCosts: otherCosts,
    losses: losses,
  );
}

class ReportRepository {
  ReportRepository(
    this.db,
    this.storeId, {
    required this.shipping,
    required this.stock,
    required this.money,
    required this.sales,
  });

  final AppDatabase db;
  final String storeId;
  final ShippingRepository shipping;
  final StockRepository stock;
  final MoneyRepository money;
  final SalesRepository sales;

  static const slowMoverDays = 60;

  Stream<BusinessSnapshot> watchSnapshot() => db
      .tableUpdates(TableUpdateQuery.onAllTables(db.allTables))
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => loadSnapshot());

  Future<BusinessSnapshot> loadSnapshot({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final landed = await shipping.computeLandedCosts();
    final (batches, demands) = await stock.loadStockInputs();
    final ledger = fifo(batches: batches, demands: demands);

    final names = <String, String>{
      for (final p in await (db.select(db.products)..where((p) => p.storeId.equals(storeId))).get())
        p.id: p.name,
      for (final l in await (db.select(db.lookups)..where((l) => l.storeId.equals(storeId))).get())
        l.id: l.name,
    };

    // Purchases and what has been paid for them so far.
    final purchases = await (db.select(
      db.purchases,
    )..where((p) => p.storeId.equals(storeId) & p.deletedAt.isNull())).get();
    final items = await (db.select(
      db.purchaseItems,
    )..where((i) => i.storeId.equals(storeId) & i.deletedAt.isNull())).get();
    final landedByPurchase = <String, int>{};
    for (final i in items) {
      landedByPurchase.update(
        i.purchaseId,
        (v) => v + (landed[i.id]?.totalZmw ?? 0),
        ifAbsent: () => landed[i.id]?.totalZmw ?? 0,
      );
    }
    final purchaseById = {for (final p in purchases) p.id: p};
    final platformByBatch = <String, String?>{
      for (final i in items) i.id: purchaseById[i.purchaseId]?.platformId,
    };
    const open = [
      PurchaseStatus.ordered,
      PurchaseStatus.shipped,
      PurchaseStatus.atAgent,
      PurchaseStatus.inTransit,
    ];
    final inTransit = purchases.where((p) => open.contains(p.status)).toList();

    // Sales.
    final allSales = await sales.loadSales();
    final saleItems = await (db.select(
      db.saleItems,
    )..where((i) => i.storeId.equals(storeId) & i.deletedAt.isNull())).get();
    final itemsBySale = <String, List<SaleItem>>{};
    for (final i in saleItems) {
      itemsBySale.putIfAbsent(i.saleId, () => []).add(i);
    }
    final saleFacts = [
      for (final s in allSales)
        if (s.sale.status == SaleStatus.fulfilled)
          SaleFact(
            id: s.sale.id,
            at: s.sale.fulfilledAt ?? s.sale.soldAt,
            channelId: s.sale.channelId,
            items: [
              for (final i in itemsBySale[s.sale.id] ?? const <SaleItem>[])
                SaleItemFact(
                  id: i.id,
                  productId: i.productId,
                  qty: i.qty,
                  revenueZmw: i.qty * i.unitPriceZmw,
                ),
            ],
          ),
    ];

    // Adjustments: returns, refunds, lost parcels, write-offs.
    final adjustments = await (db.select(
      db.adjustments,
    )..where((a) => a.storeId.equals(storeId) & a.deletedAt.isNull())).get();
    final returns = <ReturnFact>[];
    for (final s in allSales.where((s) => s.sale.status == SaleStatus.returned)) {
      final refunds = adjustments.where((a) => a.saleId == s.sale.id && a.kind == AdjustmentKind.saleReturn);
      returns.add(
        ReturnFact(
          at: refunds.isEmpty ? s.sale.updatedAt : refunds.first.occurredAt,
          paidZmw: s.paidZmw,
          refundedZmw: refunds.fold(0, (a, r) => a + r.amountZmw),
        ),
      );
    }
    int recovered(String purchaseId, AdjustmentKind kind) => adjustments
        .where((a) => a.purchaseId == purchaseId && a.kind == kind)
        .fold(0, (s, a) => s + a.amountZmw);
    final losses = <LossFact>[
      for (final a in adjustments)
        if (a.kind == AdjustmentKind.writeOff)
          LossFact(
            kind: LossKind.writeOff,
            at: a.occurredAt,
            amountZmw: ledger.demandCosts[a.id]?.costZmw ?? 0,
            label:
                '${names[a.productId] ?? 'Item'} × ${a.qty} · '
                '${writeOffReasonLabels[WriteOffReason.values.asNameMap()[a.reason]] ?? 'written off'}',
            refId: a.productId,
          )
        else if (a.kind == AdjustmentKind.refund &&
            a.reason == 'whole' &&
            purchaseById[a.purchaseId]?.status == PurchaseStatus.refunded)
          LossFact(
            kind: LossKind.refund,
            at: a.occurredAt,
            amountZmw:
                (landedByPurchase[a.purchaseId] ?? 0) - recovered(a.purchaseId!, AdjustmentKind.refund),
            label: 'Refunded order: currency loss',
            refId: a.purchaseId,
          )
        else if (a.kind == AdjustmentKind.lostParcel &&
            purchaseById[a.purchaseId]?.status == PurchaseStatus.lost)
          LossFact(
            kind: LossKind.lostParcel,
            at: a.occurredAt,
            amountZmw:
                (landedByPurchase[a.purchaseId] ?? 0) - recovered(a.purchaseId!, AdjustmentKind.compensation),
            label: 'Lost parcel',
            refId: a.purchaseId,
          ),
    ];

    final expenses = await (db.select(
      db.expenses,
    )..where((e) => e.storeId.equals(storeId) & e.deletedAt.isNull())).get();
    final transfers = await (db.select(
      db.transfers,
    )..where((t) => t.storeId.equals(storeId) & t.deletedAt.isNull())).get();
    final checks =
        await (db.select(db.balanceChecks)..where(
              (c) =>
                  c.storeId.equals(storeId) &
                  c.deletedAt.isNull() &
                  c.gapLabel.equalsValue(BalanceGapLabel.forgotExpense),
            ))
            .get();

    // Debts.
    final debts = await sales.watchDebts().first;

    // Slow movers: in stock, and nothing sold or received for a while.
    final lastActivity = <String, DateTime>{};
    void touch(String productId, DateTime at) {
      final current = lastActivity[productId];
      if (current == null || at.isAfter(current)) lastActivity[productId] = at;
    }

    for (final b in batches) {
      if ((ledger.remainingByBatch[b.id] ?? 0) > 0 && b.receivedAt.year > 1970) {
        touch(b.productId, b.receivedAt);
      }
    }
    for (final s in saleFacts) {
      for (final i in s.items) {
        touch(i.productId, s.at);
      }
    }
    final cutoff = today.subtract(const Duration(days: slowMoverDays));
    final slowMovers = [
      for (final MapEntry(key: productId, value: stockLeft) in ledger.stock.entries)
        if (stockLeft.qty > 0 && (lastActivity[productId]?.isBefore(cutoff) ?? true)) productId,
    ];

    final bills = await (db.select(
      db.shippingBills,
    )..where((b) => b.storeId.equals(storeId) & b.deletedAt.isNull())).get();

    return BusinessSnapshot(
      sales: saleFacts,
      returns: returns,
      expenses: [
        for (final e in expenses)
          ExpenseFact(at: e.spentAt, amountZmw: e.amountZmw, categoryId: e.categoryId),
      ],
      otherCosts: [
        for (final t in transfers)
          if (t.feeZmw > 0) OtherCostFact(at: t.transferredAt, amountZmw: t.feeZmw),
        for (final c in checks)
          if (c.expectedZmw > c.actualZmw)
            OtherCostFact(at: c.checkedAt, amountZmw: c.expectedZmw - c.actualZmw),
      ],
      losses: losses,
      ledger: ledger,
      platformByBatch: platformByBatch,
      transitZmw: inTransit.fold(0, (a, p) => a + (landedByPurchase[p.id] ?? p.paidZmw)),
      transitPurchases: inTransit.length,
      oldestTransit: inTransit.isEmpty
          ? null
          : inTransit.map((p) => p.orderedAt).reduce((a, b) => a.isBefore(b) ? a : b),
      owedZmw: debts.fold(0, (a, d) => a + d.owedZmw),
      oldestDebt: debts.isEmpty
          ? null
          : debts.map((d) => d.oldestSaleAt).reduce((a, b) => a.isBefore(b) ? a : b),
      slowMovers: slowMovers,
      balances: await money.watchBalances().first,
      cnyRates: RateSummary(
        points: [
          for (final p in purchases)
            if (p.totalCny > 0 && p.paidZmw > 0) RatePoint(at: p.orderedAt, rate: p.paidZmw / p.totalCny),
        ],
      ),
      usdRates: RateSummary(
        points: [
          for (final b in bills)
            if (b.totalUsd > 0 && b.paidZmw > 0) RatePoint(at: b.billedAt, rate: b.paidZmw / b.totalUsd),
        ],
      ),
      names: names,
    );
  }
}
