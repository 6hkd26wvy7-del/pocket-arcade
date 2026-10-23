-- BOYGAMES — MIGRATION v24 : invitations de jeu entre amis (PROTOTYPE, TEST uniquement)
-- À lancer APRÈS la v23. Tout-ou-rien, relançable. Ne modifie aucune donnée de joueur.
-- Remplace la saisie d'un code par une invitation directe depuis l'onglet Amis :
--   * live   : l'ami accepte, les deux ouvrent la même salle de duel (code généré ici, jamais saisi) ; expire en 2 min ;
--   * async  : défi « score à battre » quand l'ami n'est pas là ; expire en 48 h.
-- Les codes de salle restent disponibles dans « Jouer en ligne » pour inviter quelqu'un qui n'est pas encore ami.
-- Sécurité : table fermée (RLS sans règle, aucun droit direct) ; tout passe par des fonctions SECURITY DEFINER réservées
-- aux joueurs connectés. Seul un ami non bloqué peut inviter ; seul le destinataire répond ; seul l'expéditeur annule.
-- Anti-spam : 1 invitation en attente par paire, 5 en attente par joueur, 20/heure par joueur, 6/heure par ami,
-- 10 min de pause après un refus.
begin;

do $$ begin
  if to_regclass('public.game_runs') is null then
    raise exception 'PRE-CONTROLE : la migration v22 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
  if to_regclass('public.friendships') is null or to_regprocedure('public.is_blocked_between(uuid,uuid)') is null then
    raise exception 'PRE-CONTROLE : amis / blocages absents. Rien n''a été modifié.';
  end if;
end $$;

