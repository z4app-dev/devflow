#!/bin/bash
# Dispara una Routine de devflow (plan | implement) para un issue y devuelve el link de la sesión.
# El token nunca se imprime ni pasa por la línea de comandos (curl lo lee por stdin).
#
# Entorno: ROUTINE, ISSUE, REPO, ROUTINE_URL, ROUTINE_TOKEN, DRY_RUN.
# Outputs: session_url (vacío si falló), error (mensaje sin secretos, vacío si anduvo).
# Sale con código 1 si el disparo falla; los outputs quedan escritos igual.

source "$(dirname "$0")/../lib/common.sh"
require_tools curl jq

FIRE_BETA="experimental-cc-routine-2026-04-01"

fail() { set_output session_url ""; set_output error "$1"; die "$1"; }

[ "${ROUTINE:-}" = plan ] || [ "${ROUTINE:-}" = implement ] || fail "routine inválida: '${ROUTINE:-}' (plan | implement)"
[[ "${ISSUE:-}" =~ ^[1-9][0-9]*$ ]] || fail "el issue tiene que ser un número (recibido: '${ISSUE:-}')"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "repo inválido: '$REPO' (owner/repo)"
[ -n "${ROUTINE_URL:-}" ] || fail "falta la URL de la Routine devflow-$ROUTINE"
[[ "$ROUTINE_URL" =~ ^https://api\.anthropic\.com/v1/claude_code/routines/[A-Za-z0-9_-]+/fire$ ]] \
    || fail "la URL de la Routine devflow-$ROUTINE no tiene el formato esperado (…/v1/claude_code/routines/<id>/fire)"
[ -n "${ROUTINE_TOKEN:-}" ] || fail "falta el token de la Routine devflow-$ROUTINE"
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$ROUTINE_TOKEN"

body=$(jq -cn --arg t "issue=$ISSUE repo=$REPO" '{text: $t}')

if is_dry_run; then
    log "[dry-run] POST $ROUTINE_URL con $body"
    set_output session_url "https://claude.ai/code/session_dry-run"
    set_output error ""
    exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
status=$(printf 'header = "Authorization: Bearer %s"\n' "$ROUTINE_TOKEN" | curl -sS -K - \
    -o "$tmp" -w '%{http_code}' -X POST "$ROUTINE_URL" \
    -H "anthropic-beta: $FIRE_BETA" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    --data "$body" 2>/dev/null) || fail "falló la conexión con la API de Routines"
unset ROUTINE_TOKEN

if [ "$status" != 200 ] && [ "$status" != 201 ]; then
    detail=$(jq -r '(.error // .) | if type == "object" then "\(.type // "") \(.message // "")" else tostring end' "$tmp" 2>/dev/null \
        | tr -d '\r' | head -c 300 || true)
    fail "HTTP $status al disparar devflow-$ROUTINE${detail:+: $detail}"
fi

# La API devuelve el id con prefijo `cse_`; el link de la web usa `session_`.
url=$(jq -r '.claude_code_session_url // empty' "$tmp" | sed 's|/code/cse_|/code/session_|')
[[ "$url" =~ ^https://[A-Za-z0-9./_-]+$ ]] || fail "la respuesta no trae claude_code_session_url"
log "devflow-$ROUTINE disparada para #$ISSUE: $url"
set_output session_url "$url"
set_output error ""
