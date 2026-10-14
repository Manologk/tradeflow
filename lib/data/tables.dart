import 'package:drift/drift.dart';

import '../core/ids.dart';

// Money columns hold integer minor units: *Zmw = ngwee, *Cny = fen,
// *Usd = cents. Weights are grams.

enum LookupKind { platform, cargoType, channel, expenseCategory }

enum MoneyPlaceKind { card, mobileMoney, cash, other }

enum PurchaseStatus { ordered, shipped, atAgent, inTransit, collected, refunded, lost }

enum SaleKind { stock, preOrder }

enum SaleStatus { pending, fulfilled, returned }

enum AdjustmentKind { writeOff, lostParcel, saleReturn, refund, compensation, currencyLoss }

enum BalanceGapLabel { unrecorded, personal, forgotExpense }

/// Columns every synced record carries, so the local-only MVP can later sync
/// to the cloud and support several stores and users without a rewrite.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get storeId => text().references(Stores, #id)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get createdBy => text().withDefault(const Constant('owner'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Stores extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text()();
  TextColumn get baseCurrency => text().withDefault(const Constant('ZMW'))();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Short editable lists: platforms, cargo types, sales channels and expense
/// categories.
class Lookups extends Table with SyncColumns {
  TextColumn get kind => textEnum<LookupKind>()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class MoneyPlaces extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<MoneyPlaceKind>()();
  IntColumn get openingBalanceZmw => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Agents extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get contact => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Default shipping rate an agent charges per kg for a cargo type.
class AgentRates extends Table with SyncColumns {
  TextColumn get agentId => text().references(Agents, #id)();
  TextColumn get cargoTypeId => text().references(Lookups, #id)();
  IntColumn get usdPerKg => integer()();
}

class Products extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Variants extends Table with SyncColumns {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get label => text()();
}

class Purchases extends Table with SyncColumns {
  TextColumn get platformId => text().nullable().references(Lookups, #id)();
  TextColumn get sellerName => text().nullable()();
  TextColumn get orderRef => text().nullable()();
  DateTimeColumn get orderedAt => dateTime()();
  IntColumn get totalCny => integer()();
  IntColumn get paidZmw => integer()();
  TextColumn get moneyPlaceId => text().references(MoneyPlaces, #id)();
  TextColumn get status => textEnum<PurchaseStatus>()();
  TextColumn get preOrderSaleId => text().nullable().references(Sales, #id)();
  TextColumn get notes => text().nullable()();
}

class PurchaseItems extends Table with SyncColumns {
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get variantId => text().nullable().references(Variants, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPriceCny => integer()();
  TextColumn get cargoTypeId => text().references(Lookups, #id)();
}

class TrackingNumbers extends Table with SyncColumns {
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get number => text()();
}

class ShippingBills extends Table with SyncColumns {
  TextColumn get agentId => text().references(Agents, #id)();
  DateTimeColumn get billedAt => dateTime()();
  IntColumn get totalUsd => integer()();
  IntColumn get paidZmw => integer()();
  TextColumn get moneyPlaceId => text().references(MoneyPlaces, #id)();
}

class ShippingLines extends Table with SyncColumns {
  TextColumn get billId => text().references(ShippingBills, #id)();
  TextColumn get cargoTypeId => text().references(Lookups, #id)();
  IntColumn get weightGrams => integer()();
  IntColumn get amountUsd => integer()();
}

/// A shipping line covers one purchase (one-by-one bill) or several
/// (consolidated bill).
class ShippingLinePurchases extends Table with SyncColumns {
  TextColumn get lineId => text().references(ShippingLines, #id)();
  TextColumn get purchaseId => text().references(Purchases, #id)();
}

class Collections extends Table with SyncColumns {
  DateTimeColumn get collectedAt => dateTime()();
  IntColumn get transportZmw => integer().withDefault(const Constant(0))();
  IntColumn get storageZmw => integer().withDefault(const Constant(0))();
  TextColumn get moneyPlaceId => text().nullable().references(MoneyPlaces, #id)();
}

class CollectionPurchases extends Table with SyncColumns {
  TextColumn get collectionId => text().references(Collections, #id)();
  TextColumn get purchaseId => text().references(Purchases, #id)();
}

class Customers extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
}

class Sales extends Table with SyncColumns {
  DateTimeColumn get soldAt => dateTime()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get channelId => text().nullable().references(Lookups, #id)();
  TextColumn get kind => textEnum<SaleKind>()();
  TextColumn get status => textEnum<SaleStatus>()();
  DateTimeColumn get fulfilledAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
}

class SaleItems extends Table with SyncColumns {
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get variantId => text().nullable().references(Variants, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPriceZmw => integer()();
}

class Payments extends Table with SyncColumns {
  TextColumn get saleId => text().references(Sales, #id)();
  DateTimeColumn get paidAt => dateTime()();
  IntColumn get amountZmw => integer()();
  TextColumn get moneyPlaceId => text().references(MoneyPlaces, #id)();
}

class Expenses extends Table with SyncColumns {
  DateTimeColumn get spentAt => dateTime()();
  TextColumn get categoryId => text().references(Lookups, #id)();
  IntColumn get amountZmw => integer()();
  TextColumn get moneyPlaceId => text().references(MoneyPlaces, #id)();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  TextColumn get note => text().nullable()();
}

/// Refunds, lost parcels, write-offs, returns, compensation, currency loss.
class Adjustments extends Table with SyncColumns {
  TextColumn get kind => textEnum<AdjustmentKind>()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get reason => text().nullable()();
  TextColumn get purchaseId => text().nullable().references(Purchases, #id)();
  TextColumn get purchaseItemId => text().nullable().references(PurchaseItems, #id)();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  TextColumn get productId => text().nullable().references(Products, #id)();
  TextColumn get variantId => text().nullable().references(Variants, #id)();
  IntColumn get qty => integer().nullable()();
  IntColumn get amountZmw => integer().withDefault(const Constant(0))();
  TextColumn get moneyPlaceId => text().nullable().references(MoneyPlaces, #id)();
  TextColumn get note => text().nullable()();
}

class Transfers extends Table with SyncColumns {
  @ReferenceName('outgoingTransfers')
  TextColumn get fromPlaceId => text().references(MoneyPlaces, #id)();
  @ReferenceName('incomingTransfers')
  TextColumn get toPlaceId => text().references(MoneyPlaces, #id)();
  DateTimeColumn get transferredAt => dateTime()();
  IntColumn get amountZmw => integer()();
  IntColumn get feeZmw => integer().withDefault(const Constant(0))();
}

class BalanceChecks extends Table with SyncColumns {
  DateTimeColumn get checkedAt => dateTime()();
  TextColumn get moneyPlaceId => text().references(MoneyPlaces, #id)();
  IntColumn get actualZmw => integer()();
  IntColumn get expectedZmw => integer()();
  TextColumn get gapLabel => textEnum<BalanceGapLabel>().withDefault(const Constant('unrecorded'))();
}

/// Stock already held when the store was set up.
class OpeningStockItems extends Table with SyncColumns {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get variantId => text().nullable().references(Variants, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitCostZmw => integer()();
}
