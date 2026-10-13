#!/bin/bash
# Setea el Status de un issue en el project de devflow. Si el issue no está en el project, lo agrega.
# Idempotente: si ya tiene ese Status, no hace nada.
#
# Entorno: ISSUE, STATUS (clave de config: review, merged…), ONLY_FROM (clave, opcional),
#          GH_TOKEN, REPO, CONFIG, DRY_RUN.
# Outputs: changed (true|false), previous (nombre del Status anterior, vacío si no tenía).

source "$(dirname "$0")/../lib/common.sh"
require_tools gh jq
require_token
resolve_repo
require_number issue "${ISSUE:-}"
[[ "${STATUS:-}" =~ ^[a-z_]+$ ]] || die "status inválido: '${STATUS:-}' (clave de config, p. ej. review)"

target=$(cfg "statuses.$STATUS")
only_from=""
if [ -n "${ONLY_FROM:-}" ]; then
    [[ "$ONLY_FROM" =~ ^[a-z_]+$ ]] || die "only_from inválido: '$ONLY_FROM'"
    only_from=$(cfg "statuses.$ONLY_FROM")
fi
project_owner=$(cfg project.owner)
project_number=$(cfg project.number)
require_number project.number "$project_number"

project_fields='id title field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } }'
project=$(gql "query(\$login: String!, \$number: Int!) {
    organization(login: \$login) { projectV2(number: \$number) { $project_fields } } }" \
    -f login="$project_owner" -F number="$project_number" --jq '.data.organization.projectV2' 2>/dev/null || true)
if [ -z "$project" ] || [ "$project" = null ]; then
    project=$(gql "query(\$login: String!, \$number: Int!) {
        user(login: \$login) { projectV2(number: \$number) { $project_fields } } }" \
        -f login="$project_owner" -F number="$project_number" --jq '.data.user.projectV2' 2>/dev/null || true)
fi
[ -n "$project" ] && [ "$project" != null ] || die "no encuentro el project $project_owner #$project_number (¿permisos del token?)"

project_id=$(jq -r .id <<<"$project")
field_id=$(jq -r '.field.id // empty' <<<"$project")
[ -n "$field_id" ] || die "el project no tiene un campo single-select 'Status'"
option_id=$(jq -r --arg n "$target" '.field.options[] | select(.name == $n) | .id' <<<"$project")
[ -n "$option_id" ] || die "el campo Status no tiene la opción '$target' (revisá statuses en la config)"

issue=$(gql 'query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { issue(number: $number) {
        id
        projectItems(first: 100, includeArchived: true) { nodes {
            id isArchived project { id }
            fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
        } }
    } } }' -f owner="$REPO_OWNER" -f name="$REPO_NAME" -F number="$ISSUE" --jq '.data.repository.issue')
[ -n "$issue" ] && [ "$issue" != null ] || die "no encuentro el issue #$ISSUE en $REPO"

issue_id=$(jq -r .id <<<"$issue")
item=$(jq -c --arg p "$project_id" '[.projectItems.nodes[] | select(.project.id == $p)][0] // empty' <<<"$issue")
current=$(jq -r '.fieldValueByName.name // empty' <<<"${item:-null}")

set_output previous "$current"

if [ -n "$only_from" ] && [ "$current" != "$only_from" ]; then
    warn "#$ISSUE está en '${current:-sin Status}', no en '$only_from': no lo muevo a '$target'"
    set_output changed false
    exit 0
fi

if [ -n "$item" ] && [ "$current" = "$target" ]; then
    log "#$ISSUE ya está en '$target': sin cambios"
    set_output changed false
    exit 0
fi

if [ -z "$item" ]; then
    if is_dry_run; then
        log "[dry-run] agregaría #$ISSUE al project $project_owner #$project_number"
        item_id="<nuevo-item>"
    else
        item_id=$(gql 'mutation($project: ID!, $content: ID!) {
            addProjectV2ItemById(input: {projectId: $project, contentId: $content}) { item { id } } }' \
            -f project="$project_id" -f content="$issue_id" --jq '.data.addProjectV2ItemById.item.id')
        log "#$ISSUE agregado al project $project_owner #$project_number"
    fi
else
    item_id=$(jq -r .id <<<"$item")
    [ "$(jq -r .isArchived <<<"$item")" = true ] && warn "el item de #$ISSUE está archivado en el project"
fi

if is_dry_run; then
    log "[dry-run] movería #$ISSUE: '${current:-sin Status}' → '$target'"
else
    gql 'mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
        updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field,
            value: {singleSelectOptionId: $option}}) { projectV2Item { id } } }' \
        -f project="$project_id" -f item="$item_id" -f field="$field_id" -f option="$option_id" >/dev/null
    log "#$ISSUE: '${current:-sin Status}' → '$target'"
fi
set_output changed true
