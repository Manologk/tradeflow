import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/domain/costing.dart';
import 'package:tradeflow/data/money_repository.dart';
import 'package:tradeflow/data/purchase_repository.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';
import 'package:tradeflow/data/shipping_repository.dart';

void main() {
  late AppDatabase db;
  late PurchaseRepository purchases;
  late ShippingRepository shipping;
  late MoneyRepository money;
  late String card;
  late String cash;
  late String general;
  late String sensitive;
  late String agent;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final storeId = await SetupRepository(db).completeSetup(
      storeName: 'Test',
      places: const [
        OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 1000000),
        OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 50000),
      ],
    );
    final settings = SettingsRepository(db, storeId);
    purchases = PurchaseRepository(db, storeId);
    shipping = ShippingRepository(db, storeId);
    money = MoneyRepository(db, storeId);
    final places = await settings.watchMoneyPlaces().first;
    card = places[0].id;
    cash = places[1].id;
    final cargo = await settings.watchLookups(LookupKind.cargoType).first;
    general = cargo[0].id;
    sensitive = cargo[1].id;
    agent = await settings.saveAgent(name: 'Speedy', usdPerKgByCargoType: {general: 900});
  });

  tearDown(() => db.close());

  Future<String> buy(List<PurchaseItemDraft> items, int paidZmw, {List<String> tracking = const []}) =>
      purchases.savePurchase(
        PurchaseDraft(
          orderedAt: DateTime(2026, 10, 1),
          items: items,
          paidZmw: paidZmw,
          moneyPlaceId: card,
          trackingNumbers: tracking,
        ),
      );

  PurchaseItemDraft line(String name, int qty, int cny, String cargo) =>
      PurchaseItemDraft(productName: name, qty: qty, unitPriceCny: cny, cargoTypeId: cargo);

  Future<PurchaseStatus> statusOf(String id) async =>
      (await purchases.watchPurchase(id).first)!.purchase.status;

  test('full journey: buy, bill (consolidated + per parcel), collect, landed cost', () async {
    final p1 = await buy(
      [line('Cable', 10, 1000, general), line('Power bank', 2, 5000, sensitive)],
      74000,
      tracking: ['YT1'],
    );
    final p2 = await buy([line('Shoes', 2, 10000, general)], 74000, tracking: ['SF2']);

    expect(await shipping.purchasesForTracking(' yt1 '), [p1]);
    expect(await shipping.purchasesForTracking('nope'), isEmpty);

    final billId = await shipping.saveBill(
      ShippingBillDraft(
        agentId: agent,
        billedAt: DateTime(2026, 10, 10),
        paidZmw: 60000,
        moneyPlaceId: card,
        lines: [
          // Consolidated general line across both purchases.
          ShippingLineDraft(cargoTypeId: general, weightGrams: 3000, amountUsd: 2000, purchaseIds: [p1, p2]),
          // Per-parcel sensitive line.
          ShippingLineDraft(cargoTypeId: sensitive, weightGrams: 500, amountUsd: 1000, purchaseIds: [p1]),
        ],
      ),
    );
    expect(await statusOf(p1), PurchaseStatus.inTransit);
    expect(await statusOf(p2), PurchaseStatus.inTransit);

    final bill = (await shipping.watchBill(billId).first)!;
    expect(bill.bill.totalUsd, 3000);
    expect(bill.lines.map((l) => l.costZmw), [40000, 20000]);
    expect(bill.weightGrams, 3500);
    expect(bill.purchaseIds, {p1, p2});

    final open = await shipping.openPurchases();
    expect(open.map((o) => o.purchase.id).toSet(), {p1, p2});

    await shipping.saveCollection(
      CollectionDraft(
        collectedAt: DateTime(2026, 10, 20),
        transportZmw: 5000,
        storageZmw: 1000,
        moneyPlaceId: cash,
        purchaseIds: [p1, p2],
      ),
    );
    expect(await statusOf(p1), PurchaseStatus.collected);
    expect(await shipping.openPurchases(), isEmpty);

    final costs = await shipping.computeLandedCosts();
    final items = [
      ...(await purchases.watchPurchase(p1).first)!.items,
      ...(await purchases.watchPurchase(p2).first)!.items,
    ];
    ItemCostCheck cost(String product) =>
        ItemCostCheck(costs[items.firstWhere((i) => i.product.name == product).item.id]!);

    // Purchase split: K740 over ¥100/¥100 -> 37000 each; shoes take all 74000.
    // General line K400 over cable (37000) and shoes (74000) by value.
    // Sensitive line K200 goes only to the power bank.
    // Collection K60 spread by purchase + shipping.
    expect(cost('Cable').parts, (37000, 13333, 1452));
    expect(cost('Power bank').parts, (37000, 20000, 1644));
    expect(cost('Shoes').parts, (74000, 26667, 2904));
    expect(cost('Cable').unit, 5179);
    expect(cost('Shoes').unit, 51786);

    final total = costs.values.fold<int>(0, (s, c) => s + c.totalZmw);
    expect(total, 74000 + 74000 + 60000 + 6000, reason: 'every ngwee lands on an item');

    final balances = await money.watchBalances().first;
    expect(balances.map((b) => b.balanceZmw), [1000000 - 148000 - 60000, 50000 - 6000]);
  });

  test('sensitive line lands only on sensitive items', () async {
    final p1 = await buy([line('Cable', 1, 1000, general), line('Power bank', 1, 1000, sensitive)], 20000);
    await shipping.saveBill(
      ShippingBillDraft(
        agentId: agent,
        billedAt: DateTime(2026, 10, 10),
        paidZmw: 9000,
        moneyPlaceId: card,
        lines: [
          ShippingLineDraft(cargoTypeId: sensitive, weightGrams: 400, amountUsd: 500, purchaseIds: [p1]),
        ],
      ),
    );
    final detail = (await purchases.watchPurchase(p1).first)!;
    final costs = await shipping.computeLandedCosts();
    final cable = detail.items.firstWhere((i) => i.product.name == 'Cable').item.id;
    final bank = detail.items.firstWhere((i) => i.product.name == 'Power bank').item.id;
    expect(costs[cable]!.shippingZmw, 0);
    expect(costs[bank]!.shippingZmw, 9000);
  });

  test('editing a bill relinks lines and deleting it removes its cost', () async {
    final p1 = await buy([line('A', 1, 1000, general)], 10000);
    final p2 = await buy([line('B', 1, 1000, general)], 10000);
    final billId = await shipping.saveBill(
      ShippingBillDraft(
        agentId: agent,
        billedAt: DateTime(2026, 10, 10),
        paidZmw: 4000,
        moneyPlaceId: card,
        lines: [
          ShippingLineDraft(cargoTypeId: general, weightGrams: 1000, amountUsd: 900, purchaseIds: [p1]),
        ],
      ),
    );
    final lineId = (await shipping.watchBill(billId).first)!.lines.single.line.id;

    await shipping.saveBill(
      ShippingBillDraft(
        id: billId,
        agentId: agent,
        billedAt: DateTime(2026, 10, 10),
        paidZmw: 4000,
        moneyPlaceId: card,
        lines: [
          ShippingLineDraft(
            id: lineId,
            cargoTypeId: general,
            weightGrams: 1000,
            amountUsd: 900,
            purchaseIds: [p2],
          ),
        ],
      ),
    );
    var bill = (await shipping.watchBill(billId).first)!;
    expect(bill.lines.single.line.id, lineId);
    expect(bill.lines.single.purchaseIds, [p2]);

    var costs = await shipping.computeLandedCosts();
    expect(costs.values.map((c) => c.shippingZmw).toList()..sort(), [0, 4000]);

    await shipping.deleteBill(billId);
    expect(await shipping.watchBill(billId).first, isNull);
    costs = await shipping.computeLandedCosts();
    expect(costs.values.every((c) => c.shippingZmw == 0), isTrue);
  });

  test('deleting a collection puts purchases back in transit', () async {
    final p1 = await buy([line('A', 1, 1000, general)], 10000);
    final collectionId = await shipping.saveCollection(
      CollectionDraft(collectedAt: DateTime(2026, 10, 20), transportZmw: 0, storageZmw: 0, purchaseIds: [p1]),
    );
    expect(await statusOf(p1), PurchaseStatus.collected);
    await shipping.deleteCollection(collectionId);
    expect(await statusOf(p1), PurchaseStatus.inTransit);
    expect(await shipping.watchCollections().first, isEmpty);
  });

  test('collection with a cost needs a money place', () async {
    final p1 = await buy([line('A', 1, 1000, general)], 10000);
    expect(
      () => shipping.saveCollection(
        CollectionDraft(
          collectedAt: DateTime(2026, 10, 20),
          transportZmw: 100,
          storageZmw: 0,
          purchaseIds: [p1],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('landed costs stream updates when a bill is added', () async {
    final p1 = await buy([line('A', 1, 1000, general)], 10000);
    final stream = shipping.watchLandedCosts();
    final emissions = <int>[];
    final sub = stream.listen((c) => emissions.add(c.values.single.totalZmw));
    await pumpEventQueue();
    await shipping.saveBill(
      ShippingBillDraft(
        agentId: agent,
        billedAt: DateTime(2026, 10, 10),
        paidZmw: 2500,
        moneyPlaceId: card,
        lines: [
          ShippingLineDraft(cargoTypeId: general, weightGrams: 100, amountUsd: 100, purchaseIds: [p1]),
        ],
      ),
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(emissions.first, 10000);
    expect(emissions.last, 12500);
  });
}

class ItemCostCheck {
  ItemCostCheck(this.cost);

  final ItemLandedCost cost;

  (int, int, int) get parts => (cost.purchaseZmw, cost.shippingZmw, cost.collectionZmw);
  int get unit => cost.unitZmw;
}
