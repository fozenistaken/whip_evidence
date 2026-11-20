// pure-whip-police fork: the crime scene photo viewer as a police kit panel. Upstream's #viewer keeps loading, zoom,
// keys and controller; its picture element (#shot: image, date stamp, click to zoom) moves into this panel, and the
// rest is drawn from what upstream renders.
(() => {
  const PW = window.PW;
  const up = document.getElementById('viewer');
  const shot = document.getElementById('shot');
  if (!PW || !up || !shot) return;
  const { e, I } = PW;
  const root = PW.layer('pwPhoto');
  root.innerHTML = `<section class="pwp-panel pw-photo" role="dialog">
    <div class="pwp-panel-head"><div class="k"><small data-pw="kicker"></small><h1 data-pw="street"></h1><span class="sub" data-pw="meta"></span></div>
      <span class="pwp-flag route" data-pw="case"></span>
      <button class="pwp-btn ghost icon pwp-press" data-pw="close">${I.x}</button></div>
    <div class="pw-photo-grid">
      <div class="pwp-card pw-shot" data-pw="shot"></div>
      <div class="pw-photo-side">
        <div class="pwp-card"><p class="pwp-lbl" data-pw="inpic"></p><span class="sub" data-pw="scene"></span><div data-pw="rows"></div></div>
        <div class="pwp-card pw-custody" data-pw="custody"></div>
      </div>
    </div>
    <div class="pwp-panel-foot"><div class="pwp-hint" data-pw="hint"></div></div>
  </section>`;
  const $ = (k) => root.querySelector(`[data-pw="${k}"]`);
  $('shot').appendChild(shot);

  const KIND = { car: 'car', body: 'body' };
  const draw = () => {
    $('kicker').textContent = PW.txt('kicker');
    $('street').textContent = PW.txt('street');
    $('meta').textContent = PW.txt('meta');
    $('case').textContent = PW.txt('casestamp');
    const h2 = up.querySelector('.log h2');
    $('inpic').textContent = h2 ? h2.textContent : '';
    $('scene').textContent = PW.txt('scene');
    $('rows').innerHTML = [...document.querySelectorAll('#rows > .row')].map((r) => {
      const no = (r.querySelector('.no') || {}).textContent || '';
      const t = r.querySelector('.what .t');
      const i = (r.querySelector('.what .i') || {}).textContent || '';
      const d = (r.querySelector('.d') || {}).textContent || '';
      const kind = r.classList.contains('car') ? 'car' : r.classList.contains('body') ? 'body' : 'trace';
      return `<div class="pwp-row"><span class="pw-tag ${KIND[kind] || 'trace'}">${e(no)}</span><span class="t">${t ? t.innerHTML : ''}${i ? `<span class="s">${e(i)}</span>` : ''}</span>${d ? `<span class="pwp-code">${e(d)}</span>` : ''}</div>`;
    }).join('');
    const steps = [...document.querySelectorAll('#custody .step')];
    const h3 = document.querySelector('#custody h3');
    $('custody').hidden = steps.length === 0;
    $('custody').innerHTML = steps.length ? `<p class="pwp-lbl">${e(h3 ? h3.textContent : '')}</p>${steps.map((s) => `<div class="pwp-row pw-step"><span class="t">${e(s.textContent)}</span></div>`).join('')}` : '';
    $('hint').innerHTML = PW.closeHint(PW.txt('close'));
    root.classList.toggle('log-hidden', up.classList.contains('log-hidden'));
    root.classList.toggle('no-stamp', up.classList.contains('no-stamp'));
  };
  PW.watch(up, draw);
  new MutationObserver(draw).observe(up, { attributes: true, attributeFilter: ['class'] });
  PW.follow(up, root);
  draw();

  root.addEventListener('click', (ev) => {
    if (ev.target.closest('[data-pw="close"]')) document.getElementById('close').click();
  });
})();
