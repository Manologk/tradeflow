import { useMemo, useState } from 'preact/hooks';
import { kwacha } from '../../lib/money';
import { Icon } from '../Icon';
import { QtyStepper } from '../QtyStepper';

export interface SaleProduct {
  id: string;
  name: string;
  priceZmw: number;
  photo: string | null;
  sizes: string[];
  trackStock: boolean;
  preOrder: boolean;
  stock: Record<string, number>;
}

interface Line {
  productId: string;
  name: string;
  size: string | null;
  qty: number;
  /** Kwacha as typed, so a discount can be given. */
  price: string;
  max: number;
}

const toNgwee = (k: string) => Math.round(Number(k.replace(/[k,\s]/gi, '')) * 100);

/** Records a sale made outside the website: items, customer, payment. */
export default function SaleBuilder({ products }: { products: SaleProduct[] }) {
  const [query, setQuery] = useState('');
  const [picking, setPicking] = useState<SaleProduct | null>(null);
  const [lines, setLines] = useState<Line[]>([]);
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [notes, setNotes] = useState('');
  const [delivered, setDelivered] = useState(true);
  const [paid, setPaid] = useState<'full' | 'part' | 'none'>('full');
  const [partAmount, setPartAmount] = useState('');
  const [method, setMethod] = useState<'mobile_money' | 'cash'>('mobile_money');
  const [error, setError] = useState('');
  const [sending, setSending] = useState(false);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return products.filter((p) => !q || p.name.toLowerCase().includes(q)).slice(0, 30);
  }, [query, products]);

  const total = lines.reduce((t, l) => t + l.qty * (toNgwee(l.price) || 0), 0);
  const available = (p: SaleProduct, size: string) => (p.trackStock && !p.preOrder ? p.stock[size] ?? 0 : 99);

  function add(p: SaleProduct, size: string | null) {
    setPicking(null);
    setError('');
    setLines((ls) => {
      const i = ls.findIndex((l) => l.productId === p.id && l.size === size);
      if (i >= 0) return ls.map((l, j) => (j === i ? { ...l, qty: Math.min(l.max, l.qty + 1) } : l));
      return [...ls, { productId: p.id, name: p.name, size, qty: 1, price: String(p.priceZmw / 100), max: Math.min(99, available(p, size ?? '')) }];
    });
  }

  async function submit(e: Event) {
    e.preventDefault();
    if (lines.length === 0) return setError('Add at least one item.');
    if (lines.some((l) => !(toNgwee(l.price) > 0))) return setError('Every item needs a price, e.g. 250.');
    const amount = paid === 'full' ? total : paid === 'part' ? toNgwee(partAmount) : 0;
    if (paid === 'part' && !(amount > 0)) return setError('Enter how much was paid.');
    setSending(true);
    setError('');
    try {
      const res = await fetch('/api/admin/sales', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          customer: { name, phone },
          notes,
          status: delivered ? 'delivered' : 'confirmed',
          lines: lines.map((l) => ({ productId: l.productId, size: l.size, qty: l.qty, unitPriceZmw: toNgwee(l.price) })),
          payment: amount > 0 ? { amountZmw: amount, method } : null,
        }),
      });
      const body = (await res.json()) as { code?: string; error?: string };
      if (!res.ok || !body.code) throw new Error(body.error ?? 'Couldn’t save the sale.');
      window.location.href = `/admin/orders/${body.code}?ok=${encodeURIComponent('Sale recorded')}`;
    } catch (err) {
      setSending(false);
      setError(err instanceof Error ? err.message : 'Couldn’t save the sale.');
    }
  }

  return (
    <form onSubmit={submit} class="grid gap-5 lg:grid-cols-[1fr_1fr]" noValidate>
      <section class="rounded-3xl bg-white p-4 md:p-5" aria-labelledby="pick-h">
        <h2 id="pick-h" class="display text-2xl">1. Pick items</h2>
        <input
          type="search"
          class="field mt-3"
          placeholder="Search products…"
          aria-label="Search products"
          value={query}
          onInput={(e) => setQuery(e.currentTarget.value)}
        />
        <ul class="mt-3 grid max-h-[420px] grid-cols-2 gap-2 overflow-y-auto sm:grid-cols-3">
          {shown.map((p) => {
            const total = (p.sizes.length ? p.sizes : ['']).reduce((t, s) => t + available(p, s), 0);
            const out = p.trackStock && !p.preOrder && total === 0;
            return (
              <li key={p.id}>
                <button
                  type="button"
                  disabled={out}
                  onClick={() => (p.sizes.length ? setPicking(p) : add(p, null))}
                  class="flex w-full flex-col overflow-hidden rounded-2xl border border-line text-left transition hover:border-ink-deep active:scale-95 disabled:opacity-40"
                >
                  <span class="aspect-square w-full bg-surface">
                    {p.photo && <img src={p.photo} alt="" class="size-full object-cover" loading="lazy" />}
                  </span>
                  <span class="p-2">
                    <span class="line-clamp-2 text-xs font-semibold leading-tight">{p.name}</span>
                    <span class="block text-xs muted">
                      {kwacha(p.priceZmw)}
                      {p.trackStock && !p.preOrder && ` · ${out ? 'out' : `${total} left`}`}
                    </span>
                  </span>
                </button>
              </li>
            );
          })}
        </ul>

        {picking && (
          <div class="rise mt-3 rounded-2xl bg-surface p-3" role="group" aria-label={`Size for ${picking.name}`}>
            <p class="text-sm font-semibold">Size for {picking.name}</p>
            <div class="mt-2 flex flex-wrap gap-2">
              {picking.sizes.map((s) => (
                <button
                  key={s}
                  type="button"
                  disabled={available(picking, s) === 0}
                  onClick={() => add(picking, s)}
                  class="h-11 min-w-11 rounded-full border border-line bg-white px-3 text-sm font-semibold hover:border-ink-deep disabled:border-dashed disabled:text-grey-light"
                  aria-label={`Size ${s}`}
                >
                  {s}
                  {picking.trackStock && !picking.preOrder && <span class="ml-1 text-[10px] font-normal muted">{available(picking, s)}</span>}
                </button>
              ))}
              <button type="button" class="px-2 text-sm muted" onClick={() => setPicking(null)}>Cancel</button>
            </div>
          </div>
        )}
      </section>

      <section class="grid content-start gap-5">
        <div class="rounded-3xl bg-white p-4 md:p-5" aria-labelledby="items-h">
          <h2 id="items-h" class="display text-2xl">2. Items</h2>
          {lines.length === 0 ? (
            <p class="mt-2 text-sm muted">Tap a product to add it.</p>
          ) : (
            <ul class="mt-2 divide-y divide-line">
              {lines.map((l, i) => (
                <li key={`${l.productId}|${l.size}`} class="rise flex flex-wrap items-center gap-3 py-3">
                  <span class="min-w-0 basis-full sm:basis-auto sm:flex-1">
                    <span class="block font-semibold leading-tight">{l.name}</span>
                    {l.size && <span class="text-xs muted">Size {l.size}</span>}
                  </span>
                  <QtyStepper value={l.qty} max={l.max} label={l.name} onChange={(v) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, qty: v } : x)))} />
                  <label class="flex items-center gap-1 text-sm">
                    K
                    <input
                      class="field w-20 px-2 py-2 text-right"
                      inputMode="decimal"
                      aria-label={`Price each for ${l.name}`}
                      value={l.price}
                      onInput={(e) => {
                        const v = e.currentTarget.value;
                        setLines((ls) => ls.map((x, j) => (j === i ? { ...x, price: v } : x)));
                      }}
                    />
                  </label>
                  <button type="button" aria-label={`Remove ${l.name}`} onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}>
                    <Icon name="close" size={18} />
                  </button>
                </li>
              ))}
            </ul>
          )}
          <p class="mt-2 flex items-baseline justify-between border-t border-line pt-3"><span class="display text-2xl">Total</span><span class="figure text-2xl">{kwacha(total)}</span></p>
        </div>

        <div class="rounded-3xl bg-white p-4 md:p-5" aria-labelledby="cust-h">
          <h2 id="cust-h" class="display text-2xl">3. Customer & payment</h2>
          <div class="mt-3 grid gap-3 sm:grid-cols-2">
            <input class="field" placeholder="Name (optional)" aria-label="Customer name" value={name} onInput={(e) => setName(e.currentTarget.value)} />
            <input class="field" type="tel" placeholder="Phone (optional)" aria-label="Customer phone" value={phone} onInput={(e) => setPhone(e.currentTarget.value)} />
          </div>
          <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Delivery">
            <button type="button" aria-pressed={delivered} onClick={() => setDelivered(true)} class={`pill ${delivered ? 'pill-on' : ''}`}>Handed over now</button>
            <button type="button" aria-pressed={!delivered} onClick={() => setDelivered(false)} class={`pill ${!delivered ? 'pill-on' : ''}`}>Deliver later</button>
          </div>
          <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Payment">
            {(['full', 'part', 'none'] as const).map((p) => (
              <button key={p} type="button" aria-pressed={paid === p} onClick={() => setPaid(p)} class={`pill ${paid === p ? 'pill-on' : ''}`}>
                {p === 'full' ? 'Paid in full' : p === 'part' ? 'Part paid' : 'Not paid yet'}
              </button>
            ))}
          </div>
          {paid === 'part' && (
            <input class="field mt-3" inputMode="decimal" placeholder="Amount paid, e.g. 100" aria-label="Amount paid" value={partAmount} onInput={(e) => setPartAmount(e.currentTarget.value)} />
          )}
          {paid !== 'none' && (
            <div class="mt-3 flex gap-2" role="group" aria-label="Paid by">
              <button type="button" aria-pressed={method === 'mobile_money'} onClick={() => setMethod('mobile_money')} class={`pill ${method === 'mobile_money' ? 'pill-on' : ''}`}>Mobile money</button>
              <button type="button" aria-pressed={method === 'cash'} onClick={() => setMethod('cash')} class={`pill ${method === 'cash' ? 'pill-on' : ''}`}>Cash</button>
            </div>
          )}
          <textarea class="field mt-3" rows={2} placeholder="Notes (optional)" aria-label="Notes" value={notes} onInput={(e) => setNotes(e.currentTarget.value)} />
          {error && <p role="alert" class="mt-3 text-sm font-semibold text-sale">{error}</p>}
          <button class="btn-primary mt-4" disabled={sending}>{sending ? 'Saving…' : `Record sale · ${kwacha(total)}`}</button>
        </div>
      </section>
    </form>
  );
}
