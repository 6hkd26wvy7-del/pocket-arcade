-- BOYGAMES — MIGRATION v14 : BoyBlocks 9x9 (expérimentation, TEST)
-- À lancer APRÈS la v13. Tout-ou-rien, relançable. Ne modifie aucune donnée : les parties, scores et records 8x8
-- restent tels quels et la vérification 8x8 (bb_replay2) n'est pas touchée.
-- - Grille 9x9 vérifiée côté base (miroir de shared/boyblocks-engine.js avec size: 9, comparaison automatique).
-- - Classement, records et paliers SÉPARÉS : jeu « boyblocks9 » (les scores 8x8 et 9x9 ne se comparent pas).
-- - Interrupteur dans l'administration : 9x9 activé ou non (désactivé = retour au 8x8 pour tous).
begin;

do $$ begin
  if to_regclass('public.marketing_videos') is null or to_regprocedure('public.bb_replay2(bigint,jsonb,boolean,integer)') is null then
    raise exception 'PRE-CONTROLE : les migrations v10 et v13 doivent être lancées AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'runs', (select count(*) from public.boyblocks_runs), 'user_badges', (select count(*) from public.user_badges),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

-- ============ Données ============
alter table public.bb_shapes add column if not exists weight9 int;
update public.bb_shapes set weight9 = weight where weight9 is null;          -- 9x9 : mêmes fréquences (simulations du 15/10)
alter table public.boyblocks_runs add column if not exists size int not null default 8;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'boyblocks_runs_size_check') then
    alter table public.boyblocks_runs add constraint boyblocks_runs_size_check check (size in (8, 9));
  end if;
end $$;

create table if not exists public.game_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table public.game_settings enable row level security;
revoke all on public.game_settings from anon, authenticated;
insert into public.game_settings (key, value) values ('boyblocks9', '{"enabled": true}') on conflict (key) do nothing;

-- paliers du 9x9 : mêmes seuils que le 8x8, comptés à part
insert into public.badge_tracks (game, tier, name, min_score, min_plays) values
  ('boyblocks9',0,'Recrue',100,1),('boyblocks9',1,'Argent',600,10),('boyblocks9',2,'Or',2000,30),('boyblocks9',3,'Platine',6000,80),('boyblocks9',4,'Diamant',15000,200),('boyblocks9',5,'Légende',40000,400)
on conflict (game, tier) do nothing;

-- ============ Moteur généralisé (taille n = 8 ou 9) ============
create or replace function public.bb_fits_n(grid int[], shp int[], shn int[], id int, r int, c int, n int) returns boolean language plpgsql immutable as $$
declare i int; rr int; cc int;
begin
  for i in 0 .. shn[id + 1] - 1 loop
    rr := r + shp[id + 1][2 * i + 1]; cc := c + shp[id + 1][2 * i + 2];
    if rr < 0 or cc < 0 or rr >= n or cc >= n or grid[rr * n + cc + 1] <> 0 then return false; end if;
  end loop;
  return true;
end $$;

create or replace function public.bb_can_n(grid int[], shp int[], shn int[], shh int[], shw int[], id int, n int) returns boolean language plpgsql immutable as $$
declare r int; c int;
begin
  for r in 0 .. n - shh[id + 1] loop
    for c in 0 .. n - shw[id + 1] loop
      if public.bb_fits_n(grid, shp, shn, id, r, c, n) then return true; end if;
    end loop;
  end loop;
  return false;
end $$;

-- tirage « au hasard » (règles 1) : jusqu'à 12 essais si ensure, comme dealRandom
create or replace function public.bb_deal_n(seed bigint, idx int, grid int[], ensure boolean, shp int[], shn int[], shh int[], shw int[], shwt int[], total int, n int)
returns int[] language plpgsql immutable as $$
declare salt int; res int[];
begin
  for salt in 0 .. (case when ensure then 11 else 0 end) loop
    res := public.bb_raw(seed, idx, salt, shwt, total);
    if not ensure or public.bb_can_n(grid, shp, shn, shh, shw, res[1], n) or public.bb_can_n(grid, shp, shn, shh, shw, res[2], n)
       or public.bb_can_n(grid, shp, shn, shh, shw, res[3], n) then return res; end if;
  end loop;
  return res;
end $$;

create or replace function public.bb_quality_n(grid int[], shp int[], shn int[], shh int[], shw int[], t int[], n int)
returns int language plpgsql immutable as $$
declare re int[] := array_fill(0, array[n]); ce int[] := array_fill(0, array[n]);
  rown int[]; coln int[]; q int := 0; clearing int := 0; k int; i int; id int; r int; c int; dr int; dc int;
  fitsn int; best int; lines int;
