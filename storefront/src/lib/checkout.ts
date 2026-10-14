import { canOrder, type CartLine, type Catalog, type Customer, type Order, type OrderLine, type ShopSettings } from './models';
import { kwacha } from './money';

export interface CartTotals {
  itemsZmw: number;
  deliveryZmw: number;
  depositZmw: number;
  units: number;
  totalZmw: number;
}

/** Prices the cart against the catalog. Gone or sold-out products drop out. */
export function priceLines(cart: CartLine[], catalog: Catalog): OrderLine[] {
  const lines: OrderLine[] = [];
  for (const line of cart) {
    const p = catalog.products.find((x) => x.id === line.productId);
    if (!p || !canOrder(p) || line.qty < 1) continue;
    lines.push({
      productId: p.id,
      name: p.name,
      size: line.size,
      color: line.color,
      qty: Math.min(Math.floor(line.qty), 99),
      unitPriceZmw: p.priceZmw,
      preOrder: p.availability === 'preOrder',
      leadTimeWeeks: p.leadTimeWeeks,
    });
  }
  return lines;
}

const lineTotal = (l: OrderLine) => l.qty * l.unitPriceZmw;

/** Deposit on pre-order items, rounded up to whole kwacha. */
export function depositFor(lines: OrderLine[], percent: number): number {
  const preOrderValue = lines.filter((l) => l.preOrder).reduce((s, l) => s + lineTotal(l), 0);
  if (preOrderValue === 0 || percent <= 0) return 0;
  const deposit = Math.ceil((preOrderValue * percent) / 100);
  return Math.ceil(deposit / 100) * 100;
}

export function totalsFor(lines: OrderLine[], settings: ShopSettings, areaId: string | null): CartTotals {
  const area = settings.deliveryAreas.find((a) => a.id === areaId);
  const itemsZmw = lines.reduce((s, l) => s + lineTotal(l), 0);
  const deliveryZmw = area?.feeZmw ?? 0;
  return {
    itemsZmw,
    deliveryZmw,
    depositZmw: depositFor(lines, settings.depositPercent),
    units: lines.reduce((s, l) => s + l.qty, 0),
    totalZmw: itemsZmw + deliveryZmw,
  };
}

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Short code customers quote on WhatsApp, e.g. "TF-7K3Q". No 0/O or 1/I. */
export function newOrderCode(random: () => number = Math.random): string {
  let code = '';
  for (let i = 0; i < 4; i++) code += CODE_ALPHABET[Math.floor(random() * CODE_ALPHABET.length)];
  return `TF-${code}`;
}

/**
 * Normalises a Zambian mobile number to international digits:
 * "097 123 4567" / "+260971234567" -> "260971234567". Null if not valid.
 */
export function normalisePhone(input: string): string | null {
  const digits = input.replace(/\D/g, '');
  if (/^0[79]\d{8}$/.test(digits)) return `260${digits.slice(1)}`;
  if (/^260[79]\d{8}$/.test(digits)) return digits;
  if (/^[79]\d{8}$/.test(digits)) return `260${digits}`;
  return null;
}

/** "260971234567" -> "097 123 4567" for display. */
export function localPhone(international: string): string {
  const local = `0${international.slice(3)}`;
  return `${local.slice(0, 3)} ${local.slice(3, 6)} ${local.slice(6)}`;
}

export function buildOrder(args: {
  code: string;
  now: Date;
  customer: Customer;
  lines: OrderLine[];
  settings: ShopSettings;
}): Order {
  const { code, now, customer, lines, settings } = args;
  const totals = totalsFor(lines, settings, customer.areaId);
  return {
    code,
    createdAt: now.toISOString(),
    customer,
    areaName: settings.deliveryAreas.find((a) => a.id === customer.areaId)?.name ?? null,
    lines,
    itemsZmw: totals.itemsZmw,
    deliveryZmw: totals.deliveryZmw,
    depositZmw: totals.depositZmw,
  };
}

export const orderTotal = (o: Order) => o.itemsZmw + o.deliveryZmw;

/** The message the customer sends the shop on WhatsApp. */
export function whatsappMessage(order: Order, settings: ShopSettings): string {
  const out: string[] = [`Hi ${settings.name}! I'd like to order (${order.code}):`, ''];
  for (const l of order.lines) {
    const options = [l.size ? `Size ${l.size}` : null, l.color].filter(Boolean).join(', ');
    const pre = l.preOrder ? ` [Pre-order${l.leadTimeWeeks ? ` ~${l.leadTimeWeeks} weeks` : ''}]` : '';
    out.push(`• ${l.qty} × ${l.name}${options ? ` (${options})` : ''}${pre}: ${kwacha(lineTotal(l))}`);
  }
  out.push('', `Items: ${kwacha(order.itemsZmw)}`);
  if (order.areaName) out.push(`Delivery (${order.areaName}): ${kwacha(order.deliveryZmw)}`);
  out.push(`Total: ${kwacha(orderTotal(order))}`);
  if (order.depositZmw > 0) out.push(`Pre-order deposit (${settings.depositPercent}%): ${kwacha(order.depositZmw)}`);
  out.push('', `Name: ${order.customer.name}`, `Phone: +${order.customer.phone}`);
  const notes = order.customer.notes.trim();
  if (notes) out.push(`Notes: ${notes}`);
  return out.join('\n');
}

export function whatsappLink(order: Order, settings: ShopSettings): string {
  return `https://wa.me/${settings.whatsappNumber}?text=${encodeURIComponent(whatsappMessage(order, settings))}`;
}
