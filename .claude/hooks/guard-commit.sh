#!/usr/bin/env bash
# Avant tout `git commit` : bloque si un .env est indexé, si flutter analyze
# échoue, ou si des tests échouent. Exit 2 = blocage du commit.
set -uo pipefail
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
case "$CMD" in
  *"git commit"*)
    # Bloque tout .env réel, mais autorise le modèle public .env.example.
    if git diff --cached --name-only \
         | grep -E '(^|/)\.env($|\.)' \
         | grep -qvE '(^|/)\.env\.example$'; then
      echo "Blocage : un fichier .env est indexé. git restore --staged <fichier>." >&2
      exit 2
    fi
    if ! flutter analyze --no-pub > /tmp/vibeo_analyze.log 2>&1; then
      echo "Blocage : flutter analyze échoue. Voir /tmp/vibeo_analyze.log" >&2
      exit 2
    fi
    if ! flutter test > /tmp/vibeo_test.log 2>&1; then
      echo "Blocage : des tests échouent. Voir /tmp/vibeo_test.log" >&2
      exit 2
    fi
    ;;
esac
exit 0
