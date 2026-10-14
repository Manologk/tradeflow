import type { APIRoute } from 'astro';
import { normalisePhone } from '../../lib/checkout';
import { json } from '../../lib/load';
import { getShop } from '../../lib/shop';

/** Statuses for a phone's own orders (the database checks the phone matches). */
export const POST: APIRoute = async ({ request }) => {
  let body: { codes?: unknown; phone?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid request' }, 400);
  }
  const phone = typeof body.phone === 'string' ? normalisePhone(body.phone) : null;
  const codes = Array.isArray(body.codes)
    ? body.codes.filter((c): c is string => typeof c === 'string' && /^TF-[A-Z0-9]{4}$/.test(c)).slice(0, 50)
    : [];
  if (!phone || codes.length === 0) return json({}, 200);
  try {
    return json(await getShop().orderStatuses(codes, phone));
  } catch {
    return json({ error: 'Unavailable' }, 503);
  }
};
