import 'package:drift/drift.dart';

import '../core/streams.dart';
import 'database.dart';

class SaleItemDraft {
  const SaleItemDraft({this.id, required this.productName, required this.qty, required this.unitPriceZmw});

  final String? id;
  final String productName;
  final int qty;
  final int unitPriceZmw;

  int get totalZmw => qty * unitPriceZmw;
}

class SaleDraft {
  const SaleDraft({
    this.id,
    required this.soldAt,
    required this.kind,
    this.customerName,
    this.customerPhone,
    this.channelId,
    required this.items,
    this.paymentZmw = 0,
    this.paymentPlaceId,
    this.notes,
  });

  final String? id;
  final DateTime soldAt;
  final SaleKind kind;
  final String? customerName;
  final String? customerPhone;
  final String? channelId;
  final List<SaleItemDraft> items;

  /// Money received when the sale is first recorded (ignored on edit).
  final int paymentZmw;
  final String? paymentPlaceId;
  final String? notes;

  int get totalZmw => items.fold(0, (sum, i) => sum + i.totalZmw);
}

class SaleSummary {
  const SaleSummary({
    required this.sale,
    this.customer,
    this.channelName,
    required this.itemNames,
    required this.totalZmw,
    required this.paidZmw,
  });

  final Sale sale;
  final Customer? customer;
  final String? channelName;
  final List<String> itemNames;
  final int totalZmw;
  final int paidZmw;

  /// Nothing is owed on a returned sale.
  int get owedZmw => sale.status == SaleStatus.returned ? 0 : totalZmw - paidZmw;
  bool get isPendingPreOrder => sale.kind == SaleKind.preOrder && sale.status == SaleStatus.pending;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [...itemNames, customer?.name ?? '', channelName ?? ''].any((s) => s.toLowerCase().contains(q));
  }
}

class SaleItemDetail {
  const SaleItemDetail({required this.item, required this.product});

  final SaleItem item;
  final Product product;
}

class SaleDetail {
  const SaleDetail({
    required this.summary,
    required this.items,
    required this.payments,
    required this.linkedPurchases,
  });

  final SaleSummary summary;
  final List<SaleItemDetail> items;
  final List<(Payment, MoneyPlace)> payments;

  /// Purchases made for this pre-order.
  final List<Purchase> linkedPurchases;

  Sale get sale => summary.sale;
}

class CustomerDebt {
  const CustomerDebt({
    required this.customer,
    required this.owedZmw,
    required this.oldestSaleAt,
    required this.sales,
  });

  final Customer customer;
  final int owedZmw;
  final DateTime oldestSaleAt;
  final List<SaleSummary> sales;
}

class SalesRepository {
  SalesRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  // Reading ---------------------------------------------------------------

