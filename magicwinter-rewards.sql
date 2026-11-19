-- MagicWinter reward points — run in the Ares Supabase project after magicwinter-accounts.sql and magicwinter-links.sql.
-- Every point is given by these database functions, so the browser can't hand itself points.
-- © MagicWinter Studio. All rights reserved.

alter table public.mw_accounts add column if not exists floof_pro_until timestamptz;

create table if not exists public.mw_points (
  id bigserial primary key,
  username text not null references public.mw_accounts(username) on delete cascade,
  amount int not null,
  reason text not null,
  ref text not null default '',
  note text,
  created_at timestamptz not null default now(),
  unique (username, reason, ref)
);
create index if not exists mw_points_user on public.mw_points (username, created_at desc);
create table if not exists public.mw_streaks (username text primary key references public.mw_accounts(username) on delete cascade,
  last_day date, streak int not null default 0, best int not null default 0);
create table if not exists public.mw_link_rewarded (kind text not null, ext_id text not null, username text, at timestamptz not null default now(), primary key (kind, ext_id));
create table if not exists public.mw_play (username text not null references public.mw_accounts(username) on delete cascade,
  game text not null, day date not null, seconds int not null default 0, last_beat timestamptz, primary key (username, game, day));
create table if not exists public.mw_inventory (username text not null references public.mw_accounts(username) on delete cascade,
  item text not null, at timestamptz not null default now(), primary key (username, item));
create table if not exists public.mw_equipped (username text primary key references public.mw_accounts(username) on delete cascade,
  colour text, title text, badge text);
create table if not exists public.mw_projects (name text primary key);
insert into public.mw_projects (name) values ('Ares Revision'), ('AGŌN'), ('Frontlines Warfare'), ('Port Sable'), ('Terra Command'),
  ('Territory Clash'), ('Space Waves'), ('Cipher'), ('Floof AI'), ('M.E.G.A Client') on conflict do nothing;
create table if not exists public.mw_votes (project text not null references public.mw_projects(name) on update cascade on delete cascade,
  voter text not null check (char_length(voter) between 12 and 64), value int not null check (value in (-1, 1)),
  updated_at timestamptz not null default now(), primary key (project, voter));

do $$ declare t text; begin
  foreach t in array array['mw_points','mw_streaks','mw_link_rewarded','mw_play','mw_inventory','mw_equipped','mw_projects','mw_votes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- shop
create or replace function public.mw__catalog() returns table (item text, kind text, name text, cost int, val text)
language sql immutable as $$ values
  ('colour_mint','colour','Mint name colour',100,'#3ddc84'),
  ('colour_sky','colour','Sky name colour',150,'#5bb8ff'),
  ('colour_gold','colour','Gold name colour',300,'#f2c14e'),
  ('colour_aurora','colour','Aurora name colour',600,'aurora'),
  ('title_explorer','title','Explorer title',150,'Explorer'),
  ('title_critic','title','Critic title',200,'Critic'),
  ('title_veteran','title','Veteran title',500,'Veteran'),
  ('title_legend','title','Legend title',1500,'Legend'),
  ('badge_star','badge','Star badge',200,'⭐'),
  ('badge_flame','badge','Flame badge',300,'🔥'),
  ('badge_gem','badge','Gem badge',700,'💎'),
  ('badge_crown','badge','Crown badge',1200,'👑'),
  ('floof_pro_7','pro','Floof AI Pro · 7 days',500,'7'),
  ('floof_pro_30','pro','Floof AI Pro · 30 days',1500,'30'),
  ('ares_pro','pro','Ares Pro · forever',3000,'ares')
$$;

create or replace function public.mw__today() returns date language sql stable as $$ select (now() at time zone 'Europe/London')::date $$;

create or replace function public.mw__award(u text, amt int, why text, r text, nt text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into mw_points (username, amount, reason, ref, note) values (u, amt, why, coalesce(r, ''), nt) on conflict do nothing;
  get diagnostics n = row_count;
  return case when n > 0 then amt else 0 end;
end $$;

create or replace function public.mw__balance(u text) returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount), 0)::int from mw_points where username = u $$;

