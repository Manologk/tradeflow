import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/money_repository.dart';
import 'package:tradeflow/data/purchase_repository.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  late AppDatabase db;
  late PurchaseRepository purchases;
  late MoneyRepository money;
  late String cardId;
  late String general;
  late String sensitive;
  late String taobao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final storeId = await SetupRepository(db).completeSetup(
      storeName: 'Test',
      places: const [
        OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 500000),
        OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 10000),
      ],
      stock: const [OpeningStockEntry(productName: 'Phone case', qty: 3, unitCostZmw: 2500)],
    );
    final settings = SettingsRepository(db, storeId);
    purchases = PurchaseRepository(db, storeId);
    money = MoneyRepository(db, storeId);
    cardId = (await settings.watchMoneyPlaces().first).first.id;
    final cargo = await settings.watchLookups(LookupKind.cargoType).first;
    general = cargo[0].id;
    sensitive = cargo[1].id;
    taobao = (await settings.watchLookups(LookupKind.platform).first).first.id;
  });

  tearDown(() => db.close());

  PurchaseDraft draft({String? id, List<PurchaseItemDraft>? items, List<String> tracking = const []}) =>
      PurchaseDraft(
        id: id,
        platformId: taobao,
        sellerName: ' Shenzhen Gadgets ',
        orderedAt: DateTime(2026, 10, 1),
        items:
            items ??
            [
              PurchaseItemDraft(productName: 'Earbuds', qty: 2, unitPriceCny: 5000, cargoTypeId: sensitive),
              PurchaseItemDraft(
                productName: ' phone   CASE ',
                qty: 10,
                unitPriceCny: 800,
                cargoTypeId: general,
              ),
            ],
        sellerDeliveryCny: 1000,
        paidZmw: 70000,
        moneyPlaceId: cardId,
        trackingNumbers: tracking,
      );

  test('saves a purchase, reusing existing products by name', () async {
    final id = await purchases.savePurchase(draft());
    final detail = (await purchases.watchPurchase(id).first)!;

    expect(detail.purchase.totalCny, 2 * 5000 + 10 * 800 + 1000);
    expect(detail.purchase.sellerName, 'Shenzhen Gadgets');
    expect(detail.purchase.status, PurchaseStatus.ordered);
    expect(detail.sellerDeliveryCny, 1000);
    expect(detail.items.map((i) => i.product.name), ['Earbuds', 'Phone case']);

    // 'phone   CASE' matched the opening-stock product instead of duplicating it.
    final products = await purchases.watchProducts().first;
    expect(products.map((p) => p.product.name), ['Earbuds', 'Phone case']);
    final phoneCase = products.firstWhere((p) => p.product.name == 'Phone case');
    expect(
      (phoneCase.unitsBought, phoneCase.openingUnits, phoneCase.unitsReceived, phoneCase.unitsOnTheWay),
      (10, 3, 3, 10),
    );
  });

  test('ZMW paid is split across items by CNY value and sums exactly', () async {
    final id = await purchases.savePurchase(draft());
    final detail = (await purchases.watchPurchase(id).first)!;
    // Items worth ¥100 and ¥80 share K700.00 -> 7000000/18000 ratio.
    expect(detail.items.map((i) => i.costZmw), [38889, 31111]);
    expect(detail.items.fold<int>(0, (s, i) => s + i.costZmw), 70000);
  });

  test('tracking numbers are normalised and mark the purchase shipped', () async {
    final id = await purchases.savePurchase(draft(tracking: [' yt123 ', 'YT123', 'sf9']));
    var detail = (await purchases.watchPurchase(id).first)!;
    expect(detail.trackingNumbers, ['YT123', 'SF9']);
    expect(detail.purchase.status, PurchaseStatus.shipped);

    final list = await purchases.watchPurchases().first;
    expect(list.single.matches('sf9'), isTrue);
    expect(list.single.matches('earbud'), isTrue);
    expect(list.single.matches('nothing'), isFalse);

    await purchases.savePurchase(draft(id: id, tracking: ['SF9', 'ZT7']));
    detail = (await purchases.watchPurchase(id).first)!;
    expect(detail.trackingNumbers, ['SF9', 'ZT7']);
  });

  test('editing keeps item ids, updates, adds and soft-deletes lines', () async {
    final id = await purchases.savePurchase(draft());
    final before = (await purchases.watchPurchase(id).first)!;
    final earbuds = before.items.first.item;

    await purchases.savePurchase(
      draft(
        id: id,
        items: [
          PurchaseItemDraft(
            id: earbuds.id,
            productName: 'Earbuds',
            qty: 3,
            unitPriceCny: 5000,
            cargoTypeId: sensitive,
          ),
          PurchaseItemDraft(productName: 'Charger', qty: 1, unitPriceCny: 2000, cargoTypeId: sensitive),
        ],
      ),
    );
    final after = (await purchases.watchPurchase(id).first)!;
    expect(after.items.map((i) => (i.product.name, i.item.qty)), [('Earbuds', 3), ('Charger', 1)]);
    expect(after.items.first.item.id, earbuds.id);

    final all = await db.select(db.purchaseItems).get();
    expect(all.where((i) => i.deletedAt != null).length, 1);

    final summary = (await purchases.watchPurchases().first).single;
    expect(summary.units, 4);
  });

  test('payments reduce the money place balance; deleting restores it', () async {
    final id = await purchases.savePurchase(draft());
    var balances = await money.watchBalances().first;
    expect(balances.map((b) => b.balanceZmw), [500000 - 70000, 10000]);

    await purchases.deletePurchase(id);
    balances = await money.watchBalances().first;
    expect(balances.map((b) => b.balanceZmw), [500000, 10000]);
    expect(await purchases.watchPurchases().first, isEmpty);
    expect(await purchases.watchPurchase(id).first, isNull);
  });

  test('status can be moved by hand', () async {
    final id = await purchases.savePurchase(draft());
    await purchases.setStatus(id, PurchaseStatus.inTransit);
    expect((await purchases.watchPurchase(id).first)!.purchase.status, PurchaseStatus.inTransit);
  });

  test('last used money place is remembered', () async {
    expect(await purchases.lastUsedMoneyPlaceId(), isNull);
    await purchases.savePurchase(draft());
    expect(await purchases.lastUsedMoneyPlaceId(), cardId);
  });

  test('a purchase needs items', () {
    expect(() => purchases.savePurchase(draft(items: [])), throwsArgumentError);
  });
}
