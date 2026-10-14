import '../core/allocation.dart';

// Landed-cost rules from docs/PRODUCT_SPEC.md §4. Pure functions so they can
// be tested exhaustively; repositories feed them rows from the database.

/// §4.1 — Splits the ZMW actually charged for a purchase across its items by
/// their CNY value. Seller delivery and card fees ride along proportionally.
List<int> itemPurchaseCosts({required int paidZmw, required List<int> itemValuesCny}) =>
    allocate(paidZmw, itemValuesCny);

/// Kwacha per yuan actually achieved on a payment, or null if nothing in CNY.
double? effectiveRate({required int paidZmw, required int totalCny}) =>
    totalCny == 0 ? null : paidZmw / totalCny;