begin
  for r in 0 .. n - 1 loop
    for c in 0 .. n - 1 loop
      if grid[r * n + c + 1] = 0 then re[r + 1] := re[r + 1] + 1; ce[c + 1] := ce[c + 1] + 1; end if;
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
    for r in 0 .. n - shh[id + 1] loop
      for c in 0 .. n - shw[id + 1] loop
        if public.bb_fits_n(grid, shp, shn, id, r, c, n) then
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

create or replace function public.bb_deal2_n(seed bigint, idx int, grid int[], shp int[], shn int[], shh int[], shw int[], shwt int[], total int, n int)
returns int[] language plpgsql immutable as $$
declare st bigint; v double precision; salt int; t int[]; q int; best int[]; bestq int;
begin
  st := public.bb_mix(seed, idx, 97);
  select o_v into v from public.bb_step(st);
  if floor(v * 100)::int >= 70 then
    return public.bb_deal_n(seed, idx, grid, true, shp, shn, shh, shw, shwt, total, n);
  end if;
  for salt in 0 .. 3 loop
    t := public.bb_raw(seed, idx, salt, shwt, total);
    q := public.bb_quality_n(grid, shp, shn, shh, shw, t, n);
    if best is null or q > bestq then best := t; bestq := q; end if;
  end loop;
  return best;
end $$;

-- Rejeu complet, taille n : mêmes règles de score que le 8x8 (cases posées, lignes, combos, grille vidée)
create or replace function public.bb_replay_n(p_seed bigint, p_moves jsonb, p_ensure boolean, p_rules int, p_n int)
returns table (ok boolean, err text, at int, score int, moves int, lines int, best_streak int, over boolean)
language plpgsql stable as $$
declare
  sz int := case when p_n = 9 then 9 else 8 end;
  shwt int[]; shn int[]; shh int[]; shw int[]; shp int[]; total int;
  grid int[] := array_fill(0, array[sz * sz]);
  pc int[]; g_score int := 0; streak int := 0; best int := 0; nlines int := 0; nmoves int := 0; idx int := 0; is_over boolean;
  i int; m jsonb; slot int; r int; c int; id int; k int; rr int; cc int; nl int; gain int; clr int;
  rows_full boolean[]; cols_full boolean[]; any_left boolean; mult numeric; strategic boolean := p_ensure and p_rules = 2;
begin
  select array_agg(case when sz = 9 then s.weight9 else s.weight end order by s.id), array_agg(s.n order by s.id), array_agg(h order by s.id),
         array_agg(w order by s.id), array_agg(cells order by s.id), sum(case when sz = 9 then s.weight9 else s.weight end)::int
    into shwt, shn, shh, shw, shp, total from public.bb_shapes s;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) > 3000 then
    return query select false, 'moves', 0, 0, 0, 0, 0, false; return;
  end if;
  if strategic then pc := public.bb_deal2_n(p_seed, 0, grid, shp, shn, shh, shw, shwt, total, sz);
  else pc := public.bb_deal_n(p_seed, 0, grid, p_ensure, shp, shn, shh, shw, shwt, total, sz); end if;
  is_over := not (public.bb_can_n(grid, shp, shn, shh, shw, pc[1], sz) or public.bb_can_n(grid, shp, shn, shh, shw, pc[2], sz) or public.bb_can_n(grid, shp, shn, shh, shw, pc[3], sz));
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
    if not public.bb_fits_n(grid, shp, shn, id, r, c, sz) then return query select false, 'fit', i, g_score, nmoves, nlines, best, is_over; return; end if;
    clr := pc[4 + slot];
    for k in 0 .. shn[id + 1] - 1 loop
      grid[(r + shp[id + 1][2 * k + 1]) * sz + (c + shp[id + 1][2 * k + 2]) + 1] := clr;
    end loop;
    gain := shn[id + 1];
    rows_full := array_fill(true, array[sz]); cols_full := array_fill(true, array[sz]); nl := 0;
    for rr in 0 .. sz - 1 loop
      for cc in 0 .. sz - 1 loop
        if grid[rr * sz + cc + 1] = 0 then rows_full[rr + 1] := false; cols_full[cc + 1] := false; end if;
      end loop;
    end loop;
    for rr in 1 .. sz loop
      if rows_full[rr] then nl := nl + 1; end if;
      if cols_full[rr] then nl := nl + 1; end if;
    end loop;
    if nl > 0 then
      for rr in 0 .. sz - 1 loop
        for cc in 0 .. sz - 1 loop
          if rows_full[rr + 1] or cols_full[cc + 1] then grid[rr * sz + cc + 1] := 0; end if;
        end loop;
      end loop;
      streak := streak + 1;
      if streak > best then best := streak; end if;
      mult := least(4, 1 + 0.5 * (streak - 1));
      gain := gain + floor(5 * nl * (nl + 1) * mult + 0.5)::int;
      nlines := nlines + nl;
      any_left := false;
      for k in 1 .. sz * sz loop if grid[k] <> 0 then any_left := true; exit; end if; end loop;
      if not any_left then gain := gain + 300; end if;
    else
      streak := 0;
    end if;
    g_score := g_score + gain; nmoves := nmoves + 1;
    pc[slot + 1] := -1;
    if pc[1] < 0 and pc[2] < 0 and pc[3] < 0 then
      idx := idx + 1;
      if strategic then pc := public.bb_deal2_n(p_seed, idx, grid, shp, shn, shh, shw, shwt, total, sz);
      else pc := public.bb_deal_n(p_seed, idx, grid, p_ensure, shp, shn, shh, shw, shwt, total, sz); end if;
    end if;
    is_over := not ((pc[1] >= 0 and public.bb_can_n(grid, shp, shn, shh, shw, pc[1], sz)) or (pc[2] >= 0 and public.bb_can_n(grid, shp, shn, shh, shw, pc[2], sz))
                 or (pc[3] >= 0 and public.bb_can_n(grid, shp, shn, shh, shw, pc[3], sz)));
  end loop;
  return query select true, null::text, null::int, g_score, nmoves, nlines, best, is_over;
