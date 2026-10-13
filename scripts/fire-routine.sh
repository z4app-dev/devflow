#!/bin/bash
# Dispara una Routine de devflow (plan | implement) para un issue e imprime la URL de la sesión.
#
# Uso:
#   scripts/fire-routine.sh <plan|implement> <issue> [repo]    # dispara (repo por defecto: z4app-organization/ab_gym)
#   scripts/fire-routine.sh --check [plan|implement]           # verifica que estén URL y token (no dispara)
#   scripts/fire-routine.sh --store <plan|implement>           # guarda URL y token (los pide sin eco)
#
# URL y token viven en el almacén de secretos del sistema, nunca en archivos:
#   - macOS: Llavero (`security`), servicio devflow-routine-<routine>, cuentas `url` y `token`.
#   - Linux: libsecret (`secret-tool`), atributos service=devflow-routine-<routine> account=url|token.
# El token no se imprime ni se pasa por la línea de comandos (curl lo lee por stdin).

set -euo pipefail

DEFAULT_REPO="z4app-organization/ab_gym"
FIRE_BETA="experimental-cc-routine-2026-04-01"

die() { echo "Error: $*" >&2; exit 1; }

case "$(uname -s)" in
    Darwin) BACKEND=keychain ;;
    Linux) BACKEND=libsecret ;;
    *) die "plataforma no soportada: $(uname -s)" ;;
esac

secret_get() { # <routine> <url|token>
    local service="devflow-routine-$1"
    if [ "$BACKEND" = keychain ]; then
        security find-generic-password -s "$service" -a "$2" -w 2>/dev/null
    else
        secret-tool lookup service "$service" account "$2" 2>/dev/null
    fi
}

secret_set() { # <routine> <url|token> ; valor por stdin
    local service="devflow-routine-$1" value
    IFS= read -r value
    if [ "$BACKEND" = keychain ]; then
        security add-generic-password -U -s "$service" -a "$2" -w "$value"
    else
        printf '%s' "$value" | secret-tool store --label="$service $2" service "$service" account "$2"
    fi
}

check_tools() {
    if [ "$BACKEND" = keychain ]; then
        command -v security >/dev/null || die "falta 'security' (Llavero de macOS)"
    else
        command -v secret-tool >/dev/null || die "falta 'secret-tool' (paquete libsecret-tools / libsecret)"
    fi
    command -v curl >/dev/null || die "falta curl"
    command -v python3 >/dev/null || die "falta python3"
}

valid_routine() { [ "${1:-}" = plan ] || [ "${1:-}" = implement ]; }

check_routine() { # <routine> → 0 si están URL y token
    local ok=0 url
    url=$(secret_get "$1" url) || true
    if [ -z "$url" ]; then
        echo "✗ $1: falta la URL (servicio devflow-routine-$1, cuenta url)"; ok=1
    elif [[ "$url" != https://api.anthropic.com/v1/claude_code/routines/*/fire ]]; then
        echo "✗ $1: la URL no tiene el formato esperado (…/v1/claude_code/routines/<id>/fire)"; ok=1
    else
        echo "✓ $1: URL $url"
    fi
    if [ -z "$(secret_get "$1" token || true)" ]; then
        echo "✗ $1: falta el token (servicio devflow-routine-$1, cuenta token)"; ok=1
    else
        echo "✓ $1: token presente (no se muestra)"
    fi
    return $ok
}

check_tools

case "${1:-}" in
    --check)
        if [ -n "${2:-}" ]; then
            valid_routine "$2" || die "routine inválida: '$2' (plan | implement)"
            check_routine "$2"
        else
            rc=0
            check_routine plan || rc=1
            check_routine implement || rc=1
            exit $rc
        fi
        ;;
    --store)
        valid_routine "${2:-}" || die "uso: $0 --store <plan|implement>"
        read -rs -p "URL de la Routine devflow-$2 (…/fire): " url; echo
        read -rs -p "Token de la Routine devflow-$2: " token; echo
        [ -n "$url" ] && [ -n "$token" ] || die "URL y token no pueden estar vacíos"
        printf '%s\n' "$url" | secret_set "$2" url
        printf '%s\n' "$token" | secret_set "$2" token
        unset url token
        check_routine "$2"
        ;;
    plan|implement)
        routine="$1"
        issue="${2:-}"
        repo="${3:-$DEFAULT_REPO}"
        [[ "$issue" =~ ^[0-9]+$ ]] || die "el issue tiene que ser un número (recibido: '$issue')"
        [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "repo inválido: '$repo' (owner/repo)"

        url=$(secret_get "$routine" url) || true
        token=$(secret_get "$routine" token) || true
        [ -n "$url" ] || die "no encuentro la URL de devflow-$routine. Guardala con: $0 --store $routine"
        [ -n "$token" ] || die "no encuentro el token de devflow-$routine. Guardalo con: $0 --store $routine"

        body=$(python3 -c 'import json,sys; print(json.dumps({"text": f"issue={sys.argv[1]} repo={sys.argv[2]}"}))' "$issue" "$repo")
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        # Headers por stdin (-K -): el token no queda en `ps` ni en el historial.
        status=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS -K - \
            -o "$tmp" -w '%{http_code}' -X POST "$url" \
            -H "anthropic-beta: $FIRE_BETA" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            --data "$body") || die "falló la conexión con $url"
        unset token

        if [ "$status" != 200 ] && [ "$status" != 201 ]; then
            echo "Error: HTTP $status al disparar devflow-$routine" >&2
            python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); e=d.get("error",d)
    print(e.get("type",""), e.get("message","") if isinstance(e,dict) else e, file=sys.stderr)
except Exception:
    print(open(sys.argv[1]).read()[:500], file=sys.stderr)' "$tmp"
            exit 1
        fi
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["claude_code_session_url"])' "$tmp" \
            || die "respuesta sin claude_code_session_url"
        ;;
    *)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
        exit 1
        ;;
esac
