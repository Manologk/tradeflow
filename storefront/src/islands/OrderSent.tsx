import { useEffect, useState } from 'preact/hooks';
import { orderTotal } from '../lib/checkout';
import { kwacha } from '../lib/money';
import { Icon } from './Icon';
import { lastOrder } from './store';

/** "Send on WhatsApp" step and the order summary, right after ordering. */
export default function OrderSent({ code }: { code: string }) {
  const [state, setState] = useState<ReturnType<typeof lastOrder.get> | undefined>(undefined);
  useEffect(() => {
    const saved = lastOrder.get();
    setState(saved?.order.code === code ? saved : null);
  }, [code]);

  if (state === undefined) return null;
  const order = state?.order;

  return (
    <div class="px-6 pt-10 pb-10">
      <div class="mx-auto grid size-22 place-items-center rounded-full bg-ink text-white">
        <Icon name="check" size={44} />
      </div>
      <h1 class="mt-6 text-center text-2xl font-bold text-balance">{state ? 'One more step' : 'Order placed'}</h1>
      <p class="mt-2 text-center muted">
        Your order code is <strong class="text-ink-deep">{code}</strong>
      </p>

      {state && (
        <a href={state.whatsappUrl} target="_blank" rel="noopener" class="btn-primary mt-6">
          <Icon name="chat" size={20} /> Send on WhatsApp
        </a>
      )}

      <div class="mt-6 rounded-2xl bg-surface p-4">
        <h2 class="font-semibold">What happens next</h2>
        <ol class="mt-2 grid gap-2">
          {['Send the message in WhatsApp so we get your order.', 'We confirm availability and share payment details.', 'Track it any time under My orders.'].map((t, i) => (
            <li class="flex gap-2.5">
              <span class="grid size-5.5 shrink-0 place-items-center rounded-full bg-ink text-xs text-white">{i + 1}</span>
              <span>{t}</span>
            </li>
          ))}
        </ol>
        {state && !state.savedOnline && (
          <p class="mt-3 text-sm text-sale">Your connection dropped while saving, but your WhatsApp message has everything we need.</p>
        )}
      </div>

      {order && (
        <dl class="mt-5 grid gap-1.5 tabular-nums">
          {order.lines.map((l) => (
            <div class="flex justify-between gap-3">
              <dt>
                {l.qty} × {l.name}
              </dt>
              <dd>{kwacha(l.qty * l.unitPriceZmw)}</dd>
            </div>
          ))}
          <div class="mt-2 flex justify-between border-t border-line pt-3 font-bold">
            <dt>Total</dt>
            <dd>{kwacha(orderTotal(order))}</dd>
          </div>
        </dl>
      )}

      <a href="/" class="btn-outline mt-8">
        Back to shop
      </a>
    </div>
  );
}
