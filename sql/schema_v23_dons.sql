-- BOYGAMES — MIGRATION v23 : dons volontaires (préparés, DÉSACTIVÉS) (TEST)
-- À lancer APRÈS la v22. Tout-ou-rien, relançable. Ne modifie aucune donnée de joueur.
-- Un bouton « Soutenir BOYGAMES » renvoie vers une page de dons externe (Ko-fi, Liberapay, Buy Me a Coffee, PayPal,
-- HelloAsso) : aucun paiement dans l'appli, aucune donnée bancaire chez BOYGAMES, aucun avantage en jeu.
-- Rien n'est visible tant que l'équipe n'a pas activé le réglage avec l'adresse de sa page.
begin;

do $$ begin
  if to_regclass('public.game_runs') is null then
    raise exception 'PRE-CONTROLE : la migration v22 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

insert into public.monetization_settings (key, value) values ('donate', '{"enabled": false, "url": "", "message": ""}')
on conflict (key) do nothing;

create or replace function public.monetization_public() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ads', public.monet('ads'),
    'rewarded', (select r - 'daily_max' - 'bc_per_continue' from (select public.monet('rewarded') r) x),
    'premium', public.monet('premium') || jsonb_build_object('pioneer_left',
        greatest(0, coalesce((public.monet('premium') ->> 'pioneer_limit')::int, 0) - (select count(*) from public.user_badges where badge_code = 'premium_pioneer'))),
    'donate', case when coalesce((public.monet('donate') ->> 'enabled')::boolean, false)
                   then public.monet('donate') else jsonb_build_object('enabled', false) end);   -- l'adresse n'est publiée qu'une fois activé
$$;

create or replace function public.staff_monetization_set(p_key text, p_value jsonb) returns void language plpgsql security definer set search_path = public as $$
declare old jsonb; g text;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select value into old from public.monetization_settings where key = p_key;
  if not found then raise exception 'unknown setting'; end if;
  if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'enabled') <> 'boolean' then raise exception 'invalid value'; end if;
  if p_key = 'ads' then
    if (p_value ->> 'provider') not in ('test', 'adsense') or jsonb_typeof(p_value -> 'slots') <> 'object' then raise exception 'invalid value'; end if;
    if exists (select 1 from jsonb_each(p_value -> 'slots') e where e.key not in ('home', 'scores', 'shop') or jsonb_typeof(e.value) <> 'boolean') then raise exception 'invalid slot'; end if;
  elsif p_key = 'rewarded' then
    if (p_value ->> 'continue_max')::int not between 0 and 2 or (p_value ->> 'daily_max')::int not between 0 and 50
       or (p_value ->> 'bc_per_continue')::int not between 0 and 5 or jsonb_typeof(p_value -> 'games') <> 'array' then raise exception 'invalid value'; end if;
    for g in select jsonb_array_elements_text(p_value -> 'games') loop
      if g not in ('snake', 'space') then raise exception 'invalid game'; end if;      -- jeux qui savent continuer
    end loop;
  elsif p_key = 'donate' then                -- v23 : dons volontaires, uniquement vers des services de dons reconnus
    if coalesce(p_value ->> 'url', '') <> '' and ((p_value ->> 'url') !~ '^https://(www\.)?(ko-fi\.com|liberapay\.com|buymeacoffee\.com|paypal\.me|paypal\.com/donate|helloasso\.com)/[A-Za-z0-9/_?=&.%-]{1,150}$') then raise exception 'invalid url'; end if;
    if (p_value ->> 'enabled')::boolean and coalesce(p_value ->> 'url', '') = '' then raise exception 'invalid url'; end if;
    if char_length(coalesce(p_value ->> 'message', '')) > 160 then raise exception 'invalid value'; end if;
  elsif p_key = 'premium' then
    if (p_value ->> 'price_eur')::numeric not between 0 and 50 or (p_value ->> 'pioneer_limit')::int not between 0 and 100000 then raise exception 'invalid value'; end if;
  end if;
  update public.monetization_settings set value = p_value, updated_at = now(), updated_by = auth.uid() where key = p_key;
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'monetisation:' || p_key, old, p_value);
end $$;

do $$ begin
  if coalesce((select (value ->> 'enabled')::boolean from public.monetization_settings where key = 'donate'), true) then
    raise exception 'GARDE-FOU : les dons doivent rester désactivés à l''installation. Rien n''a été appliqué.';
  end if;
  if has_function_privilege('anon', 'public.staff_monetization_set(text,jsonb)', 'execute') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v23 appliquée (dons volontaires préparés, désactivés)' as resultat;
