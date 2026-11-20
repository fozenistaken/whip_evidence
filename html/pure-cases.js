// pure-whip-police fork: the evidence locker's case list as a police kit panel. Upstream's #cases keeps the search,
// selection, keys and controller; its search field and "show more" button move into this panel, rows are drawn
// from what upstream renders, and a click goes to upstream's row.
(() => {
  const PW = window.PW;
  const up = document.getElementById('cases');
  if (!PW || !up) return;
  const { e, I } = PW;
  const root = PW.layer('pwCases');
  root.innerHTML = `<section class="pwp-panel pw-cases" role="dialog">
    <div class="pwp-panel-head"><div class="k"><small data-pw="kicker"></small><h1 data-pw="title"></h1></div>
      <button class="pwp-btn ghost icon pwp-press" data-pw="close">${I.x}</button></div>
    <div class="pw-cases-search"><label class="pwp-search">${I.search || ''}<span data-pw="search"></span></label></div>
    <div class="pwp-panel-body"><div class="pw-cases-list" data-pw="list"></div><div data-pw="more"></div></div>
    <div class="pwp-panel-foot"><div class="pwp-hint" data-pw="hint"></div></div>
  </section>`;
  const $ = (k) => root.querySelector(`[data-pw="${k}"]`);
  $('search').replaceWith(document.getElementById('casesSearch'));
  const more = document.getElementById('casesMore');
  more.classList.add('pwp-btn', 'sm', 'pwp-press');
  $('more').replaceWith(more);

  const draw = () => {
    $('kicker').textContent = PW.txt('casesKicker');
    $('title').textContent = PW.txt('casesTitle');
    $('close').setAttribute('aria-label', PW.txt('casesClose'));
    $('hint').innerHTML = PW.keyHints(PW.txt('casesHint')) + PW.closeHint(PW.txt('casesClose'));
    const rows = [...document.querySelectorAll('#casesList > .c')];
    const empty = document.querySelector('#casesList > .empty');
    $('list').innerHTML = rows.length ? rows.map((r) => {
      const id = r.dataset.id;
      const info = (r.querySelector('.info') || {}).textContent || '';
      const cls = [r.classList.contains('sel') ? 'on' : '', r.classList.contains('closed') ? 'closed' : '', r.classList.contains('typed') ? 'typed' : ''].join(' ');
      return `<button class="pwp-row pw-case ${cls}" data-id="${e(id)}"><span class="pwp-code">#${e(id)}</span><span class="t">${e(info)}</span>${r.classList.contains('typed') ? I.arrow || '' : ''}</button>`;
    }).join('') : `<div class="pwp-empty">${e(empty ? empty.textContent : '')}</div>`;
    const sel = $('list').querySelector('.on');
    if (sel) sel.scrollIntoView({ block: 'nearest' });
  };
  PW.watch(up, draw);
  PW.follow(up, root);
  draw();

  root.addEventListener('click', (ev) => {
    const row = ev.target.closest('.pw-case');
    if (row) {
      const target = [...document.querySelectorAll('#casesList > .c')].find((c) => c.dataset.id === row.dataset.id);
      if (target) target.click();
      return;
    }
    if (ev.target.closest('[data-pw="close"]')) document.getElementById('casesClose').click();
  });
})();
