#!/bin/bash
# Crea o actualiza un comentario único (identificado por un marcador HTML) en un issue o PR.
# El marcador `<!-- devflow:<nombre> -->` se agrega al principio del cuerpo.
# Sólo considera comentarios de bots, para no editar a un humano que haya citado el marcador.
#
# Entorno: NUMBER, MARKER (p. ej. devflow:pr), BODY, MODE (upsert | update-only),
#          GH_TOKEN, REPO, DRY_RUN.
# Outputs: comment_url (vacío si no hizo nada), action (created | updated | skipped).

source "$(dirname "$0")/../lib/common.sh"
require_tools gh jq
require_token
resolve_repo
require_number number "${NUMBER:-}"
[[ "${MARKER:-}" =~ ^[a-z0-9][a-z0-9:_-]*$ ]] || die "marker inválido: '${MARKER:-}' (p. ej. devflow:pr)"
[ -n "${BODY:-}" ] || die "falta el body"
MODE="${MODE:-upsert}"
[ "$MODE" = upsert ] || [ "$MODE" = update-only ] || die "mode inválido: '$MODE' (upsert | update-only)"

tag="<!-- $MARKER -->"
full_body="$tag"$'\n'"$BODY"

existing=$(gh api --paginate "repos/$REPO/issues/$NUMBER/comments" \
    --jq ".[] | select(.user.type == \"Bot\" and (.body | contains(\"$tag\"))) | {id, html_url}" | sed -n 1p)

if [ -n "$existing" ]; then
    id=$(jq -r .id <<<"$existing")
    if is_dry_run; then
        log "[dry-run] actualizaría el comentario $id en #$NUMBER:"$'\n'"$full_body"
        url=$(jq -r .html_url <<<"$existing")
    else
        url=$(jq -n --arg b "$full_body" '{body: $b}' \
            | gh api -X PATCH "repos/$REPO/issues/comments/$id" --input - --jq .html_url)
        log "comentario $tag actualizado en #$NUMBER: $url"
    fi
    set_output action updated
elif [ "$MODE" = update-only ]; then
    log "no hay comentario $tag en #$NUMBER: nada que actualizar"
    set_output action skipped
    set_output comment_url ""
    exit 0
else
    if is_dry_run; then
        log "[dry-run] crearía un comentario en #$NUMBER:"$'\n'"$full_body"
        url=""
    else
        url=$(jq -n --arg b "$full_body" '{body: $b}' \
            | gh api -X POST "repos/$REPO/issues/$NUMBER/comments" --input - --jq .html_url)
        log "comentario $tag creado en #$NUMBER: $url"
    fi
    set_output action created
fi
set_output comment_url "$url"
