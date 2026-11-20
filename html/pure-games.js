// pure-whip-police fork: the minigame frame in the police UI kit (see pure-kit.js). games.js keeps the canvas, input,
// timers and results; this gives its panel the kit's head, card and keycaps, drawn from what games.js writes.
(() => {
  const PW = window.PW;
  const mg = document.getElementById('mg');
  const keys = document.getElementById('mgKeys');
  if (!PW || !mg || !keys) return;
  mg.classList.add('pwp', 'pw-mg');
  mg.querySelector('.panel').classList.add('pwp-panel');
  const canvas = mg.querySelector('#mgCanvas');
  const frame = Object.assign(document.createElement('div'), { className: 'pwp-card pwp-bracket pw-mg-frame' });
  canvas.before(frame);
  frame.appendChild(canvas);
  const hint = Object.assign(document.createElement('div'), { className: 'pwp-hint pw-mg-keys' });
  keys.after(hint);
  const draw = () => { hint.innerHTML = PW.colonKeys(keys.textContent); };
  PW.watch(keys, draw);
  draw();
})();
