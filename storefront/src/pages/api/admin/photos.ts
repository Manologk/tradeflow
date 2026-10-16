import type { APIRoute } from 'astro';
import { AdminError } from '../../../lib/admin/types';
import { json } from '../../../lib/load';

const TYPES = new Set(['image/webp', 'image/jpeg', 'image/png']);
const MAX_BYTES = 2 * 1024 * 1024;

/** Stores one (already shrunk) photo and adds it to the product. */
export const POST: APIRoute = async ({ request, url, locals }) => {
  const admin = locals.admin!;
  const productId = url.searchParams.get('product') ?? '';
  const type = (request.headers.get('Content-Type') ?? '').split(';')[0];
  if (!TYPES.has(type)) return json({ error: 'Use a JPEG, PNG or WebP photo' }, 415);
  const data = await request.arrayBuffer();
  if (data.byteLength === 0 || data.byteLength > MAX_BYTES) return json({ error: 'Photo is too large' }, 413);

  try {
    const p = await admin.product(productId);
    if (!p) return json({ error: 'Product not found' }, 404);
    const photoUrl = await admin.uploadPhoto(productId, data, type);
    const { id, name, description, categoryId, seriesId, priceZmw, compareAtZmw, sizes, availability, leadTimeWeeks, published } = p;
    await admin.saveProduct({
      id, name, description, categoryId, seriesId, priceZmw, compareAtZmw, sizes, availability, leadTimeWeeks, published,
      photos: [...p.photos, photoUrl].slice(0, 12),
    });
    return json({ url: photoUrl });
  } catch (e) {
    return json({ error: e instanceof AdminError ? e.message : 'Upload failed. Try again.' }, 502);
  }
};
