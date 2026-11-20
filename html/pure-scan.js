// pure-whip-police fork: the scan cards and the camera legend dressed in the police UI kit (see pure-kit.js). Upstream's
// scan.html paints the atlas that client/scan.lua cuts up; this only adds kit classes to what it paints, so no box moves.
(() => {
  const PW = window.PW;
  const atlas = document.getElementById('atlas');
  if (!PW || !atlas) return;
  atlas.querySelectorAll('.cell, .panel').forEach((el) => el.classList.add('pwp', 'pw-scan'));

  const probe = document.createElement('i');
  const toneOf = {};
  for (const [k, t] of Object.entries({ green: 'ok', yellow: 'warn', red: 'danger', blue: 'route' })) {
    probe.style.color = COLORS[k];
    toneOf[probe.style.color] = t;
  }
  const dress = (el, ...cls) => {
    const t = toneOf[el.style.color];
    el.style.color = '';
    el.classList.add(...cls, ...(t ? [t] : []));
  };
  const kit = (root) => {
    root.querySelectorAll('.card:not(.pwp-card)').forEach((c) => c.classList.add('pwp-card', 'pwp-bracket'));
    root.querySelectorAll('.chip:not(.pwp-flag)').forEach((c) => dress(c, 'pwp-flag'));
    root.querySelectorAll('.sheet:not(.pwp-card)').forEach((s) => s.classList.add('pwp-card'));
    root.querySelectorAll('.label:not(.pwp-lbl)').forEach((l) => l.classList.add('pwp-lbl'));
    root.querySelectorAll('.row:not(.pwp-row)').forEach((r) => r.classList.add('pwp-row'));
    root.querySelectorAll('.info:not(.pw-info)').forEach((i) => dress(i, 'pw-info'));
    root.querySelectorAll('.hint:not(.pwp-hint)').forEach((h) => { h.classList.add('pwp-hint'); h.innerHTML = PW.colonKeys(h.textContent); });
  };
  new MutationObserver((list) => new Set(list.map((r) => r.target)).forEach((t) => {
    if (t.closest && t.closest('.pw-scan')) kit(t);
  })).observe(atlas, { childList: true, subtree: true });
})();
