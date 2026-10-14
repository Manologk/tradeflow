import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/shop_repository.dart';
import '../domain/checkout.dart';
import '../domain/models.dart';

/// Overridden in main() once the online database exists, and in tests.
final shopRepositoryProvider = Provider<ShopRepository>((ref) => const UnconfiguredShopRepository());

/// Overridden in main() with the loaded instance.
final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('preferencesProvider must be overridden'),
);

final catalogProvider = FutureProvider<Catalog>((ref) => ref.watch(shopRepositoryProvider).loadCatalog());

/// The cart, kept on the device between visits.
class CartNotifier extends Notifier<List<CartLine>> {
  static const _key = 'cart';

  @override
  List<CartLine> build() {
    final raw = ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) CartLine.fromJson((j as Map).cast<String, Object?>())];
    } on Object {
      return const [];
    }
  }

  void _save(List<CartLine> lines) {
    state = lines;
    ref.read(preferencesProvider).setString(_key, jsonEncode([for (final l in lines) l.toJson()]));
  }

  void add(CartLine line) {
    final existing = state.where((l) => l.key == line.key).firstOrNull;
    _save([
      for (final l in state) l.key == line.key ? l.copyWith(qty: l.qty + line.qty) : l,
      if (existing == null) line,
    ]);
  }

  void setQty(String key, int qty) {
    _save([
      for (final l in state)
        if (l.key != key) l else if (qty > 0) l.copyWith(qty: qty),
    ]);
  }

  void remove(String key) => setQty(key, 0);
  void clear() => _save(const []);
}

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

/// Cart priced against the live catalog (empty while it loads).
final pricedCartProvider = Provider<List<OrderLine>>((ref) {
  final catalog = ref.watch(catalogProvider).value;
  return catalog == null ? const [] : priceLines(ref.watch(cartProvider), catalog);
});

/// Favourite product ids, kept on the device (no account needed).
class FavouritesNotifier extends Notifier<Set<String>> {
  static const _key = 'favourites';

  @override
  Set<String> build() => {...?ref.watch(preferencesProvider).getStringList(_key)};

  void toggle(String productId) {
    state = state.contains(productId) ? ({...state}..remove(productId)) : {...state, productId};
    ref.read(preferencesProvider).setStringList(_key, state.toList());
  }
}

final favouritesProvider = NotifierProvider<FavouritesNotifier, Set<String>>(FavouritesNotifier.new);

/// Orders placed from this device, newest first, so "My orders" works without
/// an account.
class PlacedOrder {
  const PlacedOrder({
    required this.code,
    required this.phone,
    required this.createdAt,
    required this.totalZmw,
    required this.units,
  });

  final String code;
  final String phone;
  final DateTime createdAt;
  final int totalZmw;
  final int units;

  Map<String, Object?> toJson() => {
    'code': code,
    'phone': phone,
    'at': createdAt.toIso8601String(),
    'total': totalZmw,
    'units': units,
  };

  static PlacedOrder fromJson(Map<String, Object?> j) => PlacedOrder(
    code: j['code']! as String,
    phone: j['phone']! as String,
    createdAt: DateTime.parse(j['at']! as String),
    totalZmw: j['total']! as int,
    units: j['units']! as int,
  );
}

class PlacedOrdersNotifier extends Notifier<List<PlacedOrder>> {
  static const _key = 'orders';

  @override
  List<PlacedOrder> build() {
    final raw = ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List) PlacedOrder.fromJson((j as Map).cast<String, Object?>()),
      ];
    } on Object {
      return const [];
    }
  }

  void add(Order order) {
    state = [
      PlacedOrder(
        code: order.code,
        phone: order.customer.phone,
        createdAt: order.createdAt,
        totalZmw: order.totalZmw,
        units: order.units,
      ),
      ...state,
    ];
    ref.read(preferencesProvider).setString(_key, jsonEncode([for (final o in state) o.toJson()]));
  }
}

final placedOrdersProvider = NotifierProvider<PlacedOrdersNotifier, List<PlacedOrder>>(
  PlacedOrdersNotifier.new,
);

/// Remembered checkout details so returning customers don't retype them.
class SavedCustomer {
  SavedCustomer(this._prefs);

  final SharedPreferences _prefs;

  String get name => _prefs.getString('customer.name') ?? '';
  String get phone => _prefs.getString('customer.phone') ?? '';
  String? get areaId => _prefs.getString('customer.area');

  void save(Customer c) {
    _prefs
      ..setString('customer.name', c.name)
      ..setString('customer.phone', c.phone);
    if (c.areaId != null) _prefs.setString('customer.area', c.areaId!);
  }
}

final savedCustomerProvider = Provider((ref) => SavedCustomer(ref.watch(preferencesProvider)));
