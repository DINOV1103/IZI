-- =====================================================================
--  IZI — Supabase bazasi sozlamasi (setup.sql)
--
--  Qanday ishga tushiriladi:
--    Supabase → SQL Editor → New query → shu faylni toʻliq qoʻying → Run.
--
--  Qayta ishga tushirish xavfsiz: mavjud buyurtma, foydalanuvchi va sklad
--  maʼlumotlari oʻchirilmaydi. Faqat yetishmagan jadval/ustunlar qoʻshiladi
--  va barcha izi_* funksiyalar yangi versiyaga almashtiriladi.
--  Biror tekshiruv oʻtmasa, skript butunlay bekor qilinadi — baza oʻzgarmaydi.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 0) BOSHLANGʻICH PAROL
--    Bazada hali boʻlmasa, quyidagi hisoblar shu parol bilan yaratiladi:
--      BOSHQARUV  — super-admin (hamma hudud, foydalanuvchilar, kompaniyalar)
--      ADMIN      — Buxoro va Qashqadaryo admini
--      TOSHKENT   — Toshkent admini
--    Allaqachon bor hisoblarning paroli OʻZGARMAYDI.
--    'PAROLNI_YOZING' oʻrniga kamida 4 belgili parol yozing.
-- ---------------------------------------------------------------------
create temp table _izi_setup (pass text) on commit drop;
insert into _izi_setup values ('PAROLNI_YOZING');

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1) Eski bazani tekshirish: jadval tuzilishi mos kelmasa, hech narsa
--    oʻzgartirilmaydi.
-- ---------------------------------------------------------------------
do $$
declare
  req text[] := array['izi_users.code', 'izi_users.role', 'izi_users.pass_hash', 'izi_sessions.token', 'izi_sessions.code',
                      'izi_orders.id', 'izi_orders.status', 'izi_events.id', 'izi_events.order_id', 'izi_events.type',
                      'izi_stock.company', 'izi_stock.product', 'izi_stock.qty'];
  x text;
  bad text[] := '{}';
begin
  if to_regclass('public.izi_users') is null and exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'izi\_%') then
    raise exception 'IZI: bazada eski izi_* funksiyalari bor, lekin izi_users jadvali yoʻq — eski sozlama boshqa jadval nomlarini ishlatgan. Hech narsa oʻzgartirilmadi. Eski setup.sql faylini yoki shu xabarni dasturchiga yuboring.';
  end if;
  foreach x in array req loop
    if to_regclass('public.' || split_part(x, '.', 1)) is not null and not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = split_part(x, '.', 1) and column_name = split_part(x, '.', 2)) then
      bad := bad || x;
    end if;
  end loop;
  if cardinality(bad) > 0 then
    raise exception 'IZI: eski jadvallarda quyidagi ustunlar topilmadi: %. Hech narsa oʻzgartirilmadi. Eski setup.sql faylini yoki shu xabarni dasturchiga yuboring.', array_to_string(bad, ', ');
  end if;
end $$;

