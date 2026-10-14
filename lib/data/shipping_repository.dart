import 'package:drift/drift.dart';

import '../domain/costing.dart';
import '../core/streams.dart';
import 'database.dart';

class ShippingLineDraft {
  const ShippingLineDraft({
    this.id,
    required this.cargoTypeId,
    required this.weightGrams,
    required this.amountUsd,
    required this.purchaseIds,
  });

  final String? id;
  final String cargoTypeId;
  final int weightGrams;
  final int amountUsd;
  final List<String> purchaseIds;
}

class ShippingBillDraft {
  const ShippingBillDraft({
    this.id,
    required this.agentId,
    required this.billedAt,
    required this.paidZmw,
    required this.moneyPlaceId,
    required this.lines,
  });

  final String? id;
  final String agentId;
  final DateTime billedAt;
  final int paidZmw;
  final String moneyPlaceId;
  final List<ShippingLineDraft> lines;

  int get totalUsd => lines.fold(0, (sum, l) => sum + l.amountUsd);
}

class ShippingLineDetail {
  const ShippingLineDetail({required this.line, required this.costZmw, required this.purchaseIds});

  final ShippingLine line;
  final int costZmw;
  final List<String> purchaseIds;
}

class ShippingBillDetail {
  const ShippingBillDetail({
    required this.bill,
    required this.agent,
    required this.moneyPlace,
    required this.lines,
  });

  final ShippingBill bill;
  final Agent agent;
  final MoneyPlace moneyPlace;
  final List<ShippingLineDetail> lines;

  int get weightGrams => lines.fold(0, (sum, l) => sum + l.line.weightGrams);
  Set<String> get purchaseIds => {for (final l in lines) ...l.purchaseIds};
}

class CollectionDraft {
  const CollectionDraft({
    required this.collectedAt,
    required this.transportZmw,
    required this.storageZmw,
    this.moneyPlaceId,
    required this.purchaseIds,
  });

  final DateTime collectedAt;
  final int transportZmw;
  final int storageZmw;
  final String? moneyPlaceId;
  final List<String> purchaseIds;
}

class CollectionSummary {
  const CollectionSummary({required this.collection, required this.purchaseIds});

  final Collection collection;
  final List<String> purchaseIds;

  int get costZmw => collection.transportZmw + collection.storageZmw;
}

/// A purchase that shipping lines or collections can point at.
class OpenPurchase {
  const OpenPurchase({required this.purchase, required this.label, required this.trackingNumbers});

  final Purchase purchase;
  final String label;
  final List<String> trackingNumbers;
}

/// Shipping bills, collections and the landed costs they produce.
class ShippingRepository {
  ShippingRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  static const _openStatuses = [
    PurchaseStatus.ordered,
    PurchaseStatus.shipped,
    PurchaseStatus.atAgent,
    PurchaseStatus.inTransit,
  ];

  // Bills -----------------------------------------------------------------

