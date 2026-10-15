-- Admin dashboard: stock per size, stock history, sales recorded in the shop,
-- and payments. Everything here is owner-only; the website's public key gets
-- nothing new except "which sizes are sold out".

-- Stock -----------------------------------------------------------------------

alter table public.shop_products
  -- Off: availability is set by hand (as at launch). On: it follows the stock.
  add column track_stock boolean not null default false,
  -- Sizes with no stock left, so the website can grey them out. Counts stay private.
  add column sold_out_sizes text[] not null default '{}';

create table public.shop_stock (
  product_id text not null references public.shop_products (id) on delete cascade,
  size text not null default '', -- '' for products without sizes
  qty int not null default 0 check (qty >= 0),
  primary key (product_id, size)
);

create table public.shop_stock_moves (
  id bigint generated always as identity primary key,
  product_id text not null references public.shop_products (id) on delete cascade,
  size text not null default '',
  delta int not null,
  reason text not null check (reason in ('restock', 'sale', 'cancel', 'correction')),
  order_code text,
  at timestamptz not null default now()
);
create index on public.shop_stock_moves (product_id, at desc);

-- Sales and payments ----------------------------------------------------------

alter table public.shop_orders
  add column source text not null default 'website' check (source in ('website', 'shop')),
  -- True once the order's items have been taken out of stock.
  add column stock_taken boolean not null default false,
  alter column phone drop not null; -- walk-in sales may have no number

create table public.shop_payments (
  id bigint generated always as identity primary key,
  order_code text not null references public.shop_orders (code) on delete cascade,
  amount_zmw bigint not null check (amount_zmw > 0),
  method text not null check (method in ('cash', 'mobile_money')),
  note text not null default '',
  paid_at timestamptz not null default now()
);
create index on public.shop_payments (order_code);
create index on public.shop_payments (paid_at);
create index on public.shop_orders (created_at desc);

alter table public.shop_stock enable row level security;
alter table public.shop_stock_moves enable row level security;
alter table public.shop_payments enable row level security;
create policy "owners read stock" on public.shop_stock for select to authenticated
  using ((select private.is_shop_owner()));
create policy "owners read stock moves" on public.shop_stock_moves for select to authenticated
  using ((select private.is_shop_owner()));
create policy "owners read payments" on public.shop_payments for select to authenticated
  using ((select private.is_shop_owner()));
revoke all on public.shop_stock, public.shop_stock_moves, public.shop_payments from anon;

-- Helpers (not callable through the API) --------------------------------------

create function private.require_owner() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_shop_owner() then raise exception 'Only the shop owner can do this' using errcode = '42501'; end if;
end;
$$;

