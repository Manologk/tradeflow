-- AnimeYay admin: remaining pieces to paste into Supabase → SQL Editor → Run.
-- Safe to run more than once.

drop function if exists public.admin_add_payment(text, bigint, text, text);
drop function if exists public.admin_delete_payment(bigint);
drop function if exists public.admin_set_stock(text, text, int, text);
drop function if exists public.admin_refresh_product(text);
drop function if exists public.admin_summary();

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


revoke execute on function public.admin_add_payment(text, bigint, text, text), public.admin_delete_payment(bigint),
  public.admin_set_stock(text, text, int, text), public.admin_refresh_product(text), public.admin_summary()
  from public, anon;
grant execute on function public.admin_add_payment(text, bigint, text, text), public.admin_delete_payment(bigint),
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
