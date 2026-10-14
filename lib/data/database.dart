import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/ids.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Stores,
    Lookups,
    MoneyPlaces,
    Agents,
    AgentRates,
    Products,
    Variants,
    Purchases,
    PurchaseItems,
    TrackingNumbers,
    ShippingBills,
    ShippingLines,
    ShippingLinePurchases,
    Collections,
    CollectionPurchases,
    Customers,
    Sales,
    SaleItems,
    Payments,
    Expenses,
    Adjustments,
    Transfers,
    BalanceChecks,
    OpeningStockItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'tradeflow'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
