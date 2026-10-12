#!/usr/bin/env bash
# Sincroniza las skills del plugin devflow (z4app-dev/claude-plugins) en un repo destino.
#
# Uso: scripts/sync-skills.sh <ruta-repo-destino> [ref]
#   ref: tag o rama de claude-plugins. Default: el último tag devflow-v*.
#
# Copia plugins/devflow/skills/<x>/ a <destino>/.claude/skills/devflow-<x>/, borrando antes las
# carpetas devflow-* existentes. No toca otras skills del repo y no commitea.
# Requiere: gh (autenticado con acceso a z4app-dev/claude-plugins) y git.
set -euo pipefail

PLUGINS_REPO="${DEVFLOW_PLUGINS_REPO:-z4app-dev/claude-plugins}"
TAG_PREFIX="devflow-v"

die() { echo "error: $*" >&2; exit 1; }

[ $# -ge 1 ] && [ $# -le 2 ] || die "uso: $0 <ruta-repo-destino> [ref]"
command -v gh >/dev/null || die "falta gh"
command -v git >/dev/null || die "falta git"

DEST="$1"
[ -d "$DEST" ] || die "no existe el directorio destino: $DEST"
DEST="$(cd "$DEST" && pwd)"
git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$DEST no es un repo git"
DEST="$(git -C "$DEST" rev-parse --show-toplevel)"

REF="${2:-}"
if [ -z "$REF" ]; then
  REF="$(gh api "repos/$PLUGINS_REPO/tags" --paginate --jq ".[].name | select(startswith(\"$TAG_PREFIX\"))" \
    | sort -V | tail -1)"
  [ -n "$REF" ] || die "no hay tags $TAG_PREFIX* en $PLUGINS_REPO"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Obteniendo $PLUGINS_REPO@$REF"
if ! gh repo clone "$PLUGINS_REPO" "$TMP/src" -- --quiet --depth 1 --branch "$REF" \
     -c advice.detachedHead=false 2>"$TMP/clone.log"; then
  cat "$TMP/clone.log" >&2
  die "no se pudo clonar $PLUGINS_REPO en $REF"
fi
SHA="$(git -C "$TMP/src" rev-parse HEAD)"

SRC_SKILLS="$TMP/src/plugins/devflow/skills"
[ -d "$SRC_SKILLS" ] || die "no existe plugins/devflow/skills en $REF"

DEST_SKILLS="$DEST/.claude/skills"
mkdir -p "$DEST_SKILLS"

# Borrar la copia anterior para no dejar archivos huérfanos.
find "$DEST_SKILLS" -mindepth 1 -maxdepth 1 -type d -name 'devflow-*' -exec rm -rf {} +

COPIED=()
for dir in "$SRC_SKILLS"/*/; do
  name="$(basename "$dir")"
  [ -f "$dir/SKILL.md" ] || { echo "  (salteo $name: no tiene SKILL.md)"; continue; }
  cp -R "$dir" "$DEST_SKILLS/devflow-$name"
  COPIED+=("devflow-$name")
done
[ ${#COPIED[@]} -gt 0 ] || die "no se encontró ninguna skill en $REF"

cat > "$DEST_SKILLS/DEVFLOW_VERSION" <<EOF
ref=$REF
sha=$SHA
repo=$PLUGINS_REPO
EOF

cat > "$DEST_SKILLS/README-devflow.md" <<EOF
# Skills devflow (copia sincronizada)

Generado por devflow/scripts/sync-skills.sh. No editar a mano; cambiar en $PLUGINS_REPO.

- Versión: \`$REF\` (\`$SHA\`)
- Skills: $(printf '`%s` ' "${COPIED[@]}")
EOF

echo "✔ Sincronizado $REF ($SHA) en $DEST_SKILLS:"
printf '  - %s\n' "${COPIED[@]}"
echo "  (sin commitear)"
