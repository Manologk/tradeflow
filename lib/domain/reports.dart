import '../core/allocation.dart';
import 'fifo.dart';

// Profit rules from docs/PRODUCT_SPEC.md §4.7. Pure: the repository turns
// database rows into these facts, and everything here is plain arithmetic.

class SaleItemFact {
  const SaleItemFact({
    required this.id,
    required this.productId,
    required this.qty,
    required this.revenueZmw,
  });

  final String id;
  final String productId;
  final int qty;
  final int revenueZmw;
}

/// A fulfilled sale, counted on the day it was handed over.
class SaleFact {
  const SaleFact({required this.id, required this.at, this.channelId, required this.items});

  final String id;
  final DateTime at;
  final String? channelId;
  final List<SaleItemFact> items;
}

/// A returned sale: what the customer had paid and what was refunded.
class ReturnFact {
  const ReturnFact({required this.at, required this.paidZmw, required this.refundedZmw});

  final DateTime at;
  final int paidZmw;
  final int refundedZmw;
}

class ExpenseFact {
  const ExpenseFact({required this.at, required this.amountZmw, required this.categoryId});

  final DateTime at;
  final int amountZmw;
  final String categoryId;
}

/// A cost that is not an expense row: transfer fees and balance gaps the user
/// marked as a forgotten business expense.
class OtherCostFact {
  const OtherCostFact({required this.at, required this.amountZmw});

  final DateTime at;
  final int amountZmw;
}

enum LossKind { refund, lostParcel, writeOff }

class LossFact {
  const LossFact({
    required this.kind,
    required this.at,
    required this.amountZmw,
    required this.label,
    this.refId,
  });

  final LossKind kind;
  final DateTime at;
  final int amountZmw;
  final String label;
  final String? refId;
}

class ProfitLine {
  const ProfitLine({this.units = 0, this.revenueZmw = 0, this.costZmw = 0});

  final int units;
  final int revenueZmw;
  final int costZmw;

  int get profitZmw => revenueZmw - costZmw;

  /// Profit as a share of revenue, or null with no revenue.
  double? get margin => revenueZmw == 0 ? null : profitZmw / revenueZmw;

  ProfitLine operator +(ProfitLine o) =>
      ProfitLine(units: units + o.units, revenueZmw: revenueZmw + o.revenueZmw, costZmw: costZmw + o.costZmw);
}

class ProfitReport {
  const ProfitReport({
    required this.totals,
    required this.expensesByCategory,
    required this.otherCostsZmw,
    required this.losses,
    required this.returnsKeptZmw,
    required this.byProduct,
    required this.byChannel,
    required this.byPlatform,
    required this.missingCostUnits,
  });

  /// Revenue and cost of goods across all sales in the period.
  final ProfitLine totals;
  final Map<String, int> expensesByCategory;

  /// Transfer fees and forgotten expenses.
  final int otherCostsZmw;
  final List<LossFact> losses;

  /// Money kept when a returned sale was refunded less than was paid.
  final int returnsKeptZmw;
  final Map<String, ProfitLine> byProduct;

  /// Keyed by channel id; null = no channel set.
  final Map<String?, ProfitLine> byChannel;

  /// Keyed by platform id; null = opening stock or unknown.
  final Map<String?, ProfitLine> byPlatform;

  /// Units sold with no recorded stock: their cost is missing.
  final int missingCostUnits;

  int get expensesZmw => expensesByCategory.values.fold(0, (a, b) => a + b);
  int get lossesZmw => losses.fold(0, (a, l) => a + l.amountZmw);
  int get grossProfitZmw => totals.profitZmw;
  int get netProfitZmw => grossProfitZmw - expensesZmw - otherCostsZmw - lossesZmw + returnsKeptZmw;
}

