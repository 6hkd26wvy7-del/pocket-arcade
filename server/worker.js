// Serveur de jeu BOYGAMES (Cloudflare Workers + Durable Objects).
// Une "salle" par code (ex. K7P2Q). Le serveur décide de tout : les téléphones n'envoient que des directions.
// Aucun secret ici : la connexion est vérifiée avec la clé PUBLIQUE de Supabase (JWKS).

import * as SN from "./arena-engine.js";
import * as SPC from "./space-engine.js";
import * as BK from "./blocks-engine.js";
import * as BBD from "./boyblocks-duel.js";

// Les 3 jeux en ligne. La première lettre du code de salle dit de quel jeu il s'agit : S, P, B ou X.
const KINDS = {
  S: { name: "snake", tickMs: SN.TICK_MS, coop: false,
       create: (seed) => SN.newGame(seed), input: (g, i, m) => { if (m.t === "dir") SN.setDirection(g, i, m.d); },
       step: (g) => SN.step(g), snapshot: SN.snapshot },
  P: { name: "space", tickMs: SPC.TICK_MS, coop: true,
       create: (seed) => SPC.newGame(seed), input: (g, i, m) => { if (m.t === "move") SPC.setTarget(g, i, m.x); },
       step: (g, dt) => SPC.step(g, dt), snapshot: SPC.snapshot },
  B: { name: "blocks", tickMs: BK.TICK_MS, coop: false,
       create: (seed) => BK.newGame(seed), input: (g, i, m) => { if (m.t === "act") BK.act(g, i, m.a); },
       step: (g, dt) => BK.step(g, dt), snapshot: BK.snapshot },
  X: { name: "boyblocks", tickMs: BBD.TICK_MS, coop: false, instant: true,
       create: (seed) => BBD.newGame(seed), input: (g, i, m) => BBD.input(g, i, m),
       step: (g, dt) => BBD.step(g, dt), snapshot: BBD.snapshot, syncLog: BBD.syncLog },
};
const snapshot = (g, kind) => kind.snapshot(g);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------- Vérification de la connexion du joueur (jeton Supabase) ----------
function b64urlToBytes(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function b64urlToJson(s) { return JSON.parse(new TextDecoder().decode(b64urlToBytes(s))); }

let jwksCache = { at: 0, keys: null, url: "" };
async function getJwks(env, fetchFn, now) {
  const url = env.SUPABASE_URL + "/auth/v1/.well-known/jwks.json";
  if (jwksCache.keys && jwksCache.url === url && now - jwksCache.at < 10 * 60 * 1000) return jwksCache.keys;
  const r = await fetchFn(url);
  if (!r.ok) throw new Error("jwks unavailable");
  const body = await r.json();
  jwksCache = { at: now, keys: body.keys || [], url };
  return jwksCache.keys;
}
export function resetJwksCache() { jwksCache = { at: 0, keys: null, url: "" }; }

export async function verifyJwt(token, env, fetchFn = fetch, now = Date.now()) {
  if (typeof token !== "string" || token.length > 4096) throw new Error("bad token");
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("bad token");
  const header = b64urlToJson(parts[0]);
  const payload = b64urlToJson(parts[1]);
  let algo, verifyAlgo;
  if (header.alg === "ES256") { algo = { name: "ECDSA", namedCurve: "P-256" }; verifyAlgo = { name: "ECDSA", hash: "SHA-256" }; }
  else if (header.alg === "RS256") { algo = { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }; verifyAlgo = { name: "RSASSA-PKCS1-v1_5" }; }
  else throw new Error("unsupported alg");

  const keys = await getJwks(env, fetchFn, now);
  const jwk = keys.find((k) => k.kid === header.kid) || (keys.length === 1 && !header.kid ? keys[0] : null);
  if (!jwk) throw new Error("unknown key");
  const key = await crypto.subtle.importKey("jwk", jwk, algo, false, ["verify"]);
  const ok = await crypto.subtle.verify(verifyAlgo, key, b64urlToBytes(parts[2]), new TextEncoder().encode(parts[0] + "." + parts[1]));
  if (!ok) throw new Error("bad signature");

  if (!payload.exp || payload.exp * 1000 <= now) throw new Error("expired");
  if (payload.iss !== env.SUPABASE_URL + "/auth/v1") throw new Error("bad issuer");
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.includes("authenticated")) throw new Error("bad audience");
  if (!UUID.test(payload.sub || "")) throw new Error("bad subject");
  return { uid: payload.sub.toLowerCase() };
}

