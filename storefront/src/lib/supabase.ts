import type { ShopData } from './data';
import type { Availability, Catalog, Order, OrderStatus, ShopColor } from './models';

// Reads the shop tables published by the admin app through Supabase's REST API
// with the public (anon) key. Row Level Security on the database decides what
// that key may see: published products and settings, nothing else.

interface SettingsRow {
  name: string;
  whatsapp_number: string;
  deposit_percent: number;
  logo_url: string | null;
  delivery_areas: { id: string; name: string; fee_zmw: number }[];
}

interface ProductRow {
  id: string;
  name: string;
  description: string | null;
  category_id: string;
  series_id: string | null;
  price_zmw: number;
  compare_at_zmw: number | null;
  photos: string[] | null;
  sizes: string[] | null;
  colors: ShopColor[] | null;
  availability: Availability;
  lead_time_weeks: number | null;
}

export function supabaseShop(url: string, anonKey: string, fetchFn: typeof fetch = fetch): ShopData {
  const headers = { apikey: anonKey, Authorization: `Bearer ${anonKey}` };

  async function get<T>(path: string): Promise<T> {
    const res = await fetchFn(`${url}/rest/v1/${path}`, { headers });
    if (!res.ok) throw new Error(`Supabase ${path}: ${res.status}`);
    return (await res.json()) as T;
  }

  async function rpc<T>(fn: string, body: unknown): Promise<T> {
    const res = await fetchFn(`${url}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Supabase rpc ${fn}: ${res.status}`);
    const text = await res.text();
    return (text ? JSON.parse(text) : null) as T;
  }

  return {
    async loadCatalog(): Promise<Catalog> {
      const [settings, categories, series, products] = await Promise.all([
        get<SettingsRow[]>('shop_settings?select=*&limit=1'),
        get<{ id: string; name: string }[]>('shop_categories?select=id,name&order=sort_order'),
        get<{ id: string; name: string; image_url: string | null }[]>('shop_series?select=id,name,image_url&order=sort_order'),
        get<ProductRow[]>('shop_products?select=*&order=sort_order,name'),
      ]);
      const s = settings[0];
      if (!s) throw new Error('Shop settings not published yet');
      return {
        settings: {
          name: s.name,
          whatsappNumber: s.whatsapp_number,
          depositPercent: s.deposit_percent,
          logoUrl: s.logo_url,
          deliveryAreas: s.delivery_areas.map((a) => ({ id: a.id, name: a.name, feeZmw: a.fee_zmw })),
        },
        categories,
        series: series.map((x) => ({ id: x.id, name: x.name, imageUrl: x.image_url })),
        products: products.map((p) => ({
          id: p.id,
          name: p.name,
          description: p.description ?? '',
          categoryId: p.category_id,
          seriesId: p.series_id,
          priceZmw: p.price_zmw,
          compareAtZmw: p.compare_at_zmw,
          photos: p.photos ?? [],
          sizes: p.sizes ?? [],
          colors: p.colors ?? [],
          availability: p.availability,
          leadTimeWeeks: p.lead_time_weeks,
        })),
      };
    },

    async submitOrder(order: Order) {
      await rpc('place_order', { order });
    },

    async orderStatuses(codes: string[], phone: string) {
      const rows = await rpc<{ code: string; status: OrderStatus }[]>('order_statuses', { codes, phone });
      return Object.fromEntries((rows ?? []).map((r) => [r.code, r.status]));
    },
  };
}
