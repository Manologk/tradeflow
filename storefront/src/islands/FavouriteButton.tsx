import { useEffect, useState } from 'preact/hooks';
import { favourites } from './store';
import { Icon } from './Icon';

/** Dark round heart over product photos; remembered on this phone. */
export default function FavouriteButton({ productId, size = 32 }: { productId: string; size?: number }) {
  const [on, setOn] = useState(false);
  useEffect(() => setOn(favourites.get().includes(productId)), [productId]);
  return (
    <button
      type="button"
      class="grid place-items-center rounded-full bg-ink text-white"
      style={{ width: size, height: size }}
      aria-pressed={on}
      aria-label={on ? 'Remove from favourites' : 'Add to favourites'}
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        setOn(favourites.toggle(productId));
      }}
    >
      <Icon name="heart" size={Math.round(size * 0.55)} filled={on} />
    </button>
  );
}