-- Recomputes a stock-tracked product's availability and sold-out sizes.
create function private.refresh_product(p_id text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  p public.shop_products;
  total int;
  out_sizes text[];
begin
  select * into p from public.shop_products where id = p_id;
  if not found or not p.track_stock then return; end if;
  if cardinality(p.sizes) > 0 then
    select coalesce(sum(coalesce(st.qty, 0)), 0), coalesce(array_agg(sz) filter (where coalesce(st.qty, 0) = 0), '{}')
      into total, out_sizes
      from unnest(p.sizes) sz left join public.shop_stock st on st.product_id = p_id and st.size = sz;
  else
    select coalesce(sum(qty), 0) into total from public.shop_stock where product_id = p_id and size = '';
    out_sizes := '{}';
  end if;
  if p.availability = 'preOrder' then
    update public.shop_products set sold_out_sizes = '{}' where id = p_id;
  else
    update public.shop_products
      set sold_out_sizes = out_sizes,
          availability = case when total = 0 then 'soldOut' when total <= 2 then 'fewLeft' else 'inStock' end
      where id = p_id;
  end if;
end;
$$;

create function private.move_stock(p_product text, p_size text, p_delta int, p_reason text, p_order text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  have int;
  pname text;
begin
  if p_delta = 0 then return; end if;
  insert into public.shop_stock (product_id, size, qty) values (p_product, coalesce(p_size, ''), 0)
    on conflict do nothing;
  select qty into have from public.shop_stock where product_id = p_product and size = coalesce(p_size, '') for update;
  if have + p_delta < 0 then
    select name into pname from public.shop_products where id = p_product;
    raise exception 'Not enough stock: % % has % left', pname, coalesce(nullif(p_size, ''), ''), have
      using errcode = 'P0001';
  end if;
  update public.shop_stock set qty = qty + p_delta where product_id = p_product and size = coalesce(p_size, '');
  insert into public.shop_stock_moves (product_id, size, delta, reason, order_code)
    values (p_product, coalesce(p_size, ''), p_delta, p_reason, p_order);
  perform private.refresh_product(p_product);
end;
$$;

-- Takes an order's items out of stock (sign -1) or puts them back (+1).
-- Pre-order items and products without stock tracking are skipped.
create function private.order_stock(p_code text, p_sign int, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  it record;
begin
  for it in
    select i.product_id, coalesce(i.size, '') size, i.qty
    from public.shop_order_items i join public.shop_products p on p.id = i.product_id
    where i.order_code = p_code and not i.pre_order and p.track_stock
  loop
    perform private.move_stock(it.product_id, it.size, p_sign * it.qty, p_reason, p_code);
  end loop;
end;
$$;

create function private.new_order_code() returns text
language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := 'TF-' || (select string_agg(substr(alphabet, 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 4));
    exit when not exists (select 1 from public.shop_orders where code = c);
  end loop;
  return c;
end;
$$;

-- Owner actions (called from the admin dashboard) -----------------------------

-- Moves an order through received → confirmed → ready → delivered (or
-- cancelled), taking items out of stock on confirmation and back on cancel.
create function public.admin_set_order_status(p_code text, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  o public.shop_orders;
  takes boolean := p_status in ('confirmed', 'ready', 'delivered');
begin
  perform private.require_owner();
  select * into o from public.shop_orders where code = p_code for update;
  if not found then raise exception 'Order % not found', p_code; end if;
  if p_status not in ('received', 'confirmed', 'ready', 'delivered', 'cancelled') then
    raise exception 'Unknown status %', p_status;
  end if;
  if takes and not o.stock_taken then
    perform private.order_stock(p_code, -1, 'sale');
    update public.shop_orders set stock_taken = true where code = p_code;
  elsif not takes and o.stock_taken then
    perform private.order_stock(p_code, 1, 'cancel');
    update public.shop_orders set stock_taken = false where code = p_code;
  end if;
  update public.shop_orders set status = p_status, status_changed_at = now() where code = p_code;
end;
$$;

-- Records a sale made outside the website (WhatsApp, walk-in). Prices come
-- from the dashboard, so a discount can be given. Returns the new code.
-- sale: { customer: {name, phone?}, notes?, status: 'confirmed'|'delivered',
--         lines: [{productId, size?, qty, unitPriceZmw}],
--         payment?: {amountZmw, method} }
create function public.admin_record_sale(sale jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  c text := private.new_order_code();
  line jsonb;
  p public.shop_products;
  n smallint := 0;
  items bigint := 0;
  pay jsonb := sale -> 'payment';
  st text := coalesce(sale ->> 'status', 'delivered');
begin
  perform private.require_owner();
  if jsonb_typeof(sale -> 'lines') <> 'array' or jsonb_array_length(sale -> 'lines') = 0 then
    raise exception 'Add at least one item';
  end if;
  if st not in ('confirmed', 'ready', 'delivered') then raise exception 'Unknown status %', st; end if;

  insert into public.shop_orders (code, source, customer_name, phone, notes, items_zmw, delivery_zmw, deposit_zmw)
  values (c, 'shop', coalesce(nullif(btrim(sale -> 'customer' ->> 'name'), ''), 'Walk-in customer'),
          nullif(sale -> 'customer' ->> 'phone', ''), left(coalesce(sale ->> 'notes', ''), 300), 0, 0, 0);

  for line in select * from jsonb_array_elements(sale -> 'lines') loop
    n := n + 1;
    select * into p from public.shop_products where id = line ->> 'productId';
    if not found then raise exception 'Unknown product %', line ->> 'productId'; end if;
    insert into public.shop_order_items (order_code, line_no, product_id, name, size, color, qty,
                                         unit_price_zmw, pre_order, lead_time_weeks)
    values (c, n, p.id, p.name, nullif(line ->> 'size', ''), null, (line ->> 'qty')::int,
            coalesce((line ->> 'unitPriceZmw')::bigint, p.price_zmw), p.availability = 'preOrder', p.lead_time_weeks);
    items := items + (line ->> 'qty')::int * coalesce((line ->> 'unitPriceZmw')::bigint, p.price_zmw);
  end loop;
  update public.shop_orders set items_zmw = items where code = c;

  perform public.admin_set_order_status(c, st);
  if pay is not null and coalesce((pay ->> 'amountZmw')::bigint, 0) > 0 then
    insert into public.shop_payments (order_code, amount_zmw, method)
      values (c, (pay ->> 'amountZmw')::bigint, pay ->> 'method');
  end if;
  return c;
end;
$$;

create function public.admin_add_payment(p_code text, p_amount_zmw bigint, p_method text, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  insert into public.shop_payments (order_code, amount_zmw, method, note)
    values (p_code, p_amount_zmw, p_method, left(coalesce(p_note, ''), 200));
end;
$$;

create function public.admin_delete_payment(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  delete from public.shop_payments where id = p_id;
end;
$$;

-- Sets the count for one product/size (a stock take or a delivery from the
-- agent). Turns stock tracking on for the product.
create function public.admin_set_stock(p_product text, p_size text, p_qty int, p_reason text default 'correction')
returns void language plpgsql security definer set search_path = '' as $$
declare
  have int;
begin
  perform private.require_owner();
  if p_qty < 0 then raise exception 'Stock can''t be negative'; end if;
  update public.shop_products set track_stock = true where id = p_product and not track_stock;
  select coalesce((select qty from public.shop_stock where product_id = p_product and size = coalesce(p_size, '')), 0)
    into have;
  perform private.move_stock(p_product, coalesce(p_size, ''), p_qty - have, p_reason, null);
  perform private.refresh_product(p_product);
end;
$$;

-- Call after editing a product (sizes, pre-order, tracking) to update what
-- the website shows.
create function public.admin_refresh_product(p_id text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.shop_products set sold_out_sizes = '{}' where id = p_id and not track_stock;
  perform private.refresh_product(p_id);
end;
$$;

-- Numbers for the dashboard, in Zambian time.
create function public.admin_summary() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  tz constant text := 'Africa/Lusaka';
  today date := (now() at time zone tz)::date;
  result jsonb;
begin
  perform private.require_owner();
  with sales as (
    select o.code, (o.created_at at time zone tz)::date d, o.items_zmw + o.delivery_zmw total,
           coalesce((select sum(amount_zmw) from public.shop_payments p where p.order_code = o.code), 0) paid
    from public.shop_orders o where o.status in ('confirmed', 'ready', 'delivered')
  )
  select jsonb_build_object(
    'salesToday', coalesce((select sum(total) from sales where d = today), 0),
    'salesWeek', coalesce((select sum(total) from sales where d > today - 7), 0),
    'salesMonth', coalesce((select sum(total) from sales where d >= date_trunc('month', today)::date), 0),
    'ordersMonth', (select count(*) from sales where d >= date_trunc('month', today)::date),
    'receivedMonth', coalesce((select sum(amount_zmw) from public.shop_payments
                               where (paid_at at time zone tz)::date >= date_trunc('month', today)::date), 0),
    'owed', coalesce((select sum(total - paid) from sales where total > paid), 0),
    'newOrders', (select count(*) from public.shop_orders where status = 'received'),
    'toDeliver', (select count(*) from public.shop_orders where status in ('confirmed', 'ready')),
    'lowStock', coalesce((
      select jsonb_agg(jsonb_build_object('productId', p.id, 'name', p.name, 'size', nullif(st.size, ''), 'qty', st.qty)
                       order by st.qty, p.name)
      from public.shop_stock st join public.shop_products p on p.id = st.product_id
      where p.track_stock and st.qty <= 2 and (st.size = '' or st.size = any (p.sizes))), '[]'),
    'topSellers', coalesce((
      select jsonb_agg(t order by t.qty desc) from (
        select i.name, sum(i.qty)::int qty from public.shop_order_items i
        join sales s on s.code = i.order_code where s.d >= today - 30
        group by i.name order by sum(i.qty) desc limit 5) t), '[]')
  ) into result;
  return result;
end;
$$;

revoke execute on function private.require_owner(), private.refresh_product(text),
  private.move_stock(text, text, int, text, text), private.order_stock(text, int, text),
  private.new_order_code() from public, anon, authenticated;
revoke execute on function public.admin_set_order_status(text, text), public.admin_record_sale(jsonb),
  public.admin_add_payment(text, bigint, text, text), public.admin_delete_payment(bigint),
  public.admin_set_stock(text, text, int, text), public.admin_refresh_product(text), public.admin_summary()
  from public, anon;
grant execute on function public.admin_set_order_status(text, text), public.admin_record_sale(jsonb),
  public.admin_add_payment(text, bigint, text, text), public.admin_delete_payment(bigint),
  public.admin_set_stock(text, text, int, text), public.admin_refresh_product(text), public.admin_summary()
  to authenticated;

-- The website refuses sizes that have sold out ----------------------------------

create or replace function public.place_order("order" jsonb) returns void
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
    if nullif(line ->> 'size', '') = any (p.sold_out_sizes) then
      raise exception 'size % of % is sold out', line ->> 'size', p.name;
    end if;
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
