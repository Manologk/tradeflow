import type { OrderStatus } from '../models';
import { AdminError, type AdminApi, type AdminOrder, type AdminProduct, type AdminSummary } from './types';

// The dashboard talks to Supabase as the signed-in owner: every request
// carries their access token, and the database's row-level security and
// owner-only functions decide what is allowed.

interface OrderRow {
  code: string;
  created_at: string;
  source: 'website' | 'shop';
  status: OrderStatus;
  customer_name: string;
  phone: string | null;
  area_name: string | null;
  notes: string;
  items_zmw: number;
  delivery_zmw: number;
  deposit_zmw: number;
  shop_order_items: {
    line_no: number;
    product_id: string;
    name: string;
    size: string | null;
    color: string | null;
    qty: number;
    unit_price_zmw: number;
    pre_order: boolean;
  }[];
  shop_payments: { id: number; amount_zmw: number; method: 'cash' | 'mobile_money'; note: string; paid_at: string }[];
}

interface ProductRow {
  id: string;
  name: string;
  description: string | null;
  category_id: string;
  series_id: string | null;
  price_zmw: number;
  compare_at_zmw: number | null;
  photos: string[];
  sizes: string[];
  colors: { name: string; hex: string }[];
  availability: AdminProduct['availability'];
  lead_time_weeks: number | null;
  published: boolean;
  track_stock: boolean;
  sort_order: number;
}

const ORDER_SELECT = 'select=*,shop_order_items(*),shop_payments(*)';

function toOrder(r: OrderRow): AdminOrder {
  return {
    code: r.code,
    createdAt: r.created_at,
    source: r.source,
    status: r.status,
    customerName: r.customer_name,
    phone: r.phone,
    areaName: r.area_name,
    notes: r.notes,
    itemsZmw: r.items_zmw,
    deliveryZmw: r.delivery_zmw,
    depositZmw: r.deposit_zmw,
    items: [...r.shop_order_items]
      .sort((a, b) => a.line_no - b.line_no)
      .map((i) => ({
        productId: i.product_id,
        name: i.name,
        size: i.size,
        color: i.color,
        qty: i.qty,
        unitPriceZmw: i.unit_price_zmw,
        preOrder: i.pre_order,
      })),
    payments: [...r.shop_payments]
      .sort((a, b) => a.paid_at.localeCompare(b.paid_at))
      .map((p) => ({ id: p.id, amountZmw: p.amount_zmw, method: p.method, note: p.note, paidAt: p.paid_at })),
  };
}

function toProduct(r: ProductRow, stock: { size: string; qty: number }[]): AdminProduct {
  return {
    id: r.id,
    name: r.name,
    description: r.description ?? '',
    categoryId: r.category_id,
    seriesId: r.series_id,
    priceZmw: r.price_zmw,
    compareAtZmw: r.compare_at_zmw,
    photos: r.photos ?? [],
    sizes: r.sizes ?? [],
    colors: r.colors ?? [],
    availability: r.availability,
    leadTimeWeeks: r.lead_time_weeks,
    published: r.published,
    trackStock: r.track_stock,
    stock: Object.fromEntries(stock.map((s) => [s.size, s.qty])),
    sortOrder: r.sort_order,
  };
}

