// pure-whip-police fork: the lab monitor drawn with the police UI kit (see pure-kit.js). Upstream's lab.html keeps the
// paint messages, timers, bag schedule and instrument pictures; this draws #main's content from what upstream renders
// there and moves the live instrument picture (#viz) and scan bar in, so upstream's steps keep driving them.
(() => {
  const PW = window.PW;
  const up = document.getElementById('main');
  if (!PW || !up) return;
  const { e, I } = PW;
  document.body.classList.add('pwp');
  const root = document.createElement('div');
  root.className = 'main pw-main';
  up.after(root);

  const swap = (sel, icons) => document.querySelectorAll(sel).forEach((el, i) => { if (icons[i]) el.outerHTML = icons[i]; });
  swap('.nav .item .ico', [I.search, I.locker, I.gun, I.report]);
  swap('.task .tb .ico', [I.report, I.dispatch, I.map]);

  const CHECK = '<svg viewBox="0 0 16 16"><path d="M3 8.5l3.2 3L13 4.5" fill="none" stroke="currentColor" stroke-width="2.2"/></svg>';
  const tx = (sel, el = up) => ((el.querySelector(sel) || {}).textContent || '').trim();
  const $ = (k) => root.querySelector(`[data-pw="${k}"]`);
  const adopt = (k, el) => { const box = $(k); if (el && box && el.parentNode !== box) box.replaceChildren(el); };
  const head = (kick, title, sub) => `<div class="pwp-panel-head pw-head"><div class="k">${kick ? `<small>${e(kick)}</small>` : ''}<h1>${e(title)}</h1>${sub ? `<span class="sub">${e(sub)}</span>` : ''}</div></div>`;
  const tag = (no, tone = '') => `<span class="pw-tag ${tone}">${e(no)}</span>`;
  const more = (el) => { const t = tx('.more', el); return t ? `<p class="pw-more">${e(t)}</p>` : ''; };

  const ready = () => {
    const cards = [...up.querySelectorAll('.cards .card')];
    return `${head(tx('.sub'), tx('h1'))}
      <div class="pw-cards">${cards.map((c, i) => {
        const n = tx('.n', c);
        return `<div class="pwp-card${i !== 1 && +n > 0 ? ' pwp-bracket' : ''}"><p class="pwp-lbl">${e(tx('.l', c))}</p><b class="num">${e(n)}</b></div>`;
      }).join('')}</div>
      <p class="pw-tip">${I.box}${e(tx('.tip'))}</p>`;
  };

  const done = () => {
    const rows = [...up.querySelectorAll('.results .res')];
    const match = rows.some((r) => r.classList.contains('match'));
    return `<div class="pwp-panel-head pw-head pw-done"><span class="pw-ok">${CHECK}</span><div class="k"><h1>${e(tx('h1'))}</h1><span class="sub">${e(tx('.sub'))}</span></div></div>
      <div class="pwp-card pw-results${match ? ' pwp-bracket danger' : ''}">${rows.map((r) => {
        const no = tx('.no', r);
        if (!no) return `<div class="pwp-empty">${e(r.textContent.trim())}</div>`;
        const tone = r.classList.contains('match') ? 'danger' : (r.classList.contains('reference') ? 'ok' : '');
        return `<div class="pwp-row">${tag(no, tone)}<span class="t">${e(tx('.tx', r))}</span></div>`;
      }).join('')}</div>${more()}`;
  };

  const running = (items) => {
    $('kick').textContent = tx('h1');
    $('pct').textContent = tx('#pct');
    $('left').lastChild.textContent = tx('#left');
    $('sub').textContent = tx('.sub');
    const pb = up.querySelector('#pb');
    $('bar').style.transform = `scaleX(${Math.min(1, (parseFloat(pb && pb.style.width) || 0) / 100)})`;
    if (!items) {
      $('chips').innerHTML = [...up.querySelectorAll('.chips .chip')].map((c) => `<span class="pwp-flag">${e(c.textContent)}</span>`).join('');
      adopt('scan', up.querySelector('.scan'));
      return;
    }
    const bags = up.querySelector('#bags');
    $('bags').innerHTML = [...bags.querySelectorAll('.bag')].map((b) => {
      const st = tx('.s', b);
      const isDone = b.classList.contains('done');
      return `<div class="pwp-row pw-bag${isDone ? ' done' : ''}${b.classList.contains('now') ? ' now' : ''}">${tag(tx('.no', b))}<span class="t">${e(tx('.k', b))}</span>${isDone ? `<span class="pwp-flag ok">${e(st)}</span>` : `<span class="pw-st">${e(st)}</span>`}</div>`;
    }).join('') + more(bags);
    adopt('viz', up.querySelector('#viz'));
  };

  const SKELETON = {
    running: (items) => `<div class="pwp-panel-head pw-head"><div class="k"><small data-pw="kick"></small>
        <div class="pw-pct"><h1 class="num" data-pw="pct"></h1><span class="pw-left" data-pw="left">${I.clock}<span></span></span></div>
        <span class="sub" data-pw="sub"></span></div></div>
      <div class="pw-bar"><b data-pw="bar"></b></div>
      ${items ? '<div class="pw-split"><div class="pwp-card pw-bags" data-pw="bags"></div><div class="pwp-card pw-viz" data-pw="viz"></div></div>'
        : '<div class="pw-flags" data-pw="chips"></div><div class="pw-scan" data-pw="scan"></div>'}`,
  };

  let shown = '';
  const draw = () => {
    if (!up.firstElementChild) { shown = ''; root.innerHTML = ''; return; }
    if (up.querySelector('#pb')) {
      const items = !!up.querySelector('#bags');
      const key = items ? 'running-items' : 'running';
      if (shown !== key) { shown = key; root.innerHTML = SKELETON.running(items); }
      running(items);
      return;
    }
    shown = up.querySelector('.results') ? 'done' : 'ready';
    root.innerHTML = shown === 'done' ? done() : ready();
  };
  PW.watch(up, draw);
  draw();
})();
