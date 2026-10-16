import { AdminError, orderOwed, orderPaid, orderTotal, stockTotal, type AdminApi, type AdminOrder, type AdminProduct } from './admin/types';
import { newOrderCode } from './checkout';
import type { ShopData } from './data';
import type { Catalog, OrderStatus } from './models';

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
      soldOutSizes: [],
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
      soldOutSizes: [],
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
      soldOutSizes: [],
      colors: [],
      availability: 'soldOut',
      leadTimeWeeks: null,
    },
    {
      id: 'p4',
      name: 'Zenitsu Jersey',
      description: 'Jersey-style tee.',
      categoryId: 'clothing',
      seriesId: null,
      priceZmw: 25000,
      compareAtZmw: null,
      photos: [],
      sizes: ['S', 'M', 'L'],
      soldOutSizes: ['S'],
      colors: [],
      availability: 'inStock',
      leadTimeWeeks: null,
    },
  ],
};

// One in-memory store shared by the test shop and the test dashboard, so a
// website order shows up in the admin and stock changes show on the site.
// Mirrors the database rules in supabase/migrations (stock taken on confirm,
// put back on cancel, sold-out sizes, availability from stock).

interface FixtureState {
  products: AdminProduct[];
  orders: AdminOrder[];
  nextPaymentId: number;
}

let state: FixtureState | null = null;

function fixtureState(): FixtureState {
  if (state) return state;
  const fresh: FixtureState = {
    products: testCatalog.products.map((p, i) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      categoryId: p.categoryId,
      seriesId: p.seriesId,
      priceZmw: p.priceZmw,
      compareAtZmw: p.compareAtZmw,
      photos: [...p.photos],
      sizes: [...p.sizes],
      colors: [...p.colors],
      availability: p.availability,
      leadTimeWeeks: p.leadTimeWeeks,
      published: true,
      trackStock: p.id === 'p4',
      stock: (p.id === 'p4' ? { S: 0, M: 2, L: 5 } : {}) as Record<string, number>,
      sortOrder: i,
    })),
    orders: [],
    nextPaymentId: 1,
  };
  state = fresh;
  return fresh;
}

/** Resets the shared test store (between automated tests). */
export function resetFixtures() {
  state = null;
}

function soldOutSizes(p: AdminProduct): string[] {
  if (!p.trackStock || p.availability === 'preOrder') return [];
  return p.sizes.filter((s) => (p.stock[s] ?? 0) === 0);
}

function refresh(p: AdminProduct) {
  if (!p.trackStock || p.availability === 'preOrder') return;
  const total = stockTotal(p);
  p.availability = total === 0 ? 'soldOut' : total <= 2 ? 'fewLeft' : 'inStock';
}

function moveStock(p: AdminProduct, size: string, delta: number) {
  const have = p.stock[size] ?? 0;
  if (have + delta < 0) throw new AdminError(`Not enough stock: ${p.name} ${size} has ${have} left`);
  p.stock[size] = have + delta;
  refresh(p);
}

function orderStock(o: AdminOrder, sign: 1 | -1) {
  const s = fixtureState();
  for (const it of o.items) {
    const p = s.products.find((x) => x.id === it.productId);
    if (p?.trackStock && !it.preOrder) moveStock(p, it.size ?? '', sign * it.qty);
  }
}

const takesStock = (status: OrderStatus) => status === 'confirmed' || status === 'ready' || status === 'delivered';
const stockTaken = new WeakSet<AdminOrder>();

function setStatus(o: AdminOrder, status: OrderStatus) {
  if (takesStock(status) && !stockTaken.has(o)) {
    orderStock(o, -1);
    stockTaken.add(o);
  } else if (!takesStock(status) && stockTaken.has(o)) {
    orderStock(o, 1);
    stockTaken.delete(o);
  }
  o.status = status;
}

/** In-memory shop over the test catalog; orders are kept until restart. */
export function fixtureShop(): ShopData {
  return {
    loadCatalog: async () => ({
      ...testCatalog,
      products: fixtureState()
        .products.filter((p) => p.published)
        .map((p) => ({
          id: p.id,
          name: p.name,
          description: p.description,
          categoryId: p.categoryId,
          seriesId: p.seriesId,
          priceZmw: p.priceZmw,
          compareAtZmw: p.compareAtZmw,
          photos: p.photos,
          sizes: p.sizes,
          soldOutSizes: soldOutSizes(p),
          colors: p.colors,
          availability: p.availability,
          leadTimeWeeks: p.leadTimeWeeks,
        })),
    }),
    submitOrder: async (order) => {
      fixtureState().orders.unshift({
        code: order.code,
        createdAt: order.createdAt,
        source: 'website',
        status: 'received',
        customerName: order.customer.name,
        phone: order.customer.phone,
        areaName: order.areaName,
        notes: order.customer.notes,
        itemsZmw: order.itemsZmw,
        deliveryZmw: order.deliveryZmw,
        depositZmw: order.depositZmw,
        items: order.lines.map((l) => ({
          productId: l.productId,
          name: l.name,
          size: l.size,
          color: l.color,
          qty: l.qty,
          unitPriceZmw: l.unitPriceZmw,
          preOrder: l.preOrder,
        })),
        payments: [],
      });
    },
    orderStatuses: async (codes, phone) => {
      const result: Record<string, OrderStatus> = {};
      for (const o of fixtureState().orders) if (codes.includes(o.code) && o.phone === phone) result[o.code] = o.status;
      return result;
    },
  };
}

