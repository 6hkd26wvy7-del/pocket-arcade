#!/usr/bin/env python3
"""Generate guide.html (phone-friendly setup page with copy buttons) from schema.sql."""
import html
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(ROOT, "schema.sql"), encoding="utf-8") as f:
    sql = html.escape(f.read())

EMAIL_SUBJECT = "Ton code Pocket Arcade"
EMAIL_BODY = (
    "<h2>Ton code Pocket Arcade</h2>\n"
    "<p>Entre ce code dans le jeu :</p>\n"
    '<p style="font-size:28px;letter-spacing:4px"><strong>{{ .Token }}</strong></p>\n'
    "<p>Si tu n'as rien demandé, ignore ce message.</p>\n"
)

TEMPLATE = r"""<title>Installation Pocket Arcade</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
/* Layout: one narrow column of numbered setup steps, each with its own copy button. Utilitarian, tinted toward the game's LCD green. */
:root {
  --bg: #f1f4e6;
  --fg: #16240f;
  --muted: #4d5e42;
  --accent: #306230;
  --accent-fg: #f1f4e6;
  --card: #e4ead2;
  --line: #c3cfa9;
  --code-bg: #16240f;
  --code-fg: #cfe39a;
  --warn: #7a1f1f;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #111a0c; --fg: #e3ecd0; --muted: #a2b38d; --accent: #9bbc0f; --accent-fg: #0f1a08;
    --card: #1b2714; --line: #34472a; --code-bg: #0a1006; --code-fg: #cfe39a; --warn: #f0a0a0;
    color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --bg: #111a0c; --fg: #e3ecd0; --muted: #a2b38d; --accent: #9bbc0f; --accent-fg: #0f1a08;
  --card: #1b2714; --line: #34472a; --code-bg: #0a1006; --code-fg: #cfe39a; --warn: #f0a0a0;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  background: var(--bg);
  color: var(--fg);
  font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  padding-block: 20px 40px;
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
}
main { max-width: 640px; margin: 0 auto; }
h1 { font-size: 26px; line-height: 1.2; margin: 0 0 8px; text-wrap: balance; }
.lead { color: var(--muted); margin: 0 0 24px; }
ol.steps { list-style: none; counter-reset: step; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 14px; }
ol.steps > li {
  counter-increment: step;
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 16px;
  min-width: 0;
}
ol.steps > li > h2 {
  font-size: 17px;
  margin: 0 0 8px;
  display: flex;
  gap: 10px;
  align-items: baseline;
}
ol.steps > li > h2::before {
  content: counter(step);
  flex: none;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  background: var(--accent);
  color: var(--accent-fg);
  font-size: 14px;
  display: inline-grid;
  place-items: center;
  transform: translateY(-1px);
}
p { margin: 0 0 10px; }
ul { margin: 0 0 10px; padding-left: 20px; }
li li, ul li { margin-bottom: 4px; }
.btn {
  font: inherit;
  font-weight: 600;
  background: var(--accent);
  color: var(--accent-fg);
  border: 0;
  border-radius: 8px;
  padding: 12px 16px;
  min-height: 44px;
  cursor: pointer;
}
.btn:focus-visible, summary:focus-visible, a:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
details { margin-top: 10px; }
summary { cursor: pointer; color: var(--muted); }
pre {
  margin: 8px 0 0;
  background: var(--code-bg);
  color: var(--code-fg);
  border-radius: 8px;
  padding: 12px;
  max-height: 260px;
  overflow: auto;
  font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  white-space: pre;
}
.note { color: var(--muted); font-size: 14px; }
.warn { color: var(--warn); font-weight: 600; }
code.inline { font: 14px ui-monospace, Menlo, Consolas, monospace; background: var(--bg); padding: 1px 5px; border-radius: 4px; }
a { color: var(--accent); }
.fieldlabel { font-size: 13px; color: var(--muted); margin: 12px 0 4px; }
</style>

<main>
  <h1>Installation depuis ton téléphone</h1>
  <p class="lead">Sept étapes, faisables entièrement dans le navigateur de ton téléphone. Les noms des menus chez Supabase et GitHub peuvent légèrement changer.</p>

  <ol class="steps">
    <li>
      <h2>Crée tes deux comptes</h2>
      <p>Commence par un compte gratuit sur <strong>github.com</strong>. Ensuite, sur <strong>supabase.com</strong>, connecte-toi avec ce compte GitHub : tu n'as qu'un seul identifiant à retenir.</p>
    </li>
    <li>
      <h2>Crée le projet Supabase</h2>
      <p>Dans Supabase, touche <strong>New project</strong>. Nom : <code class="inline">pocket-arcade</code>. Région : en Europe. Choisis un mot de passe de base de données et note-le quelque part de sûr. Attends que le projet soit prêt.</p>
    </li>
    <li>
      <h2>Installe la base de données</h2>
      <p>Touche le bouton, puis dans Supabase ouvre <strong>SQL Editor</strong>, <strong>New query</strong>, colle le code et touche <strong>Run</strong>. Tu dois voir « Success ».</p>
      <button class="btn" type="button" data-copy="sql" data-label="Copier le code SQL">Copier le code SQL</button>
      <details>
        <summary>Voir le code</summary>
        <pre id="sql">%%SQL%%</pre>
      </details>
    </li>
    <li>
      <h2>Désactive la confirmation par e-mail</h2>
      <p>Dans Supabase, ouvre <strong>Authentication</strong>, puis <strong>Sign In / Providers</strong>, puis <strong>Email</strong>. Désactive l'option <strong>Confirm email</strong> et enregistre (<strong>Save</strong>). Ainsi, chacun peut créer son compte avec une adresse e-mail et un mot de passe, sans recevoir d'e-mail.</p>
      <p class="note">Un mot de passe oublié ne peut pas être retrouvé. Plus tard, avec un nom de domaine, tu pourras ajouter la récupération par e-mail.</p>
    </li>
    <li>
      <h2>Envoie-moi les deux clés publiques</h2>
      <p>Dans Supabase : <strong>Project Settings</strong>, puis <strong>API</strong>. Copie le <strong>Project URL</strong> et la clé <strong>anon public</strong>, et colle-les dans la conversation avec Claude. Je prépare tes trois fichiers.</p>
      <p class="warn">N'envoie jamais le mot de passe de la base ni la clé « service_role ».</p>
    </li>
    <li>
      <h2>Mets le site en ligne avec GitHub</h2>
      <p>Sur GitHub, crée un dépôt <strong>public</strong> nommé <code class="inline">pocket-arcade</code>. Touche <strong>Add file</strong>, puis <strong>Upload files</strong>, et choisis les trois fichiers que je t'envoie : <code class="inline">index.html</code>, <code class="inline">config.js</code>, <code class="inline">privacy.html</code>. Touche <strong>Commit changes</strong>.</p>
      <p>Ensuite : <strong>Settings</strong>, <strong>Pages</strong>, source <strong>Deploy from a branch</strong>, branche <strong>main</strong>, dossier <strong>/ (root)</strong>, <strong>Save</strong>. Au bout d'une ou deux minutes, GitHub affiche l'adresse de ton site.</p>
    </li>
    <li>
      <h2>Dis à Supabase où est ton site</h2>
      <p>Dans Supabase : <strong>Authentication</strong>, <strong>URL Configuration</strong>. Colle l'adresse de ton site dans <strong>Site URL</strong> et enregistre.</p>
      <p class="note">Ton site est prêt : ouvre l'adresse, crée un compte, joue une partie, et vérifie qu'elle apparaît dans le classement.</p>
    </li>
  </ol>
</main>

<script>
(function () {
  function flash(btn, text) {
    btn.textContent = text;
    setTimeout(function () { btn.textContent = btn.getAttribute("data-label"); }, 2200);
  }
  function selectText(el) {
    var d = el.closest("details");
    if (d) d.open = true;
    var r = document.createRange();
    r.selectNodeContents(el);
    var s = window.getSelection();
    s.removeAllRanges();
    s.addRange(r);
  }
  document.querySelectorAll("[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var el = document.getElementById(btn.getAttribute("data-copy"));
      var text = el.textContent;
      function fallback() {
        selectText(el);
        flash(btn, "Texte sélectionné : touche Copier");
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { flash(btn, "Copié"); }, fallback);
      } else {
        fallback();
      }
    });
  });
})();
</script>
"""

out = (
    TEMPLATE.replace("%%SQL%%", sql)
    .replace("%%SUBJECT%%", html.escape(EMAIL_SUBJECT))
    .replace("%%BODY%%", html.escape(EMAIL_BODY))
)
with open(os.path.join(ROOT, "guide", "guide.html"), "w", encoding="utf-8") as f:
    f.write(out)
print("guide.html written", len(out), "bytes")