-- eski izi_* funksiyalarini oʻchiramiz: parametrlari oʻzgargan boʻlsa ham yangisi toza yaratiladi
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as f, p.prokind as k from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'izi\_%' and p.prokind in ('f', 'p')
  loop
    execute (case when r.k = 'p' then 'drop procedure ' else 'drop function ' end) || r.f::text || ' cascade';
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2) Jadvallar
-- ---------------------------------------------------------------------
create table if not exists public.izi_users (
  code       text primary key,
  role       text not null default 'courier',
  region     text,
  zone       text not null default 'main',
  company    text,
  pass_hash  text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.izi_users
  add column if not exists region text,
  add column if not exists zone text default 'main',
  add column if not exists company text,
  add column if not exists active boolean default true,
  add column if not exists created_at timestamptz default now();
update public.izi_users set zone = 'main' where zone is null;
update public.izi_users set active = true where active is null;

create table if not exists public.izi_sessions (
  token      text primary key,
  code       text not null,
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
alter table public.izi_sessions
  add column if not exists created_at timestamptz default now(),
  add column if not exists last_seen timestamptz default now();
update public.izi_sessions set last_seen = now() where last_seen is null;

create table if not exists public.izi_login_fails (
  code    text primary key,
  fails   integer not null default 0,
  last_at timestamptz not null default now()
);

create table if not exists public.izi_orders (
  id               bigint generated by default as identity primary key,
  order_no         text,
  order_ids        text,
  customer         text,
  phone            text,
  region           text,
  district         text,
  address          text,
  landmark         text,
  product          text,
  qty              text,
  items            jsonb,
  amount           numeric,
  note             text,
  zone             text not null default 'main',
  company          text,
  specialist       text,
  specialist_phone text,
  src              text,
  stock_taken      jsonb,
  courier          text,
  status           text not null default 'new',
  cancel_reason    text,
  courier_comment  text,
  comments         jsonb not null default '[]'::jsonb,
  created_at       timestamptz not null default now(),
  assigned_at      timestamptz,
  on_way_at        timestamptz,
  done_at          timestamptz,
  updated_at       timestamptz not null default now()
);
alter table public.izi_orders
  add column if not exists order_no text,
  add column if not exists order_ids text,
  add column if not exists customer text,
  add column if not exists phone text,
  add column if not exists region text,
  add column if not exists district text,
  add column if not exists address text,
  add column if not exists landmark text,
  add column if not exists product text,
  add column if not exists qty text,
  add column if not exists items jsonb,
  add column if not exists amount numeric,
  add column if not exists note text,
  add column if not exists zone text default 'main',
  add column if not exists company text,
  add column if not exists specialist text,
  add column if not exists specialist_phone text,
  add column if not exists src text,
  add column if not exists stock_taken jsonb,
  add column if not exists courier text,
  add column if not exists cancel_reason text,
  add column if not exists courier_comment text,
  add column if not exists comments jsonb default '[]'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists assigned_at timestamptz,
  add column if not exists on_way_at timestamptz,
  add column if not exists done_at timestamptz,
  add column if not exists updated_at timestamptz default now();
update public.izi_orders set zone = 'main' where zone is null;
update public.izi_orders set comments = '[]'::jsonb where comments is null or jsonb_typeof(comments) <> 'array';
update public.izi_orders set updated_at = coalesce(created_at, now()) where updated_at is null;

create table if not exists public.izi_events (
  id         bigint generated by default as identity primary key,
  order_id   bigint,
  courier    text,
  type       text not null,
  reason     text,
  comment    text,
  actor      text,
  created_at timestamptz not null default now()
);
alter table public.izi_events
  add column if not exists courier text,
  add column if not exists reason text,
  add column if not exists comment text,
  add column if not exists actor text,
  add column if not exists created_at timestamptz default now();

create table if not exists public.izi_stock (
  zone       text not null default 'main',
  company    text not null,
  product    text not null,
  qty        integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.izi_stock
  add column if not exists zone text default 'main',
  add column if not exists updated_at timestamptz default now();
update public.izi_stock set zone = 'main' where zone is null;

-- eski cheklovlarni tozalaymiz: yangi rollar (super, company) va hodisa turlari (comment, edited, reverted)
-- eski CHECK larga sigʻmasligi mumkin; sklad kaliti esa endi hudud (zone) bilan birga boʻladi
do $$
declare r record;
begin
  for r in select conrelid::regclass as t, conname from pg_constraint
           where contype = 'c' and conrelid in ('public.izi_users'::regclass, 'public.izi_orders'::regclass,
                                                'public.izi_events'::regclass, 'public.izi_stock'::regclass)
  loop
    execute format('alter table %s drop constraint %I', r.t, r.conname);
  end loop;
  for r in select c.conname from pg_constraint c
           where c.conrelid = 'public.izi_stock'::regclass and c.contype in ('u', 'p')
             and exists (select 1 from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any(c.conkey) and a.attname = 'product')
             and not exists (select 1 from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any(c.conkey) and a.attname = 'zone')
  loop
    execute format('alter table public.izi_stock drop constraint %I', r.conname);
  end loop;
  for r in select i.indexrelid::regclass as ix from pg_index i
           where i.indrelid = 'public.izi_stock'::regclass and i.indisunique
             and not exists (select 1 from pg_constraint c where c.conindid = i.indexrelid)
             and exists (select 1 from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any(i.indkey) and a.attname = 'product')
             and not exists (select 1 from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any(i.indkey) and a.attname = 'zone')
  loop
    execute format('drop index %s', r.ix);
  end loop;
end $$;

alter table public.izi_users  add constraint izi_users_role_chk  check (role in ('super', 'admin', 'courier', 'company')) not valid;
alter table public.izi_users  add constraint izi_users_zone_chk  check (zone in ('main', 'toshkent', 'all')) not valid;
alter table public.izi_orders add constraint izi_orders_status_chk check (status in ('new', 'assigned', 'on_way', 'delivered', 'cancelled')) not valid;
alter table public.izi_stock  add constraint izi_stock_qty_chk   check (qty >= 0) not valid;

-- ---------------------------------------------------------------------
-- 3) Yordamchi funksiyalar (brauzerdagi normCode, pkey, norm, itemsOf bilan bir xil qoida)
-- ---------------------------------------------------------------------
create function public.izi_trim(s text) returns text
language sql immutable as $$
  select regexp_replace(coalesce(s, ''), '^\s+|\s+$', '', 'g')
$$;

-- "abihayat  " → "ABIHAYAT": kompaniya va mahsulot nomini solishtirish kaliti
create function public.izi_pkey(s text) returns text
language sql immutable as $$
  select upper(regexp_replace(public.izi_trim(s), '\s+', ' ', 'g'))
$$;

-- "b1", "b 1", kirillcha "В-1" → "B-1"; "admin" → "ADMIN"
create function public.izi_code(s text) returns text
language sql immutable as $$
  select regexp_replace(
           upper(translate(regexp_replace(coalesce(s, ''), '\s+', '', 'g'), 'ВвКкАаМмНнОоРрСсТтХх', 'BbKkAaMmHhOoPpCcTtXx')),
           '^([A-Z]+)-?([0-9]+)$', '\1-\2')
$$;

-- qidiruv uchun: kichik harf, kirill → lotin, tutuq belgilarsiz
create function public.izi_norm(s text) returns text
language sql immutable as $$
  select public.izi_trim(regexp_replace(
    translate(
      replace(replace(replace(replace(replace(replace(replace(
      replace(replace(replace(replace(replace(replace(replace(lower(coalesce(s, '')),
        'ё', 'yo'), 'Ё', 'yo'), 'ц', 'ts'), 'Ц', 'ts'), 'ч', 'ch'), 'Ч', 'ch'), 'ш', 'sh'),
        'Ш', 'sh'), 'щ', 'sh'), 'Щ', 'sh'), 'ю', 'yu'), 'Ю', 'yu'), 'я', 'ya'), 'Я', 'ya'),
      'абвгғдежзийкқлмноўпрстуфхҳыэАБВГҒДЕЖЗИЙКҚЛМНОЎПРСТУФХҲЫЭъьЪЬʻʼ‘’''`´"«»',
      'abvggdejziykqlmnooprstufxhieabvggdejziykqlmnooprstufxhie'),
    '[^a-z0-9№#]+', ' ', 'g'))
$$;

-- "10452, 10453" / "10452/10453" → {10452,10453}
create function public.izi_ids(s text) returns text[]
language sql immutable as $$
  select coalesce(array_agg(x), '{}') from (
    select public.izi_trim(t) as x from regexp_split_to_table(coalesce(s, ''), '[,;/\n]+') as t
  ) q where x <> ''
$$;

-- parseInt: "2", "2.5", " 3 dona" → 2, 2, 3
create function public.izi_int(s text) returns integer
language sql immutable as $$
  select coalesce(substring(coalesce(s, '') from '^\s*([+-]?[0-9]{1,9})')::integer, 0)
$$;

-- "2,5 ta" → 3; 0 dan katta boʻlmasa 0; eng koʻpi 999
create function public.izi_parse_qty(s text) returns integer
language plpgsql immutable as $$
declare t text;
begin
  t := substring(regexp_replace(replace(coalesce(s, ''), ',', '.'), '[^0-9.]', '', 'g') from '^[0-9]*\.?[0-9]*');
  if t is null or t in ('', '.') then return 0; end if;
  if t::numeric <= 0 then return 0; end if;
  return least(999, round(t::numeric))::integer;
end $$;

-- summa: raqam boʻlmasa 0 (brauzerdagi +x || 0)
create function public.izi_num(s text) returns numeric
language plpgsql immutable as $$
begin
  return coalesce(nullif(public.izi_trim(s), '')::numeric, 0);
exception when others then
  return 0;
end $$;

-- Buyurtmadagi mahsulotlar: [{n:'ABIHAYAT', q:2}]. items boʻlmasa "ABIHAYAT × 2, TRIO × 1" matnidan olinadi.
create function public.izi_items(p_items jsonb, p_product text, p_qty text)
returns table (n text, q integer)
language plpgsql immutable as $$
declare
  s text;
  parts text[];
  x text;
  m text[];
  an text[] := '{}';
  aq integer[] := '{}';
begin
  if jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
    return query
      select public.izi_trim(e->>'n'), greatest(0, public.izi_int(e->>'q'))
      from jsonb_array_elements(p_items) as e
      where public.izi_trim(e->>'n') <> '' and public.izi_int(e->>'q') > 0;
    return;
  end if;
  s := public.izi_trim(p_product);
  if s = '' then return; end if;
  parts := regexp_split_to_array(s, '\s*,\s*');
  foreach x in array parts loop
    m := regexp_match(x, '^(.*?\S)\s*×\s*([0-9]+)$');
    if m is null then m := regexp_match(x, '^(.*?\S)\s+[xX*]\s*([0-9]+)$'); end if;
    if m is not null then
      an := an || public.izi_trim(m[1]);
      aq := aq || least(999, left(m[2], 6)::integer);
    end if;
  end loop;
  if cardinality(an) = cardinality(parts) then
    return query select * from unnest(an, aq);
    return;
  end if;
  return query select s, greatest(1, public.izi_parse_qty(p_qty));
end $$;

-- bir xil mahsulotlar qoʻshiladi: kalit → (nom, jami son)
create function public.izi_need(p_items jsonb, p_product text, p_qty text)
returns table (k text, n text, q integer)
language sql immutable as $$
  select public.izi_pkey(i.n), min(i.n), sum(i.q)::integer
  from public.izi_items(p_items, p_product, p_qty) as i
  group by public.izi_pkey(i.n)
$$;

create function public.izi_in_zone(u_zone text, o_zone text) returns boolean
language sql immutable as $$
  select coalesce(u_zone, 'main') = 'all' or coalesce(o_zone, 'main') = coalesce(u_zone, 'main')
$$;

create function public.izi_hash(p text) returns text
language sql volatile set search_path = public, extensions as $$
  select extensions.crypt(p, extensions.gen_salt('bf'))
$$;

create function public.izi_pass_ok(p text, h text) returns boolean
language plpgsql stable set search_path = public, extensions as $$
begin
  return coalesce(p, '') <> '' and h is not null and h = extensions.crypt(p, h);
exception when others then
  return false;
end $$;

-- sessiya → foydalanuvchi
create function public.izi_auth(p_token text) returns public.izi_users
language plpgsql security definer set search_path = public, extensions as $$
declare u public.izi_users;
begin
  select usr.* into u from public.izi_sessions s join public.izi_users usr on usr.code = s.code
  where s.token = p_token and usr.active;
  if not found then raise exception 'NO_SESSION'; end if;
  update public.izi_sessions set last_seen = now() where token = p_token and last_seen < now() - interval '10 minutes';
  return u;
end $$;

create function public.izi_admin(p_token text) returns public.izi_users
language plpgsql security definer set search_path = public, extensions as $$
declare u public.izi_users;
begin
  u := public.izi_auth(p_token);
  if u.role not in ('admin', 'super') then raise exception 'FORBIDDEN'; end if;
  return u;
end $$;

create function public.izi_super(p_token text) returns public.izi_users
language plpgsql security definer set search_path = public, extensions as $$
declare u public.izi_users;
begin
  u := public.izi_auth(p_token);
  if u.role <> 'super' then raise exception 'FORBIDDEN'; end if;
  return u;
end $$;

create function public.izi_ev(p_order bigint, p_courier text, p_type text, p_actor text, p_reason text default null, p_comment text default null)
returns void
language sql security definer set search_path = public, extensions as $$
  insert into public.izi_events (order_id, courier, type, reason, comment, actor, created_at)
  values (p_order, p_courier, p_type, p_reason, p_comment, p_actor, now())
$$;

-- admin koʻradigan hodisalar (yoʻlda / yetkazildi / bekor / kuryer qaytardi / admin boʻlmagan izoh)
create function public.izi_ev_rows(p_since timestamptz, p_limit integer, p_zone text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint), '[]'::jsonb) from (
    select to_jsonb(e) || jsonb_build_object('order_no', o.order_no, 'customer', o.customer, 'amount', o.amount,
                                             'address', o.address, 'company', o.company) as x
    from public.izi_events e
    left join public.izi_orders o on o.id = e.order_id
    left join public.izi_users a on a.code = e.actor
    left join public.izi_users c on c.code = e.courier
    where (e.type in ('on_way', 'delivered', 'cancelled')
           or (e.type = 'reverted' and e.actor = e.courier)
           or (e.type = 'comment' and coalesce(a.role, '') <> 'admin'))
      and (p_since is null or e.created_at > p_since)
      and (p_zone = 'all' or coalesce(o.zone, c.zone, 'main') = p_zone)
    order by e.id desc
    limit p_limit
  ) t
$$;

create function public.izi_pub_users(p_zone text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', u.code, 'role', u.role, 'region', u.region, 'active', u.active,
                                               'zone', coalesce(u.zone, 'main'), 'company', u.company) order by u.code), '[]'::jsonb)
  from public.izi_users u
  where u.role <> 'super'
    and (p_zone = 'all' or (coalesce(u.zone, 'main') = p_zone and u.role in ('admin', 'courier')))
