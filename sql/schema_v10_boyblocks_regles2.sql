-- BOYGAMES — MIGRATION v10 : BoyBlocks « règles 2 » (tirage stratégique en solo)
-- À lancer APRÈS la migration v8+v9 (le script le vérifie). Tout-ou-rien, relançable.
-- N'efface et ne modifie aucune donnée : ajoute la colonne boyblocks_runs.rules (1 pour les parties existantes)
-- et de nouvelles fonctions. Les parties « règles 1 » (anciennes, duels) se vérifient exactement comme avant.
-- Miroir exact de dealStrategic() dans shared/boyblocks-engine.js (comparaison automatique : sql/test).
-- Si la v8+v9 est relancée un jour, relancer ensuite ce script (il redéfinit boyblocks_finish).
begin;

do $$ begin
  if to_regprocedure('public.bb_replay(bigint,jsonb,boolean)') is null or to_regclass('public.boyblocks_runs') is null then
    raise exception 'PRE-CONTROLE : la migration v8+v9 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

-- Photographie avant migration, gardée dans la transaction ; arrêt si le script est exécuté en plusieurs morceaux.
do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'user_badges', (select count(*) from public.user_badges), 'bc_ledger', (select count(*) from public.bc_ledger),
    'runs', (select count(*) from public.boyblocks_runs),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

alter table public.boyblocks_runs add column if not exists rules int not null default 1;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'boyblocks_runs_rules_check') then
    alter table public.boyblocks_runs add constraint boyblocks_runs_rules_check check (rules in (1, 2));
  end if;
end $$;

-- Un lot « au hasard » pour un essai donné (même tirage que dans bb_deal).
create or replace function public.bb_raw(seed bigint, idx int, salt int, shwt int[], total int)
returns int[] language plpgsql immutable as $$
declare st bigint; v double precision; p int[3]; col int[3]; k int; x double precision; j int;
begin
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
  return array[p[1], p[2], p[3], col[1], col[2], col[3]];
end $$;

-- Note d'un lot (miroir de tripleQuality) : pièces posables, lignes complétables, combo possible.
create or replace function public.bb_quality(grid int[], shp int[], shn int[], shh int[], shw int[], t int[])
returns int language plpgsql immutable as $$
declare re int[] := array_fill(0, array[8]); ce int[] := array_fill(0, array[8]);
  rown int[]; coln int[]; q int := 0; clearing int := 0; k int; i int; id int; r int; c int; dr int; dc int;
  fitsn int; best int; lines int;
begin
  for r in 0 .. 7 loop
    for c in 0 .. 7 loop
      if grid[r * 8 + c + 1] = 0 then re[r + 1] := re[r + 1] + 1; ce[c + 1] := ce[c + 1] + 1; end if;
    end loop;
  end loop;
  for k in 1 .. 3 loop
    id := t[k];
    rown := array_fill(0, array[5]); coln := array_fill(0, array[5]);
    for i in 0 .. shn[id + 1] - 1 loop
      rown[shp[id + 1][2 * i + 1] + 1] := rown[shp[id + 1][2 * i + 1] + 1] + 1;
      coln[shp[id + 1][2 * i + 2] + 1] := coln[shp[id + 1][2 * i + 2] + 1] + 1;
    end loop;
    fitsn := 0; best := 0;
    for r in 0 .. 8 - shh[id + 1] loop
      for c in 0 .. 8 - shw[id + 1] loop
        if public.bb_fits(grid, shp, shn, id, r, c) then
          fitsn := fitsn + 1; lines := 0;
          for dr in 0 .. shh[id + 1] - 1 loop if re[r + dr + 1] = rown[dr + 1] then lines := lines + 1; end if; end loop;
          for dc in 0 .. shw[id + 1] - 1 loop if ce[c + dc + 1] = coln[dc + 1] then lines := lines + 1; end if; end loop;
          if lines > best then best := lines; end if;
        end if;
      end loop;
    end loop;
    q := q + case when fitsn = 0 then -30 else 10 + least(fitsn, 3) end + 12 * best;
    if best > 0 then clearing := clearing + 1; end if;
  end loop;
  if clearing >= 2 then q := q + 8; end if;
  return q;
end $$;

-- Tirage stratégique (miroir de dealStrategic) : 70 % meilleur des 4 lots, 30 % tirage au hasard.
create or replace function public.bb_deal2(seed bigint, idx int, grid int[], shp int[], shn int[], shh int[], shw int[], shwt int[], total int)
returns int[] language plpgsql immutable as $$
declare st bigint; v double precision; salt int; t int[]; q int; best int[]; bestq int;
begin
  st := public.bb_mix(seed, idx, 97);
  select o_v into v from public.bb_step(st);
  if floor(v * 100)::int >= 70 then
    return public.bb_deal(seed, idx, grid, true, shp, shn, shh, shw, shwt, total);
  end if;
  for salt in 0 .. 3 loop
    t := public.bb_raw(seed, idx, salt, shwt, total);
    q := public.bb_quality(grid, shp, shn, shh, shw, t);
    if best is null or q > bestq then best := t; bestq := q; end if;
  end loop;
  return best;
end $$;

