import type { Catalog, Order, OrderStatus } from './models';

/** Thrown until the shop is connected to its online database. */
export class ShopNotConfigured extends Error {
  constructor() {
    super('The shop is not connected yet.');
  }
}

/** Where the shop reads its catalog and sends orders. */
export interface ShopData {
  loadCatalog(): Promise<Catalog>;
  /** Saves the order so it reaches the admin app. */
  submitOrder(order: Order): Promise<void>;
  /** Latest status of the given orders, only if they belong to this phone. */
  orderStatuses(codes: string[], phone: string): Promise<Record<string, OrderStatus>>;
}

export const notConfigured: ShopData = {
  loadCatalog: () => Promise.reject(new ShopNotConfigured()),
  submitOrder: () => Promise.reject(new ShopNotConfigured()),
  orderStatuses: () => Promise.reject(new ShopNotConfigured()),
};

/** Keeps the catalog for [ttlMs] so each page view doesn't hit the database. */
export function cachedCatalog(source: ShopData, ttlMs = 60_000, now: () => number = Date.now): ShopData {
  let cached: { at: number; value: Promise<Catalog> } | null = null;
  return {
    ...source,
    loadCatalog() {
      if (!cached || now() - cached.at > ttlMs) {
        const value = source.loadCatalog();
        cached = { at: now(), value };
        // Don't keep a failed load around.
        value.catch(() => {
          if (cached?.value === value) cached = null;
        });
      }
      return cached.value;
    },
  };
}