end $$;

-- ============ Récompenses par jeu (« boyblocks » ou « boyblocks9 ») ============
create or replace function public.bb_award_game(p_uid uuid, p_score int, p_game text) returns jsonb language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/Paris')::date; xp_gain int; bc_gain int; earned_today int; before_level int; after_level int; badges text[];
begin
  if p_game not in ('boyblocks', 'boyblocks9') then raise exception 'unknown game'; end if;
  insert into public.player_stats (user_id) values (p_uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (p_uid, p_game, p_score);
  xp_gain := 5 + least(p_score / 80, 60);
  bc_gain := public.bc_for_score('boyblocks', p_score);                    -- même barème de BC pour les deux grilles
  select coalesce(sum(delta), 0) into earned_today from public.bc_ledger
   where user_id = p_uid and reason = 'game' and (created_at at time zone 'Europe/Paris')::date = today;
  bc_gain := least(bc_gain, greatest(0, public.bc_daily_cap() - earned_today));
  select level into before_level from public.player_stats where user_id = p_uid;
  perform public.add_xp(p_uid, xp_gain);
  if bc_gain > 0 then perform public.add_bc(p_uid, bc_gain, 'game'); end if;
  select level into after_level from public.player_stats where user_id = p_uid;
  badges := public.check_badges(p_uid);
  return jsonb_build_object('xp', xp_gain, 'bc', bc_gain, 'level', after_level, 'level_up', after_level > before_level, 'new_badges', to_jsonb(badges));
end $$;

-- ============ API joueurs ============
create or replace function public.game_settings_public() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.game_settings;
$$;

-- Nouvelle partie classée : taille 8 ou 9 (9 seulement si l'expérimentation est activée), tirage stratégique.
create or replace function public.boyblocks_start_v3(p_size int default 8) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid; s bigint;
begin
  perform public.guard_action(uid);
  if p_size not in (8, 9) then raise exception 'invalid size'; end if;
  if p_size = 9 and not coalesce((select (value ->> 'enabled')::boolean from public.game_settings where key = 'boyblocks9'), false) then
    raise exception 'grid disabled';
  end if;
  if (select count(*) from public.boyblocks_runs where user_id = uid and finished_at is null and started_at > now() - interval '1 hour') >= 12 then
    raise exception 'too many runs';
  end if;
  s := floor(random() * 4294967296)::bigint;
  insert into public.boyblocks_runs (user_id, seed, rules, size) values (uid, s, 2, p_size) returning id into rid;
  return jsonb_build_object('run_id', rid, 'seed', s, 'rules', 2, 'size', p_size);
end $$;

-- Fin de partie : 8x8 vérifié exactement comme avant (bb_replay2) ; 9x9 par bb_replay_n, classé dans « boyblocks9 ».
create or replace function public.boyblocks_finish(p_run uuid, p_moves jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); run public.boyblocks_runs; res record; aw jsonb; secs numeric; nine boolean;
begin
  perform public.guard_action(uid);
  select * into run from public.boyblocks_runs where id = p_run and user_id = uid for update;
  if not found or run.finished_at is not null then raise exception 'invalid run'; end if;
  if run.started_at < now() - interval '6 hours' then raise exception 'run expired'; end if;
  nine := coalesce(run.size, 8) = 9;
  if nine then select * into res from public.bb_replay_n(run.seed, p_moves, true, coalesce(run.rules, 1), 9);
  else select * into res from public.bb_replay2(run.seed, p_moves, true, coalesce(run.rules, 1)); end if;
  if not res.ok or res.moves < 1 then raise exception 'invalid run'; end if;
  secs := extract(epoch from (now() - run.started_at));
  if secs < res.moves * 0.2 then raise exception 'invalid run'; end if;       -- impossible de jouer aussi vite
  if res.score > 2000000 then raise exception 'invalid score'; end if;
  update public.boyblocks_runs set finished_at = now(), score = res.score, moves = res.moves where id = p_run;
  aw := public.bb_award_game(uid, res.score, case when nine then 'boyblocks9' else 'boyblocks' end);
  return aw || jsonb_build_object('score', res.score, 'lines', res.lines, 'moves', res.moves, 'best_streak', res.best_streak, 'over', res.over,
                                  'rules', coalesce(run.rules, 1), 'size', coalesce(run.size, 8));
end $$;

-- favoris : autorise les identifiants de jeu avec chiffre (« boyblocks9 »)
create or replace function public.set_favorites(p_list text[]) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); x text; clean text[] := '{}'; g text; t int;
begin
  perform public.guard_action(uid);
  if p_list is null then p_list := '{}'; end if;
  if array_length(p_list, 1) > 3 then raise exception 'too many favorites'; end if;
  foreach x in array p_list loop
    if x !~ '^[a-z][a-z0-9]{2,11}:[0-5]$' then raise exception 'invalid favorite'; end if;
    g := split_part(x, ':', 1); t := split_part(x, ':', 2)::int;
    if not exists (select 1 from public.user_tiers where user_id = uid and game = g and tier = t) then raise exception 'not unlocked'; end if;
    if not (x = any (clean)) then clean := clean || x; end if;
  end loop;
  update public.profiles set favorites = clean where id = uid;
end $$;

-- Interrupteur de l'équipe : 9x9 activé / désactivé (retour au 8x8). Les scores 9x9 déjà faits sont conservés.
create or replace function public.staff_game_settings_set(p_key text, p_value jsonb) returns void language plpgsql security definer set search_path = public as $$
declare old jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select value into old from public.game_settings where key = p_key;
  if not found then raise exception 'unknown setting'; end if;
  if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'enabled') <> 'boolean' then raise exception 'invalid value'; end if;
  update public.game_settings set value = p_value, updated_at = now() where key = p_key;
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'jeu:' || p_key, old, p_value);
end $$;

