#!/bin/bash
# Completa los issue fields de texto "Rama" y "PR" (nombres en config: issue_fields.branch / .pr).
# Los issue fields son de la organización (GraphQL: Organization.issueFields, setIssueFieldValue).
# Idempotente: sólo escribe los valores que cambian. Un input vacío no toca ese campo.
#
# Entorno: ISSUE, BRANCH, PR_URL, GH_TOKEN, REPO, CONFIG, DRY_RUN.
# Outputs: changed (true|false).

source "$(dirname "$0")/../lib/common.sh"
require_tools gh jq
require_token
resolve_repo
require_number issue "${ISSUE:-}"
[ -n "${BRANCH:-}" ] || [ -n "${PR_URL:-}" ] || die "indicá al menos branch o pr"
if [ -n "${BRANCH:-}" ]; then
    # Nombres de rama válidos de git, sin espacios ni caracteres de control.
    [[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] && [ ${#BRANCH} -le 255 ] || die "branch inválida: '$BRANCH'"
fi
if [ -n "${PR_URL:-}" ]; then
    [[ "$PR_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+$ ]] || die "pr tiene que ser la URL de un PR (recibido: '$PR_URL')"
fi

branch_field=$(cfg issue_fields.branch)
pr_field=$(cfg issue_fields.pr)

fields=$(gql 'query($login: String!) { organization(login: $login) {
    issueFields(first: 100) { nodes { ... on IssueFieldText { id name } } } } }' \
    -f login="$REPO_OWNER" --jq '[.data.organization.issueFields.nodes[] | select(.id)]')
field_id() { jq -r --arg n "$1" '.[] | select(.name == $n) | .id' <<<"$fields"; }

issue=$(gql 'query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { issue(number: $number) {
        id
        issueFieldValues(first: 50) { nodes { ... on IssueFieldTextValue { value field { ... on IssueFieldText { id } } } } }
    } } }' -f owner="$REPO_OWNER" -f name="$REPO_NAME" -F number="$ISSUE" --jq '.data.repository.issue')
[ -n "$issue" ] && [ "$issue" != null ] || die "no encuentro el issue #$ISSUE en $REPO"
issue_id=$(jq -r .id <<<"$issue")
current_value() { jq -r --arg f "$1" '.issueFieldValues.nodes[] | select(.field.id? == $f) | .value' <<<"$issue"; }

updates='[]'
plan_field() { # <nombre del campo> <valor>
    local name="$1" value="$2" id
    [ -n "$value" ] || return 0
    id=$(field_id "$name")
    [ -n "$id" ] || die "la organización $REPO_OWNER no tiene un issue field de texto '$name'"
    if [ "$(current_value "$id")" = "$value" ]; then
        log "#$ISSUE: '$name' ya es '$value'"
    else
        log "#$ISSUE: '$name' → '$value'"
        updates=$(jq -c --arg id "$id" --arg v "$value" '. + [{fieldId: $id, textValue: $v}]' <<<"$updates")
    fi
}
plan_field "$branch_field" "${BRANCH:-}"
plan_field "$pr_field" "${PR_URL:-}"

if [ "$updates" = '[]' ]; then
    set_output changed false
    exit 0
fi
if is_dry_run; then
    log "[dry-run] setIssueFieldValue en #$ISSUE: $updates"
else
    jq -n --arg q 'mutation($input: SetIssueFieldValueInput!) { setIssueFieldValue(input: $input) { clientMutationId } }' \
        --arg issue "$issue_id" --argjson fields "$updates" \
        '{query: $q, variables: {input: {issueId: $issue, issueFields: $fields}}}' \
        | gh api graphql --input - >/dev/null
fi
set_output changed true
