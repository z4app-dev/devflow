#!/bin/bash
# Lista los issues (del mismo repo) que un PR cierra al mergearse (closingIssuesReferences).
#
# Entorno: PR, GH_TOKEN, REPO.
# Outputs: issues (JSON, p. ej. [12,34]), count.

source "$(dirname "$0")/../lib/common.sh"
require_tools gh jq
require_token
resolve_repo
require_number pr "${PR:-}"

refs=$(gql 'query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        closingIssuesReferences(first: 50) { nodes { number repository { nameWithOwner } } }
    } } }' -f owner="$REPO_OWNER" -f name="$REPO_NAME" -F number="$PR" \
    --jq '.data.repository.pullRequest.closingIssuesReferences.nodes')
[ -n "$refs" ] && [ "$refs" != null ] || die "no encuentro el PR #$PR en $REPO"

other=$(jq -r --arg r "$REPO" '[.[] | select(.repository.nameWithOwner != $r) | "\(.repository.nameWithOwner)#\(.number)"] | join(", ")' <<<"$refs")
[ -n "$other" ] && warn "el PR #$PR cierra issues de otros repos (se ignoran): $other"

issues=$(jq -c --arg r "$REPO" '[.[] | select(.repository.nameWithOwner == $r) | .number] | unique' <<<"$refs")
log "PR #$PR cierra: $issues"
set_output issues "$issues"
set_output count "$(jq length <<<"$issues")"
