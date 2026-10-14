# TradeFlow — Product Spec (MVP)

> Status: agreed through a decision interview, 2026-10-14. This is the blueprint for building the MVP.

## 1. The problem

A trader in Zambia buys goods on Chinese platforms (Taobao, Pinduoduo, 1688, Xianyu, WeChat sellers), pays in **CNY with a ZMW card**, ships through an **agent** who bills in **USD (paid in ZMW)**, collects the goods locally, and resells them for **cash or mobile money**.

Excel can't answer the questions that matter:

- What did each item **really** cost once it landed?
- Am I **actually making money**, per product, per platform, per sales channel?
- How much money is **stuck in transit**, **owed to me**, or **sitting in unsold stock**?
- Where did the money go?

TradeFlow is an offline Android app that answers these with as little typing as possible.

## 2. Decisions log

| # | Topic | Decision |
|---|---|---|
| 1 | Money truth | Every payment records the **actual ZMW debited**. CNY/USD amounts are reference only; the app derives the effective exchange rate. |
| 2 | Shipping cost basis | Agent charges **per kg by cargo type**: *General* and *Sensitive* (battery/liquid). Types are editable. Shipping for a cargo type is spread only over items of that type. |
| 3 | Agent bill data | Agent shows **tracking number, kg, amount**. Tracking numbers link bill lines to purchases. |
| 4 | Bill shape | Both **one-by-one** (line → 1 purchase) and **consolidated** (line → several purchases). One rule: *a shipping line covers 1+ purchases*. Multiple agents supported, each with default rates. |
| 5 | Other costs | Customs is included in the per-kg rate. **Transport** and **storage** are entered per collection and spread across what was collected. |
| 6 | Selling | **Stock sales + pre-orders + part payments** ("who owes me"). Sales channel and customer are optional tags; a customer is required only when money is owed. |
| 7 | Products | **Lightweight catalog**, created inline while logging a purchase. Optional variants. **Per-batch landed cost, FIFO** costing. |
| 8 | Expenses | Few categories: **Transport (collecting)**, **Delivery (to customers)**, **Transfer fees**, **Other**. Delivery can attach to a sale. |
| 9 | Money places | **Card, Mobile Money, Cash** by default (editable). No withdrawal logging; instead an **on-demand balance check** records gaps as *Taken out / unrecorded*. Transfers between places, with optional fee. |
| 10 | Home screen | Profit this month · Money in transit · Owed to you · Stock value + slow movers · Money now. Reports tab for product/platform/channel profit and exchange rates. |
| 11 | Platform | **Flutter**, Android first (iOS possible later), **local SQLite**, offline. Google Drive backup + manual export. Optional PIN/fingerprint lock (off by default). APK sideload first. |
| 11b | Future-proofing | Single user/store now; schema is **sync-ready** (store id, UUIDs, timestamps, soft delete, created-by). Future: multi-store SaaS, staff, offline-first cloud sync, admin dashboard. |
| 12 | Problem flows | Refund (with currency loss), lost parcel (+ compensation), damaged write-off, customer return, personal use/gift. |
| 13 | Starting data | **Fresh start** with opening stock and opening balances. No spreadsheet import. |

## 3. How money and goods flow

```
 BUY (China)                    SHIP                       COLLECT              SELL
 ┌──────────────┐  tracking no. ┌───────────────────┐      ┌─────────────┐     ┌──────────────┐
 │ Purchase     │──────────────▶│ Shipping bill     │─────▶│ Collection  │────▶│ Sale         │
 │ ¥ → K paid   │               │ (agent) $ → K paid│      │ transport,  │     │ stock or     │
 │ items, cargo │               │ lines → 1+ purch. │      │ storage     │     │ pre-order    │
 └──────────────┘               └───────────────────┘      └─────────────┘     │ payments     │
        │                                                        │             └──────────────┘
        └──────────────── status: in transit ───────────────────▶│ items enter stock (batches)
```

Purchase status: `ordered → shipped by seller → at agent → in transit → collected` (plus `refunded`, `lost`).
"Money in transit" = landed cost so far of every purchase not yet collected (or written off).

## 4. Costing rules

All money is stored as **integer minor units** (ngwee, fen, cents). Never floats.

