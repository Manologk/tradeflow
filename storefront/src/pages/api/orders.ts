import type { APIRoute } from 'astro';
import { buildOrder, newOrderCode, normalisePhone, priceLines, whatsappLink } from '../../lib/checkout';
import { json, loadCatalog } from '../../lib/load';
import type { CartLine } from '../../lib/models';
import { getShop } from '../../lib/shop';

const str = (v: unknown, max: number) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

/**
 * Places an order. Prices are always taken from the current catalog on the
 * server, never from the browser.
 */
export const POST: APIRoute = async ({ request }) => {
  let body: { cart?: unknown; customer?: Record<string, unknown> };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid request' }, 400);
  }
  const loaded = await loadCatalog();
  if (!loaded.ok) return json({ error: 'Shop unavailable' }, 503);
  const { catalog } = loaded;

  const cart: CartLine[] = Array.isArray(body.cart)
    ? body.cart.slice(0, 50).map((l: Record<string, unknown>) => ({
        productId: str(l?.productId, 64),
        size: str(l?.size, 16) || null,
        color: str(l?.color, 32) || null,
        qty: Number(l?.qty) || 0,
      }))
    : [];
  const lines = priceLines(cart, catalog);
  const phone = normalisePhone(str(body.customer?.phone, 32));
  const name = str(body.customer?.name, 80);
  const areaId = str(body.customer?.areaId, 64) || null;
  if (lines.length === 0) return json({ error: 'Your cart is empty' }, 422);
  if (!name || !phone) return json({ error: 'Name and a Zambian mobile number are needed' }, 422);

  const order = buildOrder({
    code: newOrderCode(),
    now: new Date(),
    customer: {
      name,
      phone,
      areaId: catalog.settings.deliveryAreas.some((a) => a.id === areaId) ? areaId : null,
      notes: str(body.customer?.notes, 300),
    },
    lines,
    settings: catalog.settings,
  });

  // If saving fails the customer still gets the WhatsApp message, which has
  // everything the shop needs.
  let savedOnline = true;
  try {
    await getShop().submitOrder(order);
  } catch (e) {
    console.error('Saving order failed', e);
    savedOnline = false;
  }
  return json({ order, whatsappUrl: whatsappLink(order, catalog.settings), savedOnline });
};
