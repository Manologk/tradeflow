-- TradeFlow shop: the public catalog the admin app publishes, and the orders
-- the website sends. Money is integer ngwee (K1 = 100).
--
-- Who can do what:
--   anon (the website)   read published catalog rows; place orders and read
--                        statuses only through the two functions below
--   shop owners          everything (the admin app signs in as an owner)

create table public.shop_owners (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create function public.is_shop_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.shop_owners where user_id = (select auth.uid()));
$$;

create table public.shop_settings (
  id smallint primary key default 1 check (id = 1),
  name text not null,
  whatsapp_number text not null check (whatsapp_number ~ '^260[79][0-9]{8}$'),
  deposit_percent smallint not null default 50 check (deposit_percent between 0 and 100),
  logo_url text,
  -- [{ "id": "cbd", "name": "Lusaka CBD", "fee_zmw": 3000 }]
  delivery_areas jsonb not null default '[]' check (jsonb_typeof(delivery_areas) = 'array'),
  updated_at timestamptz not null default now()
);

create table public.shop_categories (
  id text primary key,
  name text not null,
  sort_order int not null default 0
);

create table public.shop_series (
  id text primary key,
  name text not null,
  image_url text,
  sort_order int not null default 0
);

create table public.shop_products (
  id text primary key,
  name text not null,
  description text,
  category_id text not null references public.shop_categories (id),
  series_id text references public.shop_series (id),
  price_zmw bigint not null check (price_zmw > 0),
  compare_at_zmw bigint check (compare_at_zmw > 0),
  photos text[] not null default '{}',
  sizes text[] not null default '{}',
  -- [{ "name": "Black", "hex": "#121111" }]
  colors jsonb not null default '[]' check (jsonb_typeof(colors) = 'array'),
  availability text not null default 'inStock'
    check (availability in ('inStock', 'fewLeft', 'preOrder', 'soldOut')),
  lead_time_weeks smallint check (lead_time_weeks > 0),
  sort_order int not null default 0,
  published boolean not null default true,
  updated_at timestamptz not null default now()
);
create index on public.shop_products (category_id);
create index on public.shop_products (series_id);

create table public.shop_orders (
  code text primary key check (code ~ '^TF-[A-Z0-9]{4}$'),
  created_at timestamptz not null default now(),
  customer_name text not null,
  phone text not null check (phone ~ '^260[79][0-9]{8}$'),
  area_id text,
  area_name text,
  notes text not null default '',
  items_zmw bigint not null,
  delivery_zmw bigint not null,
  deposit_zmw bigint not null,
  status text not null default 'received'
    check (status in ('received', 'confirmed', 'ready', 'delivered', 'cancelled')),
  status_changed_at timestamptz not null default now()
);
create index on public.shop_orders (phone);

create table public.shop_order_items (
  order_code text not null references public.shop_orders (code) on delete cascade,
  line_no smallint not null,
  product_id text not null,
  name text not null,
  size text,
  color text,
  qty smallint not null check (qty between 1 and 99),
  unit_price_zmw bigint not null,
  pre_order boolean not null,
  lead_time_weeks smallint,
  primary key (order_code, line_no)
);

-- Row Level Security ---------------------------------------------------------

alter table public.shop_owners enable row level security;
alter table public.shop_settings enable row level security;
alter table public.shop_categories enable row level security;
alter table public.shop_series enable row level security;
alter table public.shop_products enable row level security;
alter table public.shop_orders enable row level security;
alter table public.shop_order_items enable row level security;

create policy "owners see themselves" on public.shop_owners
  for select to authenticated using (user_id = (select auth.uid()));

create policy "public reads settings" on public.shop_settings for select to anon, authenticated using (true);
create policy "public reads categories" on public.shop_categories for select to anon, authenticated using (true);
create policy "public reads series" on public.shop_series for select to anon, authenticated using (true);
create policy "public reads published products" on public.shop_products
  for select to anon, authenticated using (published);

create policy "owners write settings" on public.shop_settings for all to authenticated
  using ((select public.is_shop_owner())) with check ((select public.is_shop_owner()));
create policy "owners write categories" on public.shop_categories for all to authenticated
  using ((select public.is_shop_owner())) with check ((select public.is_shop_owner()));
create policy "owners write series" on public.shop_series for all to authenticated
  using ((select public.is_shop_owner())) with check ((select public.is_shop_owner()));
create policy "owners write products" on public.shop_products for all to authenticated
  using ((select public.is_shop_owner())) with check ((select public.is_shop_owner()));
create policy "owners manage orders" on public.shop_orders for all to authenticated
  using ((select public.is_shop_owner())) with check ((select public.is_shop_owner()));
