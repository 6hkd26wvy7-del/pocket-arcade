-- BOYGAMES — MIGRATION v8 + v9 (BoyBlocks vérifié côté base + badges à paliers)
-- À coller EN ENTIER dans Supabase > SQL Editor de la base TEST (boygam-test), puis "Run".
-- À lancer APRÈS la migration v6+v7 (schema_v6_v7_a_lancer.sql) : le script le vérifie et s'arrête sinon.
-- Tout-ou-rien : en cas de moindre problème, RIEN n'est appliqué. Relançable sans danger.
-- Ne modifie, ne supprime et n'écrase aucune donnée existante (profils, scores, badges, BOYCOINS, messages, amis).
-- Il AJOUTE : tables bb_shapes / boyblocks_runs / badge_tracks / user_tiers, la colonne profiles.favorites,
-- des fonctions, et une mission BoyBlocks.
begin;

do $$ begin
  if to_regprocedure('public.guard_action(uuid)') is null or to_regclass('public.bug_reports') is null
     or to_regprocedure('public.public_profile(text)') is null or to_regclass('public.blocks') is null then
    raise exception 'PRE-CONTROLE : la migration v6+v7 (schema_v6_v7_a_lancer.sql) doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

-- Photographie avant migration, gardée dans la transaction (pas de table temporaire).
-- Garde-fou : si l'éditeur exécutait le script en plusieurs morceaux, le script s'arrête ici, avant toute modification.
do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'user_badges', (select count(*) from public.user_badges), 'bc_ledger', (select count(*) from public.bc_ledger),
    'messages', (select count(*) from public.messages), 'friendships', (select count(*) from public.friendships),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

