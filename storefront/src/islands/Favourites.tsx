import { useEffect, useState } from 'preact/hooks';
import { kwacha } from '../lib/money';
import type { ShopProduct } from '../lib/models';
import { Icon } from './Icon';
import FavouriteButton from './FavouriteButton';
import { favourites } from './store';

type Slim = Pick<ShopProduct, 'id' | 'name' | 'priceZmw' | 'photos' | 'availability'>;

/** Products saved with the heart on this phone. */
export default function Favourites({ products }: { products: Slim[] }) {
  const [ids, setIds] = useState<string[] | null>(null);
  useEffect(() => setIds(favourites.get()), []);
  if (ids === null) return null;
  const list = products.filter((p) => ids.includes(p.id));
  if (list.length === 0) {
    return (
      <div class="flex flex-col items-center px-8 py-24 text-center">
        <div class="grid size-18 place-items-center rounded-full bg-surface text-grey">
          <Icon name="heart" size={32} />
        </div>
        <h2 class="display mt-4 text-2xl">No favourites yet</h2>
        <p class="mt-2 muted">Tap the heart on anything you like to save it here.</p>
      </div>
    );
  }
  return (
    <ul class="grid grid-cols-2 gap-x-4 gap-y-5 sm:grid-cols-3 lg:grid-cols-4 lg:gap-x-6">
      {list.map((p) => (
        <li key={p.id}>
          <a href={`/p/${p.id}`} class="block">
            <div class="relative aspect-[0.82] overflow-hidden rounded-[20px] bg-surface">
              {p.photos[0] ? (
                <img src={p.photos[0]} alt="" class="size-full object-cover" loading="lazy" />
              ) : (
                <span class="grid size-full place-items-center text-4xl font-semibold text-grey-light">{p.name.charAt(0)}</span>
              )}
              <span class="absolute top-2.5 right-2.5">
                <FavouriteButton productId={p.id} />
              </span>
            </div>
            <p class="mt-2.5 line-clamp-2 font-semibold">{p.name}</p>
            <p class="mt-1 font-semibold tabular-nums">{kwacha(p.priceZmw)}</p>
          </a>
        </li>
      ))}
    </ul>
  );
}
