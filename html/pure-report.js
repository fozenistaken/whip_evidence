// pure-whip-police fork: the post-mortem sheet as a body chart. Upstream's #report keeps the state, keys, controller
// buttons and copy; this page draws its own sheet from the same message and follows #report open and closed.
(() => {
  const up = document.getElementById('report');
  if (!up) return;
  const sheet = document.createElement('div');
  sheet.id = 'pwReport';
  document.body.appendChild(sheet);

  const COLOR = { red: 'var(--pe-danger)', yellow: 'var(--pe-warn)', green: 'var(--pe-ok)', blue: 'var(--pe-car)' };
  const e = (s) => esc(s);

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

  const figure = (fig, hits) => {
    const S = fig.spots || {};
    const dots = hits.map((h) => `<g class="mk" data-i="${h.n}" transform="translate(${h.x.toFixed(1)} ${h.y.toFixed(1)})">
      <circle class="hl" r="15"/>${h.m.f ? '<circle r="11" fill="none" stroke="var(--pe-warn)" stroke-width="1.6" stroke-dasharray="3 2"/>' : ''}${REP_ICON[kindOf(h.m)]}
      <text x="11" y="-8">${h.n}</text><title>${e(h.name)}: ${e(h.what)}</title></g>`).join('');
    return `<svg viewBox="0 0 200 410" role="img" aria-label="${e(fig.front || 'Front')}">
      <defs><filter id="pwSkin" x="-5%" y="-5%" width="110%" height="110%"><feMorphology in="SourceAlpha" operator="dilate" radius="1.2" result="grow"/>
        <feComposite in="grow" in2="SourceAlpha" operator="out" result="edge"/><feFlood flood-color="#fff" flood-opacity=".35"/><feComposite in2="edge" operator="in" result="line"/>
        <feFlood flood-color="#fff" flood-opacity=".10"/><feComposite in2="SourceAlpha" operator="in" result="fill"/><feMerge><feMergeNode in="fill"/><feMergeNode in="line"/></feMerge></filter></defs>
      <image href="img/pure-body.webp" width="200" height="410" filter="url(#pwSkin)"/>
      <text class="side" x="16" y="28">${e(S.side_r || 'R')}</text><text class="side" x="184" y="28" text-anchor="end">${e(S.side_l || 'L')}</text>
      ${dots}</svg>`;
  };

  const legend = (fig, hits) => {
    const L = fig.legend || {}; const S = fig.spots || {};
    const has = new Set(hits.map((h) => kindOf(h.m)));
    const item = (svg, t) => `<span><svg viewBox="-12 -12 24 24">${svg}</svg>${e(t)}</span>`;
    return [['inside', L.inside || 'bullet still inside'], ['through', L.through || 'went through'], ['stab', L.stab || 'stab'], ['other', L.other || 'other wound']]
      .filter(([k]) => has.has(k)).map(([k, t]) => item(REP_ICON[k], t)).join('')
      + (hits.some((h) => h.m.f) ? item('<circle r="10" fill="none" stroke="var(--pe-warn)" stroke-width="1.6" stroke-dasharray="3 2"/>', S.fatal || 'fatal') : '');
  };

  const render = (d) => {
    const fig = d.fig || {}; const S = fig.spots || {};
    const marks = fig.marks || [];
    const at = place(marks);
    const hits = marks.map((m, i) => {
      const w = S['w_' + m.w] || m.w;
      const state = m.w === 'gunshot' ? (m.i ? S.inside : S.through) : null;
      return { m, x: at[i][0], y: at[i][1], name: S[m.s] || S[m.p] || m.p, what: [w, state].filter(Boolean).join(' · ') };
    }).sort((a, b) => (b.m.f ? 1 : 0) - (a.m.f ? 1 : 0) || a.y - b.y);
    hits.forEach((h, i) => { h.n = i + 1; });

    const rows = (d.rows || []).slice();
    const cause = fig.cause && rows.length && rows[0].c === 'red' ? rows.shift() : null;
    rows.shift();
    const details = rows.filter((r) => !/^\s/.test(r.k || ''));
    const secured = details.length ? details.pop() : null;

    const count = (fig.tiles || [])[0];
    const list = hits.map((h) => `<div class="hit" data-i="${h.n}"><span class="n">${h.n}</span><span class="t"><b>${e(h.name)}</b><span>${e(h.what)}</span></span>${h.m.f ? `<span class="fatal">${e(S.fatal || 'fatal')}</span>` : '<span></span>'}</div>`).join('');
    const dl = details.map((r) => `<dt>${e(r.k)}</dt><dd${COLOR[r.c] ? ` style="color:${COLOR[r.c]}"` : ''}>${e(r.v)}</dd>`).join('');

    sheet.innerHTML = `<div class="pw-sheet" role="dialog" aria-label="${e(d.title || '')}">
      <header><div><div class="kick">${e(d.kicker || '')}</div><h2>${e(d.title || '')}</h2><p>${e(d.sub || '')}</p></div>
        <button class="btn" data-pw="close">${e(d.close || 'Close · Esc')}</button></header>
      <div class="left"><div class="fig">${figure(fig, hits)}</div><div class="legend">${legend(fig, hits)}</div></div>
      <div class="right">
        ${cause ? `<div class="verdict"><div class="k">${e(cause.k)}</div><b>${e(cause.v)}</b></div>` : ''}
        ${list ? `<div><div class="k">${count ? `${e(count.n)} ${e(count.t)}` : ''}</div><div class="hits">${list}</div></div>` : ''}
        ${dl ? `<dl>${dl}</dl>` : ''}
      </div>
      <footer><span class="grow">${secured ? `<span class="k">${e(secured.k)}</span> ${e(secured.v)}` : ''}</span>
        <button class="btn" data-pw="copy">${e((d.pad ? 'A: ' : '') + (d.copy || 'Copy as text'))}</button></footer>
    </div>`;
  };

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.action === 'bodyReport' && d.open) render(d);
  });

  new MutationObserver(() => { sheet.classList.toggle('open', up.classList.contains('open')); })
    .observe(up, { attributes: true, attributeFilter: ['class'] });
  new MutationObserver(() => {
    const b = sheet.querySelector('[data-pw="copy"]');
    const t = document.getElementById('repCopy');
    if (b && t && t.textContent) b.textContent = t.textContent;
  }).observe(document.getElementById('repCopy'), { childList: true, characterData: true, subtree: true });

  sheet.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-pw]');
    if (!b) return;
    document.getElementById(b.dataset.pw === 'copy' ? 'repCopy' : 'repClose').click();
  });
  const hot = (i) => sheet.querySelectorAll('[data-i]').forEach((el) => el.classList.toggle('hot', el.dataset.i === i));
  sheet.addEventListener('pointerover', (ev) => { const t = ev.target.closest('[data-i]'); hot(t ? t.dataset.i : null); });
  sheet.addEventListener('pointerleave', () => hot(null));
})();
