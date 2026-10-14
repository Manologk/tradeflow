import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/money_repository.dart';
import 'package:tradeflow/data/problems_repository.dart';
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
  late ProblemsRepository problems;
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
    );
    final settings = SettingsRepository(db, storeId);
    purchases = PurchaseRepository(db, storeId);
    shipping = ShippingRepository(db, storeId);
    sales = SalesRepository(db, storeId);
    stock = StockRepository(db, storeId, shipping);
    money = MoneyRepository(db, storeId);
    problems = ProblemsRepository(db, storeId);
    final places = await settings.watchMoneyPlaces().first;
    (card, mobile) = (places[0].id, places[1].id);
    general = (await settings.watchLookups(LookupKind.cargoType).first).first.id;
  });

  tearDown(() => db.close());

  Future<String> buy(int qty, int paid, {bool collect = false}) async {
    final id = await purchases.savePurchase(
      PurchaseDraft(
        orderedAt: DateTime(2026, 10, 1),
        items: [
          PurchaseItemDraft(productName: 'Earbuds', qty: qty, unitPriceCny: 1000, cargoTypeId: general),
        ],
        paidZmw: paid,
        moneyPlaceId: card,
      ),
    );
    if (collect) {
      await shipping.saveCollection(
        CollectionDraft(
          collectedAt: DateTime(2026, 10, 2),
          transportZmw: 0,
          storageZmw: 0,
          purchaseIds: [id],
        ),
      );
    }
    return id;
  }

  Future<PurchaseStatus> statusOf(String id) async =>
      (await purchases.watchPurchase(id).first)!.purchase.status;
  Future<List<int>> balances() async => [for (final b in await money.watchBalances().first) b.balanceZmw];
  Future<String> productId() async => (await db.select(db.products).getSingle()).id;

  test('whole-order refund: money back, out of the pipeline, undoable', () async {
    final id = await buy(2, 40000);
    await problems.refundPurchase(
      purchaseId: id,
      wholeOrder: true,
      amountZmw: 38000,
      moneyPlaceId: card,
      at: DateTime(2026, 10, 3),
    );
    expect(await statusOf(id), PurchaseStatus.refunded);
    expect(await balances(), [100000 - 40000 + 38000, 0]);
    final products = await purchases.watchProducts().first;
    expect(products.single.unitsOnTheWay, 0);
    final movements = await money.watchMovements().first;
    expect(movements.first.kind, MovementKind.refund);
    expect(movements.first.label, id);

    await problems.undoPurchaseProblems(id);
    expect(await statusOf(id), PurchaseStatus.ordered);
    expect(await balances(), [60000, 0]);
  });

  test('partial refund lowers the landed cost', () async {
    final id = await buy(2, 40000, collect: true);
    await problems.refundPurchase(
      purchaseId: id,
      wholeOrder: false,
      amountZmw: 10000,
      moneyPlaceId: card,
      at: DateTime(2026, 10, 3),
    );
    expect(await statusOf(id), PurchaseStatus.collected);
    final ledger = await stock.computeLedger();
    expect(ledger.stockOf(await productId()).valueZmw, 30000);
  });

  test('lost parcel with compensation', () async {
    final id = await buy(1, 20000);
    expect(
      () => problems.markLost(purchaseId: id, compensationZmw: 500, at: DateTime(2026)),
      throwsArgumentError,
    );
    await problems.markLost(
      purchaseId: id,
      compensationZmw: 5000,
      moneyPlaceId: mobile,
      at: DateTime(2026, 10, 9),
    );
    expect(await statusOf(id), PurchaseStatus.lost);
    expect(await balances(), [80000, 5000]);
    final adjustments = await problems.watchPurchaseAdjustments(id).first;
    expect(adjustments.map((a) => a.kind), [AdjustmentKind.lostParcel, AdjustmentKind.compensation]);
  });

  test('undo restores the status the purchase had reached', () async {
    final id = await buy(1, 20000, collect: true);
    await problems.refundPurchase(
      purchaseId: id,
      wholeOrder: true,
      amountZmw: 0,
      moneyPlaceId: card,
      at: DateTime(2026),
    );
    await problems.undoPurchaseProblems(id);
    expect(await statusOf(id), PurchaseStatus.collected);
  });

  test('write-off removes stock at FIFO cost', () async {
    await buy(3, 30000, collect: true);
    final product = await productId();
    await problems.writeOff(
      productId: product,
      qty: 1,
      reason: WriteOffReason.gift,
      at: DateTime(2026, 10, 5),
    );
    final ledger = await stock.computeLedger();
    expect(ledger.stockOf(product).qty, 2);
    final writeOff = (await problems.watchWriteOffs(product).first).single;
    expect(writeOff.reason, 'gift');
    expect(ledger.demandCosts[writeOff.id]!.costZmw, 10000);

    await problems.deleteAdjustment(writeOff.id);
    expect((await stock.computeLedger()).stockOf(product).qty, 3);
  });

  test('customer return: refund, restock or write off, undo', () async {
    await buy(2, 20000, collect: true);
    final saleId = await sales.saveSale(
      SaleDraft(
        soldAt: DateTime(2026, 10, 10),
        kind: SaleKind.stock,
        customerName: 'Mwila',
        items: const [SaleItemDraft(productName: 'Earbuds', qty: 1, unitPriceZmw: 25000)],
        paymentZmw: 15000,
        paymentPlaceId: mobile,
      ),
    );
    final product = await productId();
    expect((await stock.computeLedger()).stockOf(product).qty, 1);
    expect((await sales.watchDebts().first).single.owedZmw, 10000);

    await problems.returnSale(
      saleId: saleId,
      refundZmw: 15000,
      moneyPlaceId: mobile,
      restock: true,
      at: DateTime(2026, 10, 12),
    );
    expect((await stock.computeLedger()).stockOf(product).qty, 2, reason: 'back in stock');
    expect(await sales.watchDebts().first, isEmpty, reason: 'nothing owed on a returned sale');
    expect(await balances(), [80000, 0]);

    await problems.undoReturn(saleId);
    expect((await sales.watchSale(saleId).first)!.sale.status, SaleStatus.fulfilled);
    expect(await balances(), [80000, 15000]);

    await problems.returnSale(saleId: saleId, refundZmw: 0, restock: false, at: DateTime(2026, 10, 12));
    final ledger = await stock.computeLedger();
    expect(ledger.stockOf(product).qty, 1, reason: 'broken unit written off');
    expect((await problems.watchWriteOffs(product).first).single.note, 'Returned by customer');
  });
}
