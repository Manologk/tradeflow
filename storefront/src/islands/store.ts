import { lineKey, type CartLine, type Order } from '../lib/models';

// Everything the shop remembers lives in this browser only. Storage can be
// unavailable (private mode, blocked site data), so every access is guarded
// and the shop still works, just without memory.

function read<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function write(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage full or blocked: keep going without saving.
  }
}

export const CART_EVENT = 'shop:cart';

export const cart = {
  get: (): CartLine[] => read<CartLine[]>('cart', []),
  set(lines: CartLine[]) {
    write('cart', lines);
    window.dispatchEvent(new Event(CART_EVENT));
  },
  add(line: CartLine) {
    const lines = cart.get();
    const existing = lines.find((l) => lineKey(l) === lineKey(line));
    if (existing) existing.qty = Math.min(99, existing.qty + line.qty);
    else lines.push(line);
    cart.set(lines);
  },
  setQty(key: string, qty: number) {
    cart.set(cart.get().flatMap((l) => (lineKey(l) !== key ? [l] : qty > 0 ? [{ ...l, qty }] : [])));
  },
  count: () => cart.get().reduce((s, l) => s + l.qty, 0),
};

export const favourites = {
  get: (): string[] => read<string[]>('favourites', []),
  toggle(id: string): boolean {
    const ids = favourites.get();
    const on = !ids.includes(id);
    write('favourites', on ? [...ids, id] : ids.filter((x) => x !== id));
    return on;
  },
};

export interface PlacedOrder {
  code: string;
  phone: string;
  createdAt: string;
  totalZmw: number;
  units: number;
}

export const placedOrders = {
  get: (): PlacedOrder[] => read<PlacedOrder[]>('orders', []),
  add(order: Order) {
    const entry: PlacedOrder = {
      code: order.code,
      phone: order.customer.phone,
      createdAt: order.createdAt,
      totalZmw: order.itemsZmw + order.deliveryZmw,
      units: order.lines.reduce((s, l) => s + l.qty, 0),
    };
    write('orders', [entry, ...placedOrders.get()].slice(0, 50));
  },
};

export interface SavedCustomer {
  name: string;
  phone: string;
  areaId: string | null;
}

export const savedCustomer = {
  get: () => read<SavedCustomer>('customer', { name: '', phone: '', areaId: null }),
  set: (c: SavedCustomer) => write('customer', c),
};

/** The last order, kept for the "order sent" page (this tab only). */
export const lastOrder = {
  get(): { order: Order; whatsappUrl: string; savedOnline: boolean } | null {
    try {
      const raw = sessionStorage.getItem('lastOrder');
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  },
  set(value: { order: Order; whatsappUrl: string; savedOnline: boolean }) {
    try {
      sessionStorage.setItem('lastOrder', JSON.stringify(value));
    } catch {
      // Not critical: the page falls back to showing just the code.
    }
  },
};
