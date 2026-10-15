// Prototype BOYGAMES : emblèmes de badges à 6 paliers. Chaque palier change la FORME, les ORNEMENTS, le RELIEF et les EFFETS.
(function (root) {
  var TIERS = [
    { n: "Recrue",   c1: "#E9A26B", c2: "#8A4B22", glow: 0 },
    { n: "Argent",   c1: "#E6EDF7", c2: "#7C8BA3", glow: 0 },
    { n: "Or",       c1: "#FFE08A", c2: "#C98A0B", glow: 1 },
    { n: "Platine",  c1: "#A8F3FF", c2: "#2B8FB3", glow: 2 },
    { n: "Diamant",  c1: "#E9C2FF", c2: "#7A35E0", glow: 3 },
    { n: "Légende",  c1: "#FFFFFF", c2: "#FF3D9A", glow: 4 }
  ];
  var GLYPH = {
    snake: '<path d="M-14 8 C-14 -2 -2 2 -2 -6 C-2 -14 12 -12 12 -4 C12 2 6 3 6 -1" fill="none" stroke="#0B1226" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/><path d="M-14 8 C-14 -2 -2 2 -2 -6 C-2 -14 12 -12 12 -4 C12 2 6 3 6 -1" fill="none" stroke="url(#g_ink)" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/><circle cx="6" cy="-1" r="2" fill="#FF3D9A"/>',
    space: '<path d="M0 -17 L9 9 L0 4 L-9 9 Z" fill="#0B1226"/><path d="M0 -14 L6.5 6 L0 2.5 L-6.5 6 Z" fill="url(#g_ink)"/><path d="M-9 9 L-16 14 L-6 11 Z M9 9 L16 14 L6 11 Z" fill="#0B1226"/><circle cx="0" cy="-3" r="2.4" fill="#0B1226"/><path d="M-3 12 L0 19 L3 12 Z" fill="#FF8A3D"/>',
    boyblocks: '<g stroke="#0B1226" stroke-width="1.4" stroke-linejoin="round"><rect x="-14" y="-14" width="10" height="10" rx="2" fill="url(#g_ink)"/><rect x="-3" y="-14" width="10" height="10" rx="2" fill="url(#g_ink)"/><rect x="-14" y="-3" width="10" height="10" rx="2" fill="url(#g_ink)"/><rect x="8" y="-3" width="10" height="10" rx="2" fill="#FF3D9A"/><rect x="-3" y="8" width="10" height="10" rx="2" fill="url(#g_ink)"/></g>',
    blocks: '<g stroke="#0B1226" stroke-width="1.4" stroke-linejoin="round"><rect x="-5" y="-17" width="10" height="10" rx="2" fill="url(#g_ink)"/><rect x="-5" y="-6" width="10" height="10" rx="2" fill="url(#g_ink)"/><rect x="-5" y="5" width="10" height="10" rx="2" fill="url(#g_ink)"/><rect x="6" y="5" width="10" height="10" rx="2" fill="#FF3D9A"/></g>'
  };
  function star(cx, cy, r, fill) { var p = []; for (var i = 0; i < 10; i++) { var a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? r * 0.45 : r; p.push((cx + rr * Math.cos(a)).toFixed(1) + "," + (cy + rr * Math.sin(a)).toFixed(1)); } return '<polygon points="' + p.join(" ") + '" fill="' + fill + '"/>'; }
  function body(t) {
    // t = 0..5 : cercle -> hexagone -> écu -> écu ailé -> blason couronné -> médaillon étoilé
    var s = "";
    if (t === 0) s = '<circle r="30" fill="url(#g_body)" stroke="url(#g_rim)" stroke-width="4"/><circle r="23" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1.5"/>';
    if (t === 1) s = '<path d="M0 -33 L29 -16 L29 16 L0 33 L-29 16 L-29 -16 Z" fill="url(#g_body)" stroke="url(#g_rim)" stroke-width="4" stroke-linejoin="round"/><path d="M0 -25 L22 -12 L22 12 L0 25 L-22 12 L-22 -12 Z" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1.5"/>';
    if (t === 2) s = '<path d="M-28 -26 L28 -26 L28 6 C28 22 12 30 0 36 C-12 30 -28 22 -28 6 Z" fill="url(#g_body)" stroke="url(#g_rim)" stroke-width="4" stroke-linejoin="round"/><path d="M-21 -19 L21 -19 L21 5 C21 17 9 23 0 28 C-9 23 -21 17 -21 5 Z" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1.5"/>';
    if (t === 3) s = wings() + '<path d="M-26 -24 L26 -24 L26 6 C26 21 11 28 0 34 C-11 28 -26 21 -26 6 Z" fill="url(#g_body)" stroke="url(#g_rim)" stroke-width="4" stroke-linejoin="round"/><path d="M-19 -17 L19 -17 L19 5 C19 15 9 21 0 25 C-9 21 -19 15 -19 5 Z" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1.5"/>';
    if (t === 4) s = wings() + crown() + '<path d="M-26 -22 L26 -22 L30 8 C28 22 11 29 0 36 C-11 29 -28 22 -30 8 Z" fill="url(#g_body)" stroke="url(#g_rim)" stroke-width="4" stroke-linejoin="round"/><path d="M-19 -15 L19 -15 L22 7 C20 16 9 22 0 27 C-9 22 -20 16 -22 7 Z" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1.5"/><circle cx="-24" cy="2" r="3" fill="#FFF" opacity=".9"/><circle cx="24" cy="2" r="3" fill="#FFF" opacity=".9"/>';
    if (t === 5) s = rays() + wings(1) + crown(1) + '<path d="M0 -36 L11 -26 L26 -28 L28 -12 L38 0 L28 12 L26 28 L11 26 L0 36 L-11 26 L-26 28 L-28 12 L-38 0 L-28 -12 L-26 -28 L-11 -26 Z" fill="url(#g_body)" stroke="url(#g_rim)" stroke-width="4" stroke-linejoin="round"/><circle r="25" fill="none" stroke="rgba(0,0,0,.28)" stroke-width="1.6"/>';
    return s;
  }
  function wings(big) { var k = big ? 1.25 : 1; return '<g fill="url(#g_rim)" opacity=".95" transform="scale(' + k + ')"><path d="M-27 -10 L-44 -22 L-40 -6 L-48 0 L-38 4 L-40 14 L-27 8 Z"/><path d="M27 -10 L44 -22 L40 -6 L48 0 L38 4 L40 14 L27 8 Z"/></g>'; }
  function crown(big) { var y = big ? -38 : -26; return '<g transform="translate(0,' + y + ')"><path d="M-12 4 L-14 -8 L-6 -2 L0 -12 L6 -2 L14 -8 L12 4 Z" fill="url(#g_rim)" stroke="#0B1226" stroke-width="1.2"/><circle cx="0" cy="-12" r="2.4" fill="#FF3D9A"/></g>'; }
  function rays() { var s = '<g opacity=".55" stroke="url(#g_rim)" stroke-width="2.4" stroke-linecap="round">'; for (var i = 0; i < 16; i++) { var a = i * Math.PI / 8; s += '<line x1="' + (44 * Math.cos(a)).toFixed(1) + '" y1="' + (44 * Math.sin(a)).toFixed(1) + '" x2="' + (52 * Math.cos(a)).toFixed(1) + '" y2="' + (52 * Math.sin(a)).toFixed(1) + '"/>'; } return s + '</g>'; }
  function badge(game, tier, size, uid) {
    var out = badge0(game, tier, size, uid), k = "u" + (uid || Math.random().toString(36).slice(2, 7)) + "_";
    return out.replace(/g_(body|rim|ink)/g, k + "$1");
  }
  function badge0(game, tier, size, uid) {
    var T = TIERS[tier], id = "b" + (uid || Math.random().toString(36).slice(2, 7));
    var glow = T.glow ? '<filter id="' + id + 'f" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="' + (2 + T.glow * 1.6) + '" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>' : "";
    var legend = tier === 5;
    var bodyFill = legend ? '<linearGradient id="g_body" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22D3EE"/><stop offset=".5" stop-color="#7C3AED"/><stop offset="1" stop-color="#FF3D9A"/></linearGradient>' :
      '<linearGradient id="g_body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + T.c1 + '"/><stop offset="1" stop-color="' + T.c2 + '"/></linearGradient>';
    var rim = '<linearGradient id="g_rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + (legend ? "#FFF6B0" : T.c1) + '"/><stop offset="1" stop-color="' + (legend ? "#FF9A3D" : T.c2) + '"/></linearGradient>';
    var ink = '<linearGradient id="g_ink" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#C7D2FE"/></linearGradient>';
    var shine = '<path d="M-20 -18 Q0 -34 20 -18" fill="none" stroke="#fff" stroke-opacity="' + (0.25 + T.glow * 0.08) + '" stroke-width="3" stroke-linecap="round"/>';
    var gems = tier >= 4 ? star(0, 31, 4.6, "#FFF") : "";
    var pips = ""; for (var i = 0; i <= tier; i++) pips += '<circle cx="' + ((i - tier / 2) * 8).toFixed(1) + '" cy="46" r="2.3" fill="' + T.c1 + '" stroke="#0B1226" stroke-width=".8"/>';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-56 -56 112 112" width="' + size + '" height="' + size + '" role="img" aria-label="Badge ' + game + " " + T.n + '"><defs>' + bodyFill + rim + ink + glow + '</defs>' +
      '<g' + (T.glow ? ' filter="url(#' + id + 'f)"' : "") + '>' + body(tier) + '</g>' +
      '<g transform="translate(0,-1)">' + (GLYPH[game] || GLYPH.snake) + '</g>' + shine + gems + pips + '</svg>';
  }
  root.BG_BADGES = { TIERS: TIERS, badge: badge };
})(typeof window !== "undefined" ? window : globalThis);
