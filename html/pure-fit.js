// pure-whip-police fork: the lab screen fit tool's key panel in the police UI kit (see pure-kit.js). Upstream's #fit keeps
// its texts and the mouse/controller switch; this gives it the kit card, title and keycaps.
(() => {
  const PW = window.PW;
  const fit = document.getElementById('fit');
  if (!PW || !fit) return;
  fit.classList.add('pwp', 'pwp-card', 'pwp-bracket', 'pw-fit');
  fit.querySelectorAll('kbd').forEach((k) => k.classList.add('pwp-kbd'));
  const pad = fit.querySelector('.padkeys');
  const hint = Object.assign(document.createElement('div'), { className: 'pwp-hint pw-fit-pad' });
  pad.after(hint);
  const draw = () => { hint.innerHTML = PW.colonKeys(pad.textContent); };
  PW.watch(pad, draw);
  draw();
})();
