-- Crate Drop Dash: lock down the leaderboard (run once in Supabase SQL editor)
-- 1) Least privilege: browsers may only READ the leaderboard table directly.
revoke all on public.leaderboard from anon, authenticated, public;
grant select on public.leaderboard to anon, authenticated;
drop policy if exists "Anyone can add a score" on public.leaderboard;

-- 2) Stricter data rules
alter table public.leaderboard
  add constraint leaderboard_name_chars check (name ~ '^[A-Za-z0-9א-ת _.!-]{1,12}$' and btrim(name) <> ''),
  add constraint leaderboard_distance_cap check (distance between 0 and 20000),
  add constraint leaderboard_map_ok check (map in ('RANDOM','MEADOW','TUNNELS','CLIMBER','PIT HOPPER','TOWER'));
alter table public.leaderboard add column run_id uuid unique;

-- 3) Private run tickets (not reachable through the API)
create schema if not exists game_private;
revoke all on schema game_private from public, anon, authenticated;
create table game_private.runs (
  id uuid primary key default gen_random_uuid(),
  ip_hash text not null,
  created_at timestamptz not null default now(),
  used_at timestamptz
);
create index runs_ip_time_idx on game_private.runs (ip_hash, created_at);

-- start_run: called when a solo run starts. Rate limited per (hashed) IP.
create or replace function public.start_run()
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  ip text := coalesce(nullif(btrim(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1)), ''), 'unknown');
  iph text := encode(extensions.digest(ip || ':crate-drop-dash', 'sha256'), 'hex');
  rid uuid;
begin
  delete from game_private.runs where created_at < now() - interval '1 day';
  if (select count(*) from game_private.runs where ip_hash = iph and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'Too many runs, try again later' using errcode = 'P0001';
  end if;
  insert into game_private.runs (ip_hash) values (iph) returning id into rid;
  return rid;
end $$;

-- submit_score: one score per run, and the distance must be physically possible for the time the run lasted.
create or replace function public.submit_score(p_run uuid, p_name text, p_distance int, p_map text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  r game_private.runs%rowtype;
  secs numeric;
  nm text := btrim(coalesce(p_name, ''));
  new_id bigint;
begin
  select * into r from game_private.runs where id = p_run for update;
  if not found or r.used_at is not null then
    raise exception 'Invalid or used run' using errcode = 'P0001';
  end if;
  secs := extract(epoch from now() - r.created_at);
  if secs > 6 * 3600 then raise exception 'Run expired' using errcode = 'P0001'; end if;
  -- runner tops out around 4 m/s; allow 5 m/s + 20 m grace
  if p_distance is null or p_distance < 0 or p_distance > secs * 5 + 20 then
    raise exception 'Score not possible for this run' using errcode = 'P0001';
  end if;
  update game_private.runs set used_at = now() where id = p_run;
  insert into public.leaderboard (name, distance, map, run_id) values (nm, p_distance, p_map, p_run) returning id into new_id;
  return new_id;
end $$;

revoke all on function public.start_run() from public, anon, authenticated;
revoke all on function public.submit_score(uuid, text, int, text) from public, anon, authenticated;
grant execute on function public.start_run() to anon, authenticated;
grant execute on function public.submit_score(uuid, text, int, text) to anon, authenticated;
