import '../domain/models.dart';

/// Thrown until the shop is connected to its online database.
class ShopNotConfigured implements Exception {
  const ShopNotConfigured();

  @override
  String toString() => 'The shop is not connected yet.';
}

/// Where the storefront reads the catalog and sends orders. The Supabase
/// implementation arrives with the online database; tests use a fake.
abstract interface class ShopRepository {
  Future<Catalog> loadCatalog();

  /// Saves the order so it reaches the admin app.
  Future<void> submitOrder(Order order);

  /// Latest status of orders placed from this device, by code.
  Future<Map<String, OrderStatus>> orderStatuses(List<String> codes, String phone);
}

/// Used until the database is set up: every call reports "not connected".
class UnconfiguredShopRepository implements ShopRepository {
  const UnconfiguredShopRepository();

  @override
  Future<Catalog> loadCatalog() => Future.error(const ShopNotConfigured());

  @override
  Future<void> submitOrder(Order order) => Future.error(const ShopNotConfigured());

  @override
  Future<Map<String, OrderStatus>> orderStatuses(List<String> codes, String phone) =>
      Future.error(const ShopNotConfigured());
}