-- +50 the first time any outside account is ever linked (re-linking the same account elsewhere earns nothing)
create or replace function public.mw__reward_links(u text) returns int
language plpgsql security definer set search_path = public as $$
declare l record; got int := 0; n int;
begin
  for l in select kind, ext_id from mw_links where mw_username = u loop
    insert into mw_link_rewarded (kind, ext_id, username) values (l.kind, l.ext_id, u) on conflict do nothing;
    get diagnostics n = row_count;
    if n > 0 then got := got + mw__award(u, 50, 'link', l.kind || ':' || l.ext_id,
      'Linked ' || case l.kind when 'ares' then 'Ares Revision' when 'cipher' then 'Cipher' when 'frontlines' then 'Frontlines Warfare' else l.kind end); end if;
  end loop;
  return got;
end $$;

-- daily check-in: +10 a day, +50 every 7 days in a row, +25 welcome bonus once
create or replace function public.mw_checkin(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token); d date := mw__today(); s record; ns int; got int := 0;
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  got := got + mw__award(u, 25, 'welcome', '', 'Welcome bonus');
  insert into mw_streaks (username) values (u) on conflict do nothing;
  select * into s from mw_streaks where username = u for update;
  if s.last_day = d then return json_build_object('ok', true, 'already', true, 'gained', got, 'streak', s.streak, 'balance', mw__balance(u)); end if;
  ns := case when s.last_day = d - 1 then s.streak + 1 else 1 end;
  update mw_streaks set last_day = d, streak = ns, best = greatest(best, ns) where username = u;
  got := got + mw__award(u, 10, 'checkin', d::text, 'Daily check-in');
  if ns % 7 = 0 then got := got + mw__award(u, 50, 'streak', d::text, ns || '-day streak bonus'); end if;
  return json_build_object('ok', true, 'already', false, 'gained', got, 'streak', ns, 'balance', mw__balance(u));
end $$;

-- playtime: a game sends a beat about once a minute while you play. +5 points per 10 minutes, up to 30 a day per game.
create or replace function public.mw__play(u text, g text) returns json
language plpgsql security definer set search_path = public as $$
declare d date := mw__today(); p record; gap numeric; b0 int; b1 int; got int := 0; b int;
begin
  insert into mw_play (username, game, day) values (u, g, d) on conflict do nothing;
  select * into p from mw_play where username = u and game = g and day = d for update;
  gap := extract(epoch from now() - coalesce(p.last_beat, now() - interval '1 day'));
  if gap < 45 then return json_build_object('ok', true, 'minutes', p.seconds / 60, 'gained', 0); end if;
  if gap > 300 then update mw_play set last_beat = now() where username = u and game = g and day = d;
    return json_build_object('ok', true, 'minutes', p.seconds / 60, 'gained', 0); end if;
  b0 := least(p.seconds, 3600) / 600; b1 := least(p.seconds + least(gap, 90)::int, 3600) / 600;
  update mw_play set seconds = seconds + least(gap, 90)::int, last_beat = now() where username = u and game = g and day = d;
  for b in b0 + 1 .. b1 loop got := got + mw__award(u, 5, 'play', g || ':' || d || ':' || b, 'Played ' || initcap(g)); end loop;
  return json_build_object('ok', true, 'minutes', (p.seconds + least(gap, 90)::int) / 60, 'gained', got);
end $$;
create or replace function public.mw_play_beat(p_token text, p_game text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token);
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  if p_game not in ('frontlines', 'spacewaves', 'territoryclash', 'terracommand', 'portsable') then return json_build_object('error', 'Unknown game.'); end if;
  return mw__play(u, p_game);
