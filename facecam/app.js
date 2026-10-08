/* ==========================================================================
   Habillage "chaîne d'info" — logique.

   L'HORLOGE MAÎTRE est la piste de narration (<audio id="voice">) : les
   scènes (cartes, panneau latéral, titre) changent selon voice.currentTime,
   et l'anneau autour de l'avatar réagit au volume réel de cette même piste
   (Web Audio). Ainsi image, cartes et voix restent synchronisées par
   construction, sans dérive possible, même sur plusieurs heures.

   Paramètres d'URL :
     ?audio=narration.ogg   piste de narration (absent = mode démo, horloge virtuelle)
     ?content=content.json  scènes + fil d'info (repli : demo_content.js)
     ?avatar=avatar_loop.webm
     ?t=42                  fige l'horloge à 42 s (captures d'écran, sans animation)
   ========================================================================== */
(() => {
'use strict';
const $ = s => document.querySelector(s);
const Q = new URLSearchParams(location.search);
const P = {
  content: Q.get('content') || 'content.json',
  audio: Q.get('audio') || '',
  avatar: Q.get('avatar') || 'avatar_loop.webm',
  freeze: Q.has('t') ? parseFloat(Q.get('t')) : null,
};
const STATIC = P.freeze !== null;
if (STATIC) document.body.classList.add('static');

const CATS = {
  JUSTICE:   { c:'#ffb400', i:'scale'  },
  CYBER:     { c:'#35c8ff', i:'shield' },
  POLICE:    { c:'#ff5a4d', i:'siren'  },
  CRIME:     { c:'#ff5a4d', i:'siren'  },
  POLITIQUE: { c:'#b794f6', i:'globe'  },
  MONDE:     { c:'#4ade80', i:'globe'  },
  ECONOMIE:  { c:'#4ade80', i:'coin'   },
  DEFAULT:   { c:'#ffb400', i:'doc'    },
};

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const el = html => { const d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstElementChild; };
const icon = n => `<svg viewBox="0 0 64 64"><use href="#i-${n}"/></svg>`;
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const root = $('#root'), stage = $('#stage'), side = $('#side'), voice = $('#voice');

/* ---- mise à l'échelle (toile fixe 1920x1080) ---- */
function rescale() {
  const s = Math.min(innerWidth / 1920, innerHeight / 1080);
  root.style.transform = `scale(${s})`;
  root.style.left = ((innerWidth - 1920 * s) / 2) + 'px';
  root.style.top = ((innerHeight - 1080 * s) / 2) + 'px';
}
addEventListener('resize', rescale); rescale();

/* ---- ajustement automatique du texte (jamais de débordement) ---- */
function shrink(node, fits, start, min, step = 2) {
  let s = start; node.style.fontSize = s + 'px';
  while (!fits() && s > min) { s -= step; node.style.fontSize = s + 'px'; }
}

/* ======================= Cartes de la zone principale ======================= */
const AVAIL_H = 606;   // hauteur utile d'une carte (716 - marges)
const AVAIL_W = 1132;  // largeur utile

const STAGE = {
  headline(d, cat) {
    const c = el(`<div class="card c-headline enter">
      <div class="c-icon st" style="--i:0">${icon(d.icon || cat.i)}</div>
      <div class="c-body">
        <div class="kicker st" style="--i:1">${esc(d.kicker)}</div>
        <h1 class="st" style="--i:2">${esc(d.title)}</h1>
        <ul class="lines">${(d.lines || []).map((l, i) => `<li class="st" style="--i:${3 + i}">${esc(l)}</li>`).join('')}</ul>
      </div></div>`);
    return { node: c, fit() {
      const body = c.querySelector('.c-body'), h1 = c.querySelector('h1');
      shrink(h1, () => body.offsetHeight <= AVAIL_H - 6, 82, 44);
    }};
  },
  stat(d) {
    const c = el(`<div class="card c-stat enter">
      <div class="kicker st" style="--i:0">${esc(d.kicker)}</div>
      <div class="bignum st" style="--i:1"><span class="v">${esc(d.value)}</span><span class="u">${esc(d.unit)}</span></div>
      <div class="cap st" style="--i:2">${esc(d.caption)}</div>
      ${d.sub ? `<div class="sub st" style="--i:3">${esc(d.sub)}</div>` : ''}</div>`);
    return { node: c, fit() {
      const v = c.querySelector('.v'), u = c.querySelector('.u');
      shrink(v, () => v.offsetWidth + u.offsetWidth + 28 <= AVAIL_W, 300, 120, 10);
    }};
  },
  list(d) {
    const rows = (d.rows || []).slice(0, 7);
    const c = el(`<div class="card c-list enter">
      <div class="kicker st" style="--i:0">${esc(d.kicker)}</div>
      <h2 class="st" style="--i:1">${esc(d.title)}</h2>
      <div class="rows">${rows.map((r, i) => `<div class="row st" style="--i:${2 + i}">
        <span class="tag">${esc(r.tag)}</span><span class="txt">${esc(r.text)}</span>${r.status ? `<span class="chip">${esc(r.status)}</span>` : '<span></span>'}</div>`).join('')}</div></div>`);
    return { node: c, fit() {
      // Hauteur naturelle (le texte peut passer sur 2 lignes, jamais
      // tronqué avec "...") — seule la POLICE est réduite si la liste
      // ne tient pas dans le cadre, jamais le contenu caché.
      let size = 32, guard = 0;
      while (c.scrollHeight > c.clientHeight + 1 && size > 20 && guard++ < 12) {
        size -= 2;
        c.querySelectorAll('.row .tag, .row .txt').forEach(t => t.style.fontSize = size + 'px');
        c.querySelectorAll('.row').forEach(r => r.style.padding = Math.max(6, 14 - guard) + 'px 24px');
      }
    }};
  },
  quote(d) {
    const c = el(`<div class="card c-quote enter">
      <div class="qmark st" style="--i:0">“</div>
      <blockquote class="st" style="--i:1">${esc(d.text)}</blockquote>
      ${d.by ? `<div class="by st" style="--i:2">${esc(d.by)}</div>` : ''}</div>`);
    return { node: c, fit() {
      const bq = c.querySelector('blockquote');
      shrink(bq, () => bq.offsetHeight <= 340, 70, 40);
    }};
  },
  timeline(d) {
    const items = (d.items || []).slice(0, 5);
    const c = el(`<div class="card c-timeline enter">
      <div class="kicker st" style="--i:0">${esc(d.kicker)}</div>
      <h2 class="st" style="--i:1">${esc(d.title)}</h2>
      <div class="tl">${items.map((it, i) => `<div class="it st" style="--i:${2 + i}"><span class="d">${esc(it.date)}</span><span class="t">${esc(it.text)}</span></div>`).join('')}</div></div>`);
    return { node: c, fit() {
      const n = Math.max(items.length, 1), avail = AVAIL_H - 40 - 100;
      const h = Math.min(88, Math.floor((avail - (n - 1) * 18) / n));
      c.querySelectorAll('.it').forEach(r => r.style.minHeight = h + 'px');
    }};
  },
  versus(d) {
    const s = (x, cls) => `<div class="${cls} st"><div class="lab">${esc(x.label)}</div><div class="val">${esc(x.value)}</div><div class="cap">${esc(x.caption)}</div></div>`;
    const c = el(`<div class="card c-versus enter">
      <div class="kicker st" style="--i:0">${esc(d.kicker)}</div>
      <div class="vs">${s(d.left || {}, 'side-a')}<div class="mid st">VS</div>${s(d.right || {}, 'side-b')}</div></div>`);
    return { node: c, fit() {
      c.querySelectorAll('.val').forEach(v => shrink(v, () => v.scrollWidth <= 500, 130, 60, 6));
    }};
  },
};

/* ======================= Panneau latéral ======================= */
const SIDE = {
  facts(d) {
    const c = el(`<div class="sidecard enter"><h3>${esc(d.title)}</h3>
      <ul class="facts">${(d.items || []).map(t => `<li>${esc(t)}</li>`).join('')}</ul></div>`);
    return { node: c, fit() {
      const ul = c.querySelector('.facts');
      shrink(ul, () => c.scrollHeight <= c.clientHeight + 1, 26, 19);
    }};
  },
  keyfigures(d) {
    const c = el(`<div class="sidecard enter">${d.title ? `<h3>${esc(d.title)}</h3>` : ''}
      <div class="kf">${(d.items || []).slice(0, 3).map(r => `<div class="r"><span class="v">${esc(r.value)}</span><span class="l">${esc(r.label)}</span></div>`).join('')}</div></div>`);
    return { node: c, fit() {
      c.querySelectorAll('.v').forEach(v => shrink(v, () => v.scrollWidth <= 200, 56, 34, 3));
      // Hauteur totale (titre + lignes) : réduit d'abord la taille des
      // valeurs, puis le padding des lignes, jusqu'à tenir dans le cadre —
      // même filet de sécurité que les autres cartes du panneau latéral.
      const kf = c.querySelector('.kf'), rows = c.querySelectorAll('.r');
      let vSize = 56, pad = 6, guard = 0;
      while (c.scrollHeight > c.clientHeight + 1 && guard++ < 20) {
        if (vSize > 30) { vSize -= 3; rows.forEach(r => r.querySelector('.v').style.fontSize = vSize + 'px'); }
        else if (pad > 0) { pad -= 1; rows.forEach(r => r.style.padding = pad + 'px 0'); }
        else break;
      }
    }};
  },
  tags(d) {
    const c = el(`<div class="sidecard enter"><h3>${esc(d.title)}</h3>
      <div class="chips">${(d.items || []).map(t => `<span>${esc(t)}</span>`).join('')}</div></div>`);
    return { node: c, fit() {
      const ch = c.querySelector('.chips');
      shrink(ch, () => c.scrollHeight <= c.clientHeight + 1, 22, 15);
    }};
  },
};

/* ======================= Scènes ======================= */
let content = null, scenes = [], cur = -1;

function swap(container, made, anchor) {
  const old = container.querySelector(':scope > .card:not(.leave), :scope > .sidecard:not(.leave)');
  if (old) { old.classList.remove('enter'); old.classList.add('leave'); setTimeout(() => old.remove(), 450); }
  container.insertBefore(made.node, anchor || null);
  made.fit && made.fit();
}

function show(i) {
  const s = scenes[i]; cur = i;
  const cat = CATS[(s.category || '').toUpperCase()] || CATS.DEFAULT;
  const accent = s.accent || cat.c;
  root.style.setProperty('--accent', accent);

  const mk = STAGE[s.stage?.type];
  if (mk) swap(stage, mk(s.stage, cat), stage.querySelector('.prog'));

  const sk = SIDE[s.side?.type];
  side.querySelector('.hd')?.remove();
  side.insertAdjacentHTML('afterbegin', `<div class="hd"><span>${esc(s.side?.label || 'FICHE')}</span>${icon(s.side?.icon || cat.i)}</div>`);
  if (sk) swap(side, sk(s.side));

  $('#cat-chip').textContent = (s.category || '').toUpperCase();
  $('#cat-chip').style.display = s.category ? '' : 'none';
  $('#lower-cat').textContent = (s.category || 'À LA UNE').toUpperCase();
  $('#lower .lab use').setAttribute('href', '#i-' + (s.lower_icon || cat.i));
  const span = $('#lower-txt');
  span.textContent = s.lower || '';
  span.classList.remove('in'); void span.offsetWidth; span.classList.add('in');
  shrink(span, () => span.scrollWidth <= 1478, 46, 30);
}

function indexAt(t) {
  let idx = 0;
  for (let i = 0; i < scenes.length; i++) { if (scenes[i].t <= t) idx = i; else break; }
  return idx;
}

/* ======================= Fil d'information ======================= */
function buildTicker(items, speed) {
  const track = $('#track'); track.innerHTML = '';
  const half = document.createElement('div'); half.className = 'half';
  items.forEach(it => {
    const tag = typeof it === 'string' ? '' : it.tag, text = typeof it === 'string' ? it : it.text;
    half.insertAdjacentHTML('beforeend', `<span class="tk">${tag ? `<b class="tg">${esc(tag)}</b>` : ''}${esc(text)}</span><i class="dot"></i>`);
  });
  const copy = half.cloneNode(true);
  track.append(half, copy);
  const w = half.offsetWidth;
  track.style.setProperty('--dur', (w / speed) + 's');
  if (STATIC) track.style.transform = `translateX(-${(P.freeze * speed) % w}px)`;
}

/* ======================= Anneau audio-réactif ======================= */
const ring = $('#ring'), rctx = ring.getContext('2d');
let actx, analyser, abuf, ref = 0.05, level = 0, lastTs = performance.now();
const hexRgb = h => { const n = parseInt(h.replace('#', ''), 16); return `${n >> 16},${(n >> 8) & 255},${n & 255}`; };

function setupAudio() {
  if (actx) return;
  actx = new (window.AudioContext || window.webkitAudioContext)();
  const src = actx.createMediaElementSource(voice);
  analyser = actx.createAnalyser(); analyser.fftSize = 1024;
  src.connect(analyser); analyser.connect(actx.destination);
  abuf = new Uint8Array(analyser.fftSize);
}
function audioLevel() {
  analyser.getByteTimeDomainData(abuf);
  let s = 0; for (let i = 0; i < abuf.length; i++) { const x = (abuf[i] - 128) / 128; s += x * x; }
  const rms = Math.sqrt(s / abuf.length);
  ref = Math.max(ref * 0.9993, rms, 0.03);      // gain adaptatif : s'ajuste au volume de la piste
  return Math.min(1, rms / (ref * 0.85));
}
function fakeLevel(t) {                          // mode démo : simule une voix qui parle
  const env = 0.5 + 0.5 * Math.sin(t * 1.7) * Math.sin(t * 0.53 + 1);
  const talk = Math.max(0, Math.sin(t * 9.3) * 0.6 + Math.sin(t * 4.1 + 2) * 0.4);
  return clamp(talk * (env > 0.25 ? 1 : 0.15) * (0.6 + 0.4 * env), 0, 1);
}
function drawRing(ts) {
  const dt = Math.min(0.1, (ts - lastTs) / 1000); lastTs = ts;
  let target = 0;
  if (STATIC) target = 0.55;
  else if (analyser && !voice.paused) target = audioLevel();
  else if (!P.audio) target = fakeLevel(clock());
  // lissage : montée rapide (~36 ms), descente plus lente (~200 ms) => mouvement organique
  const tau = target > level ? 0.036 : 0.2;
  level += (target - level) * (1 - Math.exp(-dt / tau));

  const col = (content?.ring_color || '#5ac8ff') === 'accent'
    ? hexRgb(getComputedStyle(root).getPropertyValue('--accent').trim() || '#ffb400')
    : hexRgb(content?.ring_color || '#5ac8ff');
  rctx.clearRect(0, 0, 360, 360);
  for (const [gap, w, amax] of [[8, 6, 140], [18, 10, 80]]) {
    const r = 120 + gap + level * 22, a = (amax * (0.35 + 0.65 * level)) / 255;
    rctx.beginPath(); rctx.arc(180, 180, r - w / 2, 0, Math.PI * 2);
    rctx.lineWidth = w; rctx.strokeStyle = `rgba(${col},${a})`;
    rctx.shadowColor = `rgba(${col},${Math.min(1, a + .25)})`; rctx.shadowBlur = 14; rctx.stroke();
  }
  requestAnimationFrame(drawRing);
}

/* ======================= Horloge ======================= */
const demoStart = performance.now();
let demoLen = 60;
function clock() {
  if (STATIC) return P.freeze;
  if (P.audio) return voice.currentTime;
  return ((performance.now() - demoStart) / 1000) % demoLen;
}

async function startAudio() {
  voice.src = P.audio; setupAudio();
  const ok = async () => { try { await Promise.race([actx.resume(), new Promise(r => setTimeout(r, 600))]); await voice.play(); } catch (e) { return false; } return actx.state === 'running' && !voice.paused; };
  if (!(await ok())) {
    const o = $('#start'); o.hidden = false;
    o.onclick = async () => { if (await ok()) o.hidden = true; };
  }
}

/* ======================= Démarrage ======================= */
async function loadContent() {
  try { const r = await fetch(P.content, { cache: 'no-store' }); if (!r.ok) throw 0; return await r.json(); }
  catch (e) { if (window.__DEMO_CONTENT__) return window.__DEMO_CONTENT__; throw new Error('contenu introuvable : ' + P.content); }
}

(async () => {
  content = await loadContent();
  scenes = (content.scenes || []).slice().sort((a, b) => a.t - b.t);
  scenes.forEach((s, i) => { if (s.until == null) s.until = scenes[i + 1] ? scenes[i + 1].t : s.t + 12; });
  demoLen = scenes.length ? scenes[scenes.length - 1].until : 60;

  const ch = content.channel || {};
  $('#brand-a').textContent = ch.name_top || 'LE JOURNAL DU';
  $('#brand-b').textContent = ch.name_main || 'NON';
  $('#edition').textContent = ch.edition ? 'Édition du ' + ch.edition : '';
  $('#ticker-lab').textContent = content.ticker_label || 'EN BREF';

  const av = $('#avatar'); av.src = P.avatar; av.play().catch(() => {});

  await (document.fonts?.ready || Promise.resolve());
  buildTicker(content.ticker || ['—'], content.ticker_speed || 110);
  show(indexAt(clock()));
  requestAnimationFrame(drawRing);

  setInterval(() => {
    const t = clock(), i = indexAt(t);
    if (i !== cur) show(i);
    const s = scenes[cur];
    if (s) $('#prog').style.width = (clamp((t - s.t) / Math.max(0.1, s.until - s.t), 0, 1) * 100) + '%';
  }, 100);

  if (P.audio && !STATIC) {
    voice.addEventListener('ended', () => { document.body.dataset.state = 'ended'; window.__NARRATION_DONE__ = true; });
    voice.addEventListener('loadedmetadata', () => { window.__NARRATION_DURATION__ = voice.duration; });
    startAudio();
  }
  window.__TEMPLATE_READY__ = true;
})().catch(e => { console.error(e); document.body.dataset.state = 'error'; window.__TEMPLATE_ERROR__ = String(e); });
})();
