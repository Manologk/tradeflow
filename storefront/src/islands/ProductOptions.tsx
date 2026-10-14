import { useState } from 'preact/hooks';
import { kwacha } from '../lib/money';
import type { ShopColor } from '../lib/models';
import { Icon } from './Icon';
import { QtyStepper } from './QtyStepper';
import { cart } from './store';

interface Props {
  productId: string;
  name: string;
  priceZmw: number;
  compareAtZmw: number | null;
  sizes: string[];
  colors: ShopColor[];
  preOrder: boolean;
  canOrder: boolean;
}

/** Quantity, size and colour choice, and the Add to Cart bar. */
export default function ProductOptions(p: Props) {
  const [qty, setQty] = useState(1);
  const [size, setSize] = useState<string | null>(null);
  const [color, setColor] = useState<string | null>(null);
  const [message, setMessage] = useState<{ text: string; added: boolean } | null>(null);

  function add() {
    if (p.sizes.length && !size) return setMessage({ text: 'Choose a size', added: false });
    if (p.colors.length && !color) return setMessage({ text: 'Choose a colour', added: false });
    cart.add({ productId: p.productId, size, color, qty });
    setMessage({ text: `Added ${qty > 1 ? `${qty} × ` : ''}${p.name} to your cart`, added: true });
  }

  const onSale = p.compareAtZmw !== null && p.compareAtZmw > p.priceZmw;

  return (
    <>
      {p.canOrder && (
        <div class="flex items-center justify-between gap-3">
          <span class="text-sm font-semibold">Quantity</span>
          <QtyStepper value={qty} onChange={setQty} />
        </div>
      )}

      {(p.sizes.length > 0 || p.colors.length > 0) && (
        <div class="mt-6 flex flex-wrap justify-between gap-6 border-t border-line pt-6">
          {p.sizes.length > 0 && (
            <fieldset>
              <legend class="mb-3 text-sm font-semibold">Choose size</legend>
              <div class="flex flex-wrap gap-2">
                {p.sizes.map((s) => (
                  <button
                    key={s}
                    type="button"
                    aria-pressed={size === s}
                    aria-label={`Size ${s}`}
                    onClick={() => {
                      setSize(s);
                      setMessage(null);
                    }}
                    class={`grid h-10 min-w-10 place-items-center rounded-full border px-2 text-sm font-semibold ${
                      size === s ? 'border-brand bg-brand text-ink-deep' : 'border-line bg-white'
                    }`}
                  >
                    {s}
                  </button>
                ))}
              </div>
            </fieldset>
          )}
          {p.colors.length > 0 && (
            <fieldset>
              <legend class="mb-3 text-sm font-semibold">{color ? `Colour: ${color}` : 'Colour'}</legend>
              <div class="flex gap-2">
                {p.colors.map((c) => (
                  <button
                    key={c.name}
                    type="button"
                    title={c.name}
                    aria-pressed={color === c.name}
                    aria-label={`Colour ${c.name}`}
                    onClick={() => {
                      setColor(c.name);
                      setMessage(null);
                    }}
                    class={`grid size-10 place-items-center rounded-full border-2 ${color === c.name ? 'border-ink' : 'border-transparent'}`}
                  >
                    <span class="size-7 rounded-full border border-line" style={{ background: c.hex }} />
                  </button>
                ))}
              </div>
            </fieldset>
          )}
        </div>
      )}

      {/* Bottom bar: message sits above the button so it never hides it. */}
      <div class="fixed inset-x-0 bottom-0 z-20 bg-white/95 px-5 pt-3 pb-[max(16px,env(safe-area-inset-bottom))] backdrop-blur md:static md:mt-8 md:bg-transparent md:p-0 md:backdrop-blur-none">
        {message && (
          <div
            role="status"
            class={`mb-3 flex items-center justify-between gap-3 rounded-2xl px-4 py-3 text-sm ${message.added ? 'bg-ink text-white' : 'bg-surface text-ink-deep'}`}
          >
            <span>{message.text}</span>
            {message.added && (
              <a href="/cart" class="shrink-0 font-semibold underline underline-offset-2">
                View cart
              </a>
            )}
          </div>
        )}
        {p.canOrder ? (
          <button type="button" class="btn-primary" onClick={add}>
            <Icon name="cart" size={20} />
            <span>
              {p.preOrder ? 'Pre-order' : 'Add to Cart'} | {kwacha(p.priceZmw * qty)}
            </span>
            {onSale && <s class="text-xs font-normal text-white/70">{kwacha(p.compareAtZmw! * qty)}</s>}
          </button>
        ) : (
          <button type="button" class="btn-primary" disabled>
            Sold out
          </button>
        )}
      </div>
    </>
  );
}
