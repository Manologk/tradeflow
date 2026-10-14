// Shop-safe data published from the admin app. Costs and suppliers never
// appear here.

enum Availability { inStock, fewLeft, preOrder, soldOut }

class ShopColor {
  const ShopColor({required this.name, required this.hex});

  final String name;

  /// e.g. "#292526".
  final String hex;
}

class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    this.description = '',
    required this.categoryId,
    this.seriesId,
    required this.priceZmw,
    this.compareAtZmw,
    this.photos = const [],
    this.sizes = const [],
    this.colors = const [],
    required this.availability,
    this.leadTimeWeeks,
  });

  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String? seriesId;

  /// Selling price in ngwee.
  final int priceZmw;

  /// Previous price, shown struck through when higher than [priceZmw].
  final int? compareAtZmw;
  final List<String> photos;
  final List<String> sizes;
  final List<ShopColor> colors;
  final Availability availability;

  /// For pre-orders: roughly how long until it arrives.
  final int? leadTimeWeeks;

  bool get canOrder => availability != Availability.soldOut;
  bool get isPreOrder => availability == Availability.preOrder;
  bool get isOnSale => compareAtZmw != null && compareAtZmw! > priceZmw;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || description.toLowerCase().contains(q);
  }
}

class ShopCategory {
  const ShopCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class ShopSeries {
  const ShopSeries({required this.id, required this.name, this.imageUrl});

  final String id;
  final String name;
  final String? imageUrl;
}

class DeliveryArea {
  const DeliveryArea({required this.id, required this.name, required this.feeZmw});

  final String id;
  final String name;
  final int feeZmw;
}

class ShopSettings {
  const ShopSettings({
    required this.name,
    required this.whatsappNumber,
    this.deliveryAreas = const [],
    this.depositPercent = 50,
    this.logoUrl,
  });

  final String name;

  /// International format, digits only, e.g. "260971234567".
  final String whatsappNumber;
  final List<DeliveryArea> deliveryAreas;

  /// Share of a pre-order's value paid up front.
  final int depositPercent;
  final String? logoUrl;
}

class Catalog {
  const Catalog({
    required this.settings,
    required this.categories,
    required this.series,
    required this.products,
  });

  final ShopSettings settings;
  final List<ShopCategory> categories;
  final List<ShopSeries> series;
  final List<ShopProduct> products;

  ShopProduct? product(String id) => products.where((p) => p.id == id).firstOrNull;
  ShopCategory? category(String? id) => categories.where((c) => c.id == id).firstOrNull;
  ShopSeries? seriesOf(String? id) => series.where((s) => s.id == id).firstOrNull;
}

/// One product (with chosen size/colour) in the cart.
class CartLine {
  const CartLine({required this.productId, this.size, this.color, required this.qty});

  final String productId;
  final String? size;
  final String? color;
  final int qty;

  /// Same product in a different size or colour is a separate line.
  String get key => '$productId|${size ?? ''}|${color ?? ''}';

  CartLine copyWith({int? qty}) =>
      CartLine(productId: productId, size: size, color: color, qty: qty ?? this.qty);

  Map<String, Object?> toJson() => {'p': productId, 's': size, 'c': color, 'q': qty};

  static CartLine fromJson(Map<String, Object?> json) => CartLine(
    productId: json['p']! as String,
    size: json['s'] as String?,
    color: json['c'] as String?,
    qty: json['q']! as int,
  );
}

enum OrderStatus { received, confirmed, ready, delivered, cancelled }

class Customer {
  const Customer({required this.name, required this.phone, this.areaId, this.notes = ''});

  final String name;
  final String phone;
  final String? areaId;
  final String notes;
}

/// A priced order line, frozen at the moment of ordering.
class OrderLine {
  const OrderLine({
    required this.productId,
    required this.name,
    this.size,
    this.color,
    required this.qty,
    required this.unitPriceZmw,
    required this.preOrder,
    this.leadTimeWeeks,
  });

  final String productId;
  final String name;
  final String? size;
  final String? color;
  final int qty;
  final int unitPriceZmw;
  final bool preOrder;
  final int? leadTimeWeeks;

  int get totalZmw => qty * unitPriceZmw;
}

class Order {
  const Order({
    required this.code,
    required this.createdAt,
    required this.customer,
    this.areaName,
    required this.lines,
    required this.itemsZmw,
    required this.deliveryZmw,
    required this.depositZmw,
    this.status = OrderStatus.received,
  });

  final String code;
  final DateTime createdAt;
  final Customer customer;
  final String? areaName;
  final List<OrderLine> lines;
  final int itemsZmw;
  final int deliveryZmw;

  /// Due up front for pre-order items.
  final int depositZmw;
  final OrderStatus status;

  int get totalZmw => itemsZmw + deliveryZmw;
  int get units => lines.fold(0, (sum, l) => sum + l.qty);
}
