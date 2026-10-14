import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/money_repository.dart';
import 'package:tradeflow/data/problems_repository.dart';
import 'package:tradeflow/data/purchase_repository.dart';
import 'package:tradeflow/data/report_repository.dart';
import 'package:tradeflow/data/sales_repository.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';
import 'package:tradeflow/data/shipping_repository.dart';
import 'package:tradeflow/data/stock_repository.dart';

void main() {
  late AppDatabase db;
  late ReportRepository reports;
  late PurchaseRepository purchases;
  late ShippingRepository shipping;
  late SalesRepository sales;
  late MoneyRepository money;
  late ProblemsRepository problems;
  late String card;
  late String mobile;
  late String general;
  late String taobao;
  late String whatsapp;
  late String transport;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final storeId = await SetupRepository(db).completeSetup(
      storeName: 'Test',
      places: const [
        OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 500000),
        OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 0),
      ],
      stock: const [OpeningStockEntry(productName: 'Old hats', qty: 2, unitCostZmw: 5000)],
    );
    final settings = SettingsRepository(db, storeId);
    purchases = PurchaseRepository(db, storeId);
    shipping = ShippingRepository(db, storeId);
    sales = SalesRepository(db, storeId);
    money = MoneyRepository(db, storeId);
    problems = ProblemsRepository(db, storeId);
    reports = ReportRepository(
      db,
      storeId,
      shipping: shipping,
      stock: StockRepository(db, storeId, shipping),
      money: money,
      sales: sales,
    );
    final places = await settings.watchMoneyPlaces().first;
    (card, mobile) = (places[0].id, places[1].id);
    general = (await settings.watchLookups(LookupKind.cargoType).first).first.id;
    taobao = (await settings.watchLookups(LookupKind.platform).first).first.id;
    whatsapp = (await settings.watchLookups(LookupKind.channel).first).first.id;
    transport = (await settings.watchLookups(LookupKind.expenseCategory).first).first.id;
  });

  tearDown(() => db.close());

  Future<String> buy(String product, int qty, int paid, DateTime at) => purchases.savePurchase(
    PurchaseDraft(
      platformId: taobao,
      orderedAt: at,
      items: [PurchaseItemDraft(productName: product, qty: qty, unitPriceCny: 1000, cargoTypeId: general)],
      paidZmw: paid,
      moneyPlaceId: card,
    ),
  );

  test('snapshot pulls the whole business together', () async {
    final now = DateTime(2026, 10, 20);
    final earbuds = await buy('Earbuds', 2, 30000, DateTime(2026, 10, 1));
    await shipping.saveCollection(
      CollectionDraft(
        collectedAt: DateTime(2026, 10, 3),
        transportZmw: 0,
        storageZmw: 0,
        purchaseIds: [earbuds],
      ),
    );
    await buy('Watch', 1, 40000, DateTime(2026, 9, 1)); // still in transit
    final lost = await buy('Lamp', 1, 20000, DateTime(2026, 10, 2));
    await problems.markLost(
      purchaseId: lost,
      compensationZmw: 5000,
      moneyPlaceId: card,
      at: DateTime(2026, 10, 15),
    );

    await sales.saveSale(
      SaleDraft(
        soldAt: DateTime(2026, 10, 10),
        kind: SaleKind.stock,
        customerName: 'Mwila',
        channelId: whatsapp,
        items: const [SaleItemDraft(productName: 'Earbuds', qty: 1, unitPriceZmw: 25000)],
        paymentZmw: 20000,
        paymentPlaceId: mobile,
      ),
    );
    await money.addExpense(
      ExpenseDraft(
        spentAt: DateTime(2026, 10, 11),
        categoryId: transport,
        amountZmw: 1000,
        moneyPlaceId: mobile,
      ),
    );
    await money.addTransfer(
      fromPlaceId: mobile,
      toPlaceId: card,
      amountZmw: 10000,
      feeZmw: 200,
      at: DateTime(2026, 10, 12),
    );

    final s = await reports.loadSnapshot(now: now);
    final r = s.report(DateTime(2026, 10), DateTime(2026, 11));

    expect(r.totals.revenueZmw, 25000);
    expect(r.totals.costZmw, 15000);
    expect(r.expensesByCategory, {transport: 1000});
    expect(r.otherCostsZmw, 200);
    expect(r.losses.single.amountZmw, 20000 - 5000);
    expect(r.netProfitZmw, 10000 - 1000 - 200 - 15000);
    expect(r.byPlatform[taobao]!.revenueZmw, 25000);
    expect(r.byChannel[whatsapp]!.profitZmw, 10000);

    expect(s.transitZmw, 40000);
    expect(s.transitPurchases, 1);
    expect(s.oldestTransit, DateTime(2026, 9, 1));
    expect(s.owedZmw, 5000);
    expect(s.stockValueZmw, 15000 + 10000);
    expect([for (final id in s.slowMovers) s.names[id]], ['Old hats']);
    expect(s.cnyRates.points.length, 3);
    expect(s.moneyNowZmw, 500000 - 90000 + 5000 + 20000 - 1000 - 200);
  });
}