$$;

create function public.izi_stock_rows(p_zone text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('zone', coalesce(s.zone, 'main'), 'company', s.company, 'product', s.product,
                                               'qty', s.qty, 'updated_at', s.updated_at) order by s.company, s.product), '[]'::jsonb)
  from public.izi_stock s
  where public.izi_in_zone(p_zone, s.zone)
$$;

-- sklad: buyurtma kuryerga berilganda ayriladi. Yetmasa hech narsa olinmaydi va false qaytadi.
create function public.izi_take_stock(p_id bigint) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  o public.izi_orders;
  r record;
  have integer;
  pname text;
  taken jsonb := '[]'::jsonb;
begin
  select * into o from public.izi_orders where id = p_id for update;
  if not found then return false; end if;
  for r in select * from public.izi_need(o.items, o.product, o.qty) loop
    select s.qty into have from public.izi_stock s
    where coalesce(s.zone, 'main') = coalesce(o.zone, 'main')
      and public.izi_pkey(s.company) = public.izi_pkey(o.company) and public.izi_pkey(s.product) = r.k
    for update;
    if not found or have < r.q then return false; end if;   -- kiritilmagan mahsulot qoldigʻi nol
  end loop;
  for r in select * from public.izi_need(o.items, o.product, o.qty) loop
    update public.izi_stock s set qty = s.qty - r.q, updated_at = now()
    where coalesce(s.zone, 'main') = coalesce(o.zone, 'main')
      and public.izi_pkey(s.company) = public.izi_pkey(o.company) and public.izi_pkey(s.product) = r.k
    returning s.product into pname;
    taken := taken || jsonb_build_array(jsonb_build_object('n', pname, 'q', r.q));
  end loop;
  update public.izi_orders set stock_taken = case when jsonb_array_length(taken) > 0 then taken end where id = p_id;
  return true;
end $$;

-- bekor qilingan / qaytarib olingan buyurtma tovari skladga qaytadi
create function public.izi_give_back(p_id bigint) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  o public.izi_orders;
  e jsonb;
