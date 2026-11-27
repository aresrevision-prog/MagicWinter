-- MagicWinter accounts everywhere: Tycoon World, Frontlines Warfare, Bed Wars and Cipher sign in with a MagicWinter account.
-- Old accounts are turned into (or linked to) MagicWinter accounts, keep their data, and earn +100 MW points each (once).
-- © MagicWinter Studio. All rights reserved.

-- old accounts that can earn the +100 transfer bonus (each one only once)
create table if not exists public.mw_transfer_pool (
  kind text not null, ext_id text not null, claimed_by text, claimed_at timestamptz,
  primary key (kind, ext_id));
alter table public.mw_transfer_pool enable row level security;

-- per-user app secrets (Cipher keeps its message key locked with this, so changing your MW password never locks you out)
create table if not exists public.mw_vault (
  username text not null, app text not null, secret text not null, primary key (username, app));
alter table public.mw_vault enable row level security;

create or replace function public.mw__transfer(u text, k text, id text) returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update mw_transfer_pool set claimed_by = u, claimed_at = now() where kind = k and ext_id = id and claimed_by is null;
  get diagnostics n = row_count;
  if n = 0 then return 0; end if;
  return mw__award(u, 100, 'transfer', k || ':' || id, 'Moved your ' ||
    case k when 'tycoon' then 'Tycoon World' when 'frontlines' then 'Frontlines Warfare' when 'bedwars' then 'Bed Wars' when 'cipher' then 'Cipher' else k end
    || ' account to MagicWinter');
end $$;

create or replace function public.mw__free_name(base text) returns text
language plpgsql security definer set search_path = public as $$
declare b text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]', '', 'g'), 17); u text; i int := 0;
begin
  if b !~ '^[a-z0-9]' then b := 'mw' || b; end if;
  if length(b) < 3 then b := rpad(b, 3, '0'); end if;
  u := b;
  while exists (select 1 from mw_accounts where username = u) loop i := i + 1; u := b || i; end loop;
  return u;
end $$;