end $$;
-- Frontlines Warfare uses its own accounts: points go to the MagicWinter account it's linked to
create or replace function public.mw_play_beat_fl(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare f text; u text;
begin
  begin execute 'select username from fl_sessions where token = $1 and expires_at > now()' into f using p_token;
  exception when others then return json_build_object('error', 'Frontlines accounts aren''t set up yet.'); end;
  if f is null then return json_build_object('error', 'Please sign in to Frontlines again.'); end if;
  select mw_username into u from mw_links where kind = 'frontlines' and ext_id = f limit 1;
  if u is null then return json_build_object('ok', false, 'linked', false, 'error', 'Link a MagicWinter account to earn points.'); end if;
  return mw__play(u, 'frontlines');
end $$;

-- ratings (the votes on the MagicWinter site). Signed-in ratings earn +5 the first time you rate each project.
create or replace function public.mw_vote_totals() returns table (project text, up bigint, down bigint)
language sql stable security definer set search_path = public as $$
  select project, count(*) filter (where value = 1), count(*) filter (where value = -1) from mw_votes group by project $$;
create or replace function public.mw__vote(p text, v text, val int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from mw_projects where name = p) then raise exception 'Unknown project'; end if;
  if val = 0 then delete from mw_votes where project = p and voter = v;
  elsif val in (-1, 1) then insert into mw_votes (project, voter, value) values (p, v, val)
    on conflict (project, voter) do update set value = excluded.value, updated_at = now();
  else raise exception 'Bad vote'; end if;
end $$;
create or replace function public.mw_cast_vote(p_project text, p_voter text, p_value int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_voter like 'mw:%' or char_length(coalesce(p_voter, '')) not between 12 and 64 then raise exception 'Bad voter'; end if;
  perform mw__vote(p_project, p_voter, p_value);
end $$;
create or replace function public.mw_rate(p_token text, p_project text, p_value int) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token); got int := 0;
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  if not exists (select 1 from mw_projects where name = p_project) then return json_build_object('error', 'Unknown project.'); end if;
  perform mw__vote(p_project, 'mw:' || u, p_value);
  if p_value <> 0 then got := mw__award(u, 5, 'rate', p_project, 'Rated ' || p_project); end if;
  return json_build_object('ok', true, 'gained', got, 'balance', mw__balance(u));
end $$;

-- everything the Rewards window needs
create or replace function public.mw_points_me(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token); s record; e record; acc record; ares_pro boolean := false; al text;
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  perform mw__reward_links(u);
  select * into s from mw_streaks where username = u;
  select * into e from mw_equipped where username = u;
  select * into acc from mw_accounts where username = u;
  select ext_id into al from mw_links where mw_username = u and kind = 'ares';
  if al is not null then select coalesce((app_data->'aresPro'->>'active')::boolean, false) into ares_pro from accounts where lower(username) = al; end if;
  return json_build_object('ok', true, 'balance', mw__balance(u),
    'streak', coalesce(s.streak, 0), 'best', coalesce(s.best, 0), 'checked_today', coalesce(s.last_day = mw__today(), false),
    'equipped', json_build_object('colour', e.colour, 'title', e.title, 'badge', e.badge),
    'owned', coalesce((select json_agg(item) from mw_inventory where username = u), '[]'::json),
    'floof_pro_until', acc.floof_pro_until, 'ares_linked', al is not null, 'ares_pro', coalesce(ares_pro, false),
    'linked', coalesce((select json_agg(kind) from mw_links where mw_username = u), '[]'::json),
    'rated', coalesce((select json_object_agg(project, value) from mw_votes where voter = 'mw:' || u), '{}'::json),
    'play_today', coalesce((select json_object_agg(game, seconds / 60) from mw_play where username = u and day = mw__today()), '{}'::json),
    'history', coalesce((select json_agg(h) from (select amount, note, created_at from mw_points where username = u order by created_at desc, id desc limit 15) h), '[]'::json),
    'catalog', (select json_agg(c) from mw__catalog() c));
end $$;

-- spend points
create or replace function public.mw_buy(p_token text, p_item text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token); c record; bal int; al text; ok boolean;
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  perform 1 from mw_accounts where username = u for update;   -- one purchase at a time per account
  select * into c from mw__catalog() where item = p_item;
  if not found then return json_build_object('error', 'That isn''t in the shop.'); end if;
  bal := mw__balance(u);
  if bal < c.cost then return json_build_object('error', 'You need ' || (c.cost - bal) || ' more points.'); end if;
  if c.kind in ('colour', 'title', 'badge') then
    if exists (select 1 from mw_inventory where username = u and item = c.item) then return json_build_object('error', 'You already own that.'); end if;
    insert into mw_inventory (username, item) values (u, c.item);
    insert into mw_equipped (username) values (u) on conflict do nothing;
    execute format('update mw_equipped set %I = $1 where username = $2', c.kind) using c.item, u;
    insert into mw_points (username, amount, reason, ref, note) values (u, -c.cost, 'buy', c.item, 'Bought ' || c.name);
  elsif c.item like 'floof_pro_%' then
    update mw_accounts set floof_pro_until = greatest(now(), coalesce(floof_pro_until, now())) + (c.val || ' days')::interval where username = u;
    insert into mw_points (username, amount, reason, ref, note) values (u, -c.cost, 'buy', c.item || ':' || gen_random_uuid(), 'Bought ' || c.name);
  elsif c.item = 'ares_pro' then
    select ext_id into al from mw_links where mw_username = u and kind = 'ares';
    if al is null then return json_build_object('error', 'Link your Ares Revision account first (Linked accounts).'); end if;
    select coalesce((app_data->'aresPro'->>'active')::boolean, false) into ok from accounts where lower(username) = al;
    if ok then return json_build_object('error', 'Your Ares account already has Ares Pro.'); end if;
    update accounts set app_data = jsonb_set(coalesce(app_data, '{}'::jsonb), '{aresPro}', jsonb_build_object('active', true,
      'grantedAt', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), 'grantedBy', 'MagicWinter points', 'method', 'points'))
      where lower(username) = al;
    insert into mw_points (username, amount, reason, ref, note) values (u, -c.cost, 'buy', 'ares_pro:' || al, 'Bought ' || c.name);
  end if;
  return json_build_object('ok', true, 'item', c.item, 'balance', mw__balance(u),
    'floof_pro_until', (select floof_pro_until from mw_accounts where username = u));
