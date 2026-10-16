import type { Availability, OrderStatus } from '../models';
import type { PaymentMethod } from './types';

const TZ = 'Africa/Lusaka';

/** "16 Oct, 14:05" in Zambian time. */
export function when(iso: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone: TZ, day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
    .format(new Date(iso))
    .replace(' at', ',');
}

export const STATUS: Record<OrderStatus, { label: string; tone: string }> = {
  received: { label: 'New', tone: 'bg-brand text-ink-deep' },
  confirmed: { label: 'Confirmed', tone: 'bg-ink-deep text-white' },
  ready: { label: 'Ready', tone: 'bg-[#1f6f43] text-white' },
  delivered: { label: 'Delivered', tone: 'bg-surface text-ink-deep' },
  cancelled: { label: 'Cancelled', tone: 'bg-surface text-grey line-through' },
};

export const METHOD: Record<PaymentMethod, string> = { cash: 'Cash', mobile_money: 'Mobile money' };

export const AVAILABILITY: Record<Availability, string> = {
  inStock: 'In stock',
  fewLeft: 'Few left',
  preOrder: 'Pre-order',
  soldOut: 'Sold out',
};

/** "250", "K250", "250.50" → ngwee. Null if not a positive amount. */
export function parseKwacha(input: FormDataEntryValue | null | undefined): number | null {
  const s = String(input ?? '').replace(/[k,\s]/gi, '');
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const n = Math.round(Number(s) * 100);
  return n > 0 ? n : null;
}

/** Ngwee → "250" or "250.50" for form fields. */
export const kwachaInput = (ngwee: number | null) =>
  ngwee === null ? '' : ngwee % 100 === 0 ? String(ngwee / 100) : (ngwee / 100).toFixed(2);

/** "Nezuko Jersey!" → "nezuko-jersey" */
export const slugify = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

/** Builds "?ok=…" / "?err=…" for messages shown after a form is sent. */
export function flash(path: string, kind: 'ok' | 'err', message: string) {
  // The message goes before any "#section" so the page still jumps there.
  const [base, hash] = path.split('#');
  const sep = base.includes('?') ? '&' : '?';
  return `${base}${sep}${kind}=${encodeURIComponent(message)}${hash ? `#${hash}` : ''}`;
}
