// BOYGAMES — lien de réinitialisation du mot de passe généré par l'équipe (projet TEST).
// Pourquoi : l'envoi d'e-mails gratuit de Supabase ne part qu'aux membres de l'équipe du projet ; un testeur qui a
// oublié son mot de passe ne recevrait rien. Le Fondateur (ou un admin) génère ici un lien à usage unique (1 h) qu'il
// transmet lui-même au joueur. L'adresse e-mail du joueur n'est jamais renvoyée. Chaque lien est inscrit au journal.
// Droits : admin/fondateur seulement ; un compte de l'équipe ne peut être visé que par le Fondateur.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.58.0";

const ALLOWED_BASES = [/^https:\/\/6hkd26wvy7-del\.github\.io\/pocket-arcade\/test\/$/, /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/$/];
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // 1. qui appelle ? (jeton de session du site)
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who, error: whoErr } = await admin.auth.getUser(jwt);
  if (whoErr || !who?.user) return json({ error: "not authenticated" }, 401);
  const callerId = who.user.id;
  const { data: callerRole } = await admin.from("user_roles").select("role").eq("user_id", callerId).maybeSingle();
  const role = callerRole?.role ?? null;
  if (role !== "founder" && role !== "admin") return json({ error: "forbidden" }, 403);

  // 2. pour qui ? et vers quel site ?
  let body: { pseudo?: string; base?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid body" }, 400); }
  const pseudo = String(body.pseudo ?? "").trim(), base = String(body.base ?? "");
  if (!pseudo || pseudo.length > 32) return json({ error: "invalid pseudo" }, 400);
  if (!ALLOWED_BASES.some((r) => r.test(base))) return json({ error: "invalid base" }, 400);
  const { data: target } = await admin.from("profiles").select("id, pseudo").ilike("pseudo", pseudo.replace(/[%_\\]/g, "\\$&")).maybeSingle();
  if (!target) return json({ error: "unknown player" }, 404);
  const { data: targetRole } = await admin.from("user_roles").select("role").eq("user_id", target.id).maybeSingle();
  if (targetRole && role !== "founder") return json({ error: "forbidden" }, 403);          // un admin ne vise pas l'équipe
  if (targetRole?.role === "founder" && target.id !== callerId) return json({ error: "forbidden" }, 403);

  // 3. lien de récupération à usage unique (aucun e-mail envoyé)
  const { data: u, error: uErr } = await admin.auth.admin.getUserById(target.id);
  if (uErr || !u?.user?.email) return json({ error: "no email" }, 400);
  const { data: link, error: lErr } = await admin.auth.admin.generateLink({ type: "recovery", email: u.user.email });
  const hashed = link?.properties?.hashed_token;
  if (lErr || !hashed) return json({ error: "link failed" }, 500);

  await admin.from("admin_actions").insert({ by_user: callerId, target_user: target.id, action: "lien_mot_de_passe", detail: { valable: "1 h, usage unique" } });
  return json({ ok: true, pseudo: target.pseudo, link: base + "?reset=" + encodeURIComponent(hashed) });
});