-- ---------- Tycoon World ----------
create or replace function public.tyc_login_mw(p_mw_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare m text := mw__user(p_mw_token); vid uuid; nm text; base text; un text; i int := 0; t uuid;
begin
  if m is null then raise exception 'MagicWinter sign-in expired — sign in again'; end if;
  select ext_id::uuid into vid from mw_links where kind = 'tycoon' and mw_username = m;
  if vid is null or not exists (select 1 from tyc_users where tyc_users.id = vid) then
    select display_name into nm from mw_accounts where username = m;
    base := left(regexp_replace(coalesce(nm, m), '[^A-Za-z0-9_]', '', 'g'), 17);
    if length(base) < 3 or lower(base) like 'guest\_%' then base := left(m, 17); end if;
    un := base;
    while exists (select 1 from tyc_users where lower(username) = lower(un)) loop i := i + 1; un := base || i; end loop;
    insert into tyc_users (username, pass_hash) values (un, crypt(encode(gen_random_bytes(18), 'hex'), gen_salt('bf')))
      returning tyc_users.id into vid;
    delete from mw_links where mw_username = m and kind = 'tycoon';
    insert into mw_links (mw_username, kind, ext_id, ext_name) values (m, 'tycoon', vid::text, un);
  end if;
  perform mw__transfer(m, 'tycoon', vid::text);
  insert into tyc_sessions (user_id) values (vid) returning token into t;
  return tyc_user_json(vid, t);
end $$;

create or replace function public.tyc_login(p_username text, p_password text) returns json
language plpgsql security definer set search_path = public as $$
begin raise exception 'Tycoon World now uses MagicWinter accounts — sign in with MagicWinter'; end $$;
create or replace function public.tyc_signup(p_username text, p_password text) returns json
language plpgsql security definer set search_path = public as $$
begin raise exception 'Tycoon World now uses MagicWinter accounts — create a MagicWinter account'; end $$;

-- ---------- Frontlines Warfare (fl_login_mw already exists; old logins switched off) ----------
create or replace function public.fl_login(p_username text, p_password text) returns json
language sql security definer set search_path = public as $$
  select json_build_object('error', 'Frontlines now uses MagicWinter accounts — sign in with MagicWinter.') $$;
create or replace function public.fl_signup(p_username text, p_password text) returns json
language sql security definer set search_path = public as $$
  select json_build_object('error', 'Frontlines now uses MagicWinter accounts — create a MagicWinter account.') $$;

create or replace function public.fl_mw_bonus(p_mw_token text) returns json
language plpgsql security definer set search_path = public as $$
declare m text := mw__user(p_mw_token); id text;
begin
  if m is null then return json_build_object('error', 'signed out'); end if;
  select ext_id into id from mw_links where kind = 'frontlines' and mw_username = m;
  return json_build_object('ok', true, 'got', case when id is null then 0 else mw__transfer(m, 'frontlines', id) end);
end $$;

-- ---------- Bed Wars: the player id comes from the MagicWinter account ----------
create or replace function public.bw_mw_uid(p_mw_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare m text := mw__user(p_mw_token); id text; nm text;
begin
  if m is null then return json_build_object('error', 'MagicWinter sign-in expired — sign in again.'); end if;
  select display_name into nm from mw_accounts where username = m;
  select ext_id into id from mw_links where kind = 'bedwars' and mw_username = m;
  if id is null then
    id := 'm' || encode(gen_random_bytes(11), 'hex');
    insert into mw_links (mw_username, kind, ext_id, ext_name) values (m, 'bedwars', id, coalesce(nm, m));
  end if;
  perform mw__transfer(m, 'bedwars', id);
  return json_build_object('ok', true, 'uid', id, 'name', coalesce(nm, m), 'mw', m);
end $$;

-- ---------- Cipher ----------
create or replace function public.cipher_mw(p_mw_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare m text := mw__user(p_mw_token); s text; n text; nm text;
begin
  if m is null then return json_build_object('error', 'MagicWinter sign-in expired — sign in again.'); end if;
  select secret into s from mw_vault where username = m and app = 'cipher';
  if s is null then
    s := encode(gen_random_bytes(32), 'hex');
    insert into mw_vault (username, app, secret) values (m, 'cipher', s) on conflict do nothing;
    select secret into s from mw_vault where username = m and app = 'cipher';
  end if;
  select ext_id into n from mw_links where kind = 'cipher' and mw_username = m;
  select display_name into nm from mw_accounts where username = m;
  return json_build_object('ok', true, 'mw', m, 'name', coalesce(nm, m), 'num', n, 'key', s);
end $$;

-- called by the MagicWinter site's /api/link-cipher after it has proved the number is theirs
create or replace function public.mw_cipher_bonus(p_secret text, p_token text, p_num text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u text := mw__user(p_token);
begin
  if not exists (select 1 from mw_link_secret where hash = encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex')) then
    perform pg_sleep(0.5); return json_build_object('error', 'Not allowed.'); end if;
  if u is null or not exists (select 1 from mw_links where kind = 'cipher' and ext_id = p_num and mw_username = u) then
    return json_build_object('error', 'Not linked.'); end if;
  insert into mw_transfer_pool (kind, ext_id) values ('cipher', p_num) on conflict do nothing;
  return json_build_object('ok', true, 'got', mw__transfer(u, 'cipher', p_num));
end $$;

-- the old 50-point link reward stays for Ares, Cipher and Frontlines only (moved accounts get the +100 instead)
create or replace function public.mw__reward_links(u text) returns integer
language plpgsql security definer set search_path = public as $$
declare l record; got int := 0; n int;
begin
  for l in select kind, ext_id from mw_links where mw_username = u and kind in ('ares', 'cipher', 'frontlines') loop
    insert into mw_link_rewarded (kind, ext_id, username) values (l.kind, l.ext_id, u) on conflict do nothing;
    get diagnostics n = row_count;
    if n > 0 then got := got + mw__award(u, 50, 'link', l.kind || ':' || l.ext_id,
      'Linked ' || case l.kind when 'ares' then 'Ares Revision' when 'cipher' then 'Cipher' when 'frontlines' then 'Frontlines Warfare' else l.kind end); end if;
  end loop;
  return got;
end $$;
revoke all on function public.mw__reward_links(text) from public, anon, authenticated;

-- ---------- permissions ----------
revoke all on function public.mw__transfer(text, text, text) from public, anon, authenticated;
revoke all on function public.mw__free_name(text) from public, anon, authenticated;
grant execute on function public.tyc_login_mw(text), public.fl_mw_bonus(text), public.bw_mw_uid(text), public.cipher_mw(text),
  public.mw_cipher_bonus(text, text, text) to anon, authenticated;

-- ---------- one-off: move every existing account over ----------
do $$
declare r record; m text; t text;
begin
  -- Tycoon World: every real (non-guest) account becomes a MagicWinter account with the same username + password
  for r in select * from tyc_users where not is_guest loop
    insert into mw_transfer_pool (kind, ext_id) values ('tycoon', r.id::text) on conflict do nothing;
    select mw_username into m from mw_links where kind = 'tycoon' and ext_id = r.id::text;
    if m is null then
      if lower(r.username) = 'nosirrah' then m := 'magicwinter';                -- the studio's own account
      else
        m := mw__free_name(r.username);
        insert into mw_accounts (username, display_name, pass_hash) values (m, r.username, r.pass_hash);
      end if;
      delete from mw_links where mw_username = m and kind = 'tycoon';
      insert into mw_links (mw_username, kind, ext_id, ext_name) values (m, 'tycoon', r.id::text, coalesce(r.display_name, r.username));
    end if;
    perform mw__transfer(m, 'tycoon', r.id::text);
  end loop;

  -- Frontlines Warfare
  for r in select * from fl_accounts loop
    insert into mw_transfer_pool (kind, ext_id) values ('frontlines', r.username) on conflict do nothing;
    select mw_username into m from mw_links where kind = 'frontlines' and ext_id = r.username;
    if m is null then
      if r.username = 'nosirrah' then m := 'magicwinter';
      elsif exists (select 1 from mw_links l join tyc_users u on u.id::text = l.ext_id
                    where l.kind = 'tycoon' and lower(u.username) = r.username) then
        select l.mw_username into m from mw_links l join tyc_users u on u.id::text = l.ext_id
          where l.kind = 'tycoon' and lower(u.username) = r.username limit 1;
      else
        m := mw__free_name(r.username);
        insert into mw_accounts (username, display_name, pass_hash) values (m, coalesce(r.display_name, r.username), r.pass_hash);
      end if;
      if not exists (select 1 from mw_links where mw_username = m and kind = 'frontlines') then
        insert into mw_links (mw_username, kind, ext_id, ext_name) values (m, 'frontlines', r.username, coalesce(r.display_name, r.username));
      end if;
    end if;
    perform mw__transfer(m, 'frontlines', r.username);
  end loop;

  -- Bed Wars: profiles had no password, so each is matched to the MagicWinter account with the same player name
  for r in select split_part(path, '/', 3) as uid, data->>'name' as nm from bw_docs where path like 'data/users/%/profile' loop
    insert into mw_transfer_pool (kind, ext_id) values ('bedwars', r.uid) on conflict do nothing;
    if exists (select 1 from mw_links where kind = 'bedwars' and ext_id = r.uid) then continue; end if;
    m := null;
    if lower(r.nm) = 'nosirrah' then m := 'magicwinter';
    else
      select l.mw_username into m from mw_links l join tyc_users u on u.id::text = l.ext_id
        where l.kind = 'tycoon' and lower(u.username) = lower(r.nm) limit 1;
      if m is null then select username into m from mw_accounts where username = lower(r.nm); end if;
    end if;
    if m is not null and not exists (select 1 from mw_links where mw_username = m and kind = 'bedwars') then
      insert into mw_links (mw_username, kind, ext_id, ext_name) values (m, 'bedwars', r.uid, r.nm);
      perform mw__transfer(m, 'bedwars', r.uid);
    end if;
  end loop;

  -- Cipher: numbers already linked to a MagicWinter account get their bonus now
  for r in select * from mw_links where kind = 'cipher' loop
    insert into mw_transfer_pool (kind, ext_id) values ('cipher', r.ext_id) on conflict do nothing;
    perform mw__transfer(r.mw_username, 'cipher', r.ext_id);
  end loop;
end $$;
