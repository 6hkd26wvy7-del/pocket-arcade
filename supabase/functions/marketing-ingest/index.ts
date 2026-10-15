// BOYGAMES — dépôt des vidéos marketing fabriquées par GitHub Actions (projet TEST).
// Reçoit : en-tête x-marketing-token + formulaire (meta JSON, video MP4, poster JPEG facultatif).
// Range la vidéo dans le stockage PRIVÉ « marketing » et l'inscrit dans la file « à valider ». Ne publie rien.
// La clé de service reste dans Supabase (variable d'environnement de la fonction), jamais dans GitHub ni dans le code.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.58.0";

const MAX_VIDEO = 50 * 1024 * 1024;
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const token = req.headers.get("x-marketing-token") ?? "";
  const { data: ok, error: tokErr } = await admin.rpc("marketing_token_ok", { p_token: token });
  if (tokErr || ok !== true) return json({ error: "forbidden" }, 403);

  let form: FormData;
  try { form = await req.formData(); } catch { return json({ error: "invalid form" }, 400); }
  let meta: Record<string, unknown>;
  try { meta = JSON.parse(String(form.get("meta") ?? "")); } catch { return json({ error: "invalid meta" }, 400); }
  const runId = String(meta.run_id ?? "");
  if (!/^[A-Za-z0-9_-]{1,60}$/.test(runId)) return json({ error: "invalid run_id" }, 400);

  const video = form.get("video");
  if (!(video instanceof File) || video.type !== "video/mp4" || video.size < 10_000 || video.size > MAX_VIDEO) {
    return json({ error: "invalid video" }, 400);
  }
  const videoPath = `${runId}/video.mp4`;
  const up = await admin.storage.from("marketing").upload(videoPath, video, { contentType: "video/mp4", upsert: false });
  if (up.error && !/exists/i.test(up.error.message)) return json({ error: "upload failed" }, 500);

  let posterPath: string | null = null;
  const poster = form.get("poster");
  if (poster instanceof File && poster.type === "image/jpeg" && poster.size < 2 * 1024 * 1024) {
    posterPath = `${runId}/poster.jpg`;
    const pu = await admin.storage.from("marketing").upload(posterPath, poster, { contentType: "image/jpeg", upsert: false });
    if (pu.error && !/exists/i.test(pu.error.message)) posterPath = null;
  }

  const { data, error } = await admin.rpc("marketing_register", { p_meta: meta, p_video_path: videoPath, p_poster_path: posterPath });
  if (error) return json({ error: "register failed" }, 500);
  return json(data);
});
