import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/costing.dart';
import '../domain/fifo.dart';

import 'database.dart';
import 'money_repository.dart';
import 'purchase_repository.dart';
import 'settings_repository.dart';
import 'sales_repository.dart';
import 'setup_repository.dart';
import 'shipping_repository.dart';
import 'stock_repository.dart';

/// Overridden in main() (and in tests with an in-memory database).
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final setupRepositoryProvider = Provider((ref) => SetupRepository(ref.watch(databaseProvider)));

final storeProvider = StreamProvider<Store?>((ref) => ref.watch(setupRepositoryProvider).watchStore());

/// Only available once setup has created the store.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final store = ref.watch(storeProvider).value;
  if (store == null) throw StateError('Store not set up yet');
  return SettingsRepository(ref.watch(databaseProvider), store.id);
});

final lookupsProvider = StreamProvider.family<List<Lookup>, LookupKind>(
  (ref, kind) => ref.watch(settingsRepositoryProvider).watchLookups(kind),
);

final moneyPlacesProvider = StreamProvider<List<MoneyPlace>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchMoneyPlaces(),
);

final agentsProvider = StreamProvider<List<Agent>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchAgents(),
);

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  final store = ref.watch(storeProvider).value;
  if (store == null) throw StateError('Store not set up yet');
  return PurchaseRepository(ref.watch(databaseProvider), store.id);
});

final moneyRepositoryProvider = Provider<MoneyRepository>((ref) {
  final store = ref.watch(storeProvider).value;
  if (store == null) throw StateError('Store not set up yet');
  return MoneyRepository(ref.watch(databaseProvider), store.id);
});

final purchasesProvider = StreamProvider<List<PurchaseSummary>>(
  (ref) => ref.watch(purchaseRepositoryProvider).watchPurchases(),
);

final purchaseDetailProvider = StreamProvider.family<PurchaseDetail?, String>(
  (ref, id) => ref.watch(purchaseRepositoryProvider).watchPurchase(id),
);

final productsProvider = StreamProvider<List<ProductSummary>>(
  (ref) => ref.watch(purchaseRepositoryProvider).watchProducts(),
);

final balancesProvider = StreamProvider<List<PlaceBalance>>(
  (ref) => ref.watch(moneyRepositoryProvider).watchBalances(),
);

final shippingRepositoryProvider = Provider<ShippingRepository>((ref) {
  final store = ref.watch(storeProvider).value;
  if (store == null) throw StateError('Store not set up yet');
  return ShippingRepository(ref.watch(databaseProvider), store.id);
});

final shippingBillsProvider = StreamProvider<List<ShippingBillDetail>>(
  (ref) => ref.watch(shippingRepositoryProvider).watchBills(),
);

final collectionsProvider = StreamProvider<List<CollectionSummary>>(
  (ref) => ref.watch(shippingRepositoryProvider).watchCollections(),
);

final landedCostsProvider = StreamProvider<Map<String, ItemLandedCost>>(
  (ref) => ref.watch(shippingRepositoryProvider).watchLandedCosts(),
);

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final store = ref.watch(storeProvider).value;
  if (store == null) throw StateError('Store not set up yet');
  return SalesRepository(ref.watch(databaseProvider), store.id);
});

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  final store = ref.watch(storeProvider).value;
  if (store == null) throw StateError('Store not set up yet');
  return StockRepository(ref.watch(databaseProvider), store.id, ref.watch(shippingRepositoryProvider));
});

final salesProvider = StreamProvider<List<SaleSummary>>(
  (ref) => ref.watch(salesRepositoryProvider).watchSales(),
);

final saleDetailProvider = StreamProvider.family<SaleDetail?, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).watchSale(id),
);

final debtsProvider = StreamProvider<List<CustomerDebt>>(
  (ref) => ref.watch(salesRepositoryProvider).watchDebts(),
);

final customersProvider = StreamProvider<List<Customer>>(
  (ref) => ref.watch(salesRepositoryProvider).watchCustomers(),
);

final stockLedgerProvider = StreamProvider<StockLedger>(
  (ref) => ref.watch(stockRepositoryProvider).watchLedger(),
);

final movementsProvider = StreamProvider<List<Movement>>(
  (ref) => ref.watch(moneyRepositoryProvider).watchMovements(),
);

final lastBalanceCheckProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(moneyRepositoryProvider).watchLastBalanceCheck(),
);

final saleExpensesProvider = StreamProvider.family<List<Expense>, String>(
  (ref, saleId) => ref.watch(moneyRepositoryProvider).watchSaleExpenses(saleId),
);
