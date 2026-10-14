-- AnimeYay launch catalog (2026-10-14). Prices in ngwee (K250 = 25000).
-- Delivery is included in prices for now, and there is no pre-order deposit.
-- Re-runnable: updates rows that already exist.

insert into public.shop_settings (id, name, whatsapp_number, deposit_percent, delivery_areas)
values (1, 'AnimeYay', '260978288892', 0, '[]')
on conflict (id) do update set name = excluded.name, whatsapp_number = excluded.whatsapp_number,
  deposit_percent = excluded.deposit_percent, delivery_areas = excluded.delivery_areas, updated_at = now();

insert into public.shop_categories (id, name, sort_order) values
  ('jerseys', 'Jerseys & Shirts', 1),
  ('figures', 'Figures', 2),
  ('accessories', 'Accessories', 3),
  ('footwear', 'Footwear', 4)
on conflict (id) do update set name = excluded.name, sort_order = excluded.sort_order;

insert into public.shop_series (id, name, image_url, sort_order) values
  ('demon-slayer', 'Demon Slayer', '/products/nezuko-jersey.webp', 1),
  ('jujutsu-kaisen', 'Jujutsu Kaisen', '/products/gojo-jersey.webp', 2),
  ('one-piece', 'One Piece', '/products/luffy-jersey.webp', 3),
  ('dragon-ball', 'Dragon Ball', '/products/goku-jersey.webp', 4),
  ('attack-on-titan', 'Attack on Titan', '/products/survey-corps-keychain.webp', 5)
on conflict (id) do update set name = excluded.name, image_url = excluded.image_url, sort_order = excluded.sort_order;

insert into public.shop_products (id, name, description, category_id, series_id, price_zmw, photos, sizes, sort_order) values
  ('nezuko-jersey', 'Nezuko Kamado Jersey', 'Jersey-style tee with a full Nezuko Kamado print.', 'jerseys', 'demon-slayer', 25000, '{/products/nezuko-jersey.webp}', '{S,M,L,XL,XXL}', 1),
  ('zenitsu-jersey', 'Zenitsu Agatsuma Jersey', 'Jersey-style tee with a full Zenitsu Agatsuma print.', 'jerseys', 'demon-slayer', 25000, '{/products/zenitsu-jersey.webp}', '{S,M,L,XL,XXL}', 2),
  ('inosuke-jersey', 'Inosuke Hashibira Jersey', 'Jersey-style tee with Inosuke Hashibira''s number 86.', 'jerseys', 'demon-slayer', 25000, '{/products/inosuke-jersey.webp}', '{S,M,L,XL,XXL}', 3),
  ('tokito-jersey', 'Muichiro Tokito Jersey', 'Jersey-style tee with a full Muichiro Tokito print.', 'jerseys', 'demon-slayer', 25000, '{/products/tokito-jersey.webp}', '{S,M,L,XL,XXL}', 4),
  ('giyu-jersey', 'Giyu Tomioka Jersey', 'Jersey-style tee with a full Giyu Tomioka print.', 'jerseys', 'demon-slayer', 25000, '{/products/giyu-jersey.webp}', '{S,M,L,XL,XXL}', 5),
  ('akaza-jersey', 'Akaza Jersey', 'Jersey-style tee with a full Akaza print.', 'jerseys', 'demon-slayer', 25000, '{/products/akaza-jersey.webp}', '{S,M,L,XL,XXL}', 6),
  ('gojo-jersey', 'Satoru Gojo Jersey', 'Jersey-style tee with Satoru Gojo''s number 97.', 'jerseys', 'jujutsu-kaisen', 25000, '{/products/gojo-jersey.webp}', '{S,M,L,XL,XXL}', 7),
  ('nanami-jersey', 'Kento Nanami Jersey', 'Jersey-style tee with a full Kento Nanami print.', 'jerseys', 'jujutsu-kaisen', 25000, '{/products/nanami-jersey.webp}', '{S,M,L,XL,XXL}', 8),
  ('luffy-jersey', 'Monkey D. Luffy Jersey #53', 'Red jersey-style tee with Luffy and the number 53.', 'jerseys', 'one-piece', 25000, '{/products/luffy-jersey.webp}', '{S,M,L,XL,XXL}', 9),
  ('one-piece-luffy-shirt', 'One Piece Luffy Shirt', 'White football-style shirt with a Luffy sketch print.', 'jerseys', 'one-piece', 25000, '{/products/one-piece-luffy-shirt.webp}', '{S,M,L,XL,XXL}', 10),
  ('one-piece-gear-5-shirt', 'One Piece Gear 5 Shirt', 'White football-style shirt with a Gear 5 print.', 'jerseys', 'one-piece', 25000, '{/products/one-piece-gear-5-shirt.webp}', '{S,M,L,XL,XXL}', 11),
  ('goku-jersey', 'Goku Jersey #10', 'Navy and gold jersey-style tee with Super Saiyan Goku.', 'jerseys', 'dragon-ball', 25000, '{/products/goku-jersey.webp}', '{S,M,L,XL,XXL}', 12),
  ('goku-super-saiyan-3-shirt', 'Goku Super Saiyan 3 Shirt', 'Green tee with a Super Saiyan 3 Goku print.', 'jerseys', 'dragon-ball', 25000, '{/products/goku-super-saiyan-3-shirt.webp}', '{S,M,L,XL,XXL}', 13),
  ('luffy-gear-5-figure', 'Luffy Gear 5 Figure', 'Gear 5 Luffy figure on a display base.', 'figures', 'one-piece', 5000, '{/products/luffy-gear-5-figure.webp}', '{}', 14),
  ('demon-slayer-necklace', 'Demon Slayer Pendant Necklace', 'Pendant on a chain. 6 designs: tell us which one on WhatsApp.', 'accessories', 'demon-slayer', 7500, '{/products/demon-slayer-necklace.webp}', '{}', 15),
  ('survey-corps-necklace', 'Survey Corps Necklace', 'Wings of Freedom pendant on a black cord.', 'accessories', 'attack-on-titan', 7500, '{/products/survey-corps-necklace.webp}', '{}', 16),
  ('survey-corps-keychain', 'Survey Corps Keychain', 'Wings of Freedom metal keychain.', 'accessories', 'attack-on-titan', 5000, '{/products/survey-corps-keychain.webp}', '{}', 17),
  ('luffy-flip-flops', 'Luffy Flip-Flops', 'One Piece flip-flops with a Luffy print. Tell us your shoe size on WhatsApp.', 'footwear', 'one-piece', 20000, '{/products/luffy-flip-flops.webp}', '{}', 18)
on conflict (id) do update set name = excluded.name, description = excluded.description,
  category_id = excluded.category_id, series_id = excluded.series_id, price_zmw = excluded.price_zmw,
  photos = excluded.photos, sizes = excluded.sizes, sort_order = excluded.sort_order, updated_at = now();