-- ============ Droits ============
revoke all on function public.bb_fits_n(int[], int[], int[], int, int, int, int), public.bb_can_n(int[], int[], int[], int[], int[], int, int),
  public.bb_deal_n(bigint, int, int[], boolean, int[], int[], int[], int[], int[], int, int),
  public.bb_quality_n(int[], int[], int[], int[], int[], int[], int),
  public.bb_deal2_n(bigint, int, int[], int[], int[], int[], int[], int[], int, int),
  public.bb_replay_n(bigint, jsonb, boolean, int, int), public.bb_award_game(uuid, int, text) from public, anon, authenticated;
revoke all on function public.boyblocks_start_v3(int), public.boyblocks_finish(uuid, jsonb), public.set_favorites(text[]),
  public.staff_game_settings_set(text, jsonb), public.game_settings_public() from public, anon;
grant execute on function public.boyblocks_start_v3(int), public.boyblocks_finish(uuid, jsonb), public.set_favorites(text[]),
  public.staff_game_settings_set(text, jsonb), public.game_settings_public() to authenticated;
grant execute on function public.game_settings_public() to anon;

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'runs', (select count(*) from public.boyblocks_runs), 'user_badges', (select count(*) from public.user_badges),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('authenticated', 'public.bb_replay_n(bigint,jsonb,boolean,integer,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.bb_award_game(uuid,integer,text)', 'execute')
     or has_function_privilege('anon', 'public.boyblocks_start_v3(integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.boyblocks_start_v3(integer)', 'execute')
     or not has_function_privilege('anon', 'public.game_settings_public()', 'execute')
     or has_function_privilege('authenticated', 'public.staff_game_settings_set(text,jsonb)', 'execute') is not true then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v14 appliquée (BoyBlocks 9x9 en essai)' as resultat,
  (select count(*) from public.boyblocks_runs where size = 8) as parties_8x8,
  (select value from public.game_settings where key = 'boyblocks9') as reglage_9x9;
