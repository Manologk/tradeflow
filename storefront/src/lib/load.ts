import { ShopNotConfigured } from './data';
import type { Catalog } from './models';
import { getShop } from './shop';

export type CatalogResult = { ok: true; catalog: Catalog } | { ok: false; kind: 'opening' | 'error' };

/** Loads the catalog for a page, turning failures into a friendly state. */
export async function loadCatalog(): Promise<CatalogResult> {
  try {
    return { ok: true, catalog: await getShop().loadCatalog() };
  } catch (e) {
    if (e instanceof ShopNotConfigured) return { ok: false, kind: 'opening' };
    console.error('Catalog load failed', e);
    return { ok: false, kind: 'error' };
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}
