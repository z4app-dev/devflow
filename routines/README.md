# Routines de devflow

`plan` e `implement` corren como **Routines** de Claude Code: sesiones en la nube de Anthropic que
se disparan por API, consumen del plan de la cuenta (no de minutos de GitHub Actions) y después se
pueden abrir para conversar con el agente. `triage` y `review` corren en GitHub Actions (Etapa 6).

| Routine | Prompt | Skill que ejecuta | Modelo |
|---|---|---|---|
| `devflow-plan` | [`plan.md`](plan.md) | `/devflow-plan <n>` | El más capaz disponible |
| `devflow-implement` | [`implement.md`](implement.md) | `/devflow-implement <n>` | A elección (ver abajo) |

Configuración común de las dos:

- **Repositorio:** `z4app-organization/ab_gym`. La Routine clona la rama por defecto (`dev`), así
  que las skills (`.claude/skills/devflow-*`) y el `CLAUDE.md` que usa son los de `dev`.
- **Entorno:** `z4app-ab_gym` (Network access **Trusted**, sin variables de entorno). Su setup
  script es `ab_gym/scripts/devflow/cloud-setup.sh`, y el hook SessionStart del repo
  (`scripts/devflow/cloud-session-start.sh`) levanta el stack de tests en cada sesión.
- **Connectors:** **ninguno**. Por defecto una Routine incluye todos los connectors de la cuenta
  (por ejemplo el MCP de Z4App) y puede usarlos sin pedir permiso: hay que quitarlos todos.
- **Trigger:** API (sin schedule ni eventos de GitHub).
- **Modelo de `implement`:** el más capaz da mejores resultados en cambios grandes; uno más chico
  rinde más el plan Max en issues acotados. Se cambia en el editor de la Routine.

## Disparo

El cuerpo del POST es siempre una sola línea:

```json
{"text": "issue=<n> repo=<owner/repo>"}
```

El texto llega a la sesión envuelto en un bloque `routine-fire-payload` marcado como no confiable.
Los prompts lo usan **solo** para leer esos dos valores, validan que `issue` sea numérico y que
`repo` esté en la lista permitida y sea el repo clonado, e ignoran cualquier otra cosa.

A mano:

```bash
scripts/fire-routine.sh plan 123                 # imprime la URL de la sesión
scripts/fire-routine.sh implement 123
scripts/fire-routine.sh plan 123 otra-org/otro-repo   # repo explícito (tiene que estar permitido en el prompt)
scripts/fire-routine.sh --check                   # verifica que estén URL y token de las dos (no dispara)
```

En la Etapa 6 lo hace un workflow que escucha `project-status-changed` (Status **Plan** →
`devflow-plan`, **In Progress** → `devflow-implement`) y comenta en el issue el link a la sesión.

## URL y token

Cada Routine tiene una URL (`https://api.anthropic.com/v1/claude_code/routines/<id>/fire`) y un
token propio que solo sirve para dispararla. El token se muestra **una sola vez** al generarlo.

Se guardan en el almacén de secretos del sistema, nunca en archivos ni en el repo:

| Sistema | Dónde | Servicio | Cuentas |
|---|---|---|---|
| macOS | Llavero (`security`) | `devflow-routine-plan` / `devflow-routine-implement` | `url`, `token` |
| Linux | libsecret (`secret-tool`) | atributo `service` = ídem | atributo `account` = `url`, `token` |

Para guardarlos (los pide sin eco, no quedan en el historial):

```bash
scripts/fire-routine.sh --store plan
scripts/fire-routine.sh --store implement
```

En la Etapa 6 se suman como secrets del repo (`DEVFLOW_ROUTINE_PLAN_URL`/`_TOKEN` y los de
`implement`).

### Rotar un token

1. claude.ai/code/routines → la Routine → menú **Edit** → trigger **API** → **Regenerate** (o
   **Revoke** si se filtró). El token anterior deja de servir en el acto.
2. `scripts/fire-routine.sh --store <plan|implement>` con la URL (no cambia) y el token nuevo, en
   cada máquina que dispare.
3. Actualizar el secret del repo en GitHub (Etapa 6).
4. `scripts/fire-routine.sh --check <plan|implement>`.

## Límites y comportamiento

- **Identidad:** commits, pushes, PRs y comentarios salen con el usuario de GitHub de la cuenta
  dueña de las Routines. Como owner puede saltear rulesets, así que la protección de `dev` y `main`
  depende de los prompts ("nunca pushear a `dev` ni a `main`").
- **Ramas:** si el prompt no dice otra cosa, una Routine pushea a ramas `claude/…`. Los prompts
  piden usar la rama de la skill (`{tipo}/{n}-{slug}`) y no tocar la `claude/…` de la sesión.
- **GitHub solo por REST:** en la nube el proxy de GitHub bloquea GraphQL (`gh pr`, `gh issue`,
  `gh repo view`). Las skills usan `gh api`. Pasar un PR de draft a ready **no existe en REST**:
  por eso `plan` no abre PR e `implement` lo crea al final, ya listo para review.
- **Disparos:** hasta 30 por hora por Routine y 100 por hora por cuenta.
- **Estado del run:** verde en la lista de runs solo significa que la sesión arrancó y terminó sin
  error de infraestructura; el resultado real está en el transcript y en el resumen final.
- Requiere las skills **devflow-v0.1.4** o posterior sincronizadas en `dev` (REST y PR al final).
