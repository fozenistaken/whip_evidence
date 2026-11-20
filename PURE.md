# pure-whip-police fork notes

How this fork differs from LeSiiN's release and how to keep it mergeable. The fork's own commits sit on branch
`pure`; upstream is the `upstream` remote (no push).

## Updating to a new upstream release

1. `git fetch upstream --tags`, read the CHANGELOG between the tags, check that the exports pure-whip-police calls still
   exist (`SetCaseCheck`, `GetUploadable`, `Upload`, `GetCase`, `OpenCaseLocker`, `CloseCase`, `ReopenCase`,
   `GetPhotoImage`, plus this fork's `GetTraits`).
2. Bundle branch `pure` to `F:\Claude-Backups\whip_evidence\snapshots\` (the fork's commits are not on GitHub), then
   `git rebase upstream/main` with the commit identity set.
3. Conflicts come from colour literals next to upstream's changed lines: keep upstream's lines, re-apply the colour.
   4.2.3 to 4.2.5 conflicted only in `html/index.html` (the new hit-spot tooltip beside the fatal-ring colour);
   4.2.5 to 4.2.6 rebased with no conflicts.
4. Re-render the themed screens and run pure-whip-police's harness.

## Theming without breaking merges

- The UIs are `html/index.html` (photo viewer, case list `#cases`, post-mortem `#report`, lab fit `#fit`),
  `html/games.js` (minigames, injects `#mg` CSS at runtime), `html/scan.html` (DUI atlas 1024x1024: cards, legend,
  marker tags, digits; positions are read by `client/scan.lua`, so never move or resize atlas boxes) and
  `html/lab.html` (DUI 1280x720 lab monitor, laid out 800 px wide and zoomed 1.6).
- Stylesheets load after each page's `</style>`: `pure-theme.css` (tokens and fonts), `pure-nui.css`, `pure-scan.css`,
  `pure-lab.css`. `games.js` adds its style later at runtime, so `#mg` is overridden with `html body #mg ...`.
- Colours set from JS (scan `COLORS`, `STRIPE`, `MARK_BG`, tag backgrounds; index `REP_COLORS`; minigame `flash()`
  colours; lab script) are swapped in the file itself; that diff stays limited to colour literals.
- The minigame canvas maps the mouse through `getBoundingClientRect`, so resizing it with CSS is safe.
- Manifest `files` adds `'html/*.css'`, `'html/fonts/*.woff2'` and `'html/img/*.webp'`.

## Item pictures

The 23 pictures in `html/img/items/` (13 bag kinds, the plain bag, 9 tools) replace upstream's under the same names,
so they match pure-whip-police's realistic items. Generated with Gemini on 2026-11-20 as two grids (bags 4x4, tools
3x3) on magenta, sliced, keyed, 256 px WebP; bags share one scale so the set lines up. Originals:
`F:/Claude-Backups/whip_evidence/assets/items-*-gemini.jpg`. If upstream changes one of these files, keep ours.

- Clear plastic shows the magenta through it: ask for bags with an opaque white back panel.
- Key with `min(r, b) - g` and remove only that shared excess; `(r + b) / 2 - g` keys pure red as half magenta and
  turned the seal strips, blood, paint chip and plier grips dark.

## Post-mortem body figure

`html/img/pure-body.webp` replaces upstream's drawn shapes with one `<image>` in the same 200x410 viewBox, drawn
through an SVG filter (feMorphology dilate minus SourceAlpha for the outline, flood-in for the fill) to keep the flat
look. Upstream's hit-spot map `REP_SPOTS` is untouched.

How the picture was made (2026-11-20, checked in a browser, not in game):

- Gemini silhouette on magenta, keyed to alpha; original in `F:\Claude-Backups\whip_evidence\assets\`.
- Scaled so the head top is y 16 and the soles y 392, centred on x 100.
- Gemini splays the hands and feet, so arms and lower legs were shifted inward per row until the hands centre on
  x 150/50 and the feet on 114/86. Row runs: the run containing x 100 is torso (no shift); below y 200 a run centred
  in x 58-142 is body or leg (legs ease in from y 250); every other run is arm (eased in from y 140).
- Two earlier rules left visible steps: "arm = run fully outside x 62-138" kinked the elbows, and "torso = run
  containing x 100" moved the hips once the crotch split them. Draw the outline large and look before using it.