  Stream<List<SaleSummary>> watchSales() => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.sales,
          db.saleItems,
          db.payments,
          db.customers,
          db.products,
          db.lookups,
        ]),
      )
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => loadSales());

  Future<List<SaleSummary>> loadSales() async {
    final query = db.customSelect(
      '''
      SELECT s.*, l.name AS channel_name,
        (SELECT group_concat(pr.name, char(31)) FROM sale_items i
           JOIN products pr ON pr.id = i.product_id
           WHERE i.sale_id = s.id AND i.deleted_at IS NULL) AS item_names,
        (SELECT COALESCE(SUM(i.qty * i.unit_price_zmw), 0) FROM sale_items i
           WHERE i.sale_id = s.id AND i.deleted_at IS NULL) AS total,
        (SELECT COALESCE(SUM(p.amount_zmw), 0) FROM payments p
           WHERE p.sale_id = s.id AND p.deleted_at IS NULL) AS paid
      FROM sales s
      LEFT JOIN lookups l ON l.id = s.channel_id
      WHERE s.store_id = ? AND s.deleted_at IS NULL
      ORDER BY s.sold_at DESC, s.created_at DESC
      ''',
      variables: [Variable.withString(storeId)],
    );
    final rows = await query.get();
    final customers = {
      for (final c in await (db.select(db.customers)..where((c) => c.storeId.equals(storeId))).get()) c.id: c,
    };
    return [
      for (final row in rows)
        () {
          final sale = db.sales.map(row.data);
          final names = row.readNullable<String>('item_names');
          return SaleSummary(
            sale: sale,
            customer: sale.customerId == null ? null : customers[sale.customerId],
            channelName: row.readNullable<String>('channel_name'),
            itemNames: names == null || names.isEmpty ? const [] : names.split('\x1f'),
            totalZmw: row.read<int>('total'),
            paidZmw: row.read<int>('paid'),
          );
        }(),
    ];
  }

  Stream<SaleDetail?> watchSale(String id) => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([db.sales, db.saleItems, db.payments, db.customers, db.purchases]),
      )
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => _detail(id));

  Future<SaleDetail?> _detail(String id) async {
    final summary = (await loadSales()).where((s) => s.sale.id == id).firstOrNull;
    if (summary == null) return null;
    final items =
        await (db.select(db.saleItems).join([
                innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
              ])
              ..where(db.saleItems.saleId.equals(id) & db.saleItems.deletedAt.isNull())
              ..orderBy([OrderingTerm(expression: db.saleItems.createdAt)]))
            .get();
    final payments =
        await (db.select(db.payments).join([
                innerJoin(db.moneyPlaces, db.moneyPlaces.id.equalsExp(db.payments.moneyPlaceId)),
              ])
              ..where(db.payments.saleId.equals(id) & db.payments.deletedAt.isNull())
              ..orderBy([OrderingTerm(expression: db.payments.paidAt)]))
            .get();
    final purchases = await (db.select(
      db.purchases,
    )..where((p) => p.preOrderSaleId.equals(id) & p.deletedAt.isNull())).get();
    return SaleDetail(
      summary: summary,
      items: [
        for (final r in items)
          SaleItemDetail(item: r.readTable(db.saleItems), product: r.readTable(db.products)),
      ],
      payments: [for (final r in payments) (r.readTable(db.payments), r.readTable(db.moneyPlaces))],
      linkedPurchases: purchases,
    );
  }

  /// Customers who owe money, biggest debt first.
  Stream<List<CustomerDebt>> watchDebts() => watchSales().map((sales) {
    final byCustomer = <String, List<SaleSummary>>{};
    for (final s in sales) {
      if (s.owedZmw > 0 && s.customer != null && s.sale.status != SaleStatus.returned) {
        byCustomer.putIfAbsent(s.customer!.id, () => []).add(s);
      }
    }
    final debts = [
      for (final list in byCustomer.values)
        CustomerDebt(
          customer: list.first.customer!,
          owedZmw: list.fold(0, (sum, s) => sum + s.owedZmw),
          oldestSaleAt: list.map((s) => s.sale.soldAt).reduce((a, b) => a.isBefore(b) ? a : b),
          sales: list..sort((a, b) => a.sale.soldAt.compareTo(b.sale.soldAt)),
        ),
    ]..sort((a, b) => b.owedZmw.compareTo(a.owedZmw));
    return debts;
  });

  Stream<List<Customer>> watchCustomers() =>
      (db.select(db.customers)
            ..where((c) => c.storeId.equals(storeId) & c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm(expression: c.name.collate(Collate.noCase))]))
          .watch();

  /// Money place used on the most recent payment, to pre-select next time.
  Future<String?> lastPaymentPlaceId() async {
    final last =
        await (db.select(db.payments)
              ..where((p) => p.storeId.equals(storeId) & p.deletedAt.isNull())
              ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return last?.moneyPlaceId;
  }

  /// Pending pre-orders a purchase can be linked to.
  Future<List<SaleSummary>> pendingPreOrders() async =>
      (await loadSales()).where((s) => s.isPendingPreOrder).toList();

  // Writing ---------------------------------------------------------------

  Future<String> saveSale(SaleDraft draft) {
    if (draft.items.isEmpty) throw ArgumentError('A sale needs at least one item');
    final customerName = _clean(draft.customerName);
    final isNew = draft.id == null;
    if (isNew && draft.paymentZmw < draft.totalZmw && customerName == null) {
      throw ArgumentError('Add the customer so you know who owes the balance');
    }
    if (isNew && draft.paymentZmw > 0 && draft.paymentPlaceId == null) {
      throw ArgumentError('Say where the money was received');
    }
    return db.transaction(() async {
      final now = DateTime.now();
      final customerId = customerName == null
          ? null
          : await _customerIdFor(customerName, draft.customerPhone);
      final fulfilled = draft.kind == SaleKind.stock;

      final String saleId;
      if (isNew) {
        final sale = await db
            .into(db.sales)
            .insertReturning(
              SalesCompanion.insert(
                storeId: storeId,
                soldAt: draft.soldAt,
                customerId: Value(customerId),
                channelId: Value(draft.channelId),
                kind: draft.kind,
                status: fulfilled ? SaleStatus.fulfilled : SaleStatus.pending,
                fulfilledAt: Value(fulfilled ? draft.soldAt : null),
                notes: Value(_clean(draft.notes)),
              ),
            );
        saleId = sale.id;
        if (draft.paymentZmw > 0) {
          await db
              .into(db.payments)
              .insert(
                PaymentsCompanion.insert(
                  storeId: storeId,
                  saleId: saleId,
                  paidAt: draft.soldAt,
                  amountZmw: draft.paymentZmw,
                  moneyPlaceId: draft.paymentPlaceId!,
                ),
              );
        }
      } else {
        saleId = draft.id!;
        final current = await (db.select(db.sales)..where((s) => s.id.equals(saleId))).getSingle();
        final keepFulfilled = current.status == SaleStatus.fulfilled;
        await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
          SalesCompanion(
            soldAt: Value(draft.soldAt),
            customerId: Value(customerId),
            channelId: Value(draft.channelId),
            kind: Value(draft.kind),
            status: Value(fulfilled || keepFulfilled ? SaleStatus.fulfilled : SaleStatus.pending),
            fulfilledAt: Value(fulfilled ? draft.soldAt : current.fulfilledAt),
            notes: Value(_clean(draft.notes)),
            updatedAt: Value(now),
          ),
        );
      }
      await _saveItems(saleId, draft.items, now);
      return saleId;
    });
  }

  Future<void> _saveItems(String saleId, List<SaleItemDraft> drafts, DateTime now) async {
    final existing = await (db.select(
      db.saleItems,
    )..where((i) => i.saleId.equals(saleId) & i.deletedAt.isNull())).get();
    final kept = <String>{};
    for (final draft in drafts) {
      final productId = await _productIdFor(draft.productName);
      if (draft.id != null && existing.any((e) => e.id == draft.id)) {
        kept.add(draft.id!);
        await (db.update(db.saleItems)..where((i) => i.id.equals(draft.id!))).write(
          SaleItemsCompanion(
            productId: Value(productId),
            qty: Value(draft.qty),
            unitPriceZmw: Value(draft.unitPriceZmw),
            updatedAt: Value(now),
          ),
        );
      } else {
        await db
            .into(db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                storeId: storeId,
                saleId: saleId,
                productId: productId,
                qty: draft.qty,
                unitPriceZmw: draft.unitPriceZmw,
              ),
            );
      }
    }
    for (final removed in existing.where((e) => !kept.contains(e.id))) {
      await (db.update(db.saleItems)..where((i) => i.id.equals(removed.id))).write(
        SaleItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    }
  }

  Future<String> _productIdFor(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final match =
        await (db.select(db.products)
              ..where(
                (p) =>
                    p.storeId.equals(storeId) &
                    p.deletedAt.isNull() &
                    p.name.lower().equals(clean.toLowerCase()),
              )
              ..limit(1))
            .getSingleOrNull();
    if (match != null) return match.id;
    final created = await db
        .into(db.products)
        .insertReturning(ProductsCompanion.insert(storeId: storeId, name: clean));
    return created.id;
  }

  Future<String> _customerIdFor(String name, String? phone) async {
    final cleanPhone = _clean(phone);
    final match =
        await (db.select(db.customers)
              ..where(
                (c) =>
                    c.storeId.equals(storeId) &
                    c.deletedAt.isNull() &
                    c.name.lower().equals(name.toLowerCase()),
              )
              ..limit(1))
            .getSingleOrNull();
    if (match != null) {
      if (cleanPhone != null && cleanPhone != match.phone) {
        await (db.update(db.customers)..where((c) => c.id.equals(match.id))).write(
          CustomersCompanion(phone: Value(cleanPhone), updatedAt: Value(DateTime.now())),
        );
      }
      return match.id;
    }
    final created = await db
        .into(db.customers)
        .insertReturning(CustomersCompanion.insert(storeId: storeId, name: name, phone: Value(cleanPhone)));
    return created.id;
  }

  Future<void> addPayment({
    required String saleId,
    required int amountZmw,
    required String moneyPlaceId,
    required DateTime paidAt,
  }) async {
    if (amountZmw <= 0) throw ArgumentError('Payment must be more than zero');
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            storeId: storeId,
            saleId: saleId,
            paidAt: paidAt,
            amountZmw: amountZmw,
            moneyPlaceId: moneyPlaceId,
          ),
        );
  }

  /// Applies a customer's payment to their unpaid sales, oldest first. Any
  /// amount beyond what they owe goes on the newest sale.
  Future<void> payDebt({
    required CustomerDebt debt,
    required int amountZmw,
    required String moneyPlaceId,
    required DateTime paidAt,
  }) {
    if (amountZmw <= 0) throw ArgumentError('Payment must be more than zero');
    final parts = splitPaymentOldestFirst(amountZmw, [for (final s in debt.sales) s.owedZmw]);
    return db.transaction(() async {
      for (final (i, sale) in debt.sales.indexed) {
        if (parts[i] == 0) continue;
        await addPayment(
          saleId: sale.sale.id,
          amountZmw: parts[i],
          moneyPlaceId: moneyPlaceId,
          paidAt: paidAt,
        );
      }
    });
  }

  Future<void> deletePayment(String paymentId) =>
      (db.update(db.payments)..where((p) => p.id.equals(paymentId))).write(
        PaymentsCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())),
      );

  /// A pre-order handed to the customer: its profit now counts.
  Future<void> markFulfilled(String saleId, DateTime at) =>
      (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value(SaleStatus.fulfilled),
          fulfilledAt: Value(at),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteSale(String id) => db.transaction(() async {
    final now = DateTime.now();
    final deleted = Value<DateTime?>(now);
    await (db.update(db.saleItems)..where((i) => i.saleId.equals(id))).write(
      SaleItemsCompanion(deletedAt: deleted, updatedAt: Value(now)),
    );
    await (db.update(
      db.payments,
    )..where((p) => p.saleId.equals(id))).write(PaymentsCompanion(deletedAt: deleted, updatedAt: Value(now)));
    await (db.update(db.purchases)..where((p) => p.preOrderSaleId.equals(id))).write(
      PurchasesCompanion(preOrderSaleId: const Value(null), updatedAt: Value(now)),
    );
    await (db.update(
      db.sales,
    )..where((s) => s.id.equals(id))).write(SalesCompanion(deletedAt: deleted, updatedAt: Value(now)));
  });

  static String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

/// Splits a payment over outstanding balances (oldest first). Anything beyond
/// the total owed lands on the last one.
List<int> splitPaymentOldestFirst(int amount, List<int> owed) {
  final parts = <int>[];
  var left = amount;
  for (final (i, o) in owed.indexed) {
    final part = i == owed.length - 1 ? left : (left < o ? left : o);
    parts.add(part < 0 ? 0 : part);
    left -= parts.last;
  }
  return parts;
}
