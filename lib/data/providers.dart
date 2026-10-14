import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'money_repository.dart';
import 'purchase_repository.dart';
import 'settings_repository.dart';
import 'setup_repository.dart';

/// Overridden in main() (and in tests with an in-memory database).
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final setupRepositoryProvider =
    Provider((ref) => SetupRepository(ref.watch(databaseProvider)));

final storeProvider = StreamProvider<Store?>(
  (ref) => ref.watch(setupRepositoryProvider).watchStore(),
);

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
