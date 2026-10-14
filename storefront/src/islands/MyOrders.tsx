import { useEffect, useState } from 'preact/hooks';
import { kwacha } from '../lib/money';
import type { OrderStatus } from '../lib/models';
import { Icon } from './Icon';
import { placedOrders, type PlacedOrder } from './store';

const labels: Record<OrderStatus, string> = {
  received: 'Received',
  confirmed: 'Confirmed',
  ready: 'Ready',
  delivered: 'Delivered',
  cancelled: 'Cancelled',
};

const date = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

/** Orders placed from this phone, with their latest status. */
export default function MyOrders() {
  const [orders, setOrders] = useState<PlacedOrder[] | null>(null);
  const [statuses, setStatuses] = useState<Record<string, OrderStatus>>({});
  const [checking, setChecking] = useState(false);
  const [failed, setFailed] = useState(false);

  async function refresh(list: PlacedOrder[]) {
    if (list.length === 0) return;
    setChecking(true);
    setFailed(false);
    try {
      const byPhone = new Map<string, string[]>();
      for (const o of list) byPhone.set(o.phone, [...(byPhone.get(o.phone) ?? []), o.code]);
      const results: Record<string, OrderStatus> = {};
      for (const [phone, codes] of byPhone) {
        const res = await fetch('/api/order-status', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phone, codes }),
        });
        if (!res.ok) throw new Error(String(res.status));
        Object.assign(results, await res.json());
      }
      setStatuses(results);
    } catch {
      setFailed(true);
    } finally {
      setChecking(false);
    }
  }

  useEffect(() => {
    const list = placedOrders.get();
    setOrders(list);
    void refresh(list);
  }, []);

  if (orders === null) return null;
  if (orders.length === 0) {
    return (
      <div class="flex flex-col items-center px-8 py-24 text-center">
        <div class="grid size-18 place-items-center rounded-full bg-surface text-grey">
          <Icon name="receipt" size={32} />
        </div>
        <h2 class="display mt-4 text-2xl">No orders yet</h2>
        <p class="mt-2 muted">Orders you place from this phone show up here.</p>
        <a href="/" class="btn-primary mt-6 max-w-56">
          Start shopping
        </a>
      </div>
    );
  }

  return (
    <div class="grid gap-3">
      {orders.map((o) => {
        const status = statuses[o.code];
        const dark = status === 'ready' || status === 'delivered';
        return (
          <div key={o.code} class="flex items-center gap-3 rounded-2xl border border-[#ededed] p-4">
            <div class="min-w-0 flex-1">
              <p class="display text-xl">{o.code}</p>
              <p class="text-sm muted tabular-nums">
                {date.format(new Date(o.createdAt))} · {o.units} {o.units === 1 ? 'item' : 'items'} · {kwacha(o.totalZmw)}
              </p>
            </div>
            <span class={`rounded-full px-3 py-1.5 text-[13px] font-semibold ${dark ? 'bg-ink text-white' : 'bg-surface'}`}>
              {status ? labels[status] : checking ? 'Checking…' : 'Sent'}
            </span>
          </div>
        );
      })}
      {failed && (
        <p class="text-sm muted">
          Couldn't check the latest status.{' '}
          <button type="button" class="font-semibold underline" onClick={() => refresh(orders)}>
            Try again
          </button>
        </p>
      )}
    </div>
  );
}