async function fetchPseudo(uid, token, env, fetchFn) {
  const r = await fetchFn(env.SUPABASE_URL + "/rest/v1/profiles?select=pseudo&id=eq." + uid, {
    headers: { apikey: env.SUPABASE_KEY, Authorization: "Bearer " + token },
  });
  if (!r.ok) return null;
  const rows = await r.json();
  return rows && rows[0] && rows[0].pseudo ? String(rows[0].pseudo) : null;
}

// Contrôle côté serveur : compte suspendu, maintenance, bêta privée.
// Appelle la fonction arena_check() de la base AVEC le jeton du joueur. En cas de doute : refus.
async function checkAccess(token, env, fetchFn) {
  let r;
  try {
    r = await fetchFn(env.SUPABASE_URL + "/rest/v1/rpc/arena_check", {
      method: "POST",
      headers: { apikey: env.SUPABASE_KEY, Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: "{}",
    });
  } catch (e) { return "auth"; }
  if (r.ok) {
    try { return (await r.json()) === true ? null : "auth"; } catch (e) { return "auth"; }
  }
  let msg = "";
  try { const j = await r.json(); msg = String((j && (j.message || j.error)) || ""); } catch (e) { /* ignore */ }
  if (/banned/.test(msg)) return "banned";
  if (/maintenance/.test(msg)) return "maintenance";
  if (/beta/.test(msg)) return "beta";
  return "auth";
}

// ---------- Point d'entrée ----------
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/play\/([SPBX][A-Z0-9]{3,7})$/);
    if (!m) return new Response("BOYGAMES arena server v4 (duel BoyBlocks)", { status: 200 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("Expected websocket", { status: 426 });
    const allowed = String(env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
    const origin = request.headers.get("Origin");
    if (allowed.length && origin && !allowed.includes(origin)) return new Response("Forbidden origin", { status: 403 });
    const id = env.ARENA.idFromName(m[1]);
    return env.ARENA.get(id).fetch(request);
  },
};

// ---------- Une salle de jeu ----------
export class ArenaRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.fetchFn = env.FETCH || fetch;
    this.tickOverride = Number(env.TICK_MS) || 0;
    this.dtOverride = Number(env.DT_MS) || 0; // pour les tests : accélère le temps du jeu
    this.kind = null;
    this.countdownMs = env.COUNTDOWN_MS !== undefined ? Number(env.COUNTDOWN_MS) : 3000;
    this.graceMs = env.GRACE_MS !== undefined ? Number(env.GRACE_MS) : 10000;
    this.slots = [null, null]; // { uid, pseudo, ws }
    this.game = null;
    this.phase = "lobby"; // lobby -> countdown -> playing -> over
    this.timer = null;
    this.graceTimers = [null, null];
    this.code = "";
    this.again = [false, false];
    this.endCloseMs = env.END_CLOSE_MS !== undefined ? Number(env.END_CLOSE_MS) : 90000;
  }

  async fetch(request) {
    this.code = new URL(request.url).pathname.split("/").pop();
    this.kind = KINDS[this.code[0]] || KINDS.S;
    this.tickMs = this.tickOverride || this.kind.tickMs;
    this.dtMs = this.dtOverride || this.tickMs;
    const pair = new WebSocketPair();
    const client = pair[0], server = pair[1];
    server.accept();
    this.handle(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  send(ws, obj) { try { ws.send(JSON.stringify(obj)); } catch (e) { /* socket fermée */ } }
  broadcast(obj) { const s = JSON.stringify(obj); this.slots.forEach((p) => { if (p && p.ws) { try { p.ws.send(s); } catch (e) { /* ignore */ } } }); }

  handle(ws) {
    let me = null; // { index }
    let authed = false;
    let bucket = 0;
    const refill = setInterval(() => { bucket = 0; }, 1000);
    const helloTimeout = setTimeout(() => { if (!authed) { this.send(ws, { t: "error", code: "timeout" }); try { ws.close(4000, "timeout"); } catch (e) { /* ignore */ } } }, 5000);

    ws.addEventListener("message", async (ev) => {
      if (++bucket > 40) return; // anti-spam : 40 messages par seconde au plus
      const raw = typeof ev.data === "string" ? ev.data : "";
      if (raw.length > 5000) return;
      let msg;
      try { msg = JSON.parse(raw); } catch (e) { return; }
      if (!msg || typeof msg !== "object") return;

      if (!authed) {
        if (msg.t !== "hello" || this.pendingAuth === ws) return;
        this.pendingAuth = ws;
        try {
          const { uid } = await verifyJwt(msg.token, this.env, this.fetchFn);
          const pseudo = await fetchPseudo(uid, msg.token, this.env, this.fetchFn);
          if (!pseudo) throw new Error("no profile");
          const denied = await checkAccess(msg.token, this.env, this.fetchFn);
          if (denied) {
            this.send(ws, { t: "error", code: denied });
            try { ws.close(4004, denied); } catch (e2) { /* ignore */ }
            return;
          }
          const idx = this.seat(uid, pseudo, ws);
          if (idx < 0) { this.send(ws, { t: "error", code: "full" }); try { ws.close(4002, "full"); } catch (e) { /* ignore */ } return; }
          authed = true;
          me = { index: idx };
          clearTimeout(helloTimeout);
          this.afterJoin();
        } catch (e) {
          this.send(ws, { t: "error", code: "auth" });
          try { ws.close(4003, "auth"); } catch (e2) { /* ignore */ }
        } finally {
          this.pendingAuth = null;
        }
        return;
      }

      if (msg.t === "again") { this.onAgain(me.index); return; }
      if (msg.t === "sync" && this.game && this.kind.syncLog && (this.phase === "playing" || this.phase === "over")) { this.send(ws, this.kind.syncLog(this.game, me.index)); return; }
      if (this.phase === "playing" && this.game) {
        const changed = this.kind.input(this.game, me.index, msg);
        if (changed && this.kind.instant) {
          this.broadcast(snapshot(this.game, this.kind));
          if (this.game.over) this.finish(this.game.reason);
        }
      }
    });

    const gone = () => {
      clearInterval(refill);
      clearTimeout(helloTimeout);
      if (me) this.onLeave(me.index, ws);
    };
    ws.addEventListener("close", gone);
    ws.addEventListener("error", gone);
  }

  // Donne une place au joueur. Même compte qui revient : il retrouve sa place.
  seat(uid, pseudo, ws) {
    for (let i = 0; i < 2; i++) {
      const p = this.slots[i];
      if (p && p.uid === uid) {
        if (p.ws && p.ws !== ws) { try { p.ws.close(4001, "replaced"); } catch (e) { /* ignore */ } }
        p.ws = ws;
        clearTimeout(this.graceTimers[i]);
        return i;
      }
    }
    for (let i = 0; i < 2; i++) {
      if (!this.slots[i]) { this.slots[i] = { uid, pseudo, ws }; return i; }
    }
    return -1;
  }

  afterJoin() {
    const names = this.slots.map((p) => (p ? p.pseudo : null));
    this.slots.forEach((p, i) => { if (p && p.ws) this.send(p.ws, { t: "lobby", code: this.code, kind: this.kind.name, you: i, players: names, phase: this.phase }); });
    if (this.phase === "playing" || this.phase === "over") {
      this.slots.forEach((p, i) => { if (p && p.ws && this.game) this.send(p.ws, snapshot(this.game, this.kind)); });
    }
    if (this.phase === "lobby" && this.slots[0] && this.slots[1] && this.slots[0].ws && this.slots[1].ws) {
      this.phase = "countdown";
      this.broadcast({ t: "countdown", ms: this.countdownMs, players: names });
      this.game = this.kind.create(crypto.getRandomValues(new Uint32Array(1))[0]);
      setTimeout(() => this.start(), this.countdownMs);
    }
  }

  start() {
    if (this.phase !== "countdown") return;
    this.phase = "playing";
    this.broadcast(snapshot(this.game, this.kind));
    this.timer = setInterval(() => this.tick(), this.tickMs);
    this.hardStop = setTimeout(() => this.finish("timeout"), 5 * 60 * 1000);
  }

  tick() {
    this.kind.step(this.game, this.dtMs);
    this.broadcast(snapshot(this.game, this.kind));
    if (this.game.over) this.finish(this.game.reason);
  }

  onLeave(index, ws) {
    const p = this.slots[index];
    if (!p || p.ws !== ws) return; // il a déjà été remplacé par une nouvelle connexion
    p.ws = null;
    if (this.phase === "lobby") { this.slots[index] = null; return; }
    if (this.phase === "over") {
      // revanche impossible si l'autre est parti
      this.again[index] = false;
      this.broadcast({ t: "left", index });
      if (!this.slots.some((q) => q && q.ws)) { clearTimeout(this.closeTimer); this.slots = [null, null]; }
      return;
    }
    if (this.phase === "playing" || this.phase === "countdown") {
      // 10 secondes pour revenir, sinon l'autre gagne
      this.graceTimers[index] = setTimeout(() => {
        if (this.phase === "over" || (this.slots[index] && this.slots[index].ws)) return;
        if (this.game && !this.game.over) {
          if (this.kind.coop) {
            // en coopération : l'autre continue ; la salle se ferme si plus personne n'est là
            if (this.game.ships) this.game.ships[index].lives = 0;
            if (!this.slots.some((q) => q && q.ws)) this.finish("left");
            return;
          }
          this.game.over = true;
          this.game.winner = 1 - index;
          this.game.reason = "left";
          this.broadcast(snapshot(this.game, this.kind));
        }
        this.finish("left");
      }, this.graceMs);
    }
  }

  finish(reason) {
    if (this.phase === "over") return;
    this.phase = "over";
    clearInterval(this.timer);
    clearTimeout(this.hardStop);
    if (this.game && !this.game.over) { this.game.over = true; this.game.winner = "draw"; this.game.reason = reason; }
    if (this.game) this.broadcast(snapshot(this.game, this.kind));
    this.again = [false, false];
    // les joueurs restent connectés un moment pour pouvoir rejouer
    clearTimeout(this.closeTimer);
    this.closeTimer = setTimeout(() => this.slots.forEach((p) => { if (p && p.ws) { try { p.ws.close(1000, "end"); } catch (e) { /* ignore */ } } }), this.endCloseMs);
  }

  // Un joueur demande à rejouer. Quand les deux sont d'accord, une nouvelle partie démarre.
  onAgain(index) {
    if (this.phase !== "over") return;
    if (!this.slots[0] || !this.slots[1] || !this.slots[0].ws || !this.slots[1].ws) return;
    this.again[index] = true;
    this.broadcast({ t: "rematch", wants: this.again });
    if (this.again[0] && this.again[1]) {
      clearTimeout(this.closeTimer);
      this.again = [false, false];
      this.phase = "countdown";
      const names = this.slots.map((p) => (p ? p.pseudo : null));
      this.broadcast({ t: "countdown", ms: this.countdownMs, players: names });
      this.game = this.kind.create(crypto.getRandomValues(new Uint32Array(1))[0]);
      setTimeout(() => this.start(), this.countdownMs);
    }
  }
}
