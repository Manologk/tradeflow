import { useEffect, useState } from 'preact/hooks';
import { CART_EVENT, cart } from './store';
import { Icon } from './Icon';

/** Cart button for the bottom bar, with a dot when the cart has items. */
export default function CartBadge() {
  const [count, setCount] = useState(0);
  useEffect(() => {
    const update = () => setCount(cart.count());
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
      <Icon name="bag" size={24} />
      {count > 0 && <span class="absolute top-2.5 right-2.5 size-2.5 rounded-full border-[1.5px] border-ink bg-brand" />}
    </a>
  );
}
