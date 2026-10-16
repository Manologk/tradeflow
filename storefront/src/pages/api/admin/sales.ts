import type { APIRoute } from 'astro';
import { AdminError, type SaleInput } from '../../../lib/admin/types';
import { normalisePhone } from '../../../lib/checkout';
import { json } from '../../../lib/load';

const str = (v: unknown, max: number) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const int = (v: unknown) => (typeof v === 'number' && Number.isInteger(v) ? v : NaN);

/** Records a sale made outside the website (the middleware checks it's the owner). */
export const POST: APIRoute = async ({ request, locals }) => {
  let body: Record<string, any>;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid request' }, 400);
  }
  const rawPhone = str(body.customer?.phone, 32);
  const phone = rawPhone ? normalisePhone(rawPhone) : null;
  if (rawPhone && !phone) return json({ error: 'That phone number doesn’t look Zambian, e.g. 097 123 4567' }, 422);

  const lines: SaleInput['lines'] = Array.isArray(body.lines)
    ? body.lines.slice(0, 50).map((l: Record<string, unknown>) => ({
        productId: str(l?.productId, 64),
        size: str(l?.size, 16) || null,
        qty: int(l?.qty),
        unitPriceZmw: int(l?.unitPriceZmw),
      }))
    : [];
  if (lines.length === 0) return json({ error: 'Add at least one item' }, 422);
  if (lines.some((l) => !l.productId || !(l.qty >= 1 && l.qty <= 99) || !(l.unitPriceZmw > 0))) {
    return json({ error: 'Check the quantities and prices' }, 422);
  }
  const payment =
    body.payment && int(body.payment.amountZmw) > 0
      ? { amountZmw: int(body.payment.amountZmw), method: body.payment.method === 'cash' ? 'cash' : 'mobile_money' } as const
      : null;
  const status = (['confirmed', 'ready', 'delivered'] as const).find((s) => s === body.status) ?? 'delivered';

  try {
    const code = await locals.admin!.recordSale({
      customer: { name: str(body.customer?.name, 80), phone },
      notes: str(body.notes, 300),
      status,
      lines,
      payment,
    });
    return json({ code });
  } catch (e) {
    return json({ error: e instanceof AdminError ? e.message : 'Couldn’t save the sale. Try again.' }, 422);
  }
};
