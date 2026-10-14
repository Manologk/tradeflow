import 'package:drift/drift.dart';

import '../domain/costing.dart';
import 'database.dart';

/// One line of a purchase being created or edited.
class PurchaseItemDraft {
  const PurchaseItemDraft({
    this.id,
    required this.productName,
    required this.qty,
    required this.unitPriceCny,
    required this.cargoTypeId,
  });

  /// Existing item id when editing; null for a new line.
  final String? id;
  final String productName;
  final int qty;
  final int unitPriceCny;
  final String cargoTypeId;

  int get valueCny => qty * unitPriceCny;
}

class PurchaseDraft {
  const PurchaseDraft({
    this.id,
    this.platformId,
    this.sellerName,
    this.orderRef,
    required this.orderedAt,
    required this.items,
    this.sellerDeliveryCny = 0,
    required this.paidZmw,
    required this.moneyPlaceId,
    this.trackingNumbers = const [],
    this.notes,
  });

  final String? id;
  final String? platformId;
  final String? sellerName;
  final String? orderRef;
  final DateTime orderedAt;
  final List<PurchaseItemDraft> items;

  /// What the seller charged to deliver to the agent's warehouse, if any.
  final int sellerDeliveryCny;
  final int paidZmw;
  final String moneyPlaceId;
  final List<String> trackingNumbers;
  final String? notes;

  int get totalCny => items.fold(0, (sum, i) => sum + i.valueCny) + sellerDeliveryCny;
}

/// A purchase row for lists, with the bits needed to recognise it.
class PurchaseSummary {
  const PurchaseSummary({
    required this.purchase,
    this.platformName,
    required this.itemNames,
    required this.units,
    required this.trackingNumbers,
  });

  final Purchase purchase;
  final String? platformName;
  final List<String> itemNames;
  final int units;
  final List<String> trackingNumbers;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      ...itemNames,
      ...trackingNumbers,
      purchase.sellerName ?? '',
      purchase.orderRef ?? '',
      platformName ?? '',
    ].any((s) => s.toLowerCase().contains(q));
  }
}

class PurchaseItemDetail {
  const PurchaseItemDetail({required this.item, required this.product, required this.costZmw});

  final PurchaseItem item;
  final Product product;

  /// This line's share of what was actually paid in ZMW (before shipping).
  final int costZmw;
}

class PurchaseDetail {
  const PurchaseDetail({
    required this.purchase,
    this.platform,
    required this.moneyPlace,
    required this.items,
    required this.trackingNumbers,
  });

  final Purchase purchase;
  final Lookup? platform;
  final MoneyPlace moneyPlace;
  final List<PurchaseItemDetail> items;
  final List<String> trackingNumbers;

  int get itemsCny => items.fold(0, (sum, i) => sum + i.item.qty * i.item.unitPriceCny);
  int get sellerDeliveryCny => purchase.totalCny - itemsCny;
}

/// Product with how many units have been bought so far.
class ProductSummary {
  const ProductSummary({required this.product, required this.unitsBought, required this.openingUnits});

  final Product product;
  final int unitsBought;
  final int openingUnits;
}

class PurchaseRepository {
  PurchaseRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  // Reading ---------------------------------------------------------------

  Stream<List<PurchaseSummary>> watchPurchases() {
    final query = db.customSelect(
      '''
      SELECT p.*, l.name AS platform_name,
        (SELECT group_concat(pr.name, char(31)) FROM purchase_items i
           JOIN products pr ON pr.id = i.product_id
           WHERE i.purchase_id = p.id AND i.deleted_at IS NULL) AS item_names,
        (SELECT COALESCE(SUM(i.qty), 0) FROM purchase_items i
           WHERE i.purchase_id = p.id AND i.deleted_at IS NULL) AS units,
        (SELECT group_concat(t.number, char(31)) FROM tracking_numbers t
           WHERE t.purchase_id = p.id AND t.deleted_at IS NULL) AS tracking
      FROM purchases p
      LEFT JOIN lookups l ON l.id = p.platform_id
      WHERE p.store_id = ? AND p.deleted_at IS NULL
      ORDER BY p.ordered_at DESC, p.created_at DESC
      ''',
      variables: [Variable.withString(storeId)],
      readsFrom: {db.purchases, db.purchaseItems, db.products, db.trackingNumbers, db.lookups},
    );
    List<String> split(String? s) => s == null || s.isEmpty ? const [] : s.split('\x1f');
    return query.watch().map((rows) => [
          for (final row in rows)
            PurchaseSummary(
              purchase: db.purchases.map(row.data),
              platformName: row.readNullable<String>('platform_name'),
              itemNames: split(row.readNullable<String>('item_names')),
              units: row.read<int>('units'),
              trackingNumbers: split(row.readNullable<String>('tracking')),
            ),
        ]);
  }