export function supabaseAdmin(url: string, anonKey: string, accessToken: string, fetchFn: typeof fetch = fetch): AdminApi {
  const auth = { apikey: anonKey, Authorization: `Bearer ${accessToken}` };

  async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
    const res = await fetchFn(`${url}${path}`, { ...init, headers: { ...auth, ...(init.headers ?? {}) } });
    const text = await res.text();
    if (!res.ok) {
      // Owner-facing refusals from the database (stock, permissions) come back as { message }.
      let message = `Request failed (${res.status})`;
      try {
        message = (JSON.parse(text) as { message?: string }).message ?? message;
      } catch {
        // not JSON
      }
      throw new AdminError(message);
    }
    return (text ? JSON.parse(text) : null) as T;
  }

  const rest = <T>(path: string, init?: RequestInit) => call<T>(`/rest/v1/${path}`, init);
  const rpc = <T>(fn: string, body: unknown) =>
    rest<T>(`rpc/${fn}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

  async function stockFor(ids?: string[]) {
    const filter = ids ? `&product_id=in.(${ids.map(encodeURIComponent).join(',')})` : '';
    return rest<{ product_id: string; size: string; qty: number }[]>(`shop_stock?select=*${filter}`);
  }

  return {
    summary: () => rpc<AdminSummary>('admin_summary', {}),

    async orders({ status, limit = 100 }) {
      const where =
        status === 'open' ? '&status=in.(received,confirmed,ready)' : status ? `&status=eq.${status}` : '';
      const rows = await rest<OrderRow[]>(`shop_orders?${ORDER_SELECT}${where}&order=created_at.desc&limit=${limit}`);
      return rows.map(toOrder);
    },

    async order(code) {
      const rows = await rest<OrderRow[]>(`shop_orders?${ORDER_SELECT}&code=eq.${encodeURIComponent(code)}`);
      return rows[0] ? toOrder(rows[0]) : null;
    },

    setStatus: (code, status) => rpc('admin_set_order_status', { p_code: code, p_status: status }),
    addPayment: (code, amountZmw, method, note) =>
      rpc('admin_add_payment', { p_code: code, p_amount_zmw: amountZmw, p_method: method, p_note: note }),
    deletePayment: (id) => rpc('admin_delete_payment', { p_id: id }),
    recordSale: (sale) => rpc<string>('admin_record_sale', { sale }),

    async products() {
      const [rows, stock] = await Promise.all([rest<ProductRow[]>('shop_products?select=*&order=sort_order,name'), stockFor()]);
      return rows.map((r) => toProduct(r, stock.filter((s) => s.product_id === r.id)));
    },

    async product(id) {
      const [rows, stock] = await Promise.all([
        rest<ProductRow[]>(`shop_products?select=*&id=eq.${encodeURIComponent(id)}`),
        stockFor([id]),
      ]);
      return rows[0] ? toProduct(rows[0], stock) : null;
    },

    async lists() {
      const [categories, series] = await Promise.all([
        rest<{ id: string; name: string }[]>('shop_categories?select=id,name&order=sort_order'),
        rest<{ id: string; name: string; image_url: string | null }[]>('shop_series?select=id,name,image_url&order=sort_order'),
      ]);
      return { categories, series: series.map((s) => ({ id: s.id, name: s.name, imageUrl: s.image_url })) };
    },

    async saveProduct(p) {
      await rest('shop_products?on_conflict=id', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({
          id: p.id,
          name: p.name,
          description: p.description,
          category_id: p.categoryId,
          series_id: p.seriesId,
          price_zmw: p.priceZmw,
          compare_at_zmw: p.compareAtZmw,
          photos: p.photos,
          sizes: p.sizes,
          availability: p.availability,
          lead_time_weeks: p.leadTimeWeeks,
          published: p.published,
          updated_at: new Date().toISOString(),
        }),
      });
      await rpc('admin_refresh_product', { p_id: p.id });
    },

    setStock: (productId, size, qty, reason) =>
      rpc('admin_set_stock', { p_product: productId, p_size: size, p_qty: qty, p_reason: reason }),

    async stopTracking(productId) {
      await rest(`shop_products?id=eq.${encodeURIComponent(productId)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify({ track_stock: false, availability: 'inStock' }),
      });
      await rpc('admin_refresh_product', { p_id: productId });
    },

    async uploadPhoto(productId, data, contentType) {
      const ext = contentType === 'image/webp' ? 'webp' : contentType === 'image/png' ? 'png' : 'jpg';
      const path = `${encodeURIComponent(productId)}/${crypto.randomUUID()}.${ext}`;
      await call(`/storage/v1/object/shop-photos/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': contentType, 'Cache-Control': 'max-age=31536000' },
        body: data,
      });
      return `${url}/storage/v1/object/public/shop-photos/${path}`;
    },
  };
}
