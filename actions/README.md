# devflow · composite actions

Lógica reutilizable de los workflows de devflow. Son composite actions (bash + `gh` + `jq`)
**sin secrets propios**: cada repo tiene sus workflows finos y les pasa el token.

> ¿Por qué no reusable workflows? `secrets: inherit` sólo funciona dentro de la misma org;
> `devflow` vive en otra org que los repos. Con composite actions el token y
> `claude-code-action` quedan en el workflow del repo.

| Action | Qué hace | Token |
|---|---|---|
| `set-status` | Setea el Status del issue en el project (lo agrega si falta). Idempotente. | App devflow |
| `linked-issues` | Issues que cierra un PR (`closingIssuesReferences`), como JSON. | App devflow |
| `fire-routine` | Dispara la Routine `plan` / `implement` y devuelve el link de sesión. | token de la Routine |
| `issues-in-range` | Issues cerrados por PRs cuyo merge commit está en `from..to`. | App devflow |
| `upsert-comment` | Crea o edita un comentario único con marcador `<!-- devflow:<x> -->`. | App devflow |

Versionado: `actions-v1` es un tag **móvil** (último `actions-v1.x.y`); los `actions-v1.x.y` son
inmutables. En los workflows usá `@actions-v1`.

## Requisitos en el repo

- `.devflow/config.yml` (la lee `set-status`; necesita `actions/checkout`):

  ```yaml
  project: { owner: z4app-organization, number: 1 }
  statuses: { backlog: Backlog, ready: Ready, plan: Plan, in_progress: In Progress,
              review: Review, merged: Merged, staging: Staging, done: Done }
  routines:
    plan:      { url_var: DEVFLOW_ROUTINE_PLAN_URL,      token_secret: DEVFLOW_ROUTINE_PLAN_TOKEN }
    implement: { url_var: DEVFLOW_ROUTINE_IMPLEMENT_URL, token_secret: DEVFLOW_ROUTINE_IMPLEMENT_TOKEN }
  ```
- Variable `DEVFLOW_APP_CLIENT_ID` y secret `DEVFLOW_APP_PRIVATE_KEY` (App con Projects write a nivel org,
  Issues y Pull requests).

## Ejemplos

```yaml
steps:
  - uses: actions/checkout@v6
    with: { sparse-checkout: .devflow }
  - id: app
    uses: actions/create-github-app-token@v3
    with:
      client-id: ${{ vars.DEVFLOW_APP_CLIENT_ID }}
      private-key: ${{ secrets.DEVFLOW_APP_PRIVATE_KEY }}
      owner: ${{ github.repository_owner }}

  - id: linked
    uses: z4app-dev/devflow/actions/linked-issues@actions-v1
    with: { token: '${{ steps.app.outputs.token }}', pr: '${{ github.event.pull_request.number }}' }

  - uses: z4app-dev/devflow/actions/set-status@actions-v1
    with: { token: '${{ steps.app.outputs.token }}', issue: '123', status: review }

  # Sólo si está en Merged (si no, advierte y sigue):
  - uses: z4app-dev/devflow/actions/set-status@actions-v1
    with: { token: '${{ steps.app.outputs.token }}', issue: '123', status: staging, only_from: merged }

  - id: fire
    continue-on-error: true      # para comentar el error en el issue
    uses: z4app-dev/devflow/actions/fire-routine@actions-v1
    with:
      routine: plan
      issue: '123'
      url: ${{ vars.DEVFLOW_ROUTINE_PLAN_URL }}
      token: ${{ secrets.DEVFLOW_ROUTINE_PLAN_TOKEN }}
  # → steps.fire.outputs.session_url / steps.fire.outputs.error

  - uses: z4app-dev/devflow/actions/upsert-comment@actions-v1
    with:
      token: ${{ steps.app.outputs.token }}
      number: '123'
      marker: devflow:pr          # → <!-- devflow:pr -->
      body: Texto del comentario
      # mode: update-only        # sólo edita si ya existe

  - uses: actions/checkout@v6
    with: { fetch-depth: 0 }     # issues-in-range necesita historia y tags
  - id: range
    uses: z4app-dev/devflow/actions/issues-in-range@actions-v1
    with: { token: '${{ steps.app.outputs.token }}', from_ref: v26.10.5, to_ref: v26.10.12 }
  # → steps.range.outputs.issues = [12,34]
```

Para iterar sobre un output JSON: `fromJSON(steps.linked.outputs.issues)` en una matrix, o
`jq -r '.[]'` en un `run:` (pasando el output por `env:`).

## Correrlas en local

Los scripts se pueden correr sin Actions; los outputs se imprimen como `nombre=valor`.
`DRY_RUN=1` imprime las mutaciones en lugar de ejecutarlas.

```bash
cd ab_gym
export GH_TOKEN=$(gh auth token) REPO=z4app-organization/ab_gym DRY_RUN=1
ISSUE=362 STATUS=review ../devflow/actions/set-status/set-status.sh
PR=369 ../devflow/actions/linked-issues/linked-issues.sh
FROM_REF=v26.10.5 TO_REF=v26.10.12 ../devflow/actions/issues-in-range/issues-in-range.sh
NUMBER=362 MARKER=devflow:test BODY='hola' ../devflow/actions/upsert-comment/upsert-comment.sh
ROUTINE=plan ISSUE=362 \
  ROUTINE_URL=$(secret-tool lookup service devflow-routine-plan account url) \
  ROUTINE_TOKEN=$(secret-tool lookup service devflow-routine-plan account token) \
  ../devflow/actions/fire-routine/fire-routine.sh
```

Todas validan sus entradas (números, nombres de rama, URLs, refs de git) antes de usarlas.
