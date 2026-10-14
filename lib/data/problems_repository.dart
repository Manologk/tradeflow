import 'package:drift/drift.dart';

import 'database.dart';

/// Why stock was written off.
enum WriteOffReason { damaged, personalUse, gift, other }

const writeOffReasonLabels = {
  WriteOffReason.damaged: 'Damaged or faulty',
  WriteOffReason.personalUse: 'Kept for myself',
  WriteOffReason.gift: 'Given away',
  WriteOffReason.other: 'Other',
};

/// Refunds, lost parcels, write-offs and customer returns (spec §2 #12).
///
/// All of them are Adjustment rows, so they sync like everything else and
/// can be undone by soft-deleting them.
class ProblemsRepository {
  ProblemsRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  Stream<List<Adjustment>> watchPurchaseAdjustments(String purchaseId) =>
      (db.select(db.adjustments)
            ..where((a) => a.purchaseId.equals(purchaseId) & a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm(expression: a.occurredAt)]))
          .watch();

  Stream<List<Adjustment>> watchSaleAdjustments(String saleId) =>
      (db.select(db.adjustments)
            ..where((a) => a.saleId.equals(saleId) & a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm(expression: a.occurredAt)]))
          .watch();

  Stream<List<Adjustment>> watchWriteOffs(String productId) =>
      (db.select(db.adjustments)
            ..where(
              (a) =>
                  a.productId.equals(productId) &
                  a.kind.equalsValue(AdjustmentKind.writeOff) &
                  a.deletedAt.isNull(),
            )
            ..orderBy([(a) => OrderingTerm.desc(a.occurredAt)]))
          .watch();

  // Purchases -------------------------------------------------------------

  /// Money back from the seller. A whole-order refund means nothing arrives:
  /// the purchase leaves stock and what wasn't returned is a currency loss.
  /// A partial refund just lowers what the items cost.
  Future<void> refundPurchase({
    required String purchaseId,
    required bool wholeOrder,
    required int amountZmw,
    required String moneyPlaceId,
    required DateTime at,
  }) {
    if (amountZmw < 0) throw ArgumentError('Refund cannot be negative');
    return db.transaction(() async {
      await db
          .into(db.adjustments)
          .insert(
            AdjustmentsCompanion.insert(
              storeId: storeId,
              kind: AdjustmentKind.refund,
              occurredAt: at,
              reason: Value(wholeOrder ? 'whole' : 'partial'),
              purchaseId: Value(purchaseId),
              amountZmw: Value(amountZmw),
              moneyPlaceId: Value(moneyPlaceId),
            ),
          );
      if (wholeOrder) await _setPurchaseStatus(purchaseId, PurchaseStatus.refunded);
    });
  }

  /// A parcel that never arrived. Its cost so far becomes a loss, less any
  /// compensation from the agent.
  Future<void> markLost({
    required String purchaseId,
    int compensationZmw = 0,
    String? moneyPlaceId,
    required DateTime at,
  }) {
    if (compensationZmw > 0 && moneyPlaceId == null) {
      throw ArgumentError('Say where the compensation was received');
    }
    return db.transaction(() async {
      await db
          .into(db.adjustments)
          .insert(
            AdjustmentsCompanion.insert(
              storeId: storeId,
              kind: AdjustmentKind.lostParcel,
              occurredAt: at,
              purchaseId: Value(purchaseId),
            ),
          );
      if (compensationZmw > 0) {
        await db
            .into(db.adjustments)
            .insert(
              AdjustmentsCompanion.insert(
                storeId: storeId,
                kind: AdjustmentKind.compensation,
                occurredAt: at,
                purchaseId: Value(purchaseId),
                amountZmw: Value(compensationZmw),
                moneyPlaceId: Value(moneyPlaceId),
              ),
            );
      }
      await _setPurchaseStatus(purchaseId, PurchaseStatus.lost);
    });
  }

  /// Undoes a refund or lost record on a purchase.
  Future<void> undoPurchaseProblems(String purchaseId) => db.transaction(() async {
    final now = DateTime.now();
    await (db.update(db.adjustments)..where(
          (a) =>
              a.purchaseId.equals(purchaseId) &
              a.kind.isInValues(const [
                AdjustmentKind.refund,
                AdjustmentKind.lostParcel,
                AdjustmentKind.compensation,
              ]),
        ))
        .write(AdjustmentsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    final purchase = await (db.select(db.purchases)..where((p) => p.id.equals(purchaseId))).getSingle();
    if (purchase.status == PurchaseStatus.refunded || purchase.status == PurchaseStatus.lost) {
      await _setPurchaseStatus(purchaseId, await _statusFromHistory(purchaseId));
    }
  });

  Future<PurchaseStatus> _statusFromHistory(String purchaseId) async {
    final collected =
        await (db.select(db.collectionPurchases)
              ..where((c) => c.purchaseId.equals(purchaseId) & c.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (collected != null) return PurchaseStatus.collected;
    final billed =
        await (db.select(db.shippingLinePurchases)
              ..where((l) => l.purchaseId.equals(purchaseId) & l.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (billed != null) return PurchaseStatus.inTransit;
    final tracked =
        await (db.select(db.trackingNumbers)
              ..where((t) => t.purchaseId.equals(purchaseId) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return tracked != null ? PurchaseStatus.shipped : PurchaseStatus.ordered;
  }

  Future<void> _setPurchaseStatus(String id, PurchaseStatus status) =>
      (db.update(db.purchases)..where((p) => p.id.equals(id))).write(
        PurchasesCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
      );

  // Stock -----------------------------------------------------------------

  /// Takes units out of stock without a sale. Their FIFO cost is a loss.
  Future<void> writeOff({
    required String productId,
    required int qty,
    required WriteOffReason reason,
    required DateTime at,
    String? saleId,
    String? note,
  }) async {
    if (qty <= 0) throw ArgumentError('Quantity must be at least 1');
    await db
        .into(db.adjustments)
        .insert(
          AdjustmentsCompanion.insert(
            storeId: storeId,
            kind: AdjustmentKind.writeOff,
            occurredAt: at,
            reason: Value(reason.name),
            productId: Value(productId),
            saleId: Value(saleId),
            qty: Value(qty),
            note: Value(note),
          ),
        );
  }

  Future<void> deleteAdjustment(String id) => (db.update(db.adjustments)..where((a) => a.id.equals(id)))
      .write(AdjustmentsCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())));

  // Sales -----------------------------------------------------------------

  /// The customer brought the whole sale back. Their money is refunded and
  /// the goods go back into stock, or are written off if they can't be sold.
  Future<void> returnSale({
    required String saleId,
    required int refundZmw,
    String? moneyPlaceId,
    required bool restock,
    required DateTime at,
  }) {
    if (refundZmw > 0 && moneyPlaceId == null) throw ArgumentError('Say where the refund was paid from');
    return db.transaction(() async {
      if (refundZmw > 0) {
        await db
            .into(db.adjustments)
            .insert(
              AdjustmentsCompanion.insert(
                storeId: storeId,
                kind: AdjustmentKind.saleReturn,
                occurredAt: at,
                saleId: Value(saleId),
                amountZmw: Value(refundZmw),
                moneyPlaceId: Value(moneyPlaceId),
              ),
            );
      }
      if (!restock) {
        final items = await (db.select(
          db.saleItems,
        )..where((i) => i.saleId.equals(saleId) & i.deletedAt.isNull())).get();
        for (final item in items) {
          await writeOff(
            productId: item.productId,
            qty: item.qty,
            reason: WriteOffReason.damaged,
            at: at,
            saleId: saleId,
            note: 'Returned by customer',
          );
        }
      }
      await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(status: const Value(SaleStatus.returned), updatedAt: Value(DateTime.now())),
      );
    });
  }

  Future<void> undoReturn(String saleId) => db.transaction(() async {
    final now = DateTime.now();
    await (db.update(db.adjustments)..where(
          (a) =>
              a.saleId.equals(saleId) &
              a.kind.isInValues(const [AdjustmentKind.saleReturn, AdjustmentKind.writeOff]),
        ))
        .write(AdjustmentsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId))).getSingle();
    await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
      SalesCompanion(
        status: Value(sale.fulfilledAt == null ? SaleStatus.pending : SaleStatus.fulfilled),
        updatedAt: Value(now),
      ),
    );
  });
}
