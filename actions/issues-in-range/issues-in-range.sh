#!/bin/bash
# Lista los issues cerrados por PRs mergeados cuyo merge commit está en FROM_REF..TO_REF.
# Necesita un checkout con historia completa (actions/checkout con fetch-depth: 0) y los tags.
#
# Entorno: FROM_REF, TO_REF, GH_TOKEN, REPO, GIT_DIR_PATH (por defecto .).
# Outputs: issues (JSON, p. ej. [12,34]), prs (JSON), count.

source "$(dirname "$0")/../lib/common.sh"
require_tools gh jq git
require_token
resolve_repo

valid_ref() { [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$1" != -* ]] && [[ "$1" != *..* ]]; }
valid_ref "${FROM_REF:-}" || die "from_ref inválido: '${FROM_REF:-}'"
valid_ref "${TO_REF:-}" || die "to_ref inválido: '${TO_REF:-}'"

cd "${GIT_DIR_PATH:-.}"
from=$(git rev-parse --verify --quiet "$FROM_REF^{commit}") || die "no encuentro '$FROM_REF' (¿fetch-depth: 0 y tags?)"
to=$(git rev-parse --verify --quiet "$TO_REF^{commit}") || die "no encuentro '$TO_REF' (¿fetch-depth: 0 y tags?)"

commits=$(git rev-list "$from..$to")
if [ -z "$commits" ]; then
    log "no hay commits en $FROM_REF..$TO_REF"
    set_output issues '[]'; set_output prs '[]'; set_output count 0
    exit 0
fi
log "$(wc -l <<<"$commits" | tr -d ' ') commits en $FROM_REF..$TO_REF"

# Cota inferior para mergedAt: el commit más viejo del rango (menos un día de margen).
# Un PR mergeado antes no puede tener su merge commit en el rango.
oldest=$(git log --format=%ct "$from..$to" | sort -n | head -1)
since=$(date -u -d "@$((oldest - 86400))" +%Y-%m-%d 2>/dev/null || date -u -r "$((oldest - 86400))" +%Y-%m-%d)

prs=$(gh pr list -R "$REPO" --state merged --search "merged:>=$since" -L 1000 \
    --json number,mergeCommit,closingIssuesReferences)

result=$(jq -c --arg commits "$commits" --arg r "$REPO" '
    ($commits | split("\n") | map(select(length > 0)) | map({(.): true}) | add) as $in
    | [.[] | select(.mergeCommit.oid and $in[.mergeCommit.oid])]
    | {
        prs: (map(.number) | sort),
        issues: ([.[].closingIssuesReferences[]
            | select("\(.repository.owner.login)/\(.repository.name)" == $r) | .number] | unique)
      }' <<<"$prs")

log "PRs en el rango: $(jq -c .prs <<<"$result")"
log "issues cerrados: $(jq -c .issues <<<"$result")"
set_output issues "$(jq -c .issues <<<"$result")"
set_output prs "$(jq -c .prs <<<"$result")"
set_output count "$(jq '.issues | length' <<<"$result")"
