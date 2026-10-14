// Design preview with the test catalog. Not part of the shipped app:
//   flutter build web -t preview/main.dart -o build/preview
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradeflow_shop/app.dart';
import 'package:tradeflow_shop/data/shop_repository.dart';
import 'package:tradeflow_shop/domain/models.dart';
import 'package:tradeflow_shop/state/providers.dart';

import '../test/fixtures.dart';

class _PreviewShop implements ShopRepository {
  @override
  Future<Catalog> loadCatalog() async => testCatalog;

  @override
  Future<void> submitOrder(Order order) async {}

  @override
  Future<Map<String, OrderStatus>> orderStatuses(List<String> codes, String phone) async => {};
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Format money and dates the same way whatever language the visitor's
  // browser reports (some report locales intl doesn't know).
  Intl.defaultLocale = 'en_US';
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        shopRepositoryProvider.overrideWithValue(_PreviewShop()),
      ],
      child: const ShopApp(),
    ),
  );
}
