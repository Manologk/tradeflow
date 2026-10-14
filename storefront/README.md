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

The live Supabase address and its public (anon) key are in `wrangler.jsonc`. They are safe to publish:
row-level security limits that key to the published catalog and the two order functions. The
`service_role` key never goes in this repo or in the site.

| Name | Where | Value |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | `wrangler.jsonc` | Supabase project `tradeflow-shop` |
| `SHOP_DATA` | `.dev.vars` only | `fixtures` to use the test catalog |

Without shop settings in the database the site shows "Opening soon" instead of breaking.

## Database

Schema, security rules and order functions: [`../supabase/migrations`](../supabase/migrations).

## Deploy (free)

The site runs as a Cloudflare Worker (free plan: 100,000 requests a day, commercial use allowed).

1. Cloudflare dashboard → **Workers & Pages → Create → Import a repository** → pick this repo.
2. Root directory `storefront`, build command `npx -y npm@11.20.0 ci && npm run build`,
   deploy command `npx wrangler deploy`.
3. Choose the branch to publish. Every push to it redeploys.

The shop is served at **https://animeyay.kryptera.cc** (set in `wrangler.jsonc`).