begin
  select * into o from public.izi_orders where id = p_id for update;
  if not found then return; end if;
  if jsonb_typeof(o.stock_taken) = 'array' then
    for e in select * from jsonb_array_elements(o.stock_taken) loop
      update public.izi_stock s set qty = s.qty + greatest(0, public.izi_int(e->>'q')), updated_at = now()
      where coalesce(s.zone, 'main') = coalesce(o.zone, 'main')
        and public.izi_pkey(s.company) = public.izi_pkey(o.company) and public.izi_pkey(s.product) = public.izi_pkey(e->>'n');
    end loop;
  end if;
  update public.izi_orders set stock_taken = null where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- 4) Indekslar
-- ---------------------------------------------------------------------
create index if not exists izi_orders_status_idx  on public.izi_orders (status);
create index if not exists izi_orders_updated_idx on public.izi_orders (updated_at);
create index if not exists izi_orders_done_idx    on public.izi_orders (done_at);
create index if not exists izi_orders_courier_idx on public.izi_orders (courier);
create index if not exists izi_orders_company_idx on public.izi_orders (public.izi_pkey(company));
create index if not exists izi_orders_ids_idx     on public.izi_orders using gin (public.izi_ids(coalesce(nullif(order_ids, ''), order_no)));
create index if not exists izi_events_order_idx   on public.izi_events (order_id);
create index if not exists izi_events_created_idx on public.izi_events (created_at);
create index if not exists izi_sessions_code_idx  on public.izi_sessions (code);
do $$
begin
  create unique index if not exists izi_stock_key on public.izi_stock (coalesce(zone, 'main'), public.izi_pkey(company), public.izi_pkey(product));
exception when unique_violation then
  raise notice 'IZI: skladda takror qatorlar bor, izi_stock_key indeksi yaratilmadi (ilova baribir ishlaydi).';
end $$;

-- ---------------------------------------------------------------------
-- 5) Ilova chaqiradigan funksiyalar (API)
-- ---------------------------------------------------------------------

