-- MagicWinter Studio: project ratings
-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run.

create table if not exists public.mw_votes (
  project    text not null check (char_length(project) between 1 and 60),
  voter      text not null check (char_length(voter) between 12 and 64),
  value      int  not null check (value in (-1, 1)),
  updated_at timestamptz not null default now(),
  primary key (project, voter)
);

-- Lock the table: visitors can only vote through the two functions below.
alter table public.mw_votes enable row level security;

create or replace function public.mw_cast_vote(p_project text, p_voter text, p_value int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(p_project,'')) not between 1 and 60
     or char_length(coalesce(p_voter,'')) not between 12 and 64 then
    raise exception 'invalid vote';
  end if;
  if p_value = 0 then
    delete from mw_votes where project = p_project and voter = p_voter;
  elsif p_value in (-1, 1) then
    insert into mw_votes (project, voter, value) values (p_project, p_voter, p_value)
    on conflict (project, voter) do update set value = excluded.value, updated_at = now();
  else
    raise exception 'invalid vote';
  end if;
end $$;

create or replace function public.mw_vote_totals()
returns table (project text, up bigint, down bigint)
language sql stable security definer set search_path = public as $$
  select project,
         count(*) filter (where value = 1),
         count(*) filter (where value = -1)
  from mw_votes group by project
$$;

revoke all on function public.mw_cast_vote(text, text, int) from public;
revoke all on function public.mw_vote_totals() from public;
grant execute on function public.mw_cast_vote(text, text, int) to anon, authenticated;
grant execute on function public.mw_vote_totals() to anon, authenticated;