### 4.1 Item purchase cost
A purchase has items with **CNY unit price × qty** and one **ZMW total actually charged** (which includes the seller's domestic shipping and card fees).
Each item's ZMW cost = ZMW total × (item CNY value ÷ purchase CNY total).
Effective rate shown = ZMW total ÷ CNY total.

### 4.2 Shipping allocation
A shipping bill has lines: `tracking no(s) · cargo type · kg · USD amount`, and the bill has a **ZMW amount actually paid** (spread over lines by USD amount).
For each line:
1. Take items in the linked purchases whose cargo type = the line's cargo type. If none match, use all items in those purchases.
2. Split the line's ZMW cost across those items **by item ZMW value**.

A one-by-one line is simply a line linked to one purchase. Multiple lines may link to the same purchase (e.g. order shipped as two parcels).

### 4.3 Collection costs
Transport and storage on a collection are split across **all items collected** by item ZMW value (purchase cost + shipping share).

### 4.4 Landed cost and stock
On collection, each item line becomes a **stock batch**: `product/variant · qty · landed cost per unit · date`.
Landed cost per unit = (purchase cost + shipping share + collection share) ÷ qty.

### 4.5 Cost of goods sold (FIFO)
A sale consumes the **oldest batches first**. COGS = sum of consumed units × their batch landed cost.

### 4.6 Derived, not frozen
Allocations, landed cost and FIFO consumption are **computed from source records**, not stored as hand-edited numbers. If a shipping bill or collection cost is entered or corrected late, landed costs and past COGS recompute automatically. (Results may be cached for speed, but the cache is rebuildable.)

### 4.7 Profit
```
Gross profit = Revenue (fulfilled sales, net of returns) − COGS
Net profit   = Gross profit − Expenses − Losses + Compensation
```
- **Losses**: write-offs (damaged, personal use, gift), lost parcels, currency loss on refunds.
- **Not in profit**: transfers, balance-check gaps (*Taken out / unrecorded*), opening balances, capital put in.

A sale's revenue and COGS are recognised when it is **fulfilled** (handed over). Deposits on pre-orders are just payments until then.

## 5. Data model

Every table has: `id (UUID)`, `store_id`, `created_at`, `updated_at`, `deleted_at (nullable)`, `created_by`.

| Entity | Key fields |
|---|---|
| **Store** | name, base currency (ZMW) |
| **MoneyPlace** | name (Card / Mobile Money / Cash), kind, opening balance, archived |
| **Lookup** | kind (platform / cargo type / channel / expense category), name, sort order, archived — one table for all short editable lists |
| **Agent** | name, contact, archived |
| **AgentRate** | agent_id, cargo_type_id, USD cents per kg |
| **Product** | name, notes, photo (optional), has_variants |
| **Variant** | product_id, label (e.g. "Black / XL") |
| **Purchase** | platform_id, seller name, order ref, date, cny_total, zmw_paid, money_place_id, status, pre_order_sale_id (optional) |
| **PurchaseItem** | purchase_id, product_id, variant_id, qty, cny_unit_price, cargo_type_id |
| **TrackingNumber** | purchase_id, number |
| **ShippingBill** | agent_id, date, usd_total, zmw_paid, money_place_id |
| **ShippingLine** | bill_id, cargo_type_id, weight_grams, usd_amount |
| **ShippingLinePurchase** | line_id, purchase_id |
| **Collection** | date, transport_zmw, storage_zmw, money_place_id |
| **CollectionPurchase** | collection_id, purchase_id |
| **StockBatch** *(derived)* | purchase_item_id, qty, landed_unit_cost, received_at |
| **Customer** | name, phone |
| **Sale** | date, customer_id?, channel_id?, kind (stock / pre-order), status (pending / fulfilled / returned), total_zmw |
| **SaleItem** | sale_id, product_id, variant_id, qty, unit_price_zmw |
| **Payment** | sale_id, date, amount_zmw, money_place_id |
| **Expense** | date, category, amount_zmw, money_place_id, sale_id? , note |
| **Adjustment** | kind (write-off / lost / return / refund / compensation / currency-loss), reason, refs (purchase, sale, product, batch), qty, amount_zmw, money_place_id? |
| **Transfer** | from_place, to_place, amount_zmw, fee_zmw |
| **BalanceCheck** | date, money_place_id, actual_zmw, expected_zmw, gap_zmw, gap_label (unrecorded / personal / forgot expense) |
| **OpeningStockItem** | product_id, variant_id?, qty, unit_cost_zmw (opening balances live on MoneyPlace) |

**Money place balance** = opening + payments in − payments out ± transfers − fees + refunds/compensation − balance-check gaps.

## 6. Screens

Bottom navigation: **Home · Buy · Sell · Money · Reports**. A single **＋** button opens quick actions (New purchase, Shipping bill, Collect, New sale, Expense, Transfer).

| Screen | Purpose |
|---|---|
| **Home** | The five tiles (see §7). Each tile drills into its list. "Balances last checked N days ago" link. |
| **Buy → Purchases** | List grouped by status; search by product, seller or tracking no. |
| **New purchase** | Platform, seller, date, items (type product name → creates product inline; qty; ¥ price; cargo type), ¥ total auto-sums, **K actually charged**, paid from, tracking no(s) (optional, addable later), link to pre-order (optional). Shows effective rate. |
| **Shipping bill** | Agent, add lines: paste/type tracking no → auto-matches purchase(s); cargo type; kg; $ amount (rate pre-filled from agent default). For consolidated lines, tick purchases. $ total → **K actually paid**. |
| **Collect** | Tick arrived purchases (pre-selected: those on a paid bill), transport, storage, paid from. Confirms → stock updated. |
| **Products / Stock** | Product list with stock qty, avg landed cost, days since last sale. Product detail: batches, sales history, profit, loss rate. |
| **Sell → New sale** | Pick products (shows stock + landed cost + suggested margin), price, customer (optional), channel (optional), payment amount + place (partial allowed). Toggle **pre-order** for items not in stock. Optional delivery cost. |
| **Sell → Owed to me** | Customers with balances, oldest first; record payment in one tap. |
| **Sell → Pre-orders** | Pending pre-orders with linked purchase status. |
| **Money** | Balance per place; transactions list; Transfer; Expense; **Balance check** (enter actual per place → gap recorded). |
| **Reports** | Profit by month · by product · by platform · by channel · exchange-rate history (¥→K, $→K) · losses. Period picker. |
| **Problem actions** | On a purchase: *Refund*, *Mark lost*. On stock: *Write off* (damaged / personal / gift). On a sale: *Return* (restock or write off). |
| **Settings** | Money places, platforms, agents & rates, cargo types, channels, expense categories, backup/export, app lock, opening balances & stock. |
| **First run** | Name store → money places + opening balances → opening stock (optional, skippable) → done. |

## 7. Home screen

1. **Profit this month** — net profit, with last month for comparison.
2. **Money in transit** — "K4,320 in 6 parcels · oldest bought 34 days ago". Highlights purchases older than a threshold (default 30 days).
3. **Owed to you** — total and oldest debt.
4. **Stock value** — cost of unsold goods; count of items unsold 60+ days.
5. **Money now** — balance per place.

## 8. Technical architecture (MVP)

- **Flutter** (Android target; iOS later from the same code).
- **SQLite via Drift** — typed schema, migrations, reactive queries.
- **Riverpod** for state.
- Money as `int` minor units; a small `Money` value type with currency.
- **Costing engine** as pure Dart functions (purchase allocation, shipping allocation, collection allocation, FIFO), fully unit-tested — it is the heart of the app.
- **Backup**: Google Drive `appDataFolder` (google_sign_in + googleapis), automatic daily/after-changes; manual export of the DB file via share sheet; CSV export of sales, purchases, expenses.
- **Lock**: `local_auth` (fingerprint/PIN), optional.
- **Distribution**: release APK built in CI and attached to GitHub Releases.
- **Sync-ready schema** per §5; later sync target on a free tier (e.g. Supabase/Firebase) with last-write-wins per record + soft deletes.

## 9. Scope

### MVP
Everything in §2–§8 for a single user and single store.

### Later
- Multi-store accounts, staff users and roles
- Cloud sync (offline-first) and web admin dashboard
- iOS build, Play Store listing
- Import from spreadsheets, receipt/photo attachments, price suggestions, low-stock alerts

## 10. Build milestones

| # | Milestone | Done when |
|---|---|---|
| M1 | Project setup, schema, settings & first run | App installs, money places/opening balances saved |
| M2 | Purchases & products | Log a purchase with items; products created inline; effective rate shown |
| M3 | Shipping bills & collections + costing engine | Landed cost per batch correct for one-by-one and consolidated bills (unit-tested) |
| M4 | Sales, pre-orders, payments, owed list | FIFO COGS and profit per sale correct |
| M5 | Money: transfers, expenses, balance check | Place balances match ledger; gaps recorded |
| M6 | Problem flows | Refund, lost, write-off, return all reflected in profit and stock |
| M7 | Home & Reports | Five tiles and four reports live |
| M8 | Backup, export, lock, APK release | Restore on a second phone works |

## 11. Open details (decide during build)
- Default agent rates (USD/kg) per cargo type — user to supply.
- Threshold for "old in transit" (default 30 days) and "slow mover" (default 60 days).
- App name: **TradeFlow** (working name).