create table if not exists public.game_invites (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references auth.users(id) on delete cascade,
  to_id uuid not null references auth.users(id) on delete cascade,
  game text not null check (game in ('snake', 'space', 'boyblocks')),
  mode text not null check (mode in ('live', 'async')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled', 'expired', 'done')),
  room_code text,
  from_score bigint check (from_score between 0 and 9007199254740991),
  to_score bigint check (to_score between 0 and 9007199254740991),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  expires_at timestamptz not null,
  check (from_id <> to_id),
  check (mode = 'async' or room_code is not null)
);
create unique index if not exists game_invites_one_pending on public.game_invites (from_id, to_id) where status = 'pending';
create index if not exists game_invites_to on public.game_invites (to_id, status, expires_at);
create index if not exists game_invites_from on public.game_invites (from_id, created_at desc);
alter table public.game_invites enable row level security;
revoke all on public.game_invites from anon, authenticated;

-- Lettre de salle du serveur de duels (voir KINDS dans server/worker.js) : S snake, P space, X boyblocks.
create or replace function public.invite_room_code(p_game text)
returns text language plpgsql volatile set search_path = public as $$
declare chars constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; raw bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex'); out text; i int;
begin
  out := case p_game when 'snake' then 'S' when 'space' then 'P' when 'boyblocks' then 'X' end;
  if out is null then raise exception 'invalid game'; end if;
  for i in 0..4 loop out := out || substr(chars, 1 + (get_byte(raw, i) % 31), 1); end loop;
  return out;
end $$;
revoke all on function public.invite_room_code(text) from public;

-- Expiration paresseuse : appelée au début de chaque fonction publique (aucune tâche planifiée nécessaire).
create or replace function public.expire_game_invites()
returns void language sql security definer set search_path = public as $$
  update public.game_invites set status = 'expired'
   where status in ('pending', 'accepted') and expires_at < now();
$$;
revoke all on function public.expire_game_invites() from public;

create or replace function public.send_game_invite(p_pseudo text, p_game text, p_mode text default 'live')
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; inv public.game_invites;
begin
  perform public.guard_action(uid);
  if p_game not in ('snake', 'space', 'boyblocks') or p_mode not in ('live', 'async') then raise exception 'invalid game'; end if;
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if other = uid then raise exception 'cannot invite yourself'; end if;
  if public.is_blocked_between(uid, other) then raise exception 'blocked'; end if;
  if not public.are_friends(uid, other) then raise exception 'not friends'; end if;
  perform public.expire_game_invites();
  if exists (select 1 from public.game_invites where status = 'pending'
              and ((from_id = uid and to_id = other) or (from_id = other and to_id = uid))) then
    raise exception 'already pending';
  end if;
  if (select count(*) from public.game_invites where from_id = uid and status = 'pending') >= 5 then raise exception 'too many pending'; end if;
  if (select count(*) from public.game_invites where from_id = uid and created_at > now() - interval '1 hour') >= 20 then raise exception 'too fast'; end if;
  if (select count(*) from public.game_invites where from_id = uid and to_id = other and created_at > now() - interval '1 hour') >= 6 then
    raise exception 'too many for this friend';
  end if;
  if exists (select 1 from public.game_invites where from_id = uid and to_id = other and status = 'declined'
              and responded_at > now() - interval '10 minutes') then
    raise exception 'declined recently';
  end if;
  insert into public.game_invites (from_id, to_id, game, mode, room_code, expires_at)
  values (uid, other, p_game, p_mode,
          case when p_mode = 'live' then public.invite_room_code(p_game) end,
          now() + case when p_mode = 'live' then interval '2 minutes' else interval '48 hours' end)
  returning * into inv;
  perform public.notify(other, 'game_invite', public.pseudo_of(uid));
  return jsonb_build_object('id', inv.id, 'mode', inv.mode, 'game', inv.game, 'expires_at', inv.expires_at);
end $$;
revoke all on function public.send_game_invite(text, text, text) from public;
grant execute on function public.send_game_invite(text, text, text) to authenticated;

create or replace function public.respond_game_invite(p_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); inv public.game_invites;
begin
  perform public.guard_action(uid);
  perform public.expire_game_invites();
  select * into inv from public.game_invites where id = p_id and to_id = uid for update;
  if not found then raise exception 'invite not found'; end if;          -- idem si l'invitation n'est pas pour moi
  if inv.status <> 'pending' then raise exception 'invite closed'; end if;
  if public.is_blocked_between(uid, inv.from_id) or not public.are_friends(uid, inv.from_id) then
    update public.game_invites set status = 'cancelled', responded_at = now() where id = inv.id;
    return jsonb_build_object('status', 'cancelled');   -- pas d'exception : elle annulerait l'écriture ci-dessus
  end if;
  if coalesce(p_accept, false) then
    update public.game_invites set status = 'accepted', responded_at = now(),
           expires_at = case when mode = 'live' then now() + interval '5 minutes' else expires_at end   -- fenêtre pour rejoindre la salle
     where id = inv.id returning * into inv;
    perform public.notify(inv.from_id, 'game_invite_accept', public.pseudo_of(uid));
  else
    update public.game_invites set status = 'declined', responded_at = now() where id = inv.id returning * into inv;   -- refus silencieux
  end if;
  return jsonb_build_object('status', inv.status, 'game', inv.game, 'mode', inv.mode,
    'room_code', case when inv.status = 'accepted' then inv.room_code end,
    'from_score', case when inv.status = 'accepted' then inv.from_score end);
end $$;
revoke all on function public.respond_game_invite(uuid, boolean) from public;
grant execute on function public.respond_game_invite(uuid, boolean) to authenticated;

create or replace function public.cancel_game_invite(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public.guard_action(uid);
  perform public.expire_game_invites();
  update public.game_invites set status = 'cancelled', responded_at = now() where id = p_id and from_id = uid and status = 'pending';
  if not found then raise exception 'invite not found'; end if;
end $$;
revoke all on function public.cancel_game_invite(uuid) from public;
grant execute on function public.cancel_game_invite(uuid) to authenticated;

-- Tout ce que la page Amis doit afficher, en un seul appel (la page l'interroge toutes les quelques secondes : pas de
-- « présence » en ligne — rien de fiable aujourd'hui pour savoir si un ami est connecté).
create or replace function public.my_game_invites()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public.guard_action(uid);
  perform public.expire_game_invites();
  return jsonb_build_object(
    'incoming', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'from', public.pseudo_of(i.from_id), 'game', i.game, 'mode', i.mode,
          'status', i.status, 'expires_at', i.expires_at, 'from_score', i.from_score,
          'room_code', case when i.status = 'accepted' and i.mode = 'live' then i.room_code end) order by i.created_at desc)
        from public.game_invites i
        where i.to_id = uid and i.expires_at > now()
          and (i.status = 'pending' or (i.status = 'accepted' and (i.mode = 'live' or i.to_score is null)))), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'to', public.pseudo_of(i.to_id), 'game', i.game, 'mode', i.mode,
          'status', i.status, 'expires_at', i.expires_at, 'from_score', i.from_score, 'to_score', i.to_score,
          'room_code', case when i.status = 'accepted' and i.mode = 'live' then i.room_code end) order by i.created_at desc)
        from public.game_invites i
        where i.from_id = uid and i.created_at > now() - interval '2 days'
          and ((i.status = 'pending' and i.expires_at > now())
            or (i.status = 'accepted' and i.expires_at > now())
            or (i.status = 'declined' and i.responded_at > now() - interval '5 minutes')
            or (i.status = 'done' and i.responded_at > now() - interval '1 day')
            or (i.status = 'expired' and i.mode = 'live' and i.expires_at > now() - interval '2 minutes'))), '[]'::jsonb));
