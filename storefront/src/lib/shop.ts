import { getSecret } from 'astro:env/server';
import { cachedCatalog, notConfigured, type ShopData } from './data';
import { fixtureShop } from './fixtures';
import { supabaseShop } from './supabase';

let shop: ShopData | null = null;

/** The shop's data source for this server instance. */
export function getShop(): ShopData {
  if (shop) return shop;
  const mode = getSecret('SHOP_DATA');
  const url = getSecret('SUPABASE_URL');
  const key = getSecret('SUPABASE_ANON_KEY');
  if (mode === 'fixtures') shop = fixtureShop();
  else if (url && key) shop = cachedCatalog(supabaseShop(url, key));
  else shop = notConfigured;
  return shop;
}
