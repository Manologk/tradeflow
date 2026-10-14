import type { ShopData } from './data';
import type { Catalog, Order, OrderStatus } from './models';

/** Test catalog for automated tests and local previews. Never used live. */
export const testCatalog: Catalog = {
  settings: {
    name: 'Otaku Corner',
    whatsappNumber: '260971234567',
    depositPercent: 50,
    logoUrl: null,
    deliveryAreas: [
      { id: 'cbd', name: 'Lusaka CBD', feeZmw: 3000 },
      { id: 'pickup', name: 'Pick up', feeZmw: 0 },
    ],
  },
  categories: [
    { id: 'figures', name: 'Figures' },
    { id: 'clothing', name: 'Clothing' },
    { id: 'keychains', name: 'Keychains' },
  ],
  series: [
    { id: 'naruto', name: 'Naruto', imageUrl: null },
    { id: 'jjk', name: 'Jujutsu Kaisen', imageUrl: null },
  ],
  products: [
    {
      id: 'p1',
      name: 'Naruto Sage Mode Figure',
      description: 'PVC figure, 18cm, with stand.',
      categoryId: 'figures',
      seriesId: 'naruto',
      priceZmw: 45000,
      compareAtZmw: 52000,
      photos: [],
      sizes: [],
      colors: [],
      availability: 'inStock',
      leadTimeWeeks: null,
    },
    {
      id: 'p2',
      name: 'Gojo Hoodie',
      description: '',
      categoryId: 'clothing',
      seriesId: 'jjk',
      priceZmw: 38000,
      compareAtZmw: null,
      photos: [],
      sizes: ['M', 'L', 'XL'],
      colors: [
        { name: 'Black', hex: '#121111' },
        { name: 'Grey', hex: '#787676' },
      ],
      availability: 'preOrder',
      leadTimeWeeks: 3,
    },
    {
      id: 'p3',
      name: 'Itachi Keychain',
      description: '',
      categoryId: 'keychains',
      seriesId: 'naruto',
      priceZmw: 4000,
      compareAtZmw: null,
      photos: [],
      sizes: [],
      colors: [],
      availability: 'soldOut',
      leadTimeWeeks: null,
    },
  ],
};

/** In-memory shop over the test catalog; orders are kept until restart. */
export function fixtureShop(): ShopData {
  const orders: Order[] = [];
  return {
    loadCatalog: async () => testCatalog,
    submitOrder: async (order) => {
      orders.push(order);
    },
    orderStatuses: async (codes, phone) => {
      const result: Record<string, OrderStatus> = {};
      for (const o of orders) if (codes.includes(o.code) && o.customer.phone === phone) result[o.code] = 'confirmed';
      return result;
    },
  };
}