end $$;
revoke all on function public.my_game_invites() from public;
grant execute on function public.my_game_invites() to authenticated;

-- Défi asynchrone « score à battre » : chacun déclare UNE partie, jamais un score.
-- Le score est lu côté serveur sur la partie enregistrée avec son ticket : Snake / Space = game_runs (v22) consommé par submit_score_v2,
-- score = ligne `scores` écrite dans la même transaction ; BoyBlocks = boyblocks_runs terminé (rejeu vérifié par boyblocks_finish).
-- La partie doit avoir commencé après l'envoi (expéditeur) ou l'acceptation (destinataire), et ne sert qu'à un seul défi.
-- Aucun XP, BOYCOINS ni classement liés au défi (les gains restent ceux de la partie elle-même).
alter table public.game_invites add column if not exists from_run uuid;
alter table public.game_invites add column if not exists to_run uuid;
create unique index if not exists game_invites_from_run on public.game_invites (from_run) where from_run is not null;
create unique index if not exists game_invites_to_run on public.game_invites (to_run) where to_run is not null;
drop function if exists public.invite_report_score(uuid, integer);   -- anciennes signatures du prototype (score envoyé par le téléphone)
drop function if exists public.invite_report_score(uuid, bigint);
create or replace function public.invite_report_score(p_id uuid, p_run uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); inv public.game_invites; since timestamptz; sc bigint; gr public.game_runs; br public.boyblocks_runs;
begin
  perform public.guard_action(uid);
  perform public.expire_game_invites();
  if p_run is null then raise exception 'invalid run'; end if;
  select * into inv from public.game_invites where id = p_id and uid in (from_id, to_id) and mode = 'async' for update;
  if not found then raise exception 'invite not found'; end if;
  if uid = inv.from_id then
    if inv.from_score is not null or inv.status not in ('pending', 'accepted') then raise exception 'invite closed'; end if;
    since := inv.created_at;
  else
    if inv.status <> 'accepted' or inv.to_score is not null then raise exception 'invite closed'; end if;
    since := inv.responded_at;
  end if;
  if exists (select 1 from public.game_invites where from_run = p_run or to_run = p_run) then raise exception 'run already used'; end if;
  if inv.game = 'boyblocks' then
    select * into br from public.boyblocks_runs where id = p_run and user_id = uid;
    if not found or br.finished_at is null or br.score is null or br.started_at < since then raise exception 'invalid run'; end if;
    sc := br.score;
  else
    select * into gr from public.game_runs where id = p_run and user_id = uid and game = inv.game;
    if not found or gr.used_at is null or gr.started_at < since then raise exception 'invalid run'; end if;
    select max(s.score) into sc from public.scores s where s.user_id = uid and s.game = inv.game and s.created_at = gr.used_at;
    if sc is null then raise exception 'invalid run'; end if;
  end if;
  if uid = inv.from_id then
    update public.game_invites set from_score = sc, from_run = p_run where id = inv.id returning * into inv;
  else
    update public.game_invites set to_score = sc, to_run = p_run where id = inv.id returning * into inv;
  end if;
  if inv.from_score is not null and inv.to_score is not null then
    update public.game_invites set status = 'done', responded_at = now() where id = inv.id returning * into inv;
    perform public.notify(case when uid = inv.from_id then inv.to_id else inv.from_id end, 'game_invite_done', public.pseudo_of(uid));
  end if;
  return jsonb_build_object('status', inv.status, 'from_score', inv.from_score, 'to_score', inv.to_score);
end $$;
revoke all on function public.invite_report_score(uuid, uuid) from public;
grant execute on function public.invite_report_score(uuid, uuid) to authenticated;

commit;
