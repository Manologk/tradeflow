import { useEffect, useMemo, useState } from 'preact/hooks';
import { localPhone, normalisePhone, priceLines, totalsFor } from '../lib/checkout';
import { kwacha } from '../lib/money';
import { lineKey, type CartLine, type Catalog, type Order } from '../lib/models';
import { Icon } from './Icon';
import { QtyStepper } from './QtyStepper';
import { CART_EVENT, cart, lastOrder, placedOrders, savedCustomer } from './store';

interface OrderResponse {
  order: Order;
  whatsappUrl: string;
  savedOnline: boolean;
}

/** Cart lines, delivery details, totals and "Order on WhatsApp". */
export default function Checkout({ catalog }: { catalog: Catalog }) {
  const settings = catalog.settings;
  const [lines, setLines] = useState<CartLine[] | null>(null);
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [areaId, setAreaId] = useState<string | null>(settings.deliveryAreas[0]?.id ?? null);
  const [notes, setNotes] = useState('');
  const [errors, setErrors] = useState<{ name?: string; phone?: string; form?: string }>({});
  const [sending, setSending] = useState(false);

  useEffect(() => {
    const load = () => setLines(cart.get());
    load();
    const saved = savedCustomer.get();
    setName(saved.name);
    if (saved.phone) setPhone(localPhone(saved.phone));
    if (saved.areaId && settings.deliveryAreas.some((a) => a.id === saved.areaId)) setAreaId(saved.areaId);
    window.addEventListener(CART_EVENT, load);
    return () => window.removeEventListener(CART_EVENT, load);
  }, []);

  const priced = useMemo(() => priceLines(lines ?? [], catalog), [lines, catalog]);
  const totals = totalsFor(priced, settings, areaId);
  const productOf = (id: string) => catalog.products.find((p) => p.id === id);

  if (lines === null) return <div class="py-24 text-center muted">Loading your cart…</div>;

  if (lines.length === 0) {
    return (
      <div class="flex flex-col items-center px-8 py-24 text-center">
        <div class="grid size-18 place-items-center rounded-full bg-surface text-grey">
          <Icon name="bag" size={32} />
        </div>
        <h2 class="display mt-4 text-2xl">Your cart is empty</h2>
        <p class="mt-2 muted">Find something you love and add it here.</p>
        <a href="/" class="btn-primary mt-6 max-w-56">
          Start shopping
        </a>
      </div>
    );
  }

  const unavailable = lines.length - priced.length;

  async function order(e: Event) {
    e.preventDefault();
    const intl = normalisePhone(phone);
    const next = {
      name: name.trim() ? undefined : 'Enter your name',
      phone: intl ? undefined : 'Enter a Zambian mobile number, e.g. 097 123 4567',
    };
    setErrors(next);
    if (next.name || next.phone || !intl) return;

    setSending(true);
    try {
      const res = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cart: lines, customer: { name: name.trim(), phone: intl, areaId, notes } }),
      });
      if (!res.ok) throw new Error(String(res.status));
      const result = (await res.json()) as OrderResponse;
      savedCustomer.set({ name: name.trim(), phone: intl, areaId });
      placedOrders.add(result.order);
      lastOrder.set(result);
      cart.set([]);
      // The next page has the "Send on WhatsApp" button: a link the customer
      // taps works on every phone, unlike opening WhatsApp automatically.
      window.location.href = `/order/${result.order.code}`;
    } catch {
      setSending(false);
      setErrors({ form: "Couldn't send your order. Check your internet connection and try again." });
    }
  }

  return (
    <form onSubmit={order} noValidate class="px-5 pb-10">
      <ul>
        {lines.map((line) => {
          const p = productOf(line.productId);
          if (!p || p.availability === 'soldOut') return null;
          const options = [line.size ? `Size ${line.size}` : null, line.color, p.availability === 'preOrder' ? 'Pre-order' : null]
            .filter(Boolean)
            .join(' · ');
          return (
            <li key={lineKey(line)} class="flex gap-3.5 border-b border-[#ededed] py-3.5">
              <div class="size-18 shrink-0 overflow-hidden rounded-2xl bg-surface">
                {p.photos[0] ? (
                  <img src={p.photos[0]} alt="" width={72} height={72} class="size-full object-cover" loading="lazy" />
                ) : (
                  <span class="grid size-full place-items-center text-2xl font-semibold text-grey-light">{p.name.charAt(0)}</span>
                )}
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex items-start gap-2">
                  <a href={`/p/${p.id}`} class="line-clamp-2 flex-1 font-semibold">
                    {p.name}
                  </a>
                  <button type="button" aria-label={`Remove ${p.name}`} class="-m-1 p-1" onClick={() => cart.setQty(lineKey(line), 0)}>
                    <Icon name="close" size={18} />
                  </button>
                </div>
                {options && <p class="text-xs text-grey-light">{options}</p>}
                <div class="mt-2 flex items-center justify-between">
                  <span class="font-semibold tabular-nums">{kwacha(p.priceZmw * line.qty)}</span>
                  <QtyStepper value={line.qty} label={p.name} onChange={(v) => cart.setQty(lineKey(line), v)} />
                </div>
              </div>
            </li>
          );
        })}
      </ul>
      {unavailable > 0 && (
        <p class="mt-2 text-sm text-sale">
          {unavailable} {unavailable === 1 ? "item is no longer available and won't" : "items are no longer available and won't"} be ordered.
        </p>
      )}

      <h2 class="display mt-7 mb-3 text-xl">Delivery information</h2>
      <div class="grid gap-3">
        <label class="grid gap-1">
          <span class="sr-only">Your name</span>
          <input id="name" class="field" placeholder="Your name" autocomplete="name" value={name} onInput={(e) => setName(e.currentTarget.value)} aria-invalid={!!errors.name} />
          {errors.name && <span class="text-sm text-sale">{errors.name}</span>}
        </label>
        <label class="grid gap-1">
          <span class="sr-only">Phone number</span>
          <input
            id="phone"
            class="field"
            type="tel"
            inputMode="tel"
            autocomplete="tel"
            placeholder="Phone number, e.g. 097 123 4567"
            value={phone}
            onInput={(e) => setPhone(e.currentTarget.value)}
            aria-invalid={!!errors.phone}
          />
          {errors.phone && <span class="text-sm text-sale">{errors.phone}</span>}
        </label>
        {settings.deliveryAreas.length > 0 && (
          <label class="grid gap-1">
            <span class="text-sm muted">Delivery</span>
            <select id="area" class="field" value={areaId ?? ''} onChange={(e) => setAreaId(e.currentTarget.value)}>
              {settings.deliveryAreas.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} · {a.feeZmw === 0 ? 'free' : kwacha(a.feeZmw)}
                </option>
              ))}
            </select>
          </label>
        )}
        <label class="grid gap-1">
          <span class="sr-only">Notes</span>
          <textarea id="notes" rows={2} class="field" placeholder="Notes (optional): landmark, best time to call…" value={notes} onInput={(e) => setNotes(e.currentTarget.value)} />
        </label>
      </div>

      <dl class="mt-7 grid gap-2 tabular-nums">
        <div class="flex justify-between">
          <dt>
            Total ({totals.units} {totals.units === 1 ? 'item' : 'items'})
          </dt>
          <dd class="font-semibold">{kwacha(totals.itemsZmw)}</dd>
        </div>
        <div class="flex justify-between">
          <dt>Delivery fee</dt>
          {/* No delivery areas set up means delivery is part of the price. */}
          <dd class="font-semibold">{settings.deliveryAreas.length ? kwacha(totals.deliveryZmw) : 'Included'}</dd>
        </div>
        <div class="display mt-2 flex justify-between border-t border-line pt-4 text-2xl">
          <dt>Total</dt>
          <dd>{kwacha(totals.totalZmw)}</dd>
        </div>
      </dl>
      {totals.depositZmw > 0 && (
        <p class="mt-3 flex gap-2.5 rounded-xl bg-surface p-3 text-sm">
          <Icon name="clock" size={20} class="shrink-0" />
          <span>
            Pre-order items need a {settings.depositPercent}% deposit of {kwacha(totals.depositZmw)}. We'll share payment details on WhatsApp.
          </span>
        </p>
      )}

      {errors.form && (
        <p role="alert" class="mt-4 text-sm text-sale">
          {errors.form}
        </p>
      )}
      <button type="submit" class="btn-primary mt-6" disabled={sending || priced.length === 0}>
        <Icon name="chat" size={20} />
        {sending ? 'Sending…' : 'Order on WhatsApp'}
      </button>
      <p class="mt-2 text-center text-xs muted">Opens WhatsApp with your order ready to send. Pay by mobile money or on delivery.</p>
    </form>
  );
}