create policy "owners manage order items" on public.shop_order_items for all to authenticated
  using ((select public.is_shop_owner())) with check ((select public.is_shop_owner()));

-- The website's key can only read; writes go through the functions below.
revoke insert, update, delete, truncate on all tables in schema public from anon;
revoke all on public.shop_orders, public.shop_order_items, public.shop_owners from anon;

-- Placing an order -------------------------------------------------------------
-- Called by the website's server after it has priced the cart. The anon key is
-- public, so this re-checks every price against the catalog: an order with a
-- made-up price is refused.

create function public.place_order("order" jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  s public.shop_settings;
  line jsonb;
  p public.shop_products;
  n smallint := 0;
  items bigint := 0;
  pre_value bigint := 0;
  v_qty int;
  delivery bigint := 0;
  v_area text := nullif("order" -> 'customer' ->> 'areaId', '');
  min_deposit bigint;
begin
  select * into s from public.shop_settings where id = 1;
  if not found then raise exception 'shop not set up'; end if;
  if jsonb_typeof("order" -> 'lines') <> 'array'
     or jsonb_array_length("order" -> 'lines') not between 1 and 50 then
    raise exception 'invalid order lines';
  end if;

  if v_area is not null then
    select (a ->> 'fee_zmw')::bigint into delivery
      from jsonb_array_elements(s.delivery_areas) a where a ->> 'id' = v_area;
    if not found then raise exception 'unknown delivery area'; end if;
  end if;

  insert into public.shop_orders (code, customer_name, phone, area_id, area_name, notes,
                                  items_zmw, delivery_zmw, deposit_zmw)
  values ("order" ->> 'code',
          left(btrim("order" -> 'customer' ->> 'name'), 80),
          "order" -> 'customer' ->> 'phone',
          v_area,
          (select a ->> 'name' from jsonb_array_elements(s.delivery_areas) a where a ->> 'id' = v_area),
          left(coalesce("order" -> 'customer' ->> 'notes', ''), 300),
          ("order" ->> 'itemsZmw')::bigint,
          coalesce(delivery, 0),
          ("order" ->> 'depositZmw')::bigint);

  for line in select * from jsonb_array_elements("order" -> 'lines') loop
    n := n + 1;
    select * into p from public.shop_products
      where id = line ->> 'productId' and published and availability <> 'soldOut';
    if not found then raise exception 'product % not available', line ->> 'productId'; end if;
    v_qty := (line ->> 'qty')::int;
    if v_qty not between 1 and 99 or (line ->> 'unitPriceZmw')::bigint <> p.price_zmw then
      raise exception 'line % does not match the catalog', n;
    end if;
    items := items + v_qty * p.price_zmw;
    if p.availability = 'preOrder' then pre_value := pre_value + v_qty * p.price_zmw; end if;
    insert into public.shop_order_items (order_code, line_no, product_id, name, size, color, qty,
                                         unit_price_zmw, pre_order, lead_time_weeks)
    values ("order" ->> 'code', n, p.id, p.name,
            left(nullif(line ->> 'size', ''), 16), left(nullif(line ->> 'color', ''), 32),
            v_qty, p.price_zmw, p.availability = 'preOrder', p.lead_time_weeks);
  end loop;

  if items <> ("order" ->> 'itemsZmw')::bigint then raise exception 'items total does not match'; end if;
  min_deposit := ceil(pre_value * s.deposit_percent / 100.0);
  if ("order" ->> 'depositZmw')::bigint not between min_deposit and min_deposit + 99 then
    raise exception 'deposit does not match';
  end if;
end;
$$;

-- Order statuses for "My orders": only for codes that belong to that phone.
create function public.order_statuses(codes text[], phone text)
returns table (code text, status text)
language sql stable security definer set search_path = '' as $$
  select o.code, o.status from public.shop_orders o
  where o.code = any (codes[1:50]) and o.phone = order_statuses.phone;
$$;

revoke execute on function public.place_order(jsonb), public.order_statuses(text[], text),
  public.is_shop_owner() from public, anon, authenticated;
grant execute on function public.place_order(jsonb), public.order_statuses(text[], text) to anon, authenticated;
grant execute on function public.is_shop_owner() to authenticated;

-- Product photos: public to read, only owners upload ---------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('shop-photos', 'shop-photos', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']);

create policy "owners upload shop photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'shop-photos' and (select public.is_shop_owner()));
create policy "owners change shop photos" on storage.objects for update to authenticated
  using (bucket_id = 'shop-photos' and (select public.is_shop_owner()));
create policy "owners delete shop photos" on storage.objects for delete to authenticated
  using (bucket_id = 'shop-photos' and (select public.is_shop_owner()));