end $$;

create or replace function public.mw_equip(p_token text, p_kind text, p_item text) returns json
language plpgsql security definer set search_path = public as $$
declare u text := mw__user(p_token);
begin
  if u is null then return json_build_object('error', 'Please sign in again.'); end if;
  if p_kind not in ('colour', 'title', 'badge') then return json_build_object('error', 'Bad slot.'); end if;
  if p_item is not null and not exists (select 1 from mw_inventory i join mw__catalog() c using (item) where i.username = u and i.item = p_item and c.kind = p_kind) then
    return json_build_object('error', 'You don''t own that.'); end if;
  insert into mw_equipped (username) values (u) on conflict do nothing;
  execute format('update mw_equipped set %I = $1 where username = $2', p_kind) using p_item, u;
  return json_build_object('ok', true);
end $$;

-- Floof AI asks this to see if someone has Pro
create or replace function public.mw_status(p_token text) returns json
language sql stable security definer set search_path = public as $$
  select coalesce((select json_build_object('ok', true, 'username', a.display_name, 'pro_until', a.floof_pro_until)
    from mw_sessions s join mw_accounts a using (username) where s.token = p_token and s.expires_at > now()),
    json_build_object('error', 'signed out'))
$$;

do $$ declare f text; begin
  foreach f in array array['mw__catalog()','mw__today()','mw__award(text,int,text,text,text)','mw__balance(text)','mw__reward_links(text)',
    'mw__play(text,text)','mw__vote(text,text,int)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
  end loop;
  foreach f in array array['mw_checkin(text)','mw_play_beat(text,text)','mw_play_beat_fl(text)','mw_vote_totals()','mw_cast_vote(text,text,int)',
    'mw_rate(text,text,int)','mw_points_me(text)','mw_buy(text,text)','mw_equip(text,text,text)','mw_status(text)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
notify pgrst, 'reload schema';
