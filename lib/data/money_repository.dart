import 'package:drift/drift.dart';

import 'database.dart';

enum MovementKind {
  purchase,
  shipping,
  pickup,
  salePayment,
  expense,
  transferOut,
  transferIn,
  adjustment,
  refund,
  compensation,
  saleRefund,
}

/// One change to a money place's balance.
class Movement {
  const Movement({
    required this.kind,
    required this.id,
    required this.at,
    required this.amountZmw,
    required this.placeId,
    this.label,
    this.detail,
  });

  final MovementKind kind;

  /// Id of the source record (purchase, payment, expense, transfer, check…).
  final String id;
  final DateTime at;

  /// Positive = money in, negative = money out.
  final int amountZmw;
  final String placeId;
  final String? label;
  final String? detail;
}

class PlaceBalance {
  const PlaceBalance({required this.place, required this.balanceZmw});

  final MoneyPlace place;
  final int balanceZmw;
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.spentAt,
    required this.categoryId,
    required this.amountZmw,
    required this.moneyPlaceId,
    this.saleId,
    this.note,
  });

  final DateTime spentAt;
  final String categoryId;
  final int amountZmw;
  final String moneyPlaceId;
  final String? saleId;
  final String? note;
}

/// Every money movement and the balance of each money place.
///
/// Balances are derived from the same movement list the Money tab shows, so
/// what you see listed always adds up to the balance.
class MoneyRepository {
  MoneyRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  static const _movementsSql = '''
    SELECT 'purchase' AS kind, p.id, p.ordered_at AS at, -p.paid_zmw AS amount, p.money_place_id AS place,
      (SELECT group_concat(pr.name, ', ') FROM purchase_items i JOIN products pr ON pr.id = i.product_id
         WHERE i.purchase_id = p.id AND i.deleted_at IS NULL) AS label,
      NULL AS detail
    FROM purchases p WHERE p.store_id = ?1 AND p.deleted_at IS NULL
    UNION ALL
    SELECT 'shipping', b.id, b.billed_at, -b.paid_zmw, b.money_place_id, a.name, NULL
    FROM shipping_bills b JOIN agents a ON a.id = b.agent_id
    WHERE b.store_id = ?1 AND b.deleted_at IS NULL
    UNION ALL
    SELECT 'pickup', c.id, c.collected_at, -(c.transport_zmw + c.storage_zmw), c.money_place_id, NULL, NULL
    FROM collections c
    WHERE c.store_id = ?1 AND c.deleted_at IS NULL AND c.money_place_id IS NOT NULL
      AND c.transport_zmw + c.storage_zmw > 0
    UNION ALL
    SELECT 'salePayment', pay.id, pay.paid_at, pay.amount_zmw, pay.money_place_id, cu.name, pay.sale_id
    FROM payments pay JOIN sales s ON s.id = pay.sale_id LEFT JOIN customers cu ON cu.id = s.customer_id
    WHERE pay.store_id = ?1 AND pay.deleted_at IS NULL AND s.deleted_at IS NULL
    UNION ALL
    SELECT 'expense', e.id, e.spent_at, -e.amount_zmw, e.money_place_id, l.name, e.note
    FROM expenses e JOIN lookups l ON l.id = e.category_id
    WHERE e.store_id = ?1 AND e.deleted_at IS NULL
    UNION ALL
    SELECT 'transferOut', t.id, t.transferred_at, -(t.amount_zmw + t.fee_zmw), t.from_place_id, mp.name,
      CASE WHEN t.fee_zmw > 0 THEN t.fee_zmw END
    FROM transfers t JOIN money_places mp ON mp.id = t.to_place_id
    WHERE t.store_id = ?1 AND t.deleted_at IS NULL
    UNION ALL
    SELECT 'transferIn', t.id, t.transferred_at, t.amount_zmw, t.to_place_id, mp.name, NULL
    FROM transfers t JOIN money_places mp ON mp.id = t.from_place_id
    WHERE t.store_id = ?1 AND t.deleted_at IS NULL
    UNION ALL
    SELECT 'adjustment', bc.id, bc.checked_at, bc.actual_zmw - bc.expected_zmw, bc.money_place_id, bc.gap_label, NULL
    FROM balance_checks bc
    WHERE bc.store_id = ?1 AND bc.deleted_at IS NULL AND bc.actual_zmw != bc.expected_zmw
    UNION ALL
    SELECT CASE a.kind WHEN 'saleReturn' THEN 'saleRefund' ELSE a.kind END, a.id, a.occurred_at,
      CASE a.kind WHEN 'saleReturn' THEN -a.amount_zmw ELSE a.amount_zmw END, a.money_place_id,
      COALESCE(a.purchase_id, a.sale_id), NULL
    FROM adjustments a
    WHERE a.store_id = ?1 AND a.deleted_at IS NULL AND a.money_place_id IS NOT NULL AND a.amount_zmw != 0
      AND a.kind IN ('refund', 'compensation', 'saleReturn')
  ''';

  Set<ResultSetImplementation> get _sources => {
    db.purchases,
    db.purchaseItems,
    db.products,
    db.shippingBills,
    db.agents,
    db.collections,
    db.payments,
    db.sales,
    db.customers,
    db.expenses,
    db.lookups,
    db.transfers,
    db.moneyPlaces,
    db.balanceChecks,
    db.adjustments,
  };

