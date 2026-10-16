# devflow

Workflows y skills reutilizables para el flujo ticket → agente → PR. Hoy lo usa
`z4app-organization/ab_gym`.

## Flujo

```
 Issue nuevo ──► [triage · Actions, claude[bot]] ── preguntas ──► /devflow triage (ronda nueva)
      │                                        └─ "Listo para Ready"
      ▼
 Backlog ─(a mano)─► Ready ─(a mano)─► Plan ──► [Routine devflow-plan]
                                         ▲        plan en documentation/plans/ (rama del issue)
                     /devflow plan ──────┘        + comentario devflow:session con la sesión
      (a mano, con el plan aprobado)
                                         ▼
                                    In Progress ──► [Routine devflow-implement]
                                         ▲            código + PR "Closes #n" (quita el plan,
              /devflow implement ────────┘            lo deja con permalink)
                                         │
                PR abierto / ready ──────▼
                                       Review ──► [review · Actions, claude[bot]]
                                         │         /devflow review para otra pasada
           PR cerrado sin mergear ──► vuelve a In Progress
                         PR mergeado ────▼
                                       Merged
                  tag v* (sandbox-release.sh)
                                         ▼
                                      Staging    pre-release + milestone del tag
            Deploy to Production OK (prod-release.sh)
                                         ▼
                                        Done     Release Latest, milestone cerrado

 guard: push a dev/sandbox/main sin PR, force push o PR mergeado sin CI en verde
        ──► comentario en el issue `devflow-alerta`
```

Los cambios de Status los avisa el **relay** con un `repository_dispatch` `project-status-changed`. Los
movimientos que hace la App devflow no llegan al relay, así que no generan loops.

## Componentes

| Carpeta | Qué es |
|---|---|
| [`relay/`](relay/) | Cloudflare Worker. Recibe el webhook `projects_v2_item` de la App devflow y, si cambió el Status de un issue, dispara `repository_dispatch` en el repo del issue. Se opera con `make` (Docker + Wrangler). |
| [`actions/`](actions/README.md) | Composite actions (`set-status`, `linked-issues`, `fire-routine`, `issues-in-range`, `upsert-comment`). Tag móvil `actions-v1`. |
| [`routines/`](routines/README.md) | Prompts y configuración de las Routines de Claude Code `devflow-plan` y `devflow-implement` (sesiones en la nube, disparadas por API). |
| [`scripts/`](scripts/) | `sync-skills.sh` copia las skills de `z4app-dev/claude-plugins` (tag `devflow-vX.Y.Z`) a `.claude/skills/devflow-*` del repo; `fire-routine.sh` dispara una Routine a mano. |

Las skills (`triage`, `plan`, `implement`, `review`) viven en el plugin `devflow` de
[`z4app-dev/claude-plugins`](https://github.com/z4app-dev/claude-plugins). Los workflows son
archivos finos en cada repo (`.github/workflows/devflow-*.yml`); en `ab_gym` son:

| Workflow | Trigger | Propósito |
|---|---|---|
| `devflow-triage` | issue nuevo, `/devflow triage` | Triage con la skill, comenta como `claude[bot]`. |
| `devflow-router` | relay (Plan / In Progress), `/devflow plan\|implement`, dispatch | Dispara la Routine y deja el link de la sesión. |
| `devflow-pr` | PR a `dev` | Review / Merged / vuelta a In Progress. |
| `devflow-review` | PR a `dev` abierto o ready, `/devflow review` | Review con la skill, comenta como `claude[bot]`. |
| `devflow-release` | tag `v*`, Deploy to Production, dispatch | Staging / Done, Releases y milestones. |
| `devflow-guard` | push a `dev`/`sandbox`/`main`, PR mergeado | Alertas de cambios sin PR o con CI en rojo. |

Reglas comunes: kill switch `vars.AGENT_ENABLED` en lo que dispara agentes; se ignoran bots y el label
`no-agent`; los comandos `/devflow` (primera línea) sólo valen de OWNER, MEMBER o COLLABORATOR; el texto
del evento pasa por `env:` y se valida; `concurrency` por issue/PR.

## Sumar otro repo (checklist)

El script de onboarding queda para cuando sumemos el segundo proyecto.

- [ ] Instalar en el repo la **App devflow** (Projects write a nivel org, Issues y Pull requests) y la
      **Claude App** (`/install-github-app`).
- [ ] Si la org es otra: sumarla a `ALLOWED_ORGS` en `relay/wrangler.toml` y `make deploy`.
- [ ] Project con las columnas Backlog, Ready, Plan, In Progress, Review, Merged, Staging, Done;
      *Auto-add* de issues activado y los workflows nativos que mueven Status desactivados.
- [ ] `.devflow/config.yml` con el project y los nombres de las columnas (ver
      [`actions/README.md`](actions/README.md)).
- [ ] Variables: `DEVFLOW_APP_CLIENT_ID`, `AGENT_ENABLED` (arrancar en `false`),
      `DEVFLOW_ROUTINE_PLAN_URL`, `DEVFLOW_ROUTINE_IMPLEMENT_URL`.
- [ ] Secrets: `DEVFLOW_APP_PRIVATE_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `DEVFLOW_ROUTINE_PLAN_TOKEN`,
      `DEVFLOW_ROUTINE_IMPLEMENT_TOKEN`.
- [ ] Routines `devflow-plan` y `devflow-implement` para el repo, con su entorno cloud (setup script y
      hook SessionStart) y sin connectors (ver [`routines/README.md`](routines/README.md)).
- [ ] Skills: `scripts/sync-skills.sh <repo> devflow-vX.Y.Z` y commit en la rama por defecto.
- [ ] Copiar y adaptar los workflows `devflow-*.yml` (nombre del CI, ramas, tags de release).
- [ ] `CLAUDE.md` del repo: comandos verificados, convenciones, zonas sensibles y la sección
      "Flujo de trabajo para agentes".
- [ ] Labels `no-agent` y `devflow-alerta`; formularios de issue con tipo.
- [ ] Probar con `workflow_dispatch` (dry run) y un issue descartable; recién ahí `AGENT_ENABLED=true`.