  Stream<List<ShippingBillDetail>> watchBills() => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.shippingBills,
          db.shippingLines,
          db.shippingLinePurchases,
          db.agents,
        ]),
      )
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => _loadBills());

  Stream<ShippingBillDetail?> watchBill(String id) =>
      watchBills().map((bills) => bills.where((b) => b.bill.id == id).firstOrNull);

  Future<List<ShippingBillDetail>> _loadBills() async {
    final bills =
        await (db.select(db.shippingBills)
              ..where((b) => b.storeId.equals(storeId) & b.deletedAt.isNull())
              ..orderBy([(b) => OrderingTerm.desc(b.billedAt), (b) => OrderingTerm.desc(b.createdAt)]))
            .get();
    if (bills.isEmpty) return const [];
    final lines =
        await (db.select(db.shippingLines)
              ..where((l) => l.storeId.equals(storeId) & l.deletedAt.isNull())
              ..orderBy([(l) => OrderingTerm(expression: l.createdAt)]))
            .get();
    final links = await (db.select(
      db.shippingLinePurchases,
    )..where((l) => l.storeId.equals(storeId) & l.deletedAt.isNull())).get();
    final agents = {for (final a in await db.select(db.agents).get()) a.id: a};
    final places = {for (final p in await db.select(db.moneyPlaces).get()) p.id: p};

    return [
      for (final bill in bills)
        () {
          final billLines = lines.where((l) => l.billId == bill.id).toList();
          final costs = billLineCosts(
            paidZmw: bill.paidZmw,
            lineAmountsUsd: [for (final l in billLines) l.amountUsd],
          );
          return ShippingBillDetail(
            bill: bill,
            agent: agents[bill.agentId]!,
            moneyPlace: places[bill.moneyPlaceId]!,
            lines: [
              for (final (i, line) in billLines.indexed)
                ShippingLineDetail(
                  line: line,
                  costZmw: costs[i],
                  purchaseIds: [
                    for (final l in links)
                      if (l.lineId == line.id) l.purchaseId,
                  ],
                ),
            ],
          );
        }(),
    ];
  }

  /// Purchases not yet collected, refunded or lost, plus any in [include]
  /// (so an edited bill still shows what it already covers).
  Future<List<OpenPurchase>> openPurchases({Set<String> include = const {}}) async {
    final query = db.customSelect(
      '''
      SELECT p.*,
        (SELECT group_concat(pr.name, ', ') FROM purchase_items i
           JOIN products pr ON pr.id = i.product_id
           WHERE i.purchase_id = p.id AND i.deleted_at IS NULL) AS item_names,
        (SELECT group_concat(t.number, char(31)) FROM tracking_numbers t
           WHERE t.purchase_id = p.id AND t.deleted_at IS NULL) AS tracking
      FROM purchases p
      WHERE p.store_id = ? AND p.deleted_at IS NULL
      ORDER BY p.ordered_at DESC
      ''',
      variables: [Variable.withString(storeId)],
      readsFrom: {db.purchases, db.purchaseItems, db.products, db.trackingNumbers},
    );
    final rows = await query.get();
    return [
      for (final row in rows)
        if (_openStatuses.contains(db.purchases.map(row.data).status) ||
            include.contains(row.read<String>('id')))
          OpenPurchase(
            purchase: db.purchases.map(row.data),
            label: row.readNullable<String>('item_names') ?? 'Purchase',
            trackingNumbers: (row.readNullable<String>('tracking') ?? '')
                .split('\x1f')
                .where((t) => t.isNotEmpty)
                .toList(),
          ),
    ];
  }

  /// Purchase ids whose tracking number matches exactly (ignoring case).
  Future<List<String>> purchasesForTracking(String number) async {
    final clean = number.trim().toUpperCase();
    if (clean.isEmpty) return const [];
    final rows =
        await (db.select(db.trackingNumbers).join([
              innerJoin(db.purchases, db.purchases.id.equalsExp(db.trackingNumbers.purchaseId)),
            ])..where(
              db.trackingNumbers.storeId.equals(storeId) &
                  db.trackingNumbers.deletedAt.isNull() &
                  db.purchases.deletedAt.isNull() &
                  db.trackingNumbers.number.equals(clean),
            ))
            .get();
    return {for (final r in rows) r.readTable(db.purchases).id}.toList();
  }

  Future<String> saveBill(ShippingBillDraft draft) {
    if (draft.lines.isEmpty) throw ArgumentError('A bill needs at least one line');
    return db.transaction(() async {
      final now = DateTime.now();
      final String billId;
      if (draft.id == null) {
        final bill = await db
            .into(db.shippingBills)
            .insertReturning(
              ShippingBillsCompanion.insert(
                storeId: storeId,
                agentId: draft.agentId,
                billedAt: draft.billedAt,
                totalUsd: draft.totalUsd,
                paidZmw: draft.paidZmw,
                moneyPlaceId: draft.moneyPlaceId,
              ),
            );
        billId = bill.id;
      } else {
        billId = draft.id!;
        await (db.update(db.shippingBills)..where((b) => b.id.equals(billId))).write(
          ShippingBillsCompanion(
            agentId: Value(draft.agentId),
            billedAt: Value(draft.billedAt),
            totalUsd: Value(draft.totalUsd),
            paidZmw: Value(draft.paidZmw),
            moneyPlaceId: Value(draft.moneyPlaceId),
            updatedAt: Value(now),
          ),
        );
      }

      final existing = await (db.select(
        db.shippingLines,
      )..where((l) => l.billId.equals(billId) & l.deletedAt.isNull())).get();
      final kept = <String>{};
      for (final line in draft.lines) {
        final String lineId;
        if (line.id != null && existing.any((e) => e.id == line.id)) {
          lineId = line.id!;
          kept.add(lineId);
          await (db.update(db.shippingLines)..where((l) => l.id.equals(lineId))).write(
            ShippingLinesCompanion(
              cargoTypeId: Value(line.cargoTypeId),
              weightGrams: Value(line.weightGrams),
              amountUsd: Value(line.amountUsd),
              updatedAt: Value(now),
            ),
          );
        } else {
          final created = await db
              .into(db.shippingLines)
              .insertReturning(
                ShippingLinesCompanion.insert(
                  storeId: storeId,
                  billId: billId,
                  cargoTypeId: line.cargoTypeId,
                  weightGrams: line.weightGrams,
                  amountUsd: line.amountUsd,
                ),
              );
          lineId = created.id;
        }
        await _setLinePurchases(lineId, line.purchaseIds, now);
      }
      for (final removed in existing.where((e) => !kept.contains(e.id))) {
        await _setLinePurchases(removed.id, const [], now);
        await (db.update(db.shippingLines)..where((l) => l.id.equals(removed.id))).write(
          ShippingLinesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      }

      // Goods the agent has billed for are on their way.
      final billed = {for (final l in draft.lines) ...l.purchaseIds};
      await (db.update(db.purchases)..where(
            (p) =>
                p.id.isIn(billed) &
                p.status.isInValues(const [
                  PurchaseStatus.ordered,
                  PurchaseStatus.shipped,
                  PurchaseStatus.atAgent,
                ]),
          ))
          .write(PurchasesCompanion(status: const Value(PurchaseStatus.inTransit), updatedAt: Value(now)));
      return billId;
    });
  }

  Future<void> _setLinePurchases(String lineId, List<String> purchaseIds, DateTime now) async {
    final wanted = purchaseIds.toSet();
    final existing = await (db.select(
      db.shippingLinePurchases,
    )..where((l) => l.lineId.equals(lineId) & l.deletedAt.isNull())).get();
    for (final link in existing) {
      if (!wanted.remove(link.purchaseId)) {
        await (db.update(db.shippingLinePurchases)..where((l) => l.id.equals(link.id))).write(
          ShippingLinePurchasesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      }
    }
    for (final purchaseId in wanted) {
      await db
          .into(db.shippingLinePurchases)
          .insert(
            ShippingLinePurchasesCompanion.insert(storeId: storeId, lineId: lineId, purchaseId: purchaseId),
          );
    }
  }

  Future<void> deleteBill(String id) => db.transaction(() async {
    final now = DateTime.now();
    final lines = await (db.select(
      db.shippingLines,
    )..where((l) => l.billId.equals(id) & l.deletedAt.isNull())).get();
    for (final line in lines) {
      await _setLinePurchases(line.id, const [], now);
    }
    await (db.update(db.shippingLines)..where((l) => l.billId.equals(id))).write(
      ShippingLinesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (db.update(db.shippingBills)..where((b) => b.id.equals(id))).write(
      ShippingBillsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  });

  // Collections -----------------------------------------------------------

  Stream<List<CollectionSummary>> watchCollections() => db
      .tableUpdates(TableUpdateQuery.onAllTables([db.collections, db.collectionPurchases]))
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => _loadCollections());

  Future<List<CollectionSummary>> _loadCollections() async {
    final collections =
        await (db.select(db.collections)
              ..where((c) => c.storeId.equals(storeId) & c.deletedAt.isNull())
              ..orderBy([(c) => OrderingTerm.desc(c.collectedAt), (c) => OrderingTerm.desc(c.createdAt)]))
            .get();
    final links = await (db.select(
      db.collectionPurchases,
    )..where((l) => l.storeId.equals(storeId) & l.deletedAt.isNull())).get();
    return [
      for (final c in collections)
        CollectionSummary(
          collection: c,
          purchaseIds: [
            for (final l in links)
              if (l.collectionId == c.id) l.purchaseId,
          ],
        ),
    ];
  }

  /// Records goods picked up from the agent. The purchases become stock.
  Future<String> saveCollection(CollectionDraft draft) {
    if (draft.purchaseIds.isEmpty) throw ArgumentError('Choose at least one purchase');
    if (draft.transportZmw + draft.storageZmw > 0 && draft.moneyPlaceId == null) {
      throw ArgumentError('Say where the transport/storage money came from');
    }
    return db.transaction(() async {
      final now = DateTime.now();
      final collection = await db
          .into(db.collections)
          .insertReturning(
            CollectionsCompanion.insert(
              storeId: storeId,
              collectedAt: draft.collectedAt,
              transportZmw: Value(draft.transportZmw),
              storageZmw: Value(draft.storageZmw),
              moneyPlaceId: Value(draft.moneyPlaceId),
            ),
          );
      for (final purchaseId in draft.purchaseIds.toSet()) {
        await db
            .into(db.collectionPurchases)
            .insert(
              CollectionPurchasesCompanion.insert(
                storeId: storeId,
                collectionId: collection.id,
                purchaseId: purchaseId,
              ),
            );
      }
      await (db.update(db.purchases)..where((p) => p.id.isIn(draft.purchaseIds))).write(
        PurchasesCompanion(status: const Value(PurchaseStatus.collected), updatedAt: Value(now)),
      );
      return collection.id;
    });
  }

  /// Undoes a collection: its purchases go back to "on the way".
  Future<void> deleteCollection(String id) => db.transaction(() async {
    final now = DateTime.now();
    final links = await (db.select(
      db.collectionPurchases,
    )..where((l) => l.collectionId.equals(id) & l.deletedAt.isNull())).get();
    final purchaseIds = [for (final l in links) l.purchaseId];
    await (db.update(db.collectionPurchases)..where((l) => l.collectionId.equals(id))).write(
      CollectionPurchasesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (db.update(db.collections)..where((c) => c.id.equals(id))).write(
      CollectionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (db.update(db.purchases)
          ..where((p) => p.id.isIn(purchaseIds) & p.status.equalsValue(PurchaseStatus.collected)))
        .write(PurchasesCompanion(status: const Value(PurchaseStatus.inTransit), updatedAt: Value(now)));
  });

  // Landed costs ----------------------------------------------------------

  /// Landed cost of every purchase item, recomputed whenever any input changes
  /// (spec §4.6: derived, never hand-edited).
  Stream<Map<String, ItemLandedCost>> watchLandedCosts() => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.purchases,
          db.purchaseItems,
          db.shippingBills,
          db.shippingLines,
          db.shippingLinePurchases,
          db.collections,
          db.collectionPurchases,
        ]),
      )
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => computeLandedCosts());

  Future<Map<String, ItemLandedCost>> computeLandedCosts() async {
    final purchases = await (db.select(
      db.purchases,
    )..where((p) => p.storeId.equals(storeId) & p.deletedAt.isNull())).get();
    final items =
        await (db.select(db.purchaseItems)
              ..where((i) => i.storeId.equals(storeId) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm(expression: i.createdAt)]))
            .get();
    final costItems = <CostItem>[];
    for (final purchase in purchases) {
      final own = items.where((i) => i.purchaseId == purchase.id).toList();
      final costs = itemPurchaseCosts(
        paidZmw: purchase.paidZmw,
        itemValuesCny: [for (final i in own) i.qty * i.unitPriceCny],
      );
      for (final (n, i) in own.indexed) {
        costItems.add(
          CostItem(
            id: i.id,
            purchaseId: purchase.id,
            cargoTypeId: i.cargoTypeId,
            qty: i.qty,
            purchaseCostZmw: costs[n],
          ),
        );
      }
    }

    final bills = await _loadBills();
    final collections = await _loadCollections();
    return landedCosts(
      items: costItems,
      shippingLines: [
        for (final bill in bills)
          for (final line in bill.lines)
            CostShippingLine(
              id: line.line.id,
              cargoTypeId: line.line.cargoTypeId,
              costZmw: line.costZmw,
              purchaseIds: line.purchaseIds,
            ),
      ],
      collections: [
        for (final c in collections)
          CostCollection(id: c.collection.id, costZmw: c.costZmw, purchaseIds: c.purchaseIds),
      ],
    );
  }
}