-- BOYGAMES schema v8 — BOYBLOCKS : parties vérifiées côté base (aucun score envoyé par le téléphone n'est cru).
-- Principe : le serveur donne la graine (le "tirage" des pièces), le joueur envoie la liste de ses coups,
-- la base REJOUE la partie avec exactement les mêmes règles que le jeu, et calcule elle-même le score.
-- Additif et idempotent. Dépend de v1–v7. Aucune donnée existante n'est modifiée.

create table if not exists public.bb_shapes (
  id int primary key, name text not null, weight int not null, h int not null, w int not null, n int not null,
  cells int[] not null            -- [ligne,colonne, ligne,colonne, ...] complété par -1
);
alter table public.bb_shapes enable row level security;     -- aucune règle de lecture : table interne
revoke all on public.bb_shapes from anon, authenticated;
insert into public.bb_shapes (id, name, weight, h, w, n, cells) values
  (0, 'dot', 3, 1, 1, 1, '{0,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (1, 'h2', 6, 1, 2, 2, '{0,0,0,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (2, 'v2', 6, 2, 1, 2, '{0,0,1,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (3, 'h3', 7, 1, 3, 3, '{0,0,0,1,0,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (4, 'v3', 7, 3, 1, 3, '{0,0,1,0,2,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (5, 'h4', 4, 1, 4, 4, '{0,0,0,1,0,2,0,3,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (6, 'v4', 4, 4, 1, 4, '{0,0,1,0,2,0,3,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (7, 'h5', 2, 1, 5, 5, '{0,0,0,1,0,2,0,3,0,4,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (8, 'v5', 2, 5, 1, 5, '{0,0,1,0,2,0,3,0,4,0,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (9, 'sq2', 6, 2, 2, 4, '{0,0,0,1,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (10, 'sq3', 2, 3, 3, 9, '{0,0,0,1,0,2,1,0,1,1,1,2,2,0,2,1,2,2}'),
  (11, 'r23', 3, 2, 3, 6, '{0,0,0,1,0,2,1,0,1,1,1,2,-1,-1,-1,-1,-1,-1}'),
  (12, 'r32', 3, 3, 2, 6, '{0,0,0,1,1,0,1,1,2,0,2,1,-1,-1,-1,-1,-1,-1}'),
  (13, 'c2a', 5, 2, 2, 3, '{0,0,0,1,1,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (14, 'c2b', 5, 2, 2, 3, '{0,0,0,1,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (15, 'c2c', 5, 2, 2, 3, '{0,0,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (16, 'c2d', 5, 2, 2, 3, '{0,1,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (17, 'c3a', 3, 3, 3, 5, '{0,0,0,1,0,2,1,0,2,0,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (18, 'c3b', 3, 3, 3, 5, '{0,0,0,1,0,2,1,2,2,2,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (19, 'c3c', 3, 3, 3, 5, '{0,0,1,0,2,0,2,1,2,2,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (20, 'c3d', 3, 3, 3, 5, '{0,2,1,2,2,0,2,1,2,2,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (21, 't3a', 3, 2, 3, 4, '{0,0,0,1,0,2,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (22, 't3b', 3, 2, 3, 4, '{0,1,1,0,1,1,1,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (23, 't3c', 3, 3, 2, 4, '{0,0,1,0,1,1,2,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (24, 't3d', 3, 3, 2, 4, '{0,1,1,0,1,1,2,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (25, 'z2a', 2, 2, 3, 4, '{0,0,0,1,1,1,1,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (26, 'z2b', 2, 2, 3, 4, '{0,1,0,2,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (27, 'z2c', 2, 3, 2, 4, '{0,1,1,0,1,1,2,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (28, 'z2d', 2, 3, 2, 4, '{0,0,1,0,1,1,2,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}')
on conflict (id) do update set name = excluded.name, weight = excluded.weight, h = excluded.h, w = excluded.w, n = excluded.n, cells = excluded.cells;

create table if not exists public.boyblocks_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  seed bigint not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  score int, moves int
);
create index if not exists boyblocks_runs_user on public.boyblocks_runs (user_id, started_at desc);
alter table public.boyblocks_runs enable row level security;
revoke all on public.boyblocks_runs from anon, authenticated;

-- ===== moteur (miroir exact de shared/boyblocks-engine.js ; vérifié par comparaison automatique) =====
create or replace function public.bb_imul(a bigint, b bigint) returns bigint language sql immutable as $$
  select (((a & 65535) * b) + ((((a >> 16) * b) & 65535) << 16)) & 4294967295
$$;

create or replace function public.bb_step(a bigint, out o_a bigint, out o_v double precision) language plpgsql immutable as $$
declare t bigint;
begin
  o_a := (a + 1831565813) & 4294967295;
  t := o_a;
  t := public.bb_imul(t # (t >> 15), t | 1);
  t := t # ((t + public.bb_imul(t # (t >> 7), t | 61)) & 4294967295);
  o_v := ((t # (t >> 14)) & 4294967295)::double precision / 4294967296.0;
end $$;

create or replace function public.bb_mix(seed bigint, idx int, salt int) returns bigint language plpgsql immutable as $$
declare h bigint;
begin
  h := (seed # public.bb_imul(idx + 1, 2654435761) # public.bb_imul(salt + 1, 2246822507)) & 4294967295;
  h := public.bb_imul(h # (h >> 16), 2146121005);
  h := public.bb_imul(h # (h >> 15), 2221713035);
  return (h # (h >> 16)) & 4294967295;
end $$;

create or replace function public.bb_fits(grid int[], shp int[], shn int[], id int, r int, c int) returns boolean language plpgsql immutable as $$
declare i int; rr int; cc int;
begin
  for i in 0 .. shn[id + 1] - 1 loop
    rr := r + shp[id + 1][2 * i + 1]; cc := c + shp[id + 1][2 * i + 2];
    if rr < 0 or cc < 0 or rr >= 8 or cc >= 8 or grid[rr * 8 + cc + 1] <> 0 then return false; end if;
  end loop;
  return true;
end $$;

create or replace function public.bb_can(grid int[], shp int[], shn int[], shh int[], shw int[], id int) returns boolean language plpgsql immutable as $$
declare r int; c int;
begin
  for r in 0 .. 8 - shh[id + 1] loop
    for c in 0 .. 8 - shw[id + 1] loop
      if public.bb_fits(grid, shp, shn, id, r, c) then return true; end if;
    end loop;
  end loop;
  return false;
end $$;

-- lot n°idx : 6 entiers = 3 pièces puis 3 couleurs
create or replace function public.bb_deal(seed bigint, idx int, grid int[], ensure boolean, shp int[], shn int[], shh int[], shw int[], shwt int[], total int)
returns int[] language plpgsql immutable as $$
declare salt int; st bigint; v double precision; p int[3]; col int[3]; k int; x double precision; j int; res int[]; ok boolean;
begin
  for salt in 0 .. (case when ensure then 11 else 0 end) loop
    st := public.bb_mix(seed, idx, salt);
    for k in 1 .. 3 loop
      select o_a, o_v into st, v from public.bb_step(st);
      x := v * total; p[k] := array_length(shwt, 1) - 1;
      for j in 1 .. array_length(shwt, 1) loop
        x := x - shwt[j];
        if x < 0 then p[k] := j - 1; exit; end if;
      end loop;
    end loop;
    for k in 1 .. 3 loop
      select o_a, o_v into st, v from public.bb_step(st);
      col[k] := 1 + floor(v * 7)::int;
    end loop;
    res := array[p[1], p[2], p[3], col[1], col[2], col[3]];
    ok := public.bb_can(grid, shp, shn, shh, shw, p[1]) or public.bb_can(grid, shp, shn, shh, shw, p[2]) or public.bb_can(grid, shp, shn, shh, shw, p[3]);
    if not ensure or ok then return res; end if;
  end loop;
  return res;
end $$;

create or replace function public.bb_replay(p_seed bigint, p_moves jsonb, p_ensure boolean default true)
returns table (ok boolean, err text, at int, score int, moves int, lines int, best_streak int, over boolean)
language plpgsql stable as $$
declare
  shwt int[]; shn int[]; shh int[]; shw int[]; shp int[]; total int;
  grid int[] := array_fill(0, array[64]);
  pc int[]; g_score int := 0; streak int := 0; best int := 0; nlines int := 0; nmoves int := 0; idx int := 0; is_over boolean;
  i int; m jsonb; slot int; r int; c int; id int; k int; rr int; cc int; n int; gain int; clr int;
  rows_full boolean[]; cols_full boolean[]; full boolean; any_left boolean; mult numeric;
begin
  select array_agg(weight order by s.id), array_agg(s.n order by s.id), array_agg(h order by s.id), array_agg(w order by s.id), array_agg(cells order by s.id), sum(weight)::int
    into shwt, shn, shh, shw, shp, total from public.bb_shapes s;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) > 3000 then
    return query select false, 'moves', 0, 0, 0, 0, 0, false; return;
  end if;
  pc := public.bb_deal(p_seed, 0, grid, p_ensure, shp, shn, shh, shw, shwt, total);
  is_over := not (public.bb_can(grid, shp, shn, shh, shw, pc[1]) or public.bb_can(grid, shp, shn, shh, shw, pc[2]) or public.bb_can(grid, shp, shn, shh, shw, pc[3]));
  for i in 0 .. jsonb_array_length(p_moves) - 1 loop
    if is_over then return query select false, 'over', i, g_score, nmoves, nlines, best, is_over; return; end if;
    m := p_moves -> i;
    if jsonb_typeof(m) <> 'array' or jsonb_array_length(m) <> 3
       or (m ->> 0) !~ '^[0-9]+$' or (m ->> 1) !~ '^-?[0-9]+$' or (m ->> 2) !~ '^-?[0-9]+$' then
      return query select false, 'pos', i, g_score, nmoves, nlines, best, is_over; return;
    end if;
    slot := (m ->> 0)::int; r := (m ->> 1)::int; c := (m ->> 2)::int;
    if slot > 2 or pc[slot + 1] < 0 then return query select false, 'slot', i, g_score, nmoves, nlines, best, is_over; return; end if;
    id := pc[slot + 1];
    if not public.bb_fits(grid, shp, shn, id, r, c) then return query select false, 'fit', i, g_score, nmoves, nlines, best, is_over; return; end if;
    clr := pc[4 + slot];
    for k in 0 .. shn[id + 1] - 1 loop
      grid[(r + shp[id + 1][2 * k + 1]) * 8 + (c + shp[id + 1][2 * k + 2]) + 1] := clr;
    end loop;
    gain := shn[id + 1];
    rows_full := array_fill(true, array[8]); cols_full := array_fill(true, array[8]); n := 0;
    for rr in 0 .. 7 loop
      for cc in 0 .. 7 loop
        if grid[rr * 8 + cc + 1] = 0 then rows_full[rr + 1] := false; cols_full[cc + 1] := false; end if;
      end loop;
    end loop;
    for rr in 1 .. 8 loop
      if rows_full[rr] then n := n + 1; end if;
      if cols_full[rr] then n := n + 1; end if;
    end loop;
    if n > 0 then
      for rr in 0 .. 7 loop
        for cc in 0 .. 7 loop
          if rows_full[rr + 1] or cols_full[cc + 1] then grid[rr * 8 + cc + 1] := 0; end if;
        end loop;
      end loop;
      streak := streak + 1;
      if streak > best then best := streak; end if;
      mult := least(4, 1 + 0.5 * (streak - 1));
      gain := gain + floor(5 * n * (n + 1) * mult + 0.5)::int;
      nlines := nlines + n;
      any_left := false;
      for k in 1 .. 64 loop if grid[k] <> 0 then any_left := true; exit; end if; end loop;
      if not any_left then gain := gain + 300; end if;
    else
      streak := 0;
    end if;
    g_score := g_score + gain; nmoves := nmoves + 1;
    pc[slot + 1] := -1;
    if pc[1] < 0 and pc[2] < 0 and pc[3] < 0 then
      idx := idx + 1;
      pc := public.bb_deal(p_seed, idx, grid, p_ensure, shp, shn, shh, shw, shwt, total);
    end if;
    is_over := not ((pc[1] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[1])) or (pc[2] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[2])) or (pc[3] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[3])));
  end loop;
  return query select true, null::text, null::int, g_score, nmoves, nlines, best, is_over;
end $$;

-- ===== récompenses (même logique que submit_score : plafond de 150 BC/jour pour les parties) =====
create or replace function public.bb_award(p_uid uuid, p_score int) returns jsonb language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/Paris')::date; xp_gain int; bc_gain int; earned_today int; before_level int; after_level int; badges text[];
begin
  insert into public.player_stats (user_id) values (p_uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (p_uid, 'boyblocks', p_score);
  xp_gain := 5 + least(p_score / 80, 60);
  bc_gain := 1 + least(p_score / 400, 25);
  select coalesce(sum(delta), 0) into earned_today from public.bc_ledger
   where user_id = p_uid and reason = 'game' and (created_at at time zone 'Europe/Paris')::date = today;
  bc_gain := least(bc_gain, greatest(0, 150 - earned_today));
  select level into before_level from public.player_stats where user_id = p_uid;
  perform public.add_xp(p_uid, xp_gain);
  if bc_gain > 0 then perform public.add_bc(p_uid, bc_gain, 'game'); end if;
  select level into after_level from public.player_stats where user_id = p_uid;
  badges := public.check_badges(p_uid);
  return jsonb_build_object('xp', xp_gain, 'bc', bc_gain, 'level', after_level, 'level_up', after_level > before_level, 'new_badges', to_jsonb(badges));
end $$;

-- ===== API joueurs =====
create or replace function public.boyblocks_start() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid; s bigint;
begin
  perform public.guard_action(uid);
  if (select count(*) from public.boyblocks_runs where user_id = uid and finished_at is null and started_at > now() - interval '1 hour') >= 12 then
    raise exception 'too many runs';
  end if;
  s := floor(random() * 4294967296)::bigint;
  insert into public.boyblocks_runs (user_id, seed) values (uid, s) returning id into rid;
  return jsonb_build_object('run_id', rid, 'seed', s);
end $$;

create or replace function public.boyblocks_finish(p_run uuid, p_moves jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); run public.boyblocks_runs; res record; aw jsonb; secs numeric;
begin
  perform public.guard_action(uid);
  select * into run from public.boyblocks_runs where id = p_run and user_id = uid for update;
  if not found or run.finished_at is not null then raise exception 'invalid run'; end if;
  if run.started_at < now() - interval '6 hours' then raise exception 'run expired'; end if;
  select * into res from public.bb_replay(run.seed, p_moves, true);
  if not res.ok or res.moves < 1 then raise exception 'invalid run'; end if;
  secs := extract(epoch from (now() - run.started_at));
  if secs < res.moves * 0.2 then raise exception 'invalid run'; end if;       -- impossible de jouer aussi vite
  if res.score > 2000000 then raise exception 'invalid score'; end if;
  update public.boyblocks_runs set finished_at = now(), score = res.score, moves = res.moves where id = p_run;
  aw := public.bb_award(uid, res.score);
  return aw || jsonb_build_object('score', res.score, 'lines', res.lines, 'moves', res.moves, 'best_streak', res.best_streak, 'over', res.over);
end $$;

-- droits : explicites (aucune exécution par défaut)
revoke all on function public.bb_imul(bigint, bigint), public.bb_step(bigint), public.bb_mix(bigint, int, int),
  public.bb_fits(int[], int[], int[], int, int, int), public.bb_can(int[], int[], int[], int[], int[], int),
  public.bb_deal(bigint, int, int[], boolean, int[], int[], int[], int[], int[], int),
  public.bb_replay(bigint, jsonb, boolean), public.bb_award(uuid, int) from public, anon, authenticated;
revoke all on function public.boyblocks_start(), public.boyblocks_finish(uuid, jsonb) from public, anon;
grant execute on function public.boyblocks_start(), public.boyblocks_finish(uuid, jsonb) to authenticated;

-- missions BoyBlocks (même mécanique que les missions existantes)
insert into public.missions (code, name, kind, game, goal, reward_bc, reward_xp, sort) values
  ('bb_1500', 'Fais 1500 points à BoyBlocks', 'best_score', 'boyblocks', 1500, 30, 30, 4)
on conflict (code) do update set name = excluded.name, kind = excluded.kind, game = excluded.game, goal = excluded.goal,
  reward_bc = excluded.reward_bc, reward_xp = excluded.reward_xp, sort = excluded.sort;

-- BOYGAMES schema v9 — BADGES À PALIERS (6 niveaux par jeu : Recrue, Argent, Or, Platine, Diamant, Légende).
-- Additif et idempotent. Ne modifie, ne supprime et n'écrase AUCUN badge ni aucune récompense existants
-- (user_badges, badges, check_badges ne sont pas touchés). Dépend de v1–v8.

create table if not exists public.badge_tracks (
  game text not null, tier int not null check (tier between 0 and 5), name text not null,
  min_score int not null, min_plays int not null,
  primary key (game, tier)
);
alter table public.badge_tracks enable row level security;
drop policy if exists "paliers lisibles par tous" on public.badge_tracks;
create policy "paliers lisibles par tous" on public.badge_tracks for select using (true);
revoke insert, update, delete, truncate on public.badge_tracks from anon, authenticated;

-- Seuils : un palier demande un meilleur score ET un nombre de parties. Légende = quasi plafond + 400 parties.
insert into public.badge_tracks (game, tier, name, min_score, min_plays) values
  ('snake',0,'Recrue',5,1),('snake',1,'Argent',25,10),('snake',2,'Or',60,30),('snake',3,'Platine',120,80),('snake',4,'Diamant',220,200),('snake',5,'Légende',350,400),
  ('blocks',0,'Recrue',300,1),('blocks',1,'Argent',1500,10),('blocks',2,'Or',5000,30),('blocks',3,'Platine',12000,80),('blocks',4,'Diamant',25000,200),('blocks',5,'Légende',40000,400),
  ('space',0,'Recrue',200,1),('space',1,'Argent',1000,10),('space',2,'Or',3000,30),('space',3,'Platine',7000,80),('space',4,'Diamant',12000,200),('space',5,'Légende',18000,400),
  ('boyblocks',0,'Recrue',100,1),('boyblocks',1,'Argent',600,10),('boyblocks',2,'Or',2000,30),('boyblocks',3,'Platine',6000,80),('boyblocks',4,'Diamant',15000,200),('boyblocks',5,'Légende',40000,400)
on conflict (game, tier) do update set name = excluded.name, min_score = excluded.min_score, min_plays = excluded.min_plays;

create table if not exists public.user_tiers (
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null, tier int not null check (tier between 0 and 5),
  unlocked_at timestamptz not null default now(),
  primary key (user_id, game, tier)
);
alter table public.user_tiers enable row level security;
drop policy if exists "je lis mes paliers" on public.user_tiers;
create policy "je lis mes paliers" on public.user_tiers for select using (auth.uid() = user_id);
revoke insert, update, delete, truncate on public.user_tiers from anon, authenticated;

alter table public.profiles add column if not exists favorites text[] not null default '{}';

-- Calcule les paliers mérités (à partir des scores déjà enregistrés), les enregistre, renvoie les NOUVEAUX.
-- Un palier débloqué n'est jamais retiré. Les paliers inférieurs sont débloqués en même temps.
create or replace function public.sync_tiers() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); fresh jsonb;
begin
  perform public.guard_action(uid);
  with st as (select game, max(score) best, count(*) plays from public.scores where user_id = uid group by game),
  earned as (
    select t.game, t.tier, t.name from public.badge_tracks t join st on st.game = t.game
     where st.best >= t.min_score and st.plays >= t.min_plays
  ),
  ins as (
    insert into public.user_tiers (user_id, game, tier)
    select uid, e.game, e.tier from earned e on conflict do nothing returning game, tier
  )
  select coalesce(jsonb_agg(jsonb_build_object('game', i.game, 'tier', i.tier, 'name', t.name) order by i.game, i.tier), '[]'::jsonb)
    into fresh from ins i join public.badge_tracks t on t.game = i.game and t.tier = i.tier;
  return fresh;
end $$;

-- Ma progression : par jeu, meilleur score, parties, palier atteint, prochain palier et ce qu'il demande.
create or replace function public.my_tiers() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public.guard_action(uid);
  return jsonb_build_object(
    'favorites', coalesce((select favorites from public.profiles where id = uid), '{}'),
    'games', coalesce((
      select jsonb_agg(jsonb_build_object(
        'game', g.game, 'best', coalesce(st.best, 0), 'plays', coalesce(st.plays, 0),
        'tier', (select max(ut.tier) from public.user_tiers ut where ut.user_id = uid and ut.game = g.game),
        'next', (select jsonb_build_object('tier', t.tier, 'name', t.name, 'min_score', t.min_score, 'min_plays', t.min_plays)
                   from public.badge_tracks t where t.game = g.game
                    and t.tier = coalesce((select max(ut.tier) + 1 from public.user_tiers ut where ut.user_id = uid and ut.game = g.game), 0))
      ) order by g.game)
      from (select distinct game from public.badge_tracks) g
      left join (select game, max(score) best, count(*) plays from public.scores where user_id = uid group by game) st on st.game = g.game
    ), '[]'::jsonb));
end $$;

-- 3 badges favoris au maximum, uniquement des paliers déjà débloqués (format "jeu:palier", ex. "snake:2").
create or replace function public.set_favorites(p_list text[]) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); x text; clean text[] := '{}'; g text; t int;
begin
  perform public.guard_action(uid);
  if p_list is null then p_list := '{}'; end if;
  if array_length(p_list, 1) > 3 then raise exception 'too many favorites'; end if;
  foreach x in array p_list loop
    if x !~ '^[a-z]{3,12}:[0-5]$' then raise exception 'invalid favorite'; end if;
    g := split_part(x, ':', 1); t := split_part(x, ':', 2)::int;
    if not exists (select 1 from public.user_tiers where user_id = uid and game = g and tier = t) then raise exception 'not unlocked'; end if;
    if not (x = any (clean)) then clean := clean || x; end if;
  end loop;
  update public.profiles set favorites = clean where id = uid;
end $$;

-- Fiche d'un joueur : mêmes règles que public_profile (soi-même ou ami ; bloqué = inconnu).
create or replace function public.public_tiers(p_pseudo text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null or public.is_blocked_between(uid, other) then raise exception 'unknown player'; end if;
  if other <> uid and not public.are_friends(uid, other) then return jsonb_build_object('favorites', '[]'::jsonb, 'games', '[]'::jsonb); end if;
  return jsonb_build_object(
    'favorites', coalesce((select to_jsonb(p.favorites) from public.profiles p where p.id = other), '[]'::jsonb),
    'games', coalesce((select jsonb_agg(jsonb_build_object('game', ut.game, 'tier', ut.tier) order by ut.game)
                         from (select game, max(tier) tier from public.user_tiers where user_id = other group by game) ut), '[]'::jsonb));
end $$;

revoke all on function public.sync_tiers(), public.my_tiers(), public.set_favorites(text[]), public.public_tiers(text) from public, anon;
grant execute on function public.sync_tiers(), public.my_tiers(), public.set_favorites(text[]), public.public_tiers(text) to authenticated;

do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'user_badges', (select count(*) from public.user_badges), 'bc_ledger', (select count(*) from public.bc_ledger),
    'messages', (select count(*) from public.messages), 'friendships', (select count(*) from public.friendships),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then
    raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a;
  end if;
end $$;
do $$ begin
  if has_function_privilege('anon', 'public.bb_replay(bigint,jsonb,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.bb_replay(bigint,jsonb,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.bb_award(uuid,integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.boyblocks_finish(uuid,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.sync_tiers()', 'execute')
     or has_function_privilege('anon', 'public.sync_tiers()', 'execute') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v8+v9 appliquée' as resultat,
  (select count(*) from public.bb_shapes) as formes_boyblocks,
  (select count(*) from public.badge_tracks) as paliers,
  (select count(*) from public.profiles) as profils,
  (select count(*) from public.scores) as scores;
