#!/usr/bin/env bash
# Script de build Vercel — lit les variables d'environnement et les injecte
# via --dart-define. Utilisé par vercel.json pour le déploiement production.
set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL manquant}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY manquant}"
: "${WEB_BASE_URL:?WEB_BASE_URL manquant}"

flutter build web --release --csp \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" \
  --dart-define="WEB_BASE_URL=$WEB_BASE_URL"
