import { useEffect, useRef, useState } from 'preact/hooks';
import { CART_EVENT, cart } from './store';
import { Icon } from './Icon';

/** Cart button for the bottom bar, with a dot when the cart has items. */
export default function CartBadge() {
  const [count, setCount] = useState(0);
  // Bumps each time something is added, to replay the bounce.
  const [bump, setBump] = useState(0);
  const last = useRef<number | null>(null);
  useEffect(() => {
    const update = () => {
      const next = cart.count();
      if (last.current !== null && next > last.current) setBump((b) => b + 1);
      last.current = next;
      setCount(next);
    };
    update();
    window.addEventListener(CART_EVENT, update);
    window.addEventListener('storage', update);
    return () => {
      window.removeEventListener(CART_EVENT, update);
      window.removeEventListener('storage', update);
    };
  }, []);
  return (
    <a href="/cart" class="relative grid size-12 place-items-center rounded-full text-white" aria-label={count ? `Cart, ${count} items` : 'Cart'}>
      <span key={bump} class={bump ? 'animate-pop' : ''}>
        <Icon name="bag" size={24} />
      </span>
      {count > 0 && <span key={`dot${bump}`} class="absolute top-2.5 right-2.5 size-2.5 animate-pop rounded-full border-[1.5px] border-ink bg-brand" />}
    </a>
  );
}