  Selectable<Movement> _movements() => db
      .customSelect(
        'SELECT * FROM ($_movementsSql) ORDER BY at DESC, kind',
        variables: [Variable.withString(storeId)],
        readsFrom: _sources,
      )
      .map(
        (row) => Movement(
          kind: MovementKind.values.byName(row.read<String>('kind')),
          id: row.read<String>('id'),
          at: row.read<DateTime>('at'),
          amountZmw: row.read<int>('amount'),
          placeId: row.read<String>('place'),
          label: row.readNullable<String>('label'),
          detail: row.data['detail']?.toString(),
        ),
      );

  Stream<List<Movement>> watchMovements() => _movements().watch();

  Stream<List<PlaceBalance>> watchBalances() => db
      .customSelect(
        '''
        SELECT mp.*, mp.opening_balance_zmw + COALESCE(
          (SELECT SUM(m.amount) FROM ($_movementsSql) m WHERE m.place = mp.id), 0) AS balance
        FROM money_places mp
        WHERE mp.store_id = ?1 AND mp.deleted_at IS NULL
        ORDER BY mp.sort_order
        ''',
        variables: [Variable.withString(storeId)],
        readsFrom: _sources,
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            PlaceBalance(place: db.moneyPlaces.map(row.data), balanceZmw: row.read<int>('balance')),
        ],
      );

  // Expenses --------------------------------------------------------------

  Future<String> addExpense(ExpenseDraft draft) async {
    if (draft.amountZmw <= 0) throw ArgumentError('Expense must be more than zero');
    final note = draft.note?.trim();
    final row = await db
        .into(db.expenses)
        .insertReturning(
          ExpensesCompanion.insert(
            storeId: storeId,
            spentAt: draft.spentAt,
            categoryId: draft.categoryId,
            amountZmw: draft.amountZmw,
            moneyPlaceId: draft.moneyPlaceId,
            saleId: Value(draft.saleId),
            note: Value(note == null || note.isEmpty ? null : note),
          ),
        );
    return row.id;
  }

  Future<void> deleteExpense(String id) => (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
    ExpensesCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())),
  );

  /// Expenses attached to a sale (e.g. delivery to the customer).
  Stream<List<Expense>> watchSaleExpenses(String saleId) =>
      (db.select(db.expenses)..where((e) => e.saleId.equals(saleId) & e.deletedAt.isNull())).watch();

  /// The expense category to use for delivery costs on a sale.
  Future<String?> deliveryCategoryId() async {
    final categories =
        await (db.select(db.lookups)..where(
              (l) =>
                  l.storeId.equals(storeId) &
                  l.kind.equalsValue(LookupKind.expenseCategory) &
                  l.deletedAt.isNull() &
                  l.archived.equals(false),
            ))
            .get();
    return (categories.where((c) => c.name.toLowerCase().contains('deliver')).firstOrNull ??
            categories.firstOrNull)
        ?.id;
  }

  // Transfers -------------------------------------------------------------

  Future<String> addTransfer({
    required String fromPlaceId,
    required String toPlaceId,
    required int amountZmw,
    int feeZmw = 0,
    required DateTime at,
  }) async {
    if (fromPlaceId == toPlaceId) throw ArgumentError('Choose two different places');
    if (amountZmw <= 0) throw ArgumentError('Amount must be more than zero');
    final row = await db
        .into(db.transfers)
        .insertReturning(
          TransfersCompanion.insert(
            storeId: storeId,
            fromPlaceId: fromPlaceId,
            toPlaceId: toPlaceId,
            transferredAt: at,
            amountZmw: amountZmw,
            feeZmw: Value(feeZmw),
          ),
        );
    return row.id;
  }

  Future<void> deleteTransfer(String id) => (db.update(db.transfers)..where((t) => t.id.equals(id))).write(
    TransfersCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())),
  );

  // Balance checks --------------------------------------------------------

  /// Records what is actually in each place. Any difference from the
  /// expected balance is kept as an adjustment, labelled "unrecorded" until
  /// the user says what it was.
  Future<void> recordBalanceCheck(Map<String, int> actualByPlace, {DateTime? at}) {
    final when = at ?? DateTime.now();
    return db.transaction(() async {
      final balances = {for (final b in await watchBalances().first) b.place.id: b.balanceZmw};
      for (final MapEntry(key: placeId, value: actual) in actualByPlace.entries) {
        await db
            .into(db.balanceChecks)
            .insert(
              BalanceChecksCompanion.insert(
                storeId: storeId,
                checkedAt: when,
                moneyPlaceId: placeId,
                actualZmw: actual,
                expectedZmw: balances[placeId] ?? 0,
              ),
            );
      }
    });
  }

  Future<void> labelGap(String checkId, BalanceGapLabel label) =>
      (db.update(db.balanceChecks)..where((c) => c.id.equals(checkId))).write(
        BalanceChecksCompanion(gapLabel: Value(label), updatedAt: Value(DateTime.now())),
      );

  Future<void> deleteBalanceCheck(String id) => (db.update(db.balanceChecks)..where((c) => c.id.equals(id)))
      .write(BalanceChecksCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())));

  Stream<DateTime?> watchLastBalanceCheck() {
    final latest = db.balanceChecks.checkedAt.max();
    return (db.selectOnly(db.balanceChecks)
          ..addColumns([latest])
          ..where(db.balanceChecks.storeId.equals(storeId) & db.balanceChecks.deletedAt.isNull()))
        .map((row) => row.read(latest))
        .watchSingle();
  }
}
