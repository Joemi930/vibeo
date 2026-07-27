-- Migration : découverte (Phase 5) -- tendances (`trending_videos`) et
-- recommandations personnalisées (`recommended_videos`). RLS activée dès la
-- création, politiques nommées, GRANT explicite (règle CLAUDE.md n°1-3).
-- Référence : docs/ARCHITECTURE.md §3.

-- =============================================================================
-- 1) trending_videos -- vue matérialisée des scores de tendance.
--
--    PROBLÈME CENTRAL : une vue matérialisée NE PORTE PAS de RLS (Postgres ne
--    permet pas `alter materialized view ... enable row level security`).
--    L'exposer directement laisserait une vidéo retirée par la modération
--    visible en tendances jusqu'au rafraîchissement suivant -- jusqu'à une
--    heure d'exposition d'un contenu qu'on vient précisément de retirer.
--    Inacceptable. Montage à deux étages, voir section 2 pour le second
--    étage (fonctions de lecture qui réappliquent la RLS).
--
--    INNER JOIN délibéré sur `recent_views` (pas LEFT JOIN) : une vidéo à
--    500 000 vues datant d'un an compte zéro vue RÉCENTE (fenêtre 7 jours) et
--    n'entre donc pas dans la table -- c'est ce qui garantit que les
--    tendances ne montrent jamais une vieille vidéo très vue il y a
--    longtemps, quelle que soit sa popularité historique.
-- =============================================================================
create materialized view public.trending_videos as
  with recent_views as (
    select ve.video_id, count(*) as n
      from public.view_events ve
     where ve.created_at >= now() - interval '7 days'
     group by ve.video_id
  ),
  recent_likes as (
    select l.video_id, count(*) as n
      from public.likes l
     where l.created_at >= now() - interval '7 days'
     group by l.video_id
  )
  select v.id as video_id,
         rv.n as recent_view_count,
         coalesce(rl.n, 0) as recent_like_count,
         ln(1 + rv.n) * 1.0
       + ln(1 + coalesce(rl.n, 0)) * 0.6
       + (case when coalesce(v.published_at, v.created_at) >= now() - interval '48 hours'
               then 0.5 else 0.0 end) as score,
         now() as computed_at
    from public.videos v
    join recent_views rv on rv.video_id = v.id
    left join recent_likes rl on rl.video_id = v.id
   where v.status = 'published';

comment on materialized view public.trending_videos is
  'Scores de tendance (fenêtre glissante 7 jours), INNER JOIN sur les vues '
  'récentes délibéré : une vidéo sans vue dans les 7 derniers jours n''entre '
  'PAS dans cette table, quel que soit son total historique. NE PORTE AUCUNE '
  'RLS (impossible sur une vue matérialisée) -- son accès est verrouillé par '
  'REVOKE ci-dessous, la lecture publique passe exclusivement par les '
  'fonctions de la section 2, qui rejoignent public.videos et donc '
  'réappliquent sa RLS/son statut à chaque appel.';

-- Index unique OBLIGATOIRE sur (video_id) : sans lui, `refresh materialized
-- view` ne peut pas être exécuté CONCURRENTLY et prend un ACCESS EXCLUSIVE
-- LOCK -- l'accueil de tous les utilisateurs se fige le temps du calcul,
-- chaque heure.
create unique index trending_videos_video_id_idx
  on public.trending_videos (video_id);

create index trending_videos_score_idx
  on public.trending_videos (score desc);

-- Verrouillage total : ni anon, ni authenticated, ni le rôle `public` ne
-- doivent pouvoir lire cette table directement (elle serait alors exposée en
-- REST par PostgREST, sans aucune RLS pour la protéger). Seule une fonction
-- SECURITY DEFINER dédiée (trending_scores, section 2) peut la lire, et
-- uniquement pour la recombiner avec une vérification fraîche de
-- public.videos.status.
revoke all on public.trending_videos from public, anon, authenticated;