/** The test dashboard: same behaviour as the real one, over the shared store. */
export function fixtureAdmin(): AdminApi {
  const find = (code: string) => {
    const o = fixtureState().orders.find((x) => x.code === code);
    if (!o) throw new AdminError(`Order ${code} not found`);
    return o;
  };
  const product = (id: string) => {
    const p = fixtureState().products.find((x) => x.id === id);
    if (!p) throw new AdminError(`Unknown product ${id}`);
    return p;
  };
  return {
    async summary() {
      const s = fixtureState();
      const sales = s.orders.filter((o) => takesStock(o.status));
      const sum = (os: AdminOrder[]) => os.reduce((t, o) => t + orderTotal(o), 0);
      return {
        salesToday: sum(sales),
        salesWeek: sum(sales),
        salesMonth: sum(sales),
        ordersMonth: sales.length,
        receivedMonth: s.orders.reduce((t, o) => t + orderPaid(o), 0),
        owed: sales.reduce((t, o) => t + orderOwed(o), 0),
        newOrders: s.orders.filter((o) => o.status === 'received').length,
        toDeliver: s.orders.filter((o) => o.status === 'confirmed' || o.status === 'ready').length,
        lowStock: s.products.flatMap((p) =>
          p.trackStock
            ? (p.sizes.length ? p.sizes : ['']).filter((k) => (p.stock[k] ?? 0) <= 2).map((k) => ({
                productId: p.id,
                name: p.name,
                size: k || null,
                qty: p.stock[k] ?? 0,
              }))
            : [],
        ),
        topSellers: [],
      };
    },
    async orders({ status, limit = 100 }) {
      return fixtureState()
        .orders.filter((o) =>
          status === 'open' ? ['received', 'confirmed', 'ready'].includes(o.status) : !status || o.status === status,
        )
        .slice(0, limit);
    },
    order: async (code) => fixtureState().orders.find((o) => o.code === code) ?? null,
    setStatus: async (code, status) => setStatus(find(code), status),
    async addPayment(code, amountZmw, method, note) {
      find(code).payments.push({ id: fixtureState().nextPaymentId++, amountZmw, method, note, paidAt: new Date().toISOString() });
    },
    async deletePayment(id) {
      for (const o of fixtureState().orders) o.payments = o.payments.filter((p) => p.id !== id);
    },
    async recordSale(sale) {
      if (sale.lines.length === 0) throw new AdminError('Add at least one item');
      const code = newOrderCode();
      const o: AdminOrder = {
        code,
        createdAt: new Date().toISOString(),
        source: 'shop',
        status: 'received',
        customerName: sale.customer.name.trim() || 'Walk-in customer',
        phone: sale.customer.phone,
        areaName: null,
        notes: sale.notes,
        itemsZmw: sale.lines.reduce((t, l) => t + l.qty * l.unitPriceZmw, 0),
        deliveryZmw: 0,
        depositZmw: 0,
        items: sale.lines.map((l) => {
          const p = product(l.productId);
          return { productId: p.id, name: p.name, size: l.size, color: null, qty: l.qty, unitPriceZmw: l.unitPriceZmw, preOrder: p.availability === 'preOrder' };
        }),
        payments: [],
      };
      setStatus(o, sale.status); // throws before saving if stock is short
      fixtureState().orders.unshift(o);
      if (sale.payment && sale.payment.amountZmw > 0) {
        await this.addPayment(code, sale.payment.amountZmw, sale.payment.method, '');
      }
      return code;
    },
    products: async () => fixtureState().products,
    product: async (id) => fixtureState().products.find((p) => p.id === id) ?? null,
    lists: async () => ({ categories: testCatalog.categories, series: testCatalog.series }),
    async saveProduct(input) {
      const s = fixtureState();
      const existing = s.products.find((p) => p.id === input.id);
      const p: AdminProduct = existing ?? {
        ...input,
        colors: [],
        trackStock: false,
        stock: {},
        sortOrder: s.products.length,
      };
      Object.assign(p, input);
      if (!existing) s.products.push(p);
      refresh(p);
    },
    async setStock(productId, size, qty) {
      const p = product(productId);
      if (qty < 0) throw new AdminError("Stock can't be negative");
      p.trackStock = true;
      moveStock(p, size, qty - (p.stock[size] ?? 0));
      refresh(p);
    },
    async stopTracking(productId) {
      const p = product(productId);
      p.trackStock = false;
      p.availability = 'inStock';
    },
    async uploadPhoto(_productId, data, contentType) {
      let binary = '';
      const bytes = new Uint8Array(data);
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return `data:${contentType};base64,${btoa(binary)}`;
    },
  };
}
