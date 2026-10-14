import 'package:tradeflow_shop/domain/models.dart';

/// Test catalog. Not used by the app itself.
const testSettings = ShopSettings(
  name: 'Otaku Corner',
  whatsappNumber: '260971234567',
  depositPercent: 50,
  deliveryAreas: [
    DeliveryArea(id: 'cbd', name: 'Lusaka CBD', feeZmw: 3000),
    DeliveryArea(id: 'pickup', name: 'Pick up', feeZmw: 0),
  ],
);

const testCatalog = Catalog(
  settings: testSettings,
  categories: [
    ShopCategory(id: 'figures', name: 'Figures'),
    ShopCategory(id: 'clothing', name: 'Clothing'),
    ShopCategory(id: 'keychains', name: 'Keychains'),
  ],
  series: [
    ShopSeries(id: 'naruto', name: 'Naruto'),
    ShopSeries(id: 'jjk', name: 'Jujutsu Kaisen'),
  ],
  products: [
    ShopProduct(
      id: 'p1',
      name: 'Naruto Sage Mode Figure',
      description: 'PVC figure, 18cm, with stand.',
      categoryId: 'figures',
      seriesId: 'naruto',
      priceZmw: 45000,
      compareAtZmw: 52000,
      availability: Availability.inStock,
    ),
    ShopProduct(
      id: 'p2',
      name: 'Gojo Hoodie',
      categoryId: 'clothing',
      seriesId: 'jjk',
      priceZmw: 38000,
      sizes: ['M', 'L', 'XL'],
      colors: [
        ShopColor(name: 'Black', hex: '#121111'),
        ShopColor(name: 'Grey', hex: '#787676'),
      ],
      availability: Availability.preOrder,
      leadTimeWeeks: 3,
    ),
    ShopProduct(
      id: 'p3',
      name: 'Itachi Keychain',
      categoryId: 'keychains',
      seriesId: 'naruto',
      priceZmw: 4000,
      availability: Availability.soldOut,
    ),
  ],
);