-- =============================================================================
-- 2) Second étage : accès public via des fonctions, jamais via la table.
--
--    DÉCISION DE CONCEPTION (à signaler explicitement à l'orchestrateur) :
--    le prompt de phase demandait `trending_videos_feed` en SECURITY INVOKER
--    pur, sur le modèle de `suggested_videos`. Repris littéralement, ce
--    serait cassé : `trending_videos` n'a AUCUN grant pour anon/authenticated
--    (revoke ci-dessus, volontaire et non négociable -- exposer la table
--    brute est le risque qu'on ferme). Une fonction SECURITY INVOKER exécute
--    le SQL avec les privilèges de L'APPELANT, pas du propriétaire : un appel
--    anon/authenticated à une fonction INVOKER qui lit `trending_videos`
--    échouerait donc systématiquement en "permission denied", quelle que
--    soit la logique de la fonction.
--
--    Solution retenue, cohérente avec le patron déjà utilisé pour
--    `reports_compute_priority_bonus` (20260727010000_moderation_core.sql) :
--    UNE SEULE fonction SECURITY DEFINER minimale, `trending_scores()`, sert
--    de pont étroit entre la table verrouillée et le reste du système. Elle
--    ne renvoie que (video_id, score) -- pas les colonnes sensibles -- et
--    revérifie elle-même `videos.status = 'published'` à CHAQUE appel (même
--    si son propriétaire postgres bypasse la RLS par nature en tant que
--    superutilisateur : cette clause explicite est donc la SEULE garantie
--    réelle, pas une simple défense en profondeur cosmétique -- sans elle,
--    une vidéo retirée resterait visible via cette fonction jusqu'au
--    prochain refresh).
--
--    `trending_videos_feed` et `recommended_videos` restent, eux, bien
--    SECURITY INVOKER comme demandé : ils ne lisent jamais `trending_videos`
--    directement, seulement via `trending_scores()` (EXECUTE accordé) et via
--    `public.videos`/`public.profiles` (déjà lisibles par anon/authenticated,
--    RLS standard). La RLS de `videos` se réapplique donc bien à chaque
--    lecture, exactement comme demandé -- seule la façon d'atteindre le score
--    de tendance diffère du modèle littéral de `suggested_videos`, qui n'a
--    jamais eu ce problème (il ne lit qu'une table déjà correctement grantée).
-- =============================================================================
create or replace function public.trending_scores()
returns table (video_id uuid, score double precision)
language sql
security definer
set search_path = ''
stable
as $$
  select tv.video_id, tv.score
    from public.trending_videos tv
    join public.videos v on v.id = tv.video_id
   where v.status = 'published';
$$;

comment on function public.trending_scores() is
  'Pont étroit et SECURITY DEFINER entre trending_videos (verrouillée) et le '
  'reste du système : ne renvoie que (video_id, score), et REVÉRIFIE '
  'videos.status = ''published'' à chaque appel -- c''est cette clause, pas la '
  'RLS (bypassée par le propriétaire postgres), qui empêche une vidéo '
  'retirée entre deux refresh de réapparaître. Jamais appelée directement par '
  'PostgREST (pas de REST public sur une fonction retournant juste des ids -- '
  'seules trending_videos_feed/recommended_videos, qui rejoignent videos pour '
  'produire une réponse utile, sont conçues pour ça).';

revoke execute on function public.trending_scores() from public;
grant execute on function public.trending_scores() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- trending_videos_feed : fonction de lecture publique du fil "Tendances".
-- SECURITY INVOKER (voir décision ci-dessus) : la RLS de videos/profiles
-- s'applique à l'appelant, exactement comme suggested_videos
-- (20260726020000_phase35.sql). `where v.status = 'published'` répété ici en
-- DÉFENSE EN PROFONDEUR (celle-ci, elle, est bien redondante avec la RLS
-- normale de videos_select_published -- contrairement à celle de
-- trending_scores() qui est la seule protection réelle).
-- ---------------------------------------------------------------------------
create or replace function public.trending_videos_feed(
  p_limit    int default 20,
  p_genre_id int default null
)
returns table (
  id                uuid,
  artist_id         uuid,
  title             text,
  description       text,
  genre_id          integer,
  video_path        text,
  thumbnail_path    text,
  duration_seconds  integer,
  size_bytes        bigint,
  status            public.video_status,
  moderation_result jsonb,
  view_count        bigint,
  like_count        bigint,
  comment_count     bigint,
  published_at      timestamptz,
  created_at        timestamptz,
  artist            jsonb
)
language sql
security invoker
set search_path = ''
stable
as $$
  select
    v.id, v.artist_id, v.title, v.description, v.genre_id, v.video_path,
    v.thumbnail_path, v.duration_seconds, v.size_bytes, v.status,
    v.moderation_result, v.view_count, v.like_count, v.comment_count,
    v.published_at, v.created_at,
    jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'display_name', p.display_name,
      'avatar_url', p.avatar_url,
      'role', p.role,
      'subscriber_count', p.subscriber_count
    ) as artist
  from public.trending_scores() ts
  join public.videos v on v.id = ts.video_id
  join public.profiles p on p.id = v.artist_id
  where v.status = 'published'
    and (p_genre_id is null or v.genre_id = p_genre_id)
  order by ts.score desc, v.published_at desc nulls last
  limit greatest(p_limit, 0)
$$;

comment on function public.trending_videos_feed(int, int) is
  'Fil "Tendances" public. SECURITY INVOKER : lit trending_scores() (execute '
  'accordé) puis rejoint public.videos/public.profiles, dont la RLS '
  's''applique normalement à l''appelant. filtre status=''published'' répété '
  'en défense en profondeur.';

revoke execute on function public.trending_videos_feed(int, int) from public;
grant execute on function public.trending_videos_feed(int, int) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- recommended_videos : fil personnalisé, démarrage à froid = tendances.
--
-- AUCUN paramètre p_user_id : l'identité vient exclusivement de auth.uid().
-- Un paramètre laisserait n'importe quel appelant lire le profil d'écoute
-- (et donc en déduire les goûts, l'activité, les horaires) d'un tiers.
--
-- SECURITY INVOKER : suffisant, car view_events porte déjà une politique de
-- lecture "ses propres événements" (view_events_select_own) -- l'appelant a
-- donc naturellement accès à SES événements sous cette identité, aucun
-- besoin de bypasser la RLS ici. Ne PAS passer en DEFINER : ce serait exposer
-- l'historique de lecture de n'importe quel utilisateur au premier appelant.
-- ---------------------------------------------------------------------------
create or replace function public.recommended_videos(
  p_limit int default 20
)
returns table (
  id                uuid,
  artist_id         uuid,
  title             text,
  description       text,
  genre_id          integer,
  video_path        text,
  thumbnail_path    text,
  duration_seconds  integer,
  size_bytes        bigint,
  status            public.video_status,
  moderation_result jsonb,
  view_count        bigint,
  like_count        bigint,
  comment_count     bigint,
  published_at      timestamptz,
  created_at        timestamptz,
  artist            jsonb
)
language plpgsql
security invoker
set search_path = ''
stable
as $$
declare
  v_user_id           uuid := auth.uid();
  v_recent_view_count integer;
begin
  -- Démarrage à froid n°1 : invité (pas de JWT authentifié).
  if v_user_id is null then
    return query select * from public.trending_videos_feed(p_limit, null);
    return;
  end if;

  -- Démarrage à froid n°2 : compte trop récent / trop peu d'activité pour
  -- qu'un profil de goûts soit fiable (< 3 vues sur 30 jours). Un compte
  -- neuf voit alors EXACTEMENT les tendances, comme un invité.
  select count(*)
    into v_recent_view_count
    from public.view_events ve
   where ve.user_id = v_user_id
     and ve.created_at >= now() - interval '30 days';

  if v_recent_view_count < 3 then
    return query select * from public.trending_videos_feed(p_limit, null);
    return;
  end if;

  -- Cas personnalisé : genres écoutés sur 30 jours (poids = nombre d'écoutes
  -- x 1.5) + score de tendance (x0.8), vidéos déjà vues sur 30 jours exclues.
  return query
    with genre_affinity as (
      select v.genre_id, count(*)::numeric as watch_count
        from public.view_events ve
        join public.videos v on v.id = ve.video_id
       where ve.user_id = v_user_id
         and ve.created_at >= now() - interval '30 days'
         and v.genre_id is not null
       group by v.genre_id
    ),
    viewed as (
      select distinct ve.video_id
        from public.view_events ve
       where ve.user_id = v_user_id
         and ve.created_at >= now() - interval '30 days'
    )
    select
      v.id, v.artist_id, v.title, v.description, v.genre_id, v.video_path,
      v.thumbnail_path, v.duration_seconds, v.size_bytes, v.status,
      v.moderation_result, v.view_count, v.like_count, v.comment_count,
      v.published_at, v.created_at,
      jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'display_name', p.display_name,
        'avatar_url', p.avatar_url,
        'role', p.role,
        'subscriber_count', p.subscriber_count
      ) as artist
    from public.videos v
    join public.profiles p on p.id = v.artist_id
    left join genre_affinity ga on ga.genre_id = v.genre_id
    left join public.trending_scores() ts on ts.video_id = v.id
    where v.status = 'published'
      and not exists (select 1 from viewed vw where vw.video_id = v.id)
    order by (coalesce(ga.watch_count, 0) * 1.5 + coalesce(ts.score, 0) * 0.8) desc,
             v.published_at desc nulls last
    limit greatest(p_limit, 0);
end;
$$;

comment on function public.recommended_videos(int) is
  'Fil personnalisé. Aucun paramètre p_user_id -- identité lue uniquement via '
  'auth.uid(). Démarrage à froid (invité OU < 3 vues/30j) = exactement '
  'trending_videos_feed(). SECURITY INVOKER : view_events_select_own suffit, '
  'ne jamais passer en DEFINER (exposerait l''historique d''autrui).';

revoke execute on function public.recommended_videos(int) from public;
grant execute on function public.recommended_videos(int) to anon, authenticated;

-- =============================================================================
-- 3) refresh_trending_videos -- rafraîchissement, appelé par le planificateur
--    (20260727010300_scheduling.sql). SECURITY DEFINER : REFRESH MATERIALIZED
--    VIEW exige d'être propriétaire de l'objet (ou superutilisateur) ; le
--    rôle qui déclenche le cron n'a aucune raison d'avoir ce privilège.
--
--    `refresh ... concurrently` exige un index unique ET une vue déjà peuplée
--    -- le tout premier rafraîchissement (juste après cette migration,
--    `create materialized view` la peuple déjà une fois, mais un
--    environnement qui la recréerait vide échouerait sur CONCURRENTLY) doit
--    donc être un refresh NON concurrent. Détecté via pg_matviews.ispopulated.
-- =============================================================================
create or replace function public.refresh_trending_videos()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_populated boolean;
begin
  select mv.ispopulated
    into v_populated
    from pg_catalog.pg_matviews mv
   where mv.schemaname = 'public'
     and mv.matviewname = 'trending_videos';

  if coalesce(v_populated, false) then
    refresh materialized view concurrently public.trending_videos;
  else
    refresh materialized view public.trending_videos;
  end if;
end;
$$;

comment on function public.refresh_trending_videos() is
  'Rafraîchit trending_videos (CONCURRENTLY dès que la vue est peuplée, sans '
  'quoi ACCESS EXCLUSIVE LOCK). Réservée au planificateur (SECURITY DEFINER, '
  'aucun grant client) -- voir 20260727010300_scheduling.sql.';

revoke execute on function public.refresh_trending_videos() from public, anon, authenticated;
