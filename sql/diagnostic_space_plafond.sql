-- LECTURE SEULE — à lancer par toi dans l'éditeur SQL Supabase (aucune écriture). Remplace MON_PSEUDO.
-- 1) Mes derniers scores Space reçus par la base : une ligne à 100000 pile = score tronqué par le site (le vrai score n'a pas été envoyé).
select s.score, s.created_at
from public.scores s join public.profiles p on p.id = s.user_id
where lower(p.pseudo) = lower('MON_PSEUDO') and s.game = 'space'
order by s.created_at desc limit 15;
-- 2) Parties continuées par vidéo (hors classement) : même troncature possible.
select c.score, c.continues, c.created_at
from public.scores_continued c join public.profiles p on p.id = c.user_id
where lower(p.pseudo) = lower('MON_PSEUDO') and c.game = 'space'
order by c.created_at desc limit 15;
-- 3) Tickets de partie : une partie sans score enregistré = ticket non utilisé ou envoi rejeté.
select r.started_at, r.used_at
from public.game_runs r join public.profiles p on p.id = r.user_id
where lower(p.pseudo) = lower('MON_PSEUDO') and r.game = 'space'
order by r.started_at desc limit 15;
-- 4) Autres joueurs touchés : combien ont au moins un score Space à 100000 pile (= probablement tronqué).
select count(distinct user_id) as joueurs_touches, count(*) as scores_tronques
from public.scores where game = 'space' and score = 100000;
