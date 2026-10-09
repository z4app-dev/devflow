/**
 * devflow-relay — Cloudflare Worker
 *
 * Recibe el webhook `projects_v2_item` de la GitHub App de devflow y, cuando
 * cambia el Status de un item que es un Issue, dispara un `repository_dispatch`
 * (event_type: "project-status-changed") en el repo de ese issue.
 *
 * Los workflows del repo deciden que hacer segun el status nuevo
 * (Plan -> agente planifica, In Progress -> agente implementa, etc.).
 *
 * Secrets (wrangler secret put ...):
 *   GITHUB_WEBHOOK_SECRET   el "Webhook secret" de la App
 *   GITHUB_APP_ID           App ID numerico
 *   GITHUB_APP_PRIVATE_KEY  clave privada en formato PKCS#8 (BEGIN PRIVATE KEY)
 * Variables (wrangler.toml):
 *   ALLOWED_ORGS            orgs aceptadas, separadas por coma
 */

const GH = "https://api.github.com";

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return new Response("devflow-relay ok");

    const body = await request.text();
    const sig = request.headers.get("x-hub-signature-256") || "";
    if (!(await verifySignature(env.GITHUB_WEBHOOK_SECRET, body, sig))) {
      return new Response("invalid signature", { status: 401 });
    }

    const event = request.headers.get("x-github-event");
    if (event === "ping") return new Response("pong");

    const p = JSON.parse(body);
    const skip = (why) => new Response(`ignored: ${why}`, { status: 202 });

    if (event !== "projects_v2_item" || p.action !== "edited") return skip("event");
    const org = p.organization?.login;
    const allowed = (env.ALLOWED_ORGS || "").split(",").map((s) => s.trim()).filter(Boolean);
    if (!allowed.includes(org)) return skip(`org ${org} not allowed`);
    if (p.sender?.type === "Bot") return skip("change made by a bot"); // evita loops con nuestros workflows
    const fv = p.changes?.field_value;
    if (!fv) return skip("no field change");
    if (fv.field_name && fv.field_name !== "Status") return skip(`field ${fv.field_name}`);
    if (p.projects_v2_item?.content_type !== "Issue") return skip("not an issue");

    const token = await installationToken(env, p.installation.id);

    // Resolvemos issue, repo y status actual (no dependemos del formato de `changes`)
    const data = await graphql(token, `
      query($item: ID!) {
        node(id: $item) {
          ... on ProjectV2Item {
            project { number }
            fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            content { ... on Issue { number repository { nameWithOwner } } }
          }
        }
      }`, { item: p.projects_v2_item.node_id });

    const node = data.node;
    const issue = node?.content;
    if (!issue?.number) return skip("content not resolvable");

    const payload = {
      event_type: "project-status-changed",
      client_payload: {
        issue: issue.number,
        status: node.fieldValueByName?.name || "",
        from: fv.from?.name || "",
        project_number: node.project.number,
        project_item_id: p.projects_v2_item.node_id,
        sender: p.sender?.login || "",
      },
    };

    const r = await fetch(`${GH}/repos/${issue.repository.nameWithOwner}/dispatches`, {
      method: "POST",
      headers: ghHeaders(token),
      body: JSON.stringify(payload),
    });
    if (!r.ok) return new Response(`dispatch failed: ${r.status} ${await r.text()}`, { status: 502 });

    return new Response(`dispatched ${issue.repository.nameWithOwner}#${issue.number} -> ${payload.client_payload.status}`);
  },
};

// ---------- helpers ----------

function ghHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "devflow-relay",
  };
}

async function graphql(token, query, variables) {
  const r = await fetch(`${GH}/graphql`, {
    method: "POST",
    headers: ghHeaders(token),
    body: JSON.stringify({ query, variables }),
  });
  const j = await r.json();
  if (j.errors) throw new Error(JSON.stringify(j.errors));
  return j.data;
}

const enc = new TextEncoder();

export async function verifySignature(secret, body, header) {
  if (!secret || !header.startsWith("sha256=")) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  const expected = "sha256=" + [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (expected.length !== header.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ header.charCodeAt(i);
  return diff === 0;
}

const b64url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

export async function appJwt(appId, pkcs8Pem) {
  const der = Uint8Array.from(
    atob(pkcs8Pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(enc.encode(JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(appId) })));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(sig)}`;
}

async function installationToken(env, installationId) {
  const jwt = await appJwt(env.GITHUB_APP_ID, env.GITHUB_APP_PRIVATE_KEY);
  const r = await fetch(`${GH}/app/installations/${installationId}/access_tokens`, {
    method: "POST",
    headers: ghHeaders(jwt),
  });
  if (!r.ok) throw new Error(`installation token failed: ${r.status} ${await r.text()}`);
  return (await r.json()).token;
}