-- Rejeu complet avec choix des règles (1 = au hasard, 2 = stratégique en solo).
create or replace function public.bb_replay2(p_seed bigint, p_moves jsonb, p_ensure boolean, p_rules int)
returns table (ok boolean, err text, at int, score int, moves int, lines int, best_streak int, over boolean)
language plpgsql stable as $$
declare
  shwt int[]; shn int[]; shh int[]; shw int[]; shp int[]; total int;
  grid int[] := array_fill(0, array[64]);
  pc int[]; g_score int := 0; streak int := 0; best int := 0; nlines int := 0; nmoves int := 0; idx int := 0; is_over boolean;
  i int; m jsonb; slot int; r int; c int; id int; k int; rr int; cc int; n int; gain int; clr int;
  rows_full boolean[]; cols_full boolean[]; any_left boolean; mult numeric; strategic boolean := p_ensure and p_rules = 2;
begin
  select array_agg(weight order by s.id), array_agg(s.n order by s.id), array_agg(h order by s.id), array_agg(w order by s.id), array_agg(cells order by s.id), sum(weight)::int
    into shwt, shn, shh, shw, shp, total from public.bb_shapes s;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) > 3000 then
    return query select false, 'moves', 0, 0, 0, 0, 0, false; return;
  end if;
  if strategic then pc := public.bb_deal2(p_seed, 0, grid, shp, shn, shh, shw, shwt, total);
  else pc := public.bb_deal(p_seed, 0, grid, p_ensure, shp, shn, shh, shw, shwt, total); end if;
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
      if strategic then pc := public.bb_deal2(p_seed, idx, grid, shp, shn, shh, shw, shwt, total);
      else pc := public.bb_deal(p_seed, idx, grid, p_ensure, shp, shn, shh, shw, shwt, total); end if;
    end if;
    is_over := not ((pc[1] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[1])) or (pc[2] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[2])) or (pc[3] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[3])));
  end loop;
  return query select true, null::text, null::int, g_score, nmoves, nlines, best, is_over;
end $$;

-- Nouvelle partie « règles 2 ». boyblocks_start() reste disponible (règles 1) pour les anciennes versions du site.
create or replace function public.boyblocks_start_v2() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid; s bigint;
begin
  perform public.guard_action(uid);
  if (select count(*) from public.boyblocks_runs where user_id = uid and finished_at is null and started_at > now() - interval '1 hour') >= 12 then
    raise exception 'too many runs';
  end if;
  s := floor(random() * 4294967296)::bigint;
  insert into public.boyblocks_runs (user_id, seed, rules) values (uid, s, 2) returning id into rid;
  return jsonb_build_object('run_id', rid, 'seed', s, 'rules', 2);
end $$;

-- Fin de partie : rejoue avec les règles de la partie (1 ou 2).
create or replace function public.boyblocks_finish(p_run uuid, p_moves jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); run public.boyblocks_runs; res record; aw jsonb; secs numeric;
begin
  perform public.guard_action(uid);
  select * into run from public.boyblocks_runs where id = p_run and user_id = uid for update;
  if not found or run.finished_at is not null then raise exception 'invalid run'; end if;
  if run.started_at < now() - interval '6 hours' then raise exception 'run expired'; end if;
  select * into res from public.bb_replay2(run.seed, p_moves, true, coalesce(run.rules, 1));
  if not res.ok or res.moves < 1 then raise exception 'invalid run'; end if;
  secs := extract(epoch from (now() - run.started_at));
  if secs < res.moves * 0.2 then raise exception 'invalid run'; end if;       -- impossible de jouer aussi vite
  if res.score > 2000000 then raise exception 'invalid score'; end if;
  update public.boyblocks_runs set finished_at = now(), score = res.score, moves = res.moves where id = p_run;
  aw := public.bb_award(uid, res.score);
  return aw || jsonb_build_object('score', res.score, 'lines', res.lines, 'moves', res.moves, 'best_streak', res.best_streak, 'over', res.over, 'rules', coalesce(run.rules, 1));
end $$;

-- droits : fonctions internes inaccessibles, deux fonctions de jeu ouvertes aux joueurs connectés
revoke all on function public.bb_raw(bigint, int, int, int[], int), public.bb_quality(int[], int[], int[], int[], int[], int[]),
  public.bb_deal2(bigint, int, int[], int[], int[], int[], int[], int[], int),
  public.bb_replay2(bigint, jsonb, boolean, int) from public, anon, authenticated;
revoke all on function public.boyblocks_start_v2(), public.boyblocks_finish(uuid, jsonb) from public, anon;
grant execute on function public.boyblocks_start_v2(), public.boyblocks_finish(uuid, jsonb) to authenticated;

do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'user_badges', (select count(*) from public.user_badges), 'bc_ledger', (select count(*) from public.bc_ledger),
    'runs', (select count(*) from public.boyblocks_runs),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then
    raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a;
  end if;
  if has_function_privilege('anon', 'public.bb_replay2(bigint,jsonb,boolean,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.bb_replay2(bigint,jsonb,boolean,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.bb_deal2(bigint,integer,integer[],integer[],integer[],integer[],integer[],integer[],integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.boyblocks_start_v2()', 'execute')
     or has_function_privilege('anon', 'public.boyblocks_start_v2()', 'execute')
     or not has_function_privilege('authenticated', 'public.boyblocks_finish(uuid,jsonb)', 'execute') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v10 appliquée' as resultat,
  (select count(*) from public.boyblocks_runs) as parties_boyblocks,
  (select count(*) from public.boyblocks_runs where rules = 1) as parties_regles_1,
  (select count(*) from public.scores) as scores;
