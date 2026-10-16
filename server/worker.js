// Serveur de jeu BOYGAMES (Cloudflare Workers + Durable Objects).
// Une "salle" par code (ex. K7P2Q). Le serveur décide de tout : les téléphones n'envoient que des directions.
// Aucun secret ici : la connexion est vérifiée avec la clé PUBLIQUE de Supabase (JWKS).

import * as SN from "./arena-engine.js";
import * as SPC from "./space-engine.js";
import * as BK from "./blocks-engine.js";
import * as BBD from "./boyblocks-duel.js";
import * as BOT from "./boybot.js";

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
  // grille 9x9 d'essai : mêmes règles, salle à part
  Y: { name: "boyblocks", tickMs: BBD.TICK_MS, coop: false, instant: true,
       create: (seed) => BBD.newGame(seed, 9), input: (g, i, m) => BBD.input(g, i, m),
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
    const m = url.pathname.match(/^\/play\/([SPBXY][A-Z0-9]{3,7})$/);
    if (!m) return new Response("BOYGAMES arena server v6 (BOYBOT)", { status: 200 });
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
    this.bot = null; // { index, level, brain } quand BOYBOT occupe la 2e place
    this.resumeMs = env.RESUME_MS !== undefined ? Number(env.RESUME_MS) : 3000;
  }

  // Un joueur est « là » s'il a une connexion ouverte, ou si c'est BOYBOT.
  present(p) { return !!(p && (p.ws || p.bot)); }
  names() { return this.slots.map((p) => (p ? p.pseudo : null)); }
  bots() { return this.slots.map((p) => !!(p && p.bot)); }

  // BOYBOT prend la place libre : seulement dans une salle neuve, à la demande du premier joueur.
  addBot(level) {
    if (this.phase !== "lobby" || this.slots[1] || !BOT.LEVELS.includes(level)) return false;
    this.slots[1] = { uid: BOT.BOT_UID, pseudo: BOT.BOT_NAME, ws: null, bot: true };
    this.bot = { index: 1, level, brain: null };
    return true;
  }
  newBrain() {
    if (this.bot) this.bot.brain = BOT.makeBot(this.kind.name, this.bot.level, crypto.getRandomValues(new Uint32Array(1))[0]);
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
          if (idx === 0 && msg.bot !== undefined && !this.addBot(String(msg.bot))) {
            if (!(this.bot && this.slots[1] && this.slots[1].bot)) { this.slots[0] = null; this.send(ws, { t: "error", code: "bot" }); try { ws.close(4005, "bot"); } catch (e) { /* ignore */ } return; }
          }
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
      if (msg.t === "pause") { this.pause(); return; }
      if (msg.t === "resume") { this.resume(); return; }
      if (msg.t === "sync" && this.game && this.kind.syncLog && (this.phase === "playing" || this.phase === "over")) { this.send(ws, this.kind.syncLog(this.game, me.index)); return; }
      if ((this.phase === "playing" || (this.phase === "resuming" && !this.kind.instant)) && this.game) {
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
    const names = this.names(), bots = this.bots();
    this.slots.forEach((p, i) => { if (p && p.ws) this.send(p.ws, { t: "lobby", code: this.code, kind: this.kind.name, you: i, players: names, bots, phase: this.phase }); });
    if (this.phase === "playing" || this.phase === "over" || this.phase === "paused" || this.phase === "resuming") {
      this.slots.forEach((p, i) => { if (p && p.ws && this.game) this.send(p.ws, snapshot(this.game, this.kind)); });
      if (this.phase === "paused") this.broadcast({ t: "paused" });
    }
    if (this.phase === "lobby" && this.present(this.slots[0]) && this.present(this.slots[1]) && this.slots.some((p) => p && p.ws)) {
      this.phase = "countdown";
      this.broadcast({ t: "countdown", ms: this.countdownMs, players: names, bots });
      this.game = this.kind.create(crypto.getRandomValues(new Uint32Array(1))[0]);
      this.newBrain();
      setTimeout(() => this.start(), this.countdownMs);
    }
  }

  start() {
    if (this.phase !== "countdown") return;
    this.phase = "playing";
    this.broadcast(snapshot(this.game, this.kind));
    this.timer = setInterval(() => this.tick(), this.tickMs);
    this.stopLeft = 5 * 60 * 1000;
    this.armStop();
  }
  armStop() { this.stopAt = Date.now(); clearTimeout(this.hardStop); this.hardStop = setTimeout(() => this.finish("timeout"), this.stopLeft); }

  // Pause : seulement dans une salle avec BOYBOT (entre deux humains, rien ne change).
  // Tout s'arrête d'un coup (les deux serpents, BOYBOT, le temps de jeu) : aucun tour ne passe pendant la pause.
  pause() {
    if (!this.bot || this.phase !== "playing" || !this.game || this.game.over) return;
    this.phase = "paused";
    clearInterval(this.timer); this.timer = null;
    clearTimeout(this.hardStop); this.stopLeft = Math.max(1000, this.stopLeft - (Date.now() - this.stopAt));
    this.broadcast({ t: "paused" });
  }
  // Reprise après 3 secondes de compte à rebours (le jeu reprend exactement où il s'était arrêté).
  resume() {
    if (!this.bot || this.phase !== "paused") return;
    this.phase = "resuming";
    this.broadcast({ t: "resume", ms: this.resumeMs });
    clearTimeout(this.resumeTimer);
    this.resumeTimer = setTimeout(() => {
      if (this.phase !== "resuming") return;
      this.phase = "playing";
      this.broadcast(snapshot(this.game, this.kind));
      this.timer = setInterval(() => this.tick(), this.tickMs);
      this.armStop();
    }, this.resumeMs);
  }

  tick() {
    if (this.bot && this.bot.brain && !this.game.over) {
      for (const m of this.bot.brain.act(this.game, this.bot.index, this.dtMs)) this.kind.input(this.game, this.bot.index, m);
    }
    this.kind.step(this.game, this.dtMs);
    this.broadcast(snapshot(this.game, this.kind));
    if (this.game.over) this.finish(this.game.reason);
  }

  onLeave(index, ws) {
    const p = this.slots[index];
    if (!p || p.ws !== ws) return; // il a déjà été remplacé par une nouvelle connexion
    p.ws = null;
    if (this.phase === "lobby") { this.slots[index] = null; if (this.bot && !this.slots.some((q) => q && q.ws)) { this.slots = [null, null]; this.bot = null; } return; }
    if (this.phase === "over") {
      // revanche impossible si l'autre est parti
      this.again[index] = false;
      this.broadcast({ t: "left", index });
      if (!this.slots.some((q) => q && q.ws)) { clearTimeout(this.closeTimer); this.slots = [null, null]; this.bot = null; }
      return;
    }
    if (this.phase === "playing" || this.phase === "countdown" || this.phase === "paused" || this.phase === "resuming") {
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
    clearTimeout(this.resumeTimer);
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
    if (!this.present(this.slots[0]) || !this.present(this.slots[1])) return;
    this.again[index] = true;
    if (this.bot) this.again[this.bot.index] = true;
    this.broadcast({ t: "rematch", wants: this.again });
    if (this.again[0] && this.again[1]) {
      clearTimeout(this.closeTimer);
      this.again = [false, false];
      this.phase = "countdown";
      this.broadcast({ t: "countdown", ms: this.countdownMs, players: this.names(), bots: this.bots() });
      this.game = this.kind.create(crypto.getRandomValues(new Uint32Array(1))[0]);
      this.newBrain();
      setTimeout(() => this.start(), this.countdownMs);
    }
  }
}
