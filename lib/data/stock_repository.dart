import 'package:drift/drift.dart';

import '../core/streams.dart';
import '../domain/fifo.dart';
import 'database.dart';
import 'shipping_repository.dart';

/// Stock on hand and cost of every sale, from landed costs and FIFO.
class StockRepository {
  StockRepository(this.db, this.storeId, this.shipping);

  final AppDatabase db;
  final String storeId;
  final ShippingRepository shipping;

  Stream<StockLedger> watchLedger() => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.purchases,
          db.purchaseItems,
          db.shippingBills,
          db.shippingLines,
          db.shippingLinePurchases,
          db.collections,
          db.collectionPurchases,
          db.openingStockItems,
          db.sales,
          db.saleItems,
          db.adjustments,
        ]),
      )
      .map((_) => null)
      .startWith(null)
      .asyncMap((_) => computeLedger());

  Future<StockLedger> computeLedger() async {
    final landed = await shipping.computeLandedCosts();

    // When each purchase was collected (its stock's received date).
    final collected =
        await (db.select(db.collectionPurchases).join([
              innerJoin(db.collections, db.collections.id.equalsExp(db.collectionPurchases.collectionId)),
            ])..where(
              db.collectionPurchases.storeId.equals(storeId) & db.collectionPurchases.deletedAt.isNull(),
            ))
            .get();
    final collectedAt = <String, DateTime>{
      for (final r in collected)
        r.readTable(db.collectionPurchases).purchaseId: r.readTable(db.collections).collectedAt,
    };

    final items =
        await (db.select(db.purchaseItems).join([
              innerJoin(db.purchases, db.purchases.id.equalsExp(db.purchaseItems.purchaseId)),
            ])..where(
              db.purchaseItems.storeId.equals(storeId) &
                  db.purchaseItems.deletedAt.isNull() &
                  db.purchases.deletedAt.isNull() &
                  db.purchases.status.equalsValue(PurchaseStatus.collected),
            ))
            .get();
    final opening = await (db.select(
      db.openingStockItems,
    )..where((o) => o.storeId.equals(storeId) & o.deletedAt.isNull())).get();

    final batches = <StockBatch>[
      for (final o in opening)
        StockBatch(
          id: o.id,
          productId: o.productId,
          // Opening stock is older than anything bought through the app.
          receivedAt: DateTime(1970),
          qty: o.qty,
          totalCostZmw: o.qty * o.unitCostZmw,
        ),
      for (final r in items)
        () {
          final item = r.readTable(db.purchaseItems);
          final purchase = r.readTable(db.purchases);
          return StockBatch(
            id: item.id,
            productId: item.productId,
            receivedAt: collectedAt[purchase.id] ?? purchase.orderedAt,
            qty: item.qty,
            totalCostZmw: landed[item.id]?.totalZmw ?? 0,
            purchaseId: purchase.id,
          );
        }(),
    ];

    final saleRows =
        await (db.select(db.saleItems).join([innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId))])
              ..where(
                db.saleItems.storeId.equals(storeId) &
                    db.saleItems.deletedAt.isNull() &
                    db.sales.deletedAt.isNull() &
                    db.sales.status.equalsValue(SaleStatus.fulfilled),
              ))
            .get();
    final preOrderPurchases = <String, Set<String>>{};
    final linked = await (db.select(
      db.purchases,
    )..where((p) => p.storeId.equals(storeId) & p.deletedAt.isNull() & p.preOrderSaleId.isNotNull())).get();
    for (final p in linked) {
      preOrderPurchases.putIfAbsent(p.preOrderSaleId!, () => {}).add(p.id);
    }

    final demands = [
      for (final r in saleRows)
        () {
          final item = r.readTable(db.saleItems);
          final sale = r.readTable(db.sales);
          return StockDemand(
            id: item.id,
            productId: item.productId,
            at: sale.fulfilledAt ?? sale.soldAt,
            qty: item.qty,
            reservedPurchaseIds: preOrderPurchases[sale.id] ?? const {},
          );
        }(),
    ];
    final writeOffs =
        await (db.select(db.adjustments)..where(
              (a) =>
                  a.storeId.equals(storeId) &
                  a.deletedAt.isNull() &
                  a.kind.equalsValue(AdjustmentKind.writeOff),
            ))
            .get();
    // Written-off units leave stock like a sale; their cost is the loss.
    demands.addAll([
      for (final w in writeOffs)
        StockDemand(id: w.id, productId: w.productId!, at: w.occurredAt, qty: w.qty ?? 0),
    ]);
    return fifo(batches: batches, demands: demands);
  }
}
