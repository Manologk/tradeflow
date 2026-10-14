# TradeFlow Storefront — Spec

> Status: agreed 2026-10-14. The Flutter app in this repo becomes the **admin**; this document covers the
> customer-facing **storefront** and the cloud link between them.

## 1. What it is

An online shop for **anime merch** (figures, plushies, keychains, clothing, posters, cosplay, accessories),
opened from a link shared on WhatsApp / Facebook / TikTok. Customers browse, add to cart and send the order on
WhatsApp. Every order lands in the admin app, so stock, profit and "owed to me" stay correct.

Design reference: Figma "ChicCraze – eCommerce Clothing Store App" (NAM Design Studio, community file
`wojX9Ap2c4oOxo0mcPPv87`). Its screens are flattened images, so they are rebuilt by eye using its style guide.

## 2. Decisions

| # | Topic | Decision |
|---|---|---|
| S1 | Role of existing app | Becomes the **admin**: stock, purchases, costs, sales, money, reports. Stays offline-first. |
| S2 | Platform | **Website first**: a plain, fast website (Astro, server-rendered, small Preact islands for cart/favourites). Mobile-first and responsive: 2 columns on phones, 3 on tablets, 4 on desktop; product page goes side-by-side on wide screens. Loads in well under half a megabyte. |
| S3 | Checkout | **WhatsApp order.** Cart → "Order on WhatsApp" opens a pre-filled message to the shop; the order is also saved online and pulled into the admin. Payment by mobile money or on delivery, recorded in the admin. |
| S4 | What's shown | **In stock + pre-order.** Pre-order items say "Pre-order · arrives in ~N weeks" (lead time set per product). |
| S5 | Accounts | **Guest checkout.** Name, phone, delivery area at checkout. "My orders" looks orders up by phone number + order code. |
| S6 | Hosting / cloud | **Free tiers:** Supabase (database, photo storage) + **Cloudflare Workers** (site and its small server functions; free plan allows commercial use, unlike Vercel's). Supabase's free project pauses after 7 days without traffic. |
| S7 | Ratings & reviews | **Dropped** from the template (fake numbers). Can return later as real reviews. |
| S8 | Browsing | Filter by **category** and by **anime series** (Naruto, One Piece, Demon Slayer, …), plus search. |
| S9 | Variants | Size / colour chips appear **only** for products that have variants (clothing). |

## 3. Visual language (Figma layout, AnimeYay branding)

- Brand: "Anime Yahh!" logo (black on orange) on the home banner; AY hexagon mark as the site icon.
- Fonts: **Bangers** for headings and prices (comic lettering, like the logo), **Barlow** for text (sporty,
  readable). Both OFL, bundled with the site.
- Colours: brand orange `#FD7312` (main buttons, selected chips and sizes, active menu item), deep orange
  `#B84500` for orange text on white, near-black `#121111`, warm surface `#F6F1EC`, grey `#787676`; white
  background.
- Shapes: large rounded product cards (~16–20px), pill buttons and chips, circular icon buttons, floating rounded
  bottom bar.
- Icons: Vuesax-style outline icons.
- Prices in **K** (ZMW). "Old price" struck through when a compare-at price is set.

## 4. Screens

From the design (adapted):
1. **Home / Shop** — greeting with shop name, search, filter button, category chips, 2-column product grid
   (photo, favourite heart, name, series, price, stock/pre-order badge), floating bottom bar
   (Home · Cart · Favourites · Orders).
2. **Product** — photo gallery, back & favourite, name, series, description with "Read more", quantity stepper,
   size/colour chips when the product has variants, availability line, "Add to Cart | K…" button.
3. **Cart / Checkout** — lines with quantity steppers and remove, delivery details (name, phone, area, notes),
   totals (items, delivery fee, discount, total), deposit note for pre-orders, **"Order on WhatsApp"** button.

Added in the same style:
4. **Order sent** — order code, summary, "We'll confirm on WhatsApp", button back to the shop.
5. **My orders** — enter phone number → list of orders with status (Received · Confirmed · Ready · Delivered).
6. **Browse** — categories and anime series as tiles.
7. **Favourites** — saved on the device (no account needed).
8. **Empty states** — empty cart, no results, nothing in favourites.

## 5. How data flows

```
 ADMIN APP (phone, offline-first)                 CLOUD (Supabase, free)              STOREFRONT (web)
 products, prices, photos, stock  ── publish ──▶  shop_products, shop_photos  ──read──▶  catalog
 pending sales / pre-orders       ◀── pull ────   shop_orders, shop_order_items ◀─write─  checkout
 order status updates             ── push ────▶   shop_orders.status          ──read──▶  my orders
```

- The admin **publishes** only shop-safe fields: name, description, category, series, photos, selling price,
  compare-at price, variants, availability (in stock / pre-order / sold out) and lead time.
  **Costs, suppliers, profit and money never leave the phone.**
- Stock is published as an availability label (and optionally a "few left" flag), not exact counts.
- The website reads the catalog on the server (cached ~60 s) and sends orders to its own `/api/orders`,
  which re-prices every line from the catalog before saving through a Supabase function, so a tampered cart
  can't change prices.
- Storefront orders are pulled into the admin as **pending sales/pre-orders** linked to a customer (by phone);
  confirming one in the admin works like any other sale (payments, deposit, delivered, profit).

## 6. Security

- Supabase Row Level Security:
  - Public (anonymous) can **read** published shop products only.
  - Public can **insert** orders, never read other people's orders; "My orders" goes through a function that needs
    phone + order code.
  - Only the shop owner (signed in from the admin app) can write products, read all orders and change status.
- The public key in the website is the Supabase *anon* key (safe to expose under RLS). The service key is never
  shipped in either app.

## 7. Admin changes needed

- Product: **selling price**, compare-at price, description, photos, category, anime series, published flag,
  pre-order allowed + lead time (weeks).
- "Shop" settings: shop name, WhatsApp number, delivery areas & fees, deposit % for pre-orders.
- Lists: categories and anime series (editable like other lists).
- Online orders inbox: new orders → confirm (creates sale/pre-order) or cancel; status updates sync back.
- Owner sign-in to Supabase (email + password) for publishing and pulling orders.

## 8. Milestones

| # | Milestone | Done when |
|---|---|---|
| S-M1 ✅ | Storefront UI behind a catalog/order interface | All screens built to the design; cart & WhatsApp message work (tested with test fixtures) |
| S-M2 ✅ | Supabase schema + RLS + storage | Catalog readable anonymously; orders insertable; security tests pass |
| S-M3 | Admin: shop fields, lists, publish to cloud | Products with photos appear on the site |
| S-M4 | Orders into admin | Website order shows in admin inbox; confirm creates sale; status visible in "My orders" |
| S-M5 | Deploy | Site live on Cloudflare with a shareable link |

## 9. Needed from the owner

- A free **Supabase** project (URL + anon key) — created under the owner's account.
- The shop **WhatsApp number**, shop **name/logo**, delivery areas and fees.
- Network access for `*.supabase.co` in the build environment when we reach S-M2.
