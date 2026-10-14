import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/money_repository.dart';
import 'package:tradeflow/data/purchase_repository.dart';
import 'package:tradeflow/data/sales_repository.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';
import 'package:tradeflow/data/shipping_repository.dart';
import 'package:tradeflow/data/stock_repository.dart';

void main() {
  late AppDatabase db;
  late PurchaseRepository purchases;
  late ShippingRepository shipping;
  late SalesRepository sales;
  late StockRepository stock;
  late MoneyRepository money;
  late String card;
  late String mobile;
  late String general;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final storeId = await SetupRepository(db).completeSetup(
      storeName: 'Test',
      places: const [
        OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 100000),
        OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 0),
      ],
      stock: const [OpeningStockEntry(productName: 'Earbuds', qty: 1, unitCostZmw: 10000)],
    );
    final settings = SettingsRepository(db, storeId);
    purchases = PurchaseRepository(db, storeId);
    shipping = ShippingRepository(db, storeId);
    sales = SalesRepository(db, storeId);
    stock = StockRepository(db, storeId, shipping);
    money = MoneyRepository(db, storeId);
    final places = await settings.watchMoneyPlaces().first;
    card = places[0].id;
    mobile = places[1].id;
    general = (await settings.watchLookups(LookupKind.cargoType).first).first.id;
  });

  tearDown(() => db.close());

  Future<String> buyAndCollect(String product, int qty, int paidZmw, {String? preOrder, int day = 1}) async {
    final id = await purchases.savePurchase(
      PurchaseDraft(
        orderedAt: DateTime(2026, 10, day),
        items: [PurchaseItemDraft(productName: product, qty: qty, unitPriceCny: 1000, cargoTypeId: general)],
        paidZmw: paidZmw,
        moneyPlaceId: card,
        preOrderSaleId: preOrder,
      ),
    );
    await shipping.saveCollection(
      CollectionDraft(
        collectedAt: DateTime(2026, 10, day + 1),
        transportZmw: 0,
        storageZmw: 0,
        purchaseIds: [id],
      ),
    );
    return id;
  }

  Future<String> sell(String product, int qty, int price, {int paid = -1, String? customer, int day = 20}) =>
      sales.saveSale(
        SaleDraft(
          soldAt: DateTime(2026, 10, day),
          kind: SaleKind.stock,
          customerName: customer,
          items: [SaleItemDraft(productName: product, qty: qty, unitPriceZmw: price)],
          paymentZmw: paid < 0 ? qty * price : paid,
          paymentPlaceId: mobile,
        ),
      );

  test('stock sale is costed FIFO: opening stock first, then purchases', () async {
    await buyAndCollect('earbuds', 2, 30000); // K150 each
    final saleId = await sell('Earbuds', 2, 25000);

    final ledger = await stock.computeLedger();
    final detail = (await sales.watchSale(saleId).first)!;
    final cost = ledger.demandCosts[detail.items.single.item.id]!;
    expect(cost.costZmw, 10000 + 15000);
    expect(cost.isComplete, isTrue);
    expect(detail.summary.totalZmw, 50000);
    expect(detail.summary.owedZmw, 0);

    final productId = detail.items.single.product.id;
    expect(ledger.stockOf(productId).qty, 1);
    expect(ledger.stockOf(productId).valueZmw, 15000);
  });

  test('part payment leaves a debt that can be paid off oldest first', () async {
    await sell('Earbuds', 1, 20000, paid: 5000, customer: 'Mwila');
    await sell('Earbuds', 1, 10000, paid: 0, customer: ' mwila ', day: 21);

    var debts = await sales.watchDebts().first;
    expect(debts.single.customer.name, 'Mwila');
    expect(debts.single.owedZmw, 25000);
    expect(debts.single.sales.length, 2);

    await sales.payDebt(
      debt: debts.single,
      amountZmw: 20000,
      moneyPlaceId: mobile,
      paidAt: DateTime(2026, 10, 25),
    );
    debts = await sales.watchDebts().first;
    expect(debts.single.owedZmw, 5000);
    // Oldest sale cleared first.
    final all = await sales.loadSales();
    expect(all.map((s) => s.owedZmw), [5000, 0]);
  });

  test('owing money requires a customer', () {
    expect(() => sell('Earbuds', 1, 20000, paid: 0), throwsArgumentError);
  });

  test('payments land in the money place', () async {
    await sell('Earbuds', 1, 20000);
    final balances = await money.watchBalances().first;
    expect(balances.map((b) => b.balanceZmw), [100000, 20000]);
  });

  test('pre-order: deposit, linked purchase, costed when delivered', () async {
    final saleId = await sales.saveSale(
      SaleDraft(
        soldAt: DateTime(2026, 10, 1),
        kind: SaleKind.preOrder,
        customerName: 'Bwalya',
        items: const [SaleItemDraft(productName: 'Smart watch', qty: 1, unitPriceZmw: 65000)],
        paymentZmw: 20000,
        paymentPlaceId: mobile,
      ),
    );
    expect((await sales.pendingPreOrders()).single.sale.id, saleId);

    // Older general stock of the same product must not be used for it.
    await buyAndCollect('Smart watch', 1, 10000, day: 2);
    await buyAndCollect('Smart watch', 1, 40000, preOrder: saleId, day: 5);
    var ledger = await stock.computeLedger();
    var detail = (await sales.watchSale(saleId).first)!;
    expect(ledger.demandCosts[detail.items.single.item.id], isNull, reason: 'not delivered yet');
    expect(detail.linkedPurchases.length, 1);

    await sales.markFulfilled(saleId, DateTime(2026, 10, 12));
    ledger = await stock.computeLedger();
    detail = (await sales.watchSale(saleId).first)!;
    expect(ledger.demandCosts[detail.items.single.item.id]!.costZmw, 40000);
    expect(detail.summary.owedZmw, 45000);
    expect(await sales.pendingPreOrders(), isEmpty);
  });

  test('deleting a sale removes its payments and returns its stock', () async {
    final saleId = await sell('Earbuds', 1, 20000);
    await sales.deleteSale(saleId);
    expect(await sales.loadSales(), isEmpty);
    final balances = await money.watchBalances().first;
    expect(balances[1].balanceZmw, 0);
    final ledger = await stock.computeLedger();
    expect(ledger.stock.values.single.qty, 1);
  });

  test('editing a sale updates items without new payments', () async {
    final saleId = await sell('Earbuds', 1, 20000);
    final item = (await sales.watchSale(saleId).first)!.items.single.item;
    await sales.saveSale(
      SaleDraft(
        id: saleId,
        soldAt: DateTime(2026, 10, 20),
        kind: SaleKind.stock,
        items: [SaleItemDraft(id: item.id, productName: 'Earbuds', qty: 1, unitPriceZmw: 22000)],
        paymentZmw: 99999,
      ),
    );
    final detail = (await sales.watchSale(saleId).first)!;
    expect(detail.summary.totalZmw, 22000);
    expect(detail.payments.length, 1);
    expect(detail.summary.owedZmw, 2000);
  });

  test('split payment oldest first', () {
    expect(splitPaymentOldestFirst(100, [30, 50, 40]), [30, 50, 20]);
    expect(splitPaymentOldestFirst(200, [30, 50]), [30, 170]);
    expect(splitPaymentOldestFirst(10, [30, 50]), [10, 0]);
  });
}
