-- Keep the owner check out of the public API (it's only for policies).
create schema if not exists private;
grant usage on schema private to authenticated;
alter function public.is_shop_owner() set schema private;
