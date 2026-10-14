import { describe, expect, it } from 'vitest';
import { buildOrder, depositFor, localPhone, newOrderCode, normalisePhone, priceLines, totalsFor, whatsappLink, whatsappMessage } from '../src/lib/checkout';
import { cachedCatalog, ShopNotConfigured, type ShopData } from '../src/lib/data';
import { supabaseShop } from '../src/lib/supabase';
import { testCatalog } from '../src/lib/fixtures';
import { kwacha } from '../src/lib/money';
import type { OrderLine } from '../src/lib/models';

const settings = testCatalog.settings;

describe('money', () => {
  it('formats kwacha', () => {
    expect(kwacha(45000)).toBe('K450');
    expect(kwacha(16299)).toBe('K162.99');
    expect(kwacha(123456700)).toBe('K1,234,567');
    expect(kwacha(-3000)).toBe('-K30');
  });
});

describe('checkout', () => {
  it('prices the cart from the catalog; sold-out and missing items drop out', () => {
    const lines = priceLines(
      [
        { productId: 'p1', size: null, color: null, qty: 2 },
        { productId: 'p2', size: 'L', color: 'Black', qty: 1 },
        { productId: 'p3', size: null, color: null, qty: 1 },
        { productId: 'gone', size: null, color: null, qty: 1 },
      ],
      testCatalog,
    );
    expect(lines.map((l) => [l.name, l.qty, l.qty * l.unitPriceZmw, l.preOrder])).toEqual([
      ['Naruto Sage Mode Figure', 2, 90000, false],
      ['Gojo Hoodie', 1, 38000, true],
    ]);
  });

  it('caps silly quantities', () => {
    const [line] = priceLines([{ productId: 'p1', size: null, color: null, qty: 5000.7 }], testCatalog);
    expect(line.qty).toBe(99);
  });

  it('totals with delivery and pre-order deposit', () => {
    const lines = priceLines(
      [
        { productId: 'p1', size: null, color: null, qty: 1 },
        { productId: 'p2', size: null, color: null, qty: 1 },
      ],
      testCatalog,
    );
    expect(totalsFor(lines, settings, 'cbd')).toEqual({
      itemsZmw: 83000,
      deliveryZmw: 3000,
      depositZmw: 19000,
      units: 2,
      totalZmw: 86000,
    });
  });

  it('rounds the deposit up to whole kwacha', () => {
    const line: OrderLine = {
      productId: 'x', name: 'x', size: null, color: null, qty: 1, unitPriceZmw: 3333, preOrder: true, leadTimeWeeks: null,
    };
    expect(depositFor([line], 50)).toBe(1700);
    expect(depositFor([line], 0)).toBe(0);
  });

  it('makes short unambiguous order codes', () => {
    let i = 0;
    const seq = [0, 0.5, 0.99, 0.2];
    expect(newOrderCode(() => seq[i++])).toMatch(/^TF-[A-HJ-NP-Z2-9]{4}$/);
  });

  it('normalises Zambian phone numbers', () => {
    expect(normalisePhone('097 123 4567')).toBe('260971234567');
    expect(normalisePhone('+260 96 1234567')).toBe('260961234567');
    expect(normalisePhone('771234567')).toBe('260771234567');
    expect(normalisePhone('12345')).toBeNull();
    expect(normalisePhone('0211234567')).toBeNull();
    expect(localPhone('260971234567')).toBe('097 123 4567');
  });

  it('writes a clear WhatsApp order', () => {
    const lines = priceLines(
      [
        { productId: 'p1', size: null, color: null, qty: 2 },
        { productId: 'p2', size: 'L', color: 'Black', qty: 1 },
      ],
      testCatalog,
    );
    const order = buildOrder({
      code: 'TF-7K3Q',
      now: new Date('2026-10-14T10:00:00Z'),
      customer: { name: 'Mwila', phone: '260971234567', areaId: 'cbd', notes: ' Call first ' },
      lines,
      settings,
    });
    expect(whatsappMessage(order, settings)).toBe(
      [
        "Hi Otaku Corner! I'd like to order (TF-7K3Q):",
        '',
        '• 2 × Naruto Sage Mode Figure: K900',
        '• 1 × Gojo Hoodie (Size L, Black) [Pre-order ~3 weeks]: K380',
        '',
        'Items: K1,280',
        'Delivery (Lusaka CBD): K30',
        'Total: K1,310',
        'Pre-order deposit (50%): K190',
        '',
        'Name: Mwila',
        'Phone: +260971234567',
        'Notes: Call first',
      ].join('\n'),
    );
    const link = new URL(whatsappLink(order, settings));
    expect(link.host).toBe('wa.me');
    expect(link.pathname).toBe('/260971234567');
    expect(link.searchParams.get('text')).toMatch(/^Hi Otaku Corner!/);
  });
});

describe('catalog cache', () => {
  it('reuses the catalog for a minute and retries after a failure', async () => {
    let calls = 0;
    let fail = true;
    let clock = 0;
    const source: ShopData = {
      loadCatalog: async () => {
        calls++;
        if (fail) throw new Error('down');
        return testCatalog;
      },
      submitOrder: async () => {},
      orderStatuses: async () => ({}),
    };
    const shop = cachedCatalog(source, 60_000, () => clock);
    await expect(shop.loadCatalog()).rejects.toThrow('down');
    fail = false;
    await shop.loadCatalog();
    await shop.loadCatalog();
    expect(calls).toBe(2);
    clock = 61_000;
    await shop.loadCatalog();
    expect(calls).toBe(3);
  });
});

describe('supabaseShop', () => {
  it('reports "not set up" until the shop settings exist', async () => {
    const fetchFn = (async () => new Response('[]', { status: 200 })) as typeof fetch;
    await expect(supabaseShop('https://x.supabase.co', 'key', fetchFn).loadCatalog()).rejects.toBeInstanceOf(
      ShopNotConfigured,
    );
  });
});