  Stream<PurchaseDetail?> watchPurchase(String id) {
    return (db.select(db.purchases)..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
        .watchSingleOrNull()
        .asyncMap((purchase) async => purchase == null ? null : _detail(purchase));
  }

  Future<PurchaseDetail> _detail(Purchase purchase) async {
    final rows = await (db.select(db.purchaseItems).join([
      innerJoin(db.products, db.products.id.equalsExp(db.purchaseItems.productId)),
    ])
          ..where(db.purchaseItems.purchaseId.equals(purchase.id) & db.purchaseItems.deletedAt.isNull())
          ..orderBy([OrderingTerm(expression: db.purchaseItems.createdAt)]))
        .get();
    final items = [for (final r in rows) (r.readTable(db.purchaseItems), r.readTable(db.products))];
    final costs = itemPurchaseCosts(
      paidZmw: purchase.paidZmw,
      itemValuesCny: [for (final (item, _) in items) item.qty * item.unitPriceCny],
    );
    final tracking = await (db.select(db.trackingNumbers)
          ..where((t) => t.purchaseId.equals(purchase.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    final platform = purchase.platformId == null
        ? null
        : await (db.select(db.lookups)..where((l) => l.id.equals(purchase.platformId!))).getSingleOrNull();
    final place =
        await (db.select(db.moneyPlaces)..where((p) => p.id.equals(purchase.moneyPlaceId))).getSingle();

    return PurchaseDetail(
      purchase: purchase,
      platform: platform,
      moneyPlace: place,
      items: [
        for (final (i, (item, product)) in items.indexed)
          PurchaseItemDetail(item: item, product: product, costZmw: costs[i]),
      ],
      trackingNumbers: [for (final t in tracking) t.number],
    );
  }

  /// Money place used on the most recent purchase, to pre-select next time.
  Future<String?> lastUsedMoneyPlaceId() async {
    final last = await (db.select(db.purchases)
          ..where((p) => p.storeId.equals(storeId) & p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    return last?.moneyPlaceId;
  }

  Stream<List<ProductSummary>> watchProducts() {
    final query = db.customSelect(
      '''
      SELECT pr.*,
        (SELECT COALESCE(SUM(i.qty), 0) FROM purchase_items i
           JOIN purchases p ON p.id = i.purchase_id
           WHERE i.product_id = pr.id AND i.deleted_at IS NULL AND p.deleted_at IS NULL) AS bought,
        (SELECT COALESCE(SUM(o.qty), 0) FROM opening_stock_items o
           WHERE o.product_id = pr.id AND o.deleted_at IS NULL) AS opening
      FROM products pr
      WHERE pr.store_id = ? AND pr.deleted_at IS NULL
      ORDER BY pr.name COLLATE NOCASE
      ''',
      variables: [Variable.withString(storeId)],
      readsFrom: {db.products, db.purchaseItems, db.purchases, db.openingStockItems},
    );
    return query.watch().map((rows) => [
          for (final row in rows)
            ProductSummary(
              product: db.products.map(row.data),
              unitsBought: row.read<int>('bought'),
              openingUnits: row.read<int>('opening'),
            ),
        ]);
  }

  Future<void> renameProduct(String id, String name) =>
      (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())),
      );

  // Writing ---------------------------------------------------------------

  /// Creates or updates a purchase with its items and tracking numbers.
  /// Product names that don't exist yet become new products.
  Future<String> savePurchase(PurchaseDraft draft) {
    if (draft.items.isEmpty) throw ArgumentError('A purchase needs at least one item');
    return db.transaction(() async {
      final now = DateTime.now();
      String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

      final String purchaseId;
      if (draft.id == null) {
        final row = await db.into(db.purchases).insertReturning(PurchasesCompanion.insert(
              storeId: storeId,
              platformId: Value(draft.platformId),
              sellerName: Value(clean(draft.sellerName)),
              orderRef: Value(clean(draft.orderRef)),
              orderedAt: draft.orderedAt,
              totalCny: draft.totalCny,
              paidZmw: draft.paidZmw,
              moneyPlaceId: draft.moneyPlaceId,
              status: draft.trackingNumbers.isEmpty ? PurchaseStatus.ordered : PurchaseStatus.shipped,
              notes: Value(clean(draft.notes)),
            ));
        purchaseId = row.id;
      } else {
        purchaseId = draft.id!;
        await (db.update(db.purchases)..where((p) => p.id.equals(purchaseId))).write(PurchasesCompanion(
          platformId: Value(draft.platformId),
          sellerName: Value(clean(draft.sellerName)),
          orderRef: Value(clean(draft.orderRef)),
          orderedAt: Value(draft.orderedAt),
          totalCny: Value(draft.totalCny),
          paidZmw: Value(draft.paidZmw),
          moneyPlaceId: Value(draft.moneyPlaceId),
          notes: Value(clean(draft.notes)),
          updatedAt: Value(now),
        ));
      }

      await _saveItems(purchaseId, draft.items, now);
      await _saveTracking(purchaseId, draft.trackingNumbers, now);
      if (draft.id != null && draft.trackingNumbers.isNotEmpty) {
        // Adding a tracking number means the seller has shipped.
        await (db.update(db.purchases)
              ..where((p) => p.id.equals(purchaseId) & p.status.equalsValue(PurchaseStatus.ordered)))
            .write(PurchasesCompanion(status: const Value(PurchaseStatus.shipped), updatedAt: Value(now)));
      }
      return purchaseId;
    });
  }

  Future<void> _saveItems(String purchaseId, List<PurchaseItemDraft> drafts, DateTime now) async {
    final existing = await (db.select(db.purchaseItems)
          ..where((i) => i.purchaseId.equals(purchaseId) & i.deletedAt.isNull()))
        .get();
    final kept = <String>{};
    for (final draft in drafts) {
      final productId = await _productIdFor(draft.productName);
      if (draft.id != null && existing.any((e) => e.id == draft.id)) {
        kept.add(draft.id!);
        await (db.update(db.purchaseItems)..where((i) => i.id.equals(draft.id!))).write(PurchaseItemsCompanion(
          productId: Value(productId),
          qty: Value(draft.qty),
          unitPriceCny: Value(draft.unitPriceCny),
          cargoTypeId: Value(draft.cargoTypeId),
          updatedAt: Value(now),
        ));
      } else {
        await db.into(db.purchaseItems).insert(PurchaseItemsCompanion.insert(
              storeId: storeId,
              purchaseId: purchaseId,
              productId: productId,
              qty: draft.qty,
              unitPriceCny: draft.unitPriceCny,
              cargoTypeId: draft.cargoTypeId,
            ));
      }
    }
    for (final removed in existing.where((e) => !kept.contains(e.id))) {
      await (db.update(db.purchaseItems)..where((i) => i.id.equals(removed.id)))
          .write(PurchaseItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    }
  }

  Future<void> _saveTracking(String purchaseId, List<String> numbers, DateTime now) async {
    final wanted = {
      for (final n in numbers)
        if (n.trim().isNotEmpty) n.trim().toUpperCase(),
    };
    final existing = await (db.select(db.trackingNumbers)
          ..where((t) => t.purchaseId.equals(purchaseId) & t.deletedAt.isNull()))
        .get();
    for (final t in existing) {
      if (!wanted.remove(t.number)) {
        await (db.update(db.trackingNumbers)..where((x) => x.id.equals(t.id)))
            .write(TrackingNumbersCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      }
    }
    for (final number in wanted) {
      await db.into(db.trackingNumbers).insert(TrackingNumbersCompanion.insert(
            storeId: storeId,
            purchaseId: purchaseId,
            number: number,
          ));
    }
  }

  /// Finds a product by name (ignoring case and spacing) or creates it.
  Future<String> _productIdFor(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final match = await (db.select(db.products)
          ..where((p) =>
              p.storeId.equals(storeId) &
              p.deletedAt.isNull() &
              p.name.lower().equals(clean.toLowerCase()))
          ..limit(1))
        .getSingleOrNull();
    if (match != null) return match.id;
    final created =
        await db.into(db.products).insertReturning(ProductsCompanion.insert(storeId: storeId, name: clean));
    return created.id;
  }

  Future<void> setStatus(String id, PurchaseStatus status) =>
      (db.update(db.purchases)..where((p) => p.id.equals(id))).write(
        PurchasesCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
      );

  Future<void> deletePurchase(String id) => db.transaction(() async {
        final now = DateTime.now();
        final deleted = Value<DateTime?>(now);
        await (db.update(db.purchaseItems)..where((i) => i.purchaseId.equals(id)))
            .write(PurchaseItemsCompanion(deletedAt: deleted, updatedAt: Value(now)));
        await (db.update(db.trackingNumbers)..where((t) => t.purchaseId.equals(id)))
            .write(TrackingNumbersCompanion(deletedAt: deleted, updatedAt: Value(now)));
        await (db.update(db.purchases)..where((p) => p.id.equals(id)))
            .write(PurchasesCompanion(deletedAt: deleted, updatedAt: Value(now)));
      });
}
