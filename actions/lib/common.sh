# Funciones comunes de las composite actions de devflow. Se carga con `source`.
#
# Variables de entorno que entiende:
#   GH_TOKEN      token para `gh` (en Actions: el de la App devflow).
#   REPO          owner/repo (por defecto $GITHUB_REPOSITORY).
#   CONFIG        ruta a .devflow/config.yml (por defecto .devflow/config.yml).
#   DRY_RUN=1     imprime las mutaciones en lugar de ejecutarlas.

set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }
warn() { echo "::warning::$*" >&2; }
log() { echo "$*" >&2; }

is_dry_run() { [ "${DRY_RUN:-0}" = 1 ] || [ "${DRY_RUN:-}" = true ]; }

require_tools() {
    local t
    for t in "$@"; do command -v "$t" >/dev/null || die "falta la herramienta '$t'"; done
}

require_number() { # <nombre> <valor>
    [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "$1 tiene que ser un número positivo (recibido: '$2')"
}

resolve_repo() {
    REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
    [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "repo inválido: '$REPO' (owner/repo)"
    REPO_OWNER="${REPO%%/*}"
    REPO_NAME="${REPO#*/}"
}

require_token() {
    [ -n "${GH_TOKEN:-}" ] || die "falta el token (input 'token')"
}

# Escribe un output de la action (o lo imprime si se corre fuera de Actions).
set_output() { # <nombre> <valor>
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        local delim="EOF_$RANDOM$RANDOM"
        printf '%s<<%s\n%s\n%s\n' "$1" "$delim" "$2" "$delim" >> "$GITHUB_OUTPUT"
    else
        printf '%s=%s\n' "$1" "$2"
    fi
}

# Lee una clave de la config con notación de puntos (p. ej. `statuses.review`).
# Usa yq si está (runners de GitHub) y si no, python3 + PyYAML.
cfg() { # <clave>
    local file="${CONFIG:-.devflow/config.yml}" value
    [ -f "$file" ] || die "no encuentro la config '$file' (¿falta el checkout?)"
    if command -v yq >/dev/null; then
        value=$(yq -r ".$1 // \"\"" "$file")
    else
        value=$(python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
for k in sys.argv[2].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print("" if d is None else d)' "$file" "$1")
    fi
    [ -n "$value" ] || die "la config '$file' no define '$1'"
    printf '%s' "$value"
}

# GraphQL con variables: gql <query> [-f nombre=valor | -F nombre=valor]...
gql() {
    local query="$1"; shift
    gh api graphql -f query="$query" "$@"
}
