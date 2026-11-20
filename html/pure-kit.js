// pure-whip-police fork: shared setup for the screens drawn from the police UI kit (pure-whip-police/html/shared/bracket.js).
// Without the kit (police not running) window.PW stays unset and upstream's screens show as before.
(() => {
  const B = window.PWPBracket;
  if (!B) return;
  const style = document.createElement('style');
  style.textContent = B.css;
  document.head.appendChild(style);
  document.body.classList.add('pw-on');

  const e = B.esc;
  const layer = (id) => {
    const el = document.createElement('div');
    el.id = id;
    el.className = 'pwp pw-layer';
    document.body.appendChild(el);
    return el;
  };
  const follow = (source, target, cls = 'open') => {
    const sync = () => target.classList.toggle('open', source.classList.contains(cls));
    new MutationObserver(sync).observe(source, { attributes: true, attributeFilter: ['class'] });
    sync();
  };
  const watch = (el, fn) => new MutationObserver(fn).observe(el, { childList: true, characterData: true, subtree: true });
  const kbd = (key, label) => `<span><span class="pwp-kbd">${e(key)}</span>${e(label)}</span>`;
  // "Close · Esc" (label · key)
  const closeHint = (text) => {
    const p = String(text || '').split(' · ');
    return p.length === 2 ? kbd(p[1], p[0]) : `<span>${e(text)}</span>`;
  };
  // "Enter opens · ↑ ↓ pick" (key label, key label)
  const keyHints = (text) => String(text || '').split(' · ').filter(Boolean).map((part) => {
    const m = /^(.*\S)\s+(\S+)$/.exec(part.trim());
    return m ? kbd(m[1], m[2]) : `<span>${e(part)}</span>`;
  }).join('');
  const txt = (id) => { const el = document.getElementById(id); return el ? el.textContent : ''; };

  window.PW = Object.freeze({ B, e, I: B.icons, layer, follow, watch, kbd, closeHint, keyHints, txt });
})();
