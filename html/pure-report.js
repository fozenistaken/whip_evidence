// pure-whip-police fork: the post-mortem sheet built from the police UI kit (pure-whip-police/html/shared/bracket.js).
// Upstream's #report keeps the state, keys, controller buttons and copy; this draws the sheet from the same message
// and follows #report open and closed. Without the kit (police not running) upstream's sheet shows as before.
(() => {
  const B = window.PWPBracket;
  const up = document.getElementById('report');
  if (!B || !up) return;
  const I = B.icons;
  const e = B.esc;
  const style = document.createElement('style');
  style.textContent = B.css;
  document.head.appendChild(style);
  document.body.classList.add('pw-on');

  const root = document.createElement('div');
  root.id = 'pwReport';
  root.className = 'pwp';
  document.body.appendChild(root);

  const place = (marks) => {
    let seed = 7;
    const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
    const used = {};
    return marks.map((m) => {
      if (m.s && REP_SPOTS[m.s]) {
        const o = repSpread(m.s, (used[m.s] = (used[m.s] || 0) + 1) - 1, REP_SPOTS[m.s]);
        return [REP_SPOTS[m.s][0] + o[0], REP_SPOTS[m.s][1] + o[1]];
      }
      const areas = REP_AREAS[m.p] || REP_AREAS.torso;
      used[m.p] = (used[m.p] || 0) + 1;
      const a = areas[(used[m.p] - 1) % areas.length];
      return [a[0] + (rnd() * 2 - 1) * a[2], a[1] + (rnd() * 2 - 1) * a[3]];
    });
  };
  const kindOf = (m) => (m.w === 'gunshot' ? (m.i ? 'inside' : 'through') : (m.w === 'stab' ? 'stab' : 'other'));
  const FATAL = '<circle r="10.5" fill="none" stroke="#f2c94c" stroke-width="1.6" stroke-dasharray="3 2"/>';

  const figure = (fig, hits) => {
    const S = fig.spots || {};
    return `<svg class="pw-body-svg" viewBox="0 0 200 410" role="img" aria-label="${e(fig.front || 'Front')}">
      <defs><filter id="pwSkin" x="-5%" y="-5%" width="110%" height="110%"><feMorphology in="SourceAlpha" operator="dilate" radius="1.2" result="grow"/>
        <feComposite in="grow" in2="SourceAlpha" operator="out" result="edge"/><feFlood flood-color="#fff" flood-opacity=".35"/><feComposite in2="edge" operator="in" result="line"/>
        <feFlood flood-color="#fff" flood-opacity=".10"/><feComposite in2="SourceAlpha" operator="in" result="fill"/><feMerge><feMergeNode in="fill"/><feMergeNode in="line"/></feMerge></filter></defs>
      <image href="img/pure-body.webp" width="200" height="410" filter="url(#pwSkin)"/>
      <text class="side" x="14" y="26">${e(S.side_r || 'R')}</text><text class="side" x="186" y="26" text-anchor="end">${e(S.side_l || 'L')}</text>
      ${hits.map((h) => `<g class="mk" data-i="${h.n}" transform="translate(${h.x.toFixed(1)} ${h.y.toFixed(1)})"><circle class="hl" r="15"/>${h.m.f ? FATAL : ''}${REP_ICON[kindOf(h.m)]}<text x="11" y="-8">${h.n}</text><title>${e(h.name)}: ${e(h.what)}</title></g>`).join('')}
    </svg>`;
  };

  const legend = (fig, hits) => {
    const L = fig.legend || {}; const S = fig.spots || {};
    const has = new Set(hits.map((h) => kindOf(h.m)));
    const item = (svg, t) => `<span><svg viewBox="-12 -12 24 24">${svg}</svg>${e(t)}</span>`;
    return [['inside', L.inside], ['through', L.through], ['stab', L.stab], ['other', L.other]]
      .filter(([k]) => has.has(k)).map(([k, t]) => item(REP_ICON[k], t || k)).join('')
      + (hits.some((h) => h.m.f) ? item(FATAL, S.fatal || 'fatal') : '');
  };

  const keyHint = (label) => {
    const parts = String(label || '').split(' · ');
    return parts.length === 2 ? `<span><span class="pwp-kbd">${e(parts[1])}</span>${e(parts[0])}</span>` : `<span>${e(label)}</span>`;
  };

  const TONE = { red: 'danger', yellow: 'warn', green: 'ok', blue: 'route' };

  const render = (d) => {
    const fig = d.fig || {}; const S = fig.spots || {};
    const marks = fig.marks || [];
    const at = place(marks);
    const hits = marks.map((m, i) => {
      const state = m.w === 'gunshot' ? (m.i ? S.inside : S.through) : null;
      return { m, x: at[i][0], y: at[i][1], name: S[m.s] || S[m.p] || m.p, what: [S['w_' + m.w] || m.w, state].filter(Boolean).join(' · ') };
    }).sort((a, b) => (b.m.f ? 1 : 0) - (a.m.f ? 1 : 0) || a.y - b.y);
    hits.forEach((h, i) => { h.n = i + 1; });

    const rows = (d.rows || []).slice();
    const cause = fig.cause && rows.length && rows[0].c === 'red' ? rows.shift() : null;
    rows.shift();
    const details = rows.filter((r) => !/^\s/.test(r.k || ''));
    const secured = details.length ? details.pop() : null;
    const count = (fig.tiles || [])[0];

    root.innerHTML = `<section class="pwp-panel pw-report" role="dialog" aria-label="${e(d.title || '')}">
      <div class="pwp-panel-head"><div class="k"><small>${e(d.kicker || '')}</small><h1>${e(d.title || '')}</h1><span class="sub">${e(d.sub || '')}</span></div>
        <button class="pwp-btn ghost icon pwp-press" data-pw="close" aria-label="${e(d.close || 'Close')}">${I.x}</button></div>
      <div class="pw-grid">
        <div class="pwp-card pw-fig">${figure(fig, hits)}<div class="pw-legend">${legend(fig, hits)}</div></div>
        <div class="pw-side">
          ${cause ? `<div class="pwp-card pwp-bracket danger pw-cause"><p class="pwp-lbl">${e(cause.k)}</p><b>${e(cause.v)}</b></div>` : ''}
          ${hits.length ? `<div class="pwp-card"><p class="pwp-lbl">${count ? `${e(count.n)} ${e(count.t)}` : ''}</p>${hits.map((h) => `<div class="pwp-row pw-hit" data-i="${h.n}"><span class="pwp-code">${h.n}</span><span class="t">${e(h.name)}<span class="s">${e(h.what)}</span></span>${h.m.f ? `<span class="pwp-flag warn">${e(S.fatal || 'fatal')}</span>` : ''}</div>`).join('')}</div>` : ''}
          ${details.length ? `<div class="pwp-card">${details.map((r) => `<div class="pwp-row"><span class="t pw-k">${e(r.k)}</span><span class="pw-v ${TONE[r.c] || ''}">${e(r.v)}</span></div>`).join('')}</div>` : ''}
        </div>
      </div>
      <div class="pwp-panel-foot"><div class="pwp-hint">${keyHint(d.close)}</div>
        ${secured ? `<span class="pw-secured"><span class="pwp-lbl">${e(secured.k)}</span>${e(secured.v)}</span>` : ''}
        <button class="pwp-cta${d.pad ? ' has-kbd' : ''} pwp-press" data-pw="copy">${e(d.copy || 'Copy as text')}${d.pad ? '<span class="pwp-kbd">A</span>' : ''}</button></div>
    </section>`;
  };

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'bodyReport' && d.open) render(d);
  });
  new MutationObserver(() => root.classList.toggle('open', up.classList.contains('open')))
    .observe(up, { attributes: true, attributeFilter: ['class'] });
  const upCopy = document.getElementById('repCopy');
  new MutationObserver(() => {
    const b = root.querySelector('[data-pw="copy"]');
    if (b && upCopy.textContent && !/^A: /.test(upCopy.textContent)) b.firstChild.textContent = upCopy.textContent;
  }).observe(upCopy, { childList: true, characterData: true, subtree: true });

  root.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-pw]');
    if (b) document.getElementById(b.dataset.pw === 'copy' ? 'repCopy' : 'repClose').click();
  });
  const hot = (i) => root.querySelectorAll('[data-i]').forEach((el) => el.classList.toggle('hot', el.dataset.i === i));
  root.addEventListener('pointerover', (ev) => { const t = ev.target.closest('[data-i]'); hot(t ? t.dataset.i : null); });
  root.addEventListener('pointerleave', () => hot(null));
})();
