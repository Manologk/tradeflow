import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradeflow_shop/app.dart';
import 'package:tradeflow_shop/data/shop_repository.dart';
import 'package:tradeflow_shop/domain/models.dart';
import 'package:tradeflow_shop/screens/cart_screen.dart';
import 'package:tradeflow_shop/state/providers.dart';

import 'fixtures.dart';

class FakeShop implements ShopRepository {
  final orders = <Order>[];

  @override
  Future<Catalog> loadCatalog() async => testCatalog;

  @override
  Future<void> submitOrder(Order order) async => orders.add(order);

  @override
  Future<Map<String, OrderStatus>> orderStatuses(List<String> codes, String phone) async => {
    for (final o in orders)
      if (codes.contains(o.code) && o.customer.phone == phone) o.code: OrderStatus.confirmed,
  };
}

Future<void> pumpShop(WidgetTester tester, {required ShopRepository repo, List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        shopRepositoryProvider.overrideWithValue(repo),
        linkOpenerProvider.overrideWithValue((uri) async {
          opened?.add(uri);
          return true;
        }),
      ],
      child: const ShopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows "opening soon" until the shop is connected', (tester) async {
    await pumpShop(tester, repo: const UnconfiguredShopRepository());
    expect(find.text('Opening soon'), findsOneWidget);
  });

  testWidgets('browse, filter and search the catalog', (tester) async {
    await pumpShop(tester, repo: FakeShop());
    expect(find.text('Otaku Corner'), findsOneWidget);
    expect(find.text('Naruto Sage Mode Figure'), findsOneWidget);
    expect(find.text('Gojo Hoodie'), findsOneWidget);
    expect(find.text('K450'), findsOneWidget);
    expect(find.text('K520'), findsOneWidget, reason: 'old price struck through');

    await tester.ensureVisible(find.text('Clothing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clothing'));
    await tester.pumpAndSettle();
    expect(find.text('Naruto Sage Mode Figure'), findsNothing);
    expect(find.text('Gojo Hoodie'), findsOneWidget);

    // Tapping the selected category again clears it.
    await tester.tap(find.text('Clothing'));
    await tester.enterText(find.byType(TextField), 'itachi');
    await tester.pumpAndSettle();
    expect(find.text('Itachi Keychain'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing found'), findsOneWidget);
  });

  testWidgets('order a figure and a pre-order hoodie on WhatsApp', (tester) async {
    final shop = FakeShop();
    final opened = <Uri>[];
    await pumpShop(tester, repo: shop, opened: opened);

    // Product page: hoodie needs a size and colour.
    await tester.tap(find.text('Gojo Hoodie'));
    await tester.pumpAndSettle();
    expect(find.text('Pre-order · arrives in ~3 weeks'), findsOneWidget);
    await tester.tap(find.textContaining('Pre-order | K380'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a size'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Size L'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Size L'));
    await tester.tap(find.bySemanticsLabel('Colour Black'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pre-order | K380'));
    await tester.pumpAndSettle();
    expect(find.text('Added Gojo Hoodie to your cart'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Naruto Sage Mode Figure'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add to Cart | K900'));
    await tester.pumpAndSettle();

    // Checkout.
    await tester.tap(find.text('View cart'));
    await tester.pumpAndSettle();
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Size L · Black · Pre-order'), findsOneWidget);
    expect(find.text('Total (3 items)'), findsOneWidget);
    expect(find.textContaining('deposit of K190'), findsOneWidget);

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Order on WhatsApp'), 300, scrollable: list);
    await tester.tap(find.text('Order on WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);

    await tester.scrollUntilVisible(find.widgetWithText(TextFormField, 'Your name'), -300, scrollable: list);
    await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Mwila');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '097 123 4567');
    await tester.pumpAndSettle();
    expect(find.text('K1,310'), findsOneWidget, reason: 'K1,280 + K30 CBD delivery');
    await tester.scrollUntilVisible(find.text('Order on WhatsApp'), 300, scrollable: list);
    await tester.tap(find.text('Order on WhatsApp'));
    await tester.pumpAndSettle();

    // Saved online and handed to WhatsApp.
    expect(shop.orders.single.customer.phone, '260971234567');
    expect(shop.orders.single.totalZmw, 131000);
    expect(opened.single.host, 'wa.me');
    expect(
      opened.single.queryParameters['text'],
      contains('1 × Gojo Hoodie (Size L, Black) [Pre-order ~3 weeks]'),
    );

    final code = shop.orders.single.code;
    expect(find.text('Order ready to send!'), findsOneWidget);
    expect(find.text('Your order code is $code'), findsOneWidget);

    // Cart is empty and the order is tracked under My orders.
    await tester.tap(find.text('Back to shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('My orders'));
    await tester.pumpAndSettle();
    expect(find.text(code), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    await tester.tap(find.byTooltip('Cart'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('favourites are kept on the device', (tester) async {
    await pumpShop(tester, repo: FakeShop());
    await tester.tap(find.bySemanticsLabel('Add to favourites').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('Naruto Sage Mode Figure'), findsOneWidget);
    expect(find.text('Gojo Hoodie'), findsNothing);
  });

  testWidgets('browse by series filters the shop', (tester) async {
    await pumpShop(tester, repo: FakeShop());
    await tester.tap(find.byTooltip('Browse by series'));
    await tester.pumpAndSettle();
    expect(find.text('Jujutsu Kaisen'), findsOneWidget);
    await tester.tap(find.text('Jujutsu Kaisen'));
    await tester.pumpAndSettle();
    expect(find.text('Series: Jujutsu Kaisen'), findsOneWidget);
    expect(find.text('Gojo Hoodie'), findsOneWidget);
    expect(find.text('Naruto Sage Mode Figure'), findsNothing);
  });
}
