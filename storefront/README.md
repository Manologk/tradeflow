# TradeFlow Shop

The customer-facing website: browse anime merch, add to cart, order on WhatsApp. See
[../docs/STOREFRONT_SPEC.md](../docs/STOREFRONT_SPEC.md) for what it does and why.

Astro (server-rendered) + Preact islands + Tailwind, running on Cloudflare Pages, with the catalog and
orders in Supabase.

## Develop

Requires Node 22. Use npm 11 (npm 10 crashes on this lockfile).

```sh
npx -y npm@11.20.0 install
echo SHOP_DATA=fixtures > .dev.vars   # use the built-in test catalog, no Supabase needed
npm run dev
```

| Command | What it does |
|---|---|
| `npm run check` | Type-check |
| `npm test` | Unit tests (pricing, deposit, WhatsApp message) |
| `npm run test:e2e` | Builds the site and runs browser tests on a phone and a desktop screen, using the test catalog |
| `npm run build` | Production build into `dist/` |

## Settings

| Name | Where | Value |
|---|---|---|
| `SUPABASE_URL` | Cloudflare Pages → Settings → Variables and secrets | Supabase project URL |
| `SUPABASE_ANON_KEY` | same | Supabase **anon / public** key (never the `service_role` key) |
| `SHOP_DATA` | `.dev.vars` only | `fixtures` to use the test catalog; leave unset in production |

Without Supabase settings the site shows "Opening soon" instead of breaking.

## Deploy (free)

1. Cloudflare dashboard → Workers & Pages → Create → Pages → connect this GitHub repo.
2. Root directory `storefront`, build command `npx -y npm@11.20.0 ci && npm run build`, output `dist`.
3. Add the two Supabase settings above, then deploy. Every push to the chosen branch redeploys.
