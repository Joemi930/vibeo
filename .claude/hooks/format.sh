#!/usr/bin/env bash
# Formate automatiquement tout fichier Dart écrit ou modifié par Claude Code.
set -uo pipefail
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0
case "$FILE" in
  *.dart) dart format "$FILE" >/dev/null 2>&1 || true ;;
esac
exit 0