/// Profit for [from] (inclusive) to [to] (exclusive).
ProfitReport profitReport({
  required DateTime from,
  required DateTime to,
  required List<SaleFact> sales,
  required StockLedger ledger,
  required Map<String, String?> platformByBatch,
  List<ReturnFact> returns = const [],
  List<ExpenseFact> expenses = const [],
  List<OtherCostFact> otherCosts = const [],
  List<LossFact> losses = const [],
}) {
  bool inPeriod(DateTime at) => !at.isBefore(from) && at.isBefore(to);

  var totals = const ProfitLine();
  final byProduct = <String, ProfitLine>{};
  final byChannel = <String?, ProfitLine>{};
  final byPlatform = <String?, ProfitLine>{};
  var missing = 0;

  for (final sale in sales.where((s) => inPeriod(s.at))) {
    for (final item in sale.items) {
      final cost = ledger.demandCosts[item.id];
      final line = ProfitLine(units: item.qty, revenueZmw: item.revenueZmw, costZmw: cost?.costZmw ?? 0);
      totals += line;
      byProduct.update(item.productId, (l) => l + line, ifAbsent: () => line);
      byChannel.update(sale.channelId, (l) => l + line, ifAbsent: () => line);
      missing += cost?.unitsShort ?? item.qty;

      // Split this item's revenue over the batches its units came from.
      final uses = cost?.uses ?? const <BatchUse>[];
      final shortUnits = item.qty - uses.fold<int>(0, (a, u) => a + u.units);
      final weights = [for (final u in uses) u.units, if (shortUnits > 0) shortUnits];
      final revenueParts = allocate(item.revenueZmw, weights);
      for (final (i, u) in uses.indexed) {
        final part = ProfitLine(units: u.units, revenueZmw: revenueParts[i], costZmw: u.costZmw);
        byPlatform.update(platformByBatch[u.batchId], (l) => l + part, ifAbsent: () => part);
      }
      if (shortUnits > 0) {
        final part = ProfitLine(units: shortUnits, revenueZmw: revenueParts.last);
        byPlatform.update(null, (l) => l + part, ifAbsent: () => part);
      }
    }
  }

  final byCategory = <String, int>{};
  for (final e in expenses.where((e) => inPeriod(e.at))) {
    byCategory.update(e.categoryId, (v) => v + e.amountZmw, ifAbsent: () => e.amountZmw);
  }

  return ProfitReport(
    totals: totals,
    expensesByCategory: byCategory,
    otherCostsZmw: otherCosts.where((c) => inPeriod(c.at)).fold(0, (a, c) => a + c.amountZmw),
    losses: losses.where((l) => inPeriod(l.at) && l.amountZmw != 0).toList()
      ..sort((a, b) => b.at.compareTo(a.at)),
    returnsKeptZmw: returns
        .where((r) => inPeriod(r.at) && r.paidZmw > r.refundedZmw)
        .fold(0, (a, r) => a + r.paidZmw - r.refundedZmw),
    byProduct: byProduct,
    byChannel: byChannel,
    byPlatform: byPlatform,
    missingCostUnits: missing,
  );
}

/// One effective exchange rate you got on a payment.
class RatePoint {
  const RatePoint({required this.at, required this.rate});

  final DateTime at;

  /// Kwacha per unit of foreign currency.
  final double rate;
}

class RateSummary {
  const RateSummary({required this.points});

  final List<RatePoint> points;

  bool get isEmpty => points.isEmpty;
  RatePoint? get latest => points.isEmpty ? null : points.reduce((a, b) => a.at.isAfter(b.at) ? a : b);
  double? get best => points.isEmpty ? null : points.map((p) => p.rate).reduce((a, b) => a < b ? a : b);
  double? get worst => points.isEmpty ? null : points.map((p) => p.rate).reduce((a, b) => a > b ? a : b);
  double? get average =>
      points.isEmpty ? null : points.map((p) => p.rate).reduce((a, b) => a + b) / points.length;
}

/// Month boundaries used by Home and Reports.
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);
