-- BOYGAMES — MIGRATION v25 : plafond absolu de score Space Attack 100 000 -> 5 000 000 (TEST, préparée, NON appliquée)
-- À lancer APRÈS la v23 (la v24 des invitations est indépendante). Tout-ou-rien, relançable. Ne modifie aucune donnée.
-- Raison : le site tronquait tout score Space au-dessus de 100 000 à exactement 100 000 avant l'envoi (plafond de la v17),
-- donc les très bonnes parties étaient enregistrées à 100 000 et le vrai score perdu.
-- La protection anti-triche ne change pas : ticket de partie à usage unique + vraisemblance liée à la durée
-- (score_plausible : 500 + 3 000 points par seconde, v22). Ce plafond n'est plus qu'un garde-fou absolu ; gains d'XP et de
-- BOYCOINS inchangés (XP plafonnée à 60 par partie, BOYCOINS plafonnés par les réglages d'économie).
begin;

do $$ begin
  if to_regprocedure('public.score_plausible(text,integer,numeric)') is null then
    raise exception 'PRE-CONTROLE : la migration v22 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

create or replace function public.game_max_score(p_game text)
returns int language sql immutable as $$
  select case p_game
    when 'snake' then 429
    when 'blocks' then 50000
    when 'space' then 5000000   -- v25 : 100 000 avant (le site tronquait les scores à 100 000)
    else 0
  end;
$$;
revoke all on function public.game_max_score(text) from public;

do $$ begin
  if public.game_max_score('space') <> 5000000 or public.game_max_score('snake') <> 429 or public.game_max_score('blocks') <> 50000
     or public.game_max_score('autre') <> 0 then
    raise exception 'GARDE-FOU : plafonds inattendus. Rien n''a été appliqué.';
  end if;
end $$;

commit;
select 'Migration v25 appliquée (plafond Space Attack 5 000 000)' as resultat, public.game_max_score('space') as plafond_space;
