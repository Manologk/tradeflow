import 'package:drift/drift.dart';

import 'database.dart';

/// A money place entered during first-run setup.
class OpeningPlace {
  const OpeningPlace({
    required this.name,
    required this.kind,
    required this.balanceZmw,
  });

  final String name;
  final MoneyPlaceKind kind;
  final int balanceZmw;
}

/// Stock already held when setting up, with a rough cost per unit.
class OpeningStockEntry {
  const OpeningStockEntry({
    required this.productName,
    required this.qty,
    required this.unitCostZmw,
  });

  final String productName;
  final int qty;
  final int unitCostZmw;
}

const defaultLookups = {
  LookupKind.platform: ['Taobao', 'Pinduoduo', '1688', 'Xianyu', 'WeChat'],
  LookupKind.cargoType: ['General', 'Sensitive (battery/liquid)'],
  LookupKind.channel: ['WhatsApp', 'Facebook', 'Shop'],
  LookupKind.expenseCategory: ['Transport', 'Delivery', 'Transfer fees', 'Other'],
};

const defaultPlaces = [
  OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 0),
  OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 0),
  OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 0),
];

class SetupRepository {
  SetupRepository(this.db);

  final AppDatabase db;

  /// The single local store, or null before first-run setup.
  Stream<Store?> watchStore() => (db.select(db.stores)
        ..where((s) => s.deletedAt.isNull())
        ..limit(1))
      .watchSingleOrNull();

  Future<void> renameStore(String storeId, String name) =>
      (db.update(db.stores)..where((s) => s.id.equals(storeId))).write(
        StoresCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())),
      );

  /// Creates the store with its money places, default lists and opening stock
  /// in one transaction, so a half-finished setup never exists.
  Future<String> completeSetup({
    required String storeName,
    required List<OpeningPlace> places,
    List<OpeningStockEntry> stock = const [],
  }) {
    return db.transaction(() async {
      final store = await db
          .into(db.stores)
          .insertReturning(StoresCompanion.insert(name: storeName.trim()));
      final storeId = store.id;

      for (final (i, place) in places.indexed) {
        await db.into(db.moneyPlaces).insert(MoneyPlacesCompanion.insert(
              storeId: storeId,
              name: place.name.trim(),
              kind: place.kind,
              openingBalanceZmw: Value(place.balanceZmw),
              sortOrder: Value(i),
            ));
      }

      for (final MapEntry(key: kind, value: names) in defaultLookups.entries) {
        for (final (i, name) in names.indexed) {
          await db.into(db.lookups).insert(LookupsCompanion.insert(
                storeId: storeId,
                kind: kind,
                name: name,
                sortOrder: Value(i),
              ));
        }
      }

      for (final entry in stock) {
        final product = await db.into(db.products).insertReturning(
              ProductsCompanion.insert(storeId: storeId, name: entry.productName.trim()),
            );
        await db.into(db.openingStockItems).insert(OpeningStockItemsCompanion.insert(
              storeId: storeId,
              productId: product.id,
              qty: entry.qty,
              unitCostZmw: entry.unitCostZmw,
            ));
      }
      return storeId;
    });
  }
}