create function public.izi_login(p_code text, p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  c text := public.izi_code(p_code);
  u public.izi_users;
  f public.izi_login_fails;
  t text;
begin
  select * into f from public.izi_login_fails where code = c;
  if found and f.fails >= 5 and f.last_at > now() - interval '10 minutes' then
    return jsonb_build_object('error', 'LOCKED');
  end if;
  select * into u from public.izi_users where code = c and active;
  if not found or not public.izi_pass_ok(p_pass, u.pass_hash) then
    -- xato urinish saqlanishi uchun exception emas, javobda error qaytaramiz
    insert into public.izi_login_fails (code, fails, last_at) values (c, 1, now())
    on conflict (code) do update
      set fails = case when public.izi_login_fails.last_at < now() - interval '10 minutes' then 1 else public.izi_login_fails.fails + 1 end,
          last_at = now();
    return jsonb_build_object('error', 'BAD_LOGIN');
  end if;
  delete from public.izi_login_fails where code = c;
  delete from public.izi_sessions where last_seen < now() - interval '60 days';
  t := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.izi_sessions (token, code, created_at, last_seen) values (t, u.code, now(), now());
  return jsonb_build_object('token', t, 'code', u.code, 'role', u.role, 'region', u.region,
                            'zone', coalesce(u.zone, 'main'), 'company', u.company);
end $$;

create function public.izi_me(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u public.izi_users;
begin
  u := public.izi_auth(p_token);
  return jsonb_build_object('code', u.code, 'role', u.role, 'region', u.region, 'zone', coalesce(u.zone, 'main'), 'company', u.company);
end $$;

create function public.izi_logout(p_token text) returns jsonb
language sql security definer set search_path = public, extensions as $$
  delete from public.izi_sessions where token = p_token;
  select jsonb_build_object('ok', true);
$$;

create function public.izi_admin_load(p_token text, p_days integer) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  z text := coalesce(u.zone, 'main');
begin
  return jsonb_build_object(
    'orders', (select coalesce(jsonb_agg(to_jsonb(o) order by o.id desc), '[]'::jsonb) from public.izi_orders o
               where public.izi_in_zone(z, o.zone)
                 and (o.status in ('new', 'assigned', 'on_way') or o.updated_at > now() - make_interval(days => greatest(1, coalesce(p_days, 3))))),
    'events', public.izi_ev_rows(null, 150, z),
    'users', public.izi_pub_users(z),
    'stock', public.izi_stock_rows(z),
    'next_since', now() - interval '15 seconds',
    'server_time', now());
end $$;

create function public.izi_admin_changes(p_token text, p_since timestamptz) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  z text := coalesce(u.zone, 'main');
  s timestamptz := coalesce(p_since, now() - interval '1 minute');
begin
  return jsonb_build_object(
    'orders', (select coalesce(jsonb_agg(to_jsonb(o) order by o.id desc), '[]'::jsonb) from public.izi_orders o
               where public.izi_in_zone(z, o.zone) and o.updated_at > s),
    'events', public.izi_ev_rows(s, 500, z),
    'stock', public.izi_stock_rows(z),
    'next_since', now() - interval '15 seconds',
    'server_time', now());
end $$;

create function public.izi_archive(p_token text, p_from text, p_to text, p_query text, p_offset integer) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  z text := coalesce(u.zone, 'main');
  d1 date := coalesce(nullif(p_from, '')::date, (now() at time zone 'Asia/Tashkent')::date - 30);
  d2 date := coalesce(nullif(p_to, '')::date, (now() at time zone 'Asia/Tashkent')::date);
  q text := public.izi_norm(p_query);
  v_total integer;
  v_rows jsonb;
begin
  with hit as (
    select o.* from public.izi_orders o
    where public.izi_in_zone(z, o.zone) and o.status in ('delivered', 'cancelled')
      and (o.done_at at time zone 'Asia/Tashkent')::date between d1 and d2
      and (q = '' or public.izi_norm(concat_ws(' ', o.order_no, o.order_ids, o.specialist, o.specialist_phone, o.customer, o.phone,
             o.region, o.district, o.address, o.landmark, o.product, o.company, o.courier, o.note, o.cancel_reason,
             o.courier_comment, o.amount::text)) like '%' || q || '%')
  )
  select (select count(*) from hit),
         (select coalesce(jsonb_agg(to_jsonb(h) order by h.done_at desc, h.id desc), '[]'::jsonb)
          from (select * from hit order by done_at desc, id desc offset greatest(0, coalesce(p_offset, 0)) limit 500) h)
  into v_total, v_rows;
  return jsonb_build_object('orders', v_rows, 'total', v_total);
end $$;

create function public.izi_import(p_token text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  uz text := coalesce(u.zone, 'main');
  r jsonb;
  z text;
  v_no text;
  ids text[];
  c text;
  v_items jsonb;
  new_id bigint;
  ins integer := 0;
  skip integer := 0;
  foreign_n integer := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'BAD_INPUT'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    z := case when r->>'zone' in ('main', 'toshkent') then r->>'zone' end;
    if uz = 'all' then
      z := coalesce(z, 'main');
    else
      z := coalesce(z, uz);
      if z <> uz then foreign_n := foreign_n + 1; continue; end if;   -- admin faqat oʻz hududi buyurtmasini qoʻsha oladi
    end if;
    v_no := public.izi_trim(r->>'order_no');
    ids := public.izi_ids(coalesce(nullif(r->>'order_ids', ''), v_no));
    if cardinality(ids) > 0 and exists (
        select 1 from public.izi_orders o
        where public.izi_ids(coalesce(nullif(o.order_ids, ''), o.order_no)) && ids
          and coalesce(o.company, '') = coalesce(r->>'company', '')) then
      skip := skip + 1; continue;
    end if;
    c := nullif(public.izi_code(r->>'courier'), '');
    if c is not null and not exists (select 1 from public.izi_users x where x.code = c and x.role = 'courier' and x.active and coalesce(x.zone, 'main') = z) then
      c := null;
    end if;
    select jsonb_agg(jsonb_build_object('n', public.izi_trim(e->>'n'), 'q', greatest(0, public.izi_int(e->>'q'))))
      into v_items
    from jsonb_array_elements(case when jsonb_typeof(r->'items') = 'array' then r->'items' else '[]'::jsonb end) as e
    where public.izi_trim(e->>'n') <> '' and public.izi_int(e->>'q') > 0;
    insert into public.izi_orders (order_no, customer, phone, region, district, address, landmark, product, qty, amount, note,
                                   zone, company, order_ids, specialist, specialist_phone, src, items, stock_taken, courier, status,
                                   comments, created_at, updated_at)
    values (nullif(v_no, ''), nullif(r->>'customer', ''), nullif(r->>'phone', ''), nullif(r->>'region', ''), nullif(r->>'district', ''),
            nullif(r->>'address', ''), nullif(r->>'landmark', ''), nullif(r->>'product', ''), nullif(r->>'qty', ''),
            case when r->'amount' is null or jsonb_typeof(r->'amount') = 'null' then null else public.izi_num(r->>'amount') end,
            nullif(r->>'note', ''), z, nullif(r->>'company', ''), array_to_string(ids, ', '), nullif(r->>'specialist', ''),
            nullif(r->>'specialist_phone', ''), nullif(r->>'src', ''), v_items, null, null, 'new', '[]'::jsonb, now(), now())
    returning id into new_id;
    -- Excelda kuryer yozilgan boʻlsa: skladda yetsa darhol beriladi, yetmasa «berilmagan» boʻlib qoladi
    if c is not null and public.izi_take_stock(new_id) then
      update public.izi_orders set courier = c, status = 'assigned', assigned_at = now() where id = new_id;
    end if;
    ins := ins + 1;
  end loop;
  return jsonb_build_object('inserted', ins, 'skipped', skip, 'other_zone', 0, 'foreign', foreign_n);
end $$;

create function public.izi_assign(p_token text, p_ids bigint[], p_courier text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  c text := nullif(public.izi_code(p_courier), '');
  cu public.izi_users;
  o public.izi_orders;
  n integer := 0;
  short bigint[] := '{}';
begin
  if c is not null then
    select * into cu from public.izi_users x
    where x.code = c and x.role = 'courier' and x.active and public.izi_in_zone(u.zone, x.zone);
    if not found then raise exception 'BAD_COURIER'; end if;
  end if;
  for o in select * from public.izi_orders where id = any(coalesce(p_ids, '{}')) order by id for update loop
    if o.status = 'delivered' or not public.izi_in_zone(u.zone, o.zone)
       or (c is not null and coalesce(o.zone, 'main') <> coalesce(cu.zone, 'main')) then
      continue;
    end if;
    if c is not null and o.stock_taken is null and not public.izi_take_stock(o.id) then
      short := short || o.id; continue;   -- skladda yetmaydi
    end if;
    if c is null and o.stock_taken is not null then perform public.izi_give_back(o.id); end if;
    update public.izi_orders
       set courier = c, status = case when c is null then 'new' else 'assigned' end,
           assigned_at = case when c is null then null else now() end,
           on_way_at = null, done_at = null, cancel_reason = null, courier_comment = null, updated_at = now()
     where id = o.id;
    perform public.izi_ev(o.id, c, case when c is null then 'unassigned' else 'assigned' end, u.code);
    n := n + 1;
  end loop;
  return jsonb_build_object('updated', n, 'short', cardinality(short), 'short_ids', to_jsonb(short));
end $$;

create function public.izi_delete_orders(p_token text, p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  ids bigint[];
  o public.izi_orders;
begin
  select coalesce(array_agg(x.id), '{}') into ids from public.izi_orders x
  where x.id = any(coalesce(p_ids, '{}')) and public.izi_in_zone(u.zone, x.zone);
  for o in select * from public.izi_orders where id = any(ids) for update loop
    if o.stock_taken is not null and o.status <> 'delivered' then perform public.izi_give_back(o.id); end if;
  end loop;
  delete from public.izi_events where order_id = any(ids);
  delete from public.izi_orders where id = any(ids);
  return jsonb_build_object('deleted', cardinality(ids));
end $$;

create function public.izi_user_save(p_token text, p_code text, p_region text, p_pass text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.izi_users := public.izi_admin(p_token);
  z text := coalesce(me.zone, 'main');
  c text := public.izi_code(p_code);
  pass text := nullif(p_pass, '');
  u public.izi_users;
begin
  if me.role = 'super' then raise exception 'FORBIDDEN'; end if;
  if c !~ '^[A-Z0-9-]{2,12}$' then raise exception 'BAD_CODE'; end if;
  if pass is not null and length(pass) < 4 then raise exception 'SHORT_PASS'; end if;
  select * into u from public.izi_users where code = c for update;
  if found and (coalesce(u.zone, 'main') <> z or u.role not in ('courier', 'admin') or (u.role = 'admin' and u.code <> me.code)) then
    raise exception 'FORBIDDEN';
  end if;
  if not found then
    if pass is null then raise exception 'SHORT_PASS'; end if;
    insert into public.izi_users (code, role, region, zone, company, pass_hash, active)
    values (c, 'courier', nullif(public.izi_trim(p_region), ''), z, null, public.izi_hash(pass), coalesce(p_active, true));
  elsif u.role = 'courier' then
    update public.izi_users
       set region = case when p_region is null then region else nullif(public.izi_trim(p_region), '') end,
           active = coalesce(p_active, active),
           pass_hash = case when pass is null then pass_hash else public.izi_hash(pass) end
     where code = c;
    if pass is not null or p_active is false then delete from public.izi_sessions where code = c; end if;
  else
    -- admin oʻz parolini almashtiradi
    if pass is null then raise exception 'SHORT_PASS'; end if;
    update public.izi_users set pass_hash = public.izi_hash(pass) where code = c;
    delete from public.izi_sessions where code = c and token <> p_token;
  end if;
  return jsonb_build_object('ok', true, 'users', public.izi_pub_users(z));
end $$;

create function public.izi_user_manage(p_token text, p_code text, p_role text, p_zone text, p_region text,
                                       p_company text, p_pass text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.izi_users := public.izi_super(p_token);
  c text := public.izi_code(p_code);
  z text := case when p_role = 'company' then 'all' when p_zone in ('main', 'toshkent') then p_zone else 'main' end;
  co text := public.izi_trim(p_company);
  pass text := nullif(p_pass, '');
  u public.izi_users;
begin
  if c !~ '^[A-Z0-9-]{2,20}$' then raise exception 'BAD_CODE'; end if;
  if coalesce(p_role, '') not in ('admin', 'courier', 'company') then raise exception 'BAD_INPUT'; end if;
  select * into u from public.izi_users where code = c for update;
  if found and u.role = 'super' then raise exception 'FORBIDDEN'; end if;
  if found and u.role <> p_role then raise exception 'ROLE_LOCKED'; end if;
  if not found then
    if p_role = 'company' and co = '' then raise exception 'BAD_INPUT'; end if;
    if pass is null or length(pass) < 4 then raise exception 'SHORT_PASS'; end if;
    insert into public.izi_users (code, role, region, zone, company, pass_hash, active)
    values (c, p_role, case when p_role = 'courier' then nullif(public.izi_trim(p_region), '') end, z,
            case when p_role = 'company' then co end, public.izi_hash(pass), coalesce(p_active, true));
  else
    update public.izi_users
       set region = case when p_role = 'courier' and p_region is not null then nullif(public.izi_trim(p_region), '') else region end,
           company = case when p_role = 'company' and co <> '' then co else company end,
           pass_hash = case when pass is not null and length(pass) >= 4 then public.izi_hash(pass) else pass_hash end,
           active = coalesce(p_active, active)
     where code = c;
    if (pass is not null and length(pass) >= 4) or p_active is false then delete from public.izi_sessions where code = c; end if;
  end if;
  return jsonb_build_object('ok', true, 'users', public.izi_pub_users('all'));
end $$;

create function public.izi_my_orders(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u public.izi_users := public.izi_auth(p_token);
begin
  if u.role <> 'courier' then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'orders', (select coalesce(jsonb_agg(to_jsonb(o) order by o.id desc), '[]'::jsonb) from public.izi_orders o
               where o.courier = u.code and (o.status in ('assigned', 'on_way') or o.done_at > now() - interval '3 days')),
    'server_time', now());
end $$;

create function public.izi_set_status(p_token text, p_id bigint, p_status text, p_reason text, p_comment text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_auth(p_token);
  o public.izi_orders;
  cm text := nullif(left(public.izi_trim(p_comment), 1000), '');
  rs text;
begin
  if u.role <> 'courier' then raise exception 'FORBIDDEN'; end if;
  if coalesce(p_status, '') not in ('on_way', 'delivered', 'cancelled') then raise exception 'BAD_STATUS'; end if;
  select * into o from public.izi_orders where id = p_id for update;
  if not found or o.courier is distinct from u.code then raise exception 'NOT_FOUND'; end if;
  if o.status = p_status then return to_jsonb(o); end if;
  if o.status not in ('assigned', 'on_way') or (p_status = 'on_way' and o.status <> 'assigned') then raise exception 'BAD_STATUS'; end if;
  if p_status = 'cancelled' and (cm is null or length(cm) < 2) then raise exception 'NEED_COMMENT'; end if;
  if p_status = 'cancelled' and o.stock_taken is not null then perform public.izi_give_back(o.id); end if;   -- bekor qilingan tovar skladga qaytadi
  rs := case when p_status = 'cancelled' then left(coalesce(p_reason, ''), 200) end;
  update public.izi_orders
     set status = p_status,
         on_way_at = case when p_status = 'on_way' then now() else on_way_at end,
         done_at = case when p_status = 'on_way' then done_at else now() end,
         cancel_reason = rs, courier_comment = cm, updated_at = now()
   where id = o.id
  returning * into o;
  perform public.izi_ev(o.id, u.code, p_status, u.code, rs, cm);
  return to_jsonb(o);
end $$;

create function public.izi_order_history(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_auth(p_token);
  o public.izi_orders;
begin
  select * into o from public.izi_orders where id = p_id;
  if not found
     or (u.role = 'courier' and o.courier is distinct from u.code)
     or (u.role = 'admin' and coalesce(o.zone, 'main') <> coalesce(u.zone, 'main'))
     or (u.role = 'company' and public.izi_pkey(o.company) <> public.izi_pkey(u.company)) then
    raise exception 'NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb) from public.izi_events e where e.order_id = p_id);
end $$;

create function public.izi_update_order(p_token text, p_id bigint, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  o public.izi_orders;
  ids text[];
  v_items jsonb;
begin
  select * into o from public.izi_orders where id = p_id and public.izi_in_zone(u.zone, zone) for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  ids := public.izi_ids(coalesce(nullif(p_data->>'order_ids', ''), p_data->>'order_no'));
  if cardinality(ids) > 0 and exists (
      select 1 from public.izi_orders x
      where x.id <> o.id and coalesce(x.company, '') = coalesce(o.company, '')
        and public.izi_ids(coalesce(nullif(x.order_ids, ''), x.order_no)) && ids) then
    raise exception 'DUP_ID';
  end if;
  v_items := case when jsonb_typeof(p_data->'items') = 'array' and jsonb_array_length(p_data->'items') > 0 then p_data->'items' end;
  update public.izi_orders
     set order_no = nullif(p_data->>'order_no', ''), order_ids = nullif(p_data->>'order_ids', ''),
         customer = nullif(p_data->>'customer', ''), phone = nullif(p_data->>'phone', ''),
         region = nullif(p_data->>'region', ''), district = nullif(p_data->>'district', ''),
         address = nullif(p_data->>'address', ''), product = nullif(p_data->>'product', ''), qty = null, items = v_items,
         amount = case when p_data->'amount' is null or jsonb_typeof(p_data->'amount') = 'null' then null else public.izi_num(p_data->>'amount') end,
         specialist = nullif(p_data->>'specialist', ''), note = nullif(p_data->>'note', ''), updated_at = now()
   where id = o.id;
  if o.stock_taken is not null and o.status in ('assigned', 'on_way') and v_items is distinct from o.items then
    perform public.izi_give_back(o.id);                                       -- eski mahsulot skladga
    if not public.izi_take_stock(o.id) then raise exception 'SHORT_STOCK'; end if;   -- saqlanmaydi: baza oʻzgarmay qoladi
  end if;
  perform public.izi_ev(o.id, o.courier, 'edited', u.code, null, nullif(p_data->>'_changes', ''));
  return (select to_jsonb(x) from public.izi_orders x where x.id = o.id);
end $$;

create function public.izi_revert_status(p_token text, p_id bigint, p_comment text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_auth(p_token);
  o public.izi_orders;
  cm text := public.izi_trim(p_comment);
  prev text;
begin
  if u.role not in ('admin', 'super', 'courier') then raise exception 'FORBIDDEN'; end if;
  select * into o from public.izi_orders where id = p_id for update;
  if not found or (u.role = 'courier' and o.courier is distinct from u.code)
     or (u.role = 'admin' and coalesce(o.zone, 'main') <> coalesce(u.zone, 'main')) then
    raise exception 'NOT_FOUND';
  end if;
  if o.status not in ('delivered', 'cancelled') then raise exception 'BAD_STATUS'; end if;
  if u.role = 'courier' and (o.done_at at time zone 'Asia/Tashkent')::date < (now() at time zone 'Asia/Tashkent')::date then
    raise exception 'TOO_LATE';
  end if;
  if length(cm) < 3 then raise exception 'NEED_COMMENT'; end if;
  prev := case when o.courier is null then 'new' when o.on_way_at is not null then 'on_way' else 'assigned' end;
  if o.status = 'cancelled' and o.stock_taken is null and prev <> 'new' and not public.izi_take_stock(o.id) then
    raise exception 'SHORT_STOCK';
  end if;
  update public.izi_orders set status = prev, done_at = null, cancel_reason = null, courier_comment = null, updated_at = now()
   where id = o.id;
  perform public.izi_ev(o.id, o.courier, 'reverted', u.code, o.status, cm);
  return (select to_jsonb(x) from public.izi_orders x where x.id = o.id);
end $$;

create function public.izi_company_list(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.izi_super(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'company', company, 'active', active) order by code), '[]'::jsonb)
          from public.izi_users where role = 'company');
end $$;

create function public.izi_company_save(p_token text, p_code text, p_company text, p_pass text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.izi_users := public.izi_super(p_token);
  c text := public.izi_code(p_code);
  co text := public.izi_trim(p_company);
  pass text := nullif(p_pass, '');
  u public.izi_users;
begin
  if c !~ '^[A-Z0-9-]{3,20}$' then raise exception 'BAD_CODE'; end if;
  if pass is not null and length(pass) < 4 then raise exception 'SHORT_PASS'; end if;
  select * into u from public.izi_users where code = c for update;
  if found and u.role <> 'company' then raise exception 'FORBIDDEN'; end if;
  if not found then
    if co = '' then raise exception 'BAD_INPUT'; end if;
    if pass is null then raise exception 'SHORT_PASS'; end if;
    insert into public.izi_users (code, role, region, zone, company, pass_hash, active)
    values (c, 'company', null, 'all', co, public.izi_hash(pass), coalesce(p_active, true));
  else
    update public.izi_users
       set company = case when co <> '' then co else company end,
           active = coalesce(p_active, active),
           pass_hash = case when pass is null then pass_hash else public.izi_hash(pass) end
     where code = c;
    if pass is not null or p_active is false then delete from public.izi_sessions where code = c; end if;
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'company', company, 'active', active) order by code), '[]'::jsonb)
          from public.izi_users where role = 'company');
end $$;

-- kompaniya kuzatuvchisi: faqat oʻz kompaniyasi buyurtmalarini koʻradi
create function public.izi_company_load(p_token text, p_from text, p_to text, p_query text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_auth(p_token);
  today date := (now() at time zone 'Asia/Tashkent')::date;
  d2 date := coalesce(nullif(p_to, '')::date, today);
  d1 date := coalesce(nullif(p_from, '')::date, today - 6);
  q text := public.izi_norm(p_query);
  qd text := regexp_replace(coalesce(p_query, ''), '\D', '', 'g');
begin
  if u.role <> 'company' or coalesce(public.izi_trim(u.company), '') = '' then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'company', u.company,
    'orders', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'order_no', o.order_no, 'order_ids', o.order_ids, 'customer', o.customer, 'phone', o.phone,
               'region', o.region, 'district', o.district, 'address', o.address, 'landmark', o.landmark, 'product', o.product,
               'items', o.items, 'qty', o.qty, 'amount', o.amount, 'specialist', o.specialist, 'note', o.note,
               'company', o.company, 'status', o.status, 'courier', o.courier, 'zone', o.zone, 'created_at', o.created_at,
               'assigned_at', o.assigned_at, 'on_way_at', o.on_way_at, 'done_at', o.done_at, 'cancel_reason', o.cancel_reason,
               'courier_comment', o.courier_comment, 'comments', coalesce(o.comments, '[]'::jsonb), 'updated_at', o.updated_at)
             order by o.id desc), '[]'::jsonb)
      from (
        select * from public.izi_orders x
        where public.izi_pkey(x.company) = public.izi_pkey(u.company)
          and case when q <> '' then
                     public.izi_norm(concat_ws(' ', x.order_no, x.order_ids, x.customer, x.phone, x.region, x.district, x.address,
                                               x.product, x.specialist, x.courier)) like '%' || q || '%'
                     or (length(qd) >= 4 and regexp_replace(coalesce(x.phone, ''), '\D', '', 'g') like '%' || qd || '%')
                   else x.status in ('new', 'assigned', 'on_way')
                     or (x.done_at is not null and (x.done_at at time zone 'Asia/Tashkent')::date between d1 and d2)
              end
        order by x.id desc
        limit 1500
      ) o),
    'stock', (select coalesce(jsonb_agg(jsonb_build_object('zone', coalesce(s.zone, 'main'), 'product', s.product, 'qty', s.qty)
                                        order by s.zone, s.product), '[]'::jsonb)
              from public.izi_stock s where public.izi_pkey(s.company) = public.izi_pkey(u.company)),
    'server_time', now());
end $$;

create function public.izi_add_comment(p_token text, p_id bigint, p_text text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_auth(p_token);
  txt text := left(public.izi_trim(p_text), 500);
  o public.izi_orders;
  cms jsonb;
begin
  if length(txt) < 2 then raise exception 'NEED_COMMENT'; end if;
  select * into o from public.izi_orders where id = p_id for update;
  if not found or not (
       (u.role = 'company' and public.izi_pkey(o.company) = public.izi_pkey(u.company) and public.izi_pkey(u.company) <> '')
    or (u.role = 'admin' and coalesce(o.zone, 'main') = coalesce(u.zone, 'main'))
    or u.role = 'super'
    or (u.role = 'courier' and o.courier = u.code)) then
    raise exception 'NOT_FOUND';
  end if;
  -- oxirgi 60 ta izoh saqlanadi
  select coalesce(jsonb_agg(e order by i), '[]'::jsonb) into cms
  from jsonb_array_elements(case when jsonb_typeof(o.comments) = 'array' then o.comments else '[]'::jsonb end) with ordinality as t(e, i)
  where i > jsonb_array_length(case when jsonb_typeof(o.comments) = 'array' then o.comments else '[]'::jsonb end) - 59;
  cms := cms || jsonb_build_array(jsonb_build_object('by', u.code, 'role', u.role,
                                                     'name', case when u.role = 'company' then u.company else u.code end,
                                                     'text', txt, 'at', now()));
  update public.izi_orders set comments = cms, updated_at = now() where id = o.id;
  perform public.izi_ev(o.id, o.courier, 'comment', u.code, null, txt);
  return jsonb_build_object('comments', cms);
end $$;

create function public.izi_stock_save(p_token text, p_company text, p_product text, p_qty numeric, p_mode text, p_zone text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  uz text := coalesce(u.zone, 'main');
  pr text := left(regexp_replace(public.izi_trim(p_product), '\s+', ' ', 'g'), 40);
  co text := public.izi_trim(p_company);
  z text;
  q integer;
begin
  if pr = '' or public.izi_norm(pr) = '' or co = '' then raise exception 'BAD_PRODUCT'; end if;
  if uz = 'all' then
    if coalesce(p_zone, '') not in ('main', 'toshkent') then raise exception 'BAD_INPUT'; end if;
    z := p_zone;
  else
    z := uz;
  end if;
  if p_qty is null or p_qty < 0 or p_qty > 1000000 or (p_mode = 'add' and trunc(p_qty) = 0) then raise exception 'BAD_QTY'; end if;
  q := trunc(p_qty)::integer;
  update public.izi_stock s
     set qty = case when p_mode = 'add' then s.qty + q else q end, updated_at = now()
   where coalesce(s.zone, 'main') = z and public.izi_pkey(s.company) = public.izi_pkey(co) and public.izi_pkey(s.product) = public.izi_pkey(pr);
  if not found then
    insert into public.izi_stock (zone, company, product, qty, updated_at) values (z, co, pr, q, now());
  end if;
  return jsonb_build_object('stock', public.izi_stock_rows(uz));
end $$;

create function public.izi_stock_delete(p_token text, p_company text, p_product text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.izi_users := public.izi_admin(p_token);
  uz text := coalesce(u.zone, 'main');
begin
  delete from public.izi_stock s
  where public.izi_in_zone(uz, s.zone)
    and public.izi_pkey(s.company) = public.izi_pkey(p_company)
    and (p_product is null or public.izi_pkey(s.product) = public.izi_pkey(p_product));
  return jsonb_build_object('stock', public.izi_stock_rows(uz));
end $$;

-- ---------------------------------------------------------------------
-- 6) Xavfsizlik: jadvallarga toʻgʻridan-toʻgʻri kirish yopiq,
--    ilova faqat quyidagi funksiyalar orqali ishlaydi.
-- ---------------------------------------------------------------------
alter table public.izi_users       enable row level security;
alter table public.izi_sessions    enable row level security;
alter table public.izi_login_fails enable row level security;
alter table public.izi_orders      enable row level security;
alter table public.izi_events      enable row level security;
alter table public.izi_stock       enable row level security;

do $$
declare
  api text[] := array['izi_login', 'izi_me', 'izi_logout', 'izi_admin_load', 'izi_admin_changes', 'izi_archive', 'izi_import',
                      'izi_assign', 'izi_delete_orders', 'izi_user_save', 'izi_my_orders', 'izi_set_status', 'izi_order_history',
                      'izi_update_order', 'izi_company_list', 'izi_company_save', 'izi_company_load', 'izi_add_comment',
                      'izi_user_manage', 'izi_revert_status', 'izi_stock_save', 'izi_stock_delete'];
  r record;
  roles text := (select string_agg(quote_ident(rolname), ', ') from pg_roles where rolname in ('anon', 'authenticated'));
begin
  if roles is not null then
    execute 'revoke all on public.izi_users, public.izi_sessions, public.izi_login_fails, public.izi_orders, public.izi_events, public.izi_stock from ' || roles;
  end if;
  for r in select p.oid::regprocedure as f, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'izi\_%'
  loop
    execute 'revoke all on function ' || r.f::text || ' from public';
    if roles is not null then
      execute 'revoke all on function ' || r.f::text || ' from ' || roles;
      if r.proname = any(api) then execute 'grant execute on function ' || r.f::text || ' to ' || roles; end if;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 7) Boshlangʻich hisoblar (faqat bazada yoʻq boʻlsa)
-- ---------------------------------------------------------------------
do $$
declare
  v_pass text := (select s.pass from _izi_setup s limit 1);
  need_super boolean := not exists (select 1 from public.izi_users where role = 'super');
  need_main boolean := not exists (select 1 from public.izi_users where role = 'admin' and coalesce(zone, 'main') = 'main');
  need_tosh boolean := not exists (select 1 from public.izi_users where role = 'admin' and zone = 'toshkent');
begin
  if not (need_super or need_main or need_tosh) then return; end if;
  if v_pass is null or v_pass = 'PAROLNI_YOZING' or length(v_pass) < 4 then
    raise exception 'IZI: boshlangʻich parol yozilmagan. Fayl boshidagi ''PAROLNI_YOZING'' oʻrniga kamida 4 belgili parol yozib, qayta Run bosing. Hech narsa oʻzgartirilmadi.';
  end if;
  if need_super then
    insert into public.izi_users (code, role, zone, pass_hash) values ('BOSHQARUV', 'super', 'all', public.izi_hash(v_pass))
    on conflict (code) do nothing;
  end if;
  if need_main then
    insert into public.izi_users (code, role, zone, pass_hash) values ('ADMIN', 'admin', 'main', public.izi_hash(v_pass))
    on conflict (code) do nothing;
  end if;
  if need_tosh then
    insert into public.izi_users (code, role, zone, pass_hash) values ('TOSHKENT', 'admin', 'toshkent', public.izi_hash(v_pass))
    on conflict (code) do nothing;
  end if;
end $$;

-- Supabase API yangi funksiyalarni darhol koʻrsin
notify pgrst, 'reload schema';

commit;

-- =====================================================================
--  Foydali buyruqlar (kerak boʻlganda alohida ishga tushiring):
--
--  BOSHQARUV (super-admin) parolini almashtirish:
--    update public.izi_users set pass_hash = public.izi_hash('yangi-parol') where code = 'BOSHQARUV';
--    delete from public.izi_sessions where code = 'BOSHQARUV';
--
--  Koʻp xato urinishdan bloklangan loginni ochish:
--    delete from public.izi_login_fails where code = 'ADMIN';
-- =====================================================================
