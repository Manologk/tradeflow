import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/money_repository.dart';
import 'package:tradeflow/data/purchase_repository.dart';
import 'package:tradeflow/data/sales_repository.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';
import 'package:tradeflow/data/shipping_repository.dart';

void main() {
  late AppDatabase db;
  late MoneyRepository money;
  late SettingsRepository settings;
  late String card;
  late String mobile;
  late String cash;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final storeId = await SetupRepository(db).completeSetup(
      storeName: 'Test',
      places: const [
        OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 100000),
        OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 20000),
        OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 5000),
      ],
    );
    settings = SettingsRepository(db, storeId);
    money = MoneyRepository(db, storeId);
    final places = await settings.watchMoneyPlaces().first;
    (card, mobile, cash) = (places[0].id, places[1].id, places[2].id);
  });

  tearDown(() => db.close());

  Future<List<int>> balances() async => [for (final b in await money.watchBalances().first) b.balanceZmw];

  test('every kind of movement is listed and balances add up', () async {
    final storeId = settings.storeId;
    final general = (await settings.watchLookups(LookupKind.cargoType).first).first.id;
    final agent = await settings.saveAgent(name: 'Speedy', usdPerKgByCargoType: {});
    final purchaseId = await PurchaseRepository(db, storeId).savePurchase(
      PurchaseDraft(
        orderedAt: DateTime(2026, 10, 1),
        items: [PurchaseItemDraft(productName: 'Earbuds', qty: 1, unitPriceCny: 1000, cargoTypeId: general)],
        paidZmw: 30000,
        moneyPlaceId: card,
      ),
    );
    final shipping = ShippingRepository(db, storeId);
    await shipping.saveBill(
      ShippingBillDraft(
        agentId: agent,
        billedAt: DateTime(2026, 10, 5),
        paidZmw: 10000,
        moneyPlaceId: card,
        lines: [
          ShippingLineDraft(
            cargoTypeId: general,
            weightGrams: 500,
            amountUsd: 500,
            purchaseIds: [purchaseId],
          ),
        ],
      ),
    );
    await shipping.saveCollection(
      CollectionDraft(
        collectedAt: DateTime(2026, 10, 9),
        transportZmw: 1000,
        storageZmw: 500,
        moneyPlaceId: cash,
        purchaseIds: [purchaseId],
      ),
    );
    await SalesRepository(db, storeId).saveSale(
      SaleDraft(
        soldAt: DateTime(2026, 10, 10),
        kind: SaleKind.stock,
        items: const [SaleItemDraft(productName: 'Earbuds', qty: 1, unitPriceZmw: 60000)],
        paymentZmw: 60000,
        paymentPlaceId: mobile,
      ),
    );
    final transport = (await settings.watchLookups(LookupKind.expenseCategory).first).first.id;
    await money.addExpense(
      ExpenseDraft(
        spentAt: DateTime(2026, 10, 11),
        categoryId: transport,
        amountZmw: 2000,
        moneyPlaceId: cash,
      ),
    );
    await money.addTransfer(
      fromPlaceId: mobile,
      toPlaceId: card,
      amountZmw: 50000,
      feeZmw: 750,
      at: DateTime(2026, 10, 12),
    );

    expect(await balances(), [
      100000 - 30000 - 10000 + 50000,
      20000 + 60000 - 50000 - 750,
      5000 - 1500 - 2000,
    ]);
    final movements = await money.watchMovements().first;
    expect(movements.map((m) => m.kind), [
      MovementKind.transferIn,
      MovementKind.transferOut,
      MovementKind.expense,
      MovementKind.salePayment,
      MovementKind.pickup,
      MovementKind.shipping,
      MovementKind.purchase,
    ]);
    expect(movements.first.label, 'Mobile Money');
    expect(movements[1].detail, '750');
    expect(movements.last.label, 'Earbuds');
  });

  test('balance check records the gap as an adjustment', () async {
    await money.recordBalanceCheck({card: 100000, mobile: 15000, cash: 5000}, at: DateTime(2026, 10, 20));
    expect(await balances(), [100000, 15000, 5000]);
    final gaps = (await money.watchMovements().first)
        .where((m) => m.kind == MovementKind.adjustment)
        .toList();
    expect(gaps.single.amountZmw, -5000);
    expect(gaps.single.label, 'unrecorded');

    await money.labelGap(gaps.single.id, BalanceGapLabel.personal);
    expect((await money.watchMovements().first).single.label, 'personal');
    expect(await money.watchLastBalanceCheck().first, DateTime(2026, 10, 20));

    // A second check compares against the corrected balance.
    await money.recordBalanceCheck({mobile: 15000});
    expect((await money.watchMovements().first).length, 1);
  });

  test('deleting an expense or transfer restores balances', () async {
    final category = (await settings.watchLookups(LookupKind.expenseCategory).first).first.id;
    final expense = await money.addExpense(
      ExpenseDraft(spentAt: DateTime(2026, 10, 1), categoryId: category, amountZmw: 1000, moneyPlaceId: cash),
    );
    final transfer = await money.addTransfer(
      fromPlaceId: cash,
      toPlaceId: card,
      amountZmw: 1000,
      at: DateTime(2026),
    );
    await money.deleteExpense(expense);
    await money.deleteTransfer(transfer);
    expect(await balances(), [100000, 20000, 5000]);
  });

  test('transfers need two places and a positive amount', () {
    expect(
      () => money.addTransfer(fromPlaceId: cash, toPlaceId: cash, amountZmw: 1, at: DateTime(2026)),
      throwsArgumentError,
    );
    expect(
      () => money.addTransfer(fromPlaceId: cash, toPlaceId: card, amountZmw: 0, at: DateTime(2026)),
      throwsArgumentError,
    );
  });

  test('delivery category is found by name', () async {
    final id = await money.deliveryCategoryId();
    final categories = await settings.watchLookups(LookupKind.expenseCategory).first;
    expect(categories.firstWhere((c) => c.id == id).name, 'Delivery');
  });
}
