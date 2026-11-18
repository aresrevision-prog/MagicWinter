-- MagicWinter linked accounts (Ares Revision + Cipher) — run once in the Ares Supabase project
-- (the same one that holds MagicWinter accounts): SQL Editor -> New query -> paste -> Run.
-- Run magicwinter-accounts.sql first.
--
-- BEFORE RUNNING: change CHANGE-ME on the line marked below to a long random secret,
-- and put the exact same secret in Vercel -> MagicWinter project -> Settings -> Environment Variables
-- as LINK_SECRET. Never commit the real secret to GitHub.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.mw_links (
  mw_username text not null references public.mw_accounts(username) on delete cascade,
  kind        text not null check (kind in ('ares', 'cipher')),
  ext_id      text not null,
  ext_name    text,
  linked_at   timestamptz not null default now(),
  primary key (kind, ext_id),
  unique (mw_username, kind)
);
alter table public.mw_links enable row level security;
revoke all on public.mw_links from anon, authenticated;

create table if not exists public.mw_link_secret (id int primary key default 1, hash text not null);
alter table public.mw_link_secret enable row level security;
revoke all on public.mw_link_secret from anon, authenticated;
insert into public.mw_link_secret (id, hash)
values (1, encode(extensions.digest('CHANGE-ME', 'sha256'), 'hex'))   -- <== your LINK_SECRET
on conflict (id) do update set hash = excluded.hash;

-- who is signed in (MagicWinter session token -> username)
create or replace function public.mw__user(p_token text) returns text
language sql stable security definer set search_path = public as $$
  select username from mw_sessions where token = p_token and expires_at > now()
$$;
revoke all on function public.mw__user(text) from public, anon, authenticated;

-- save a link (one Ares / one Cipher per MagicWinter account; each outside account links to one MagicWinter account)
create or replace function public.mw__save_link(u text, k text, id text, nm text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from mw_links where kind = k and ext_id = id and mw_username <> u) then
    return json_build_object('error', case k when 'ares' then 'That Ares account' else 'That Cipher number' end
                                      || ' is already linked to a different MagicWinter account.');
  end if;
  delete from mw_links where mw_username = u and kind = k;
  insert into mw_links (mw_username, kind, ext_id, ext_name) values (u, k, id, nm)
  on conflict (kind, ext_id) do update set ext_name = excluded.ext_name, linked_at = now();
  return json_build_object('ok', true, 'kind', k, 'ext_id', id, 'ext_name', nm);
end $$;
revoke all on function public.mw__save_link(text, text, text, text) from public, anon, authenticated;

-- list my links
create or replace function public.mw_links_list(p_token text) returns json
language plpgsql stable security definer set search_path = public as $$
declare u text := mw__user(p_token);
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  return json_build_object('ok', true, 'links', coalesce((
    select json_agg(json_build_object('kind', kind, 'ext_id', ext_id, 'ext_name', ext_name, 'linked_at', linked_at) order by kind)
    from mw_links where mw_username = u), '[]'::json));
end $$;

-- link Ares: call this with the user's Ares sign-in token as the Authorization header.
-- The token is signed by Ares' login server, so it proves who the Ares user is.
create or replace function public.mw_link_ares(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token); claim text := lower(coalesce(public.current_username(), '')); a record;
begin
  if u is null then return json_build_object('error', 'Please sign in to MagicWinter again.'); end if;
  if claim = '' then return json_build_object('error', 'Ares sign-in didn''t go through. Try again.'); end if;
  select username, coalesce(display_name, username) as nm into a from accounts where lower(username) = claim limit 1;
  if not found then return json_build_object('error', 'Couldn''t confirm that Ares account.'); end if;
  return mw__save_link(u, 'ares', lower(a.username), a.nm);
end $$;

-- link Cipher: only the MagicWinter site's checker (which knows LINK_SECRET) can call this,
-- after it has proved the person holds that Cipher number's private key.
create or replace function public.mw_link_cipher(p_secret text, p_token text, p_num text, p_name text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u text := mw__user(p_token);
begin
  if not exists (select 1 from mw_link_secret where hash = encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex')) then
    perform pg_sleep(0.5); return json_build_object('error', 'Not allowed.');
  end if;
  if u is null then return json_build_object('error', 'Please sign in to MagicWinter again.'); end if;
  if coalesce(p_num, '') !~ '^\d{4,12}$' then return json_build_object('error', 'That isn''t a Cipher number.'); end if;
  return mw__save_link(u, 'cipher', p_num, left(coalesce(nullif(trim(p_name), ''), '#' || p_num), 40));
end $$;

-- unlink
create or replace function public.mw_unlink(p_token text, p_kind text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token);
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  delete from mw_links where mw_username = u and kind = p_kind;
  return json_build_object('ok', true);
end $$;

grant execute on function public.mw_links_list(text), public.mw_link_ares(text),
  public.mw_link_cipher(text, text, text, text), public.mw_unlink(text, text) to anon, authenticated;
