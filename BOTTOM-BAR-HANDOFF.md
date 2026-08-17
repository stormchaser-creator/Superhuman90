# Bottom Bar Handoff — iOS standalone nav-bar positioning bug

**Status: UNRESOLVED after 12 attempts (v3.17 → v3.28).** This document is a complete
handoff for the next agent. Read it fully before changing anything — every cheap idea has
already been tried, and the measured device data below invalidates most first instincts.

---

## 1. The problem

On the owner's iPhone (Eric Whitney, iPhone Pro Max class, 430×932pt logical, iOS 26-era),
the app runs as an installed home-screen web app ("standalone"). The bottom tab bar
(Habits / Workout / Coach / Progress / Me) **renders ~59pt above the physical bottom of the
screen**, with a dead band below it. The owner's other PWA, **CredentialDOMD**
(`/Users/whit_1/Desktop/CredentialDOMD`, deployed at credentialdomd.com), shows its tab bar
flush with the physical bottom **on the same phone** — that is the acceptance bar, literally.
Screenshots comparing both apps exist in the conversation history (Aug 16–17, 2026).

Desktop/preview browsers do NOT reproduce this. Only the owner's phone (and presumably any
Dynamic-Island iPhone running the app as a webclip) shows it.

## 2. The app (context for a fresh agent)

- Single-file React PWA: everything is in `index.html` (~6000 lines, React 18 + Babel
  standalone, inline styles, theme object `t`). Repo `stormchaser-creator/Superhuman90`,
  deployed to https://sh90.netlify.app via GitHub Actions on push to main.
- **Version bump rule:** any user-visible change must bump THREE places or CI fails /
  clients loop: `APP_VERSION` in index.html, `version.txt`, `CACHE_VERSION` in `sw.js`.
- Clients self-update (SW skip-waiting + version.txt polling). The owner's phone picks up
  a deploy within minutes of opening the app.

## 3. Ground-truth telemetry (the only evidence that matters)

The app self-reports layout geometry **once per version per device**: a "layout probe"
effect in index.html (search `sh90_layoutProbe_`) runs ~4s after launch and inserts a row
into the Supabase `app_errors` table (`area='layout'`, `detail` JSONB). This is how every
claim below was established. **Do not trust desktop previews or reasoning — ship a version
bump, let the phone probe, read the row.**

Query path: Supabase project `xwhotgkmlbqcyjpdhlbt`, via the Management API. The access
token is in the macOS keychain: `security find-generic-password -s "Supabase CLI" -w`,
strip the `go-keyring-base64:` prefix, base64-decode → `sbp_…` token → POST
`https://api.supabase.com/v1/projects/xwhotgkmlbqcyjpdhlbt/database/query` with
`{"query":"…"}`. (Details in the project memory file `supabase-access.md`. Never commit
tokens.)

Owner's phone device_id: `74b14d4e-d5d2-4444-86fd-2f2f8211aa02`.

### Probe history (owner's phone)

| version | shell CSS at the time | innerH | shellH | navBottom | bodyH | vfix | notes |
|---------|----------------------|--------|--------|-----------|-------|------|-------|
| v3.24 | shell `100dvh`, nav `position:fixed; bottom:0` | 873 | 873 | 873 | — | — | bar pinned to the SHORT viewport |
| v3.26 | shell `100vh` (standalone), nav in flow (last flex child) | 873 | **932** | **932** | — | — | layout reaches true bottom… |
| v3.27 | same | 873 | 932 | 932 | — | — | …but still LOOKS 59pt short (screenshot) |
| v3.28 | same + `.sh90-vfix` root-clip expansion | 873 | 932 | 932 | **873** | **false** | fix never armed (see §5 finding A) |

Constant on every probe: `screenH 932, outerH 932, safeAreaTop 59, safeAreaBottom 34,
visualViewport.height 873, vvOffsetTop 0, standalone true, dpr 3`.

### What the numbers prove

1. **iOS reports the standalone viewport as 873pt on a 932pt screen** (932 − 59 = 873;
   59 = Dynamic Island top inset). `env(safe-area-inset-top)` resolves 59, so the view
   believes it spans the full screen top-anchored — yet layout/visual viewport are 873.
   This reproduced IDENTICALLY on a **freshly re-added webclip** (the owner deleted and
   re-added the icon on 2026-08-16) → **NOT a stale-icon problem. It is an iOS bug.**
2. **`100vh` = 932 in this context** (larger than `innerHeight`!), `100dvh` = 873.
3. With the shell at `height:100vh` and the nav as its last in-flow flex child, the nav's
   **layout box bottom = 932 = physical screen bottom** (probes v3.26–28) — but the
   owner's screenshot on v3.27 still shows the bar ENDING ~873 with a dead band below.
   ⇒ **Something clips RENDERING at 873 even though layout extends to 932.**

## 4. Every attempt so far (ledger)

| ver | change | outcome on phone |
|-----|--------|------------------|
| v3.17 | body/html painted theme bg; shell 100dvh; nav safe-area padding | band became theme-colored but bar still high |
| v3.19–20 | padding permutations on the fixed nav (`max(14px, 4px+env)` etc.) | no change (34pt safe-area ≠ the 59pt gap) |
| v3.21 | reverted paddings; added layout-probe telemetry | diagnosis unlocked, no visual change |
| v3.22 | Credential-style SOLID slab bar + page bg = slab color (seam camouflage); dropped `maximum-scale/user-scalable` from viewport meta | still visually floats |
| icon reinstall (owner) | fresh webclip | identical probe numbers → iOS bug proven; also orphaned his data (recovered server-side, see git v3.26 message) |
| v3.25 | nav OUT of `position:fixed`, into flow as shell's last flex child; shell `100vh` when `navigator.standalone` (`.app-shell.standalone`) | layout now reaches 932 (probe) but STILL RENDERS cropped at 873 |
| v3.28 | runtime "vfix": measure `screen.height - innerHeight`, expand `html/body/#root` height by that via `--sh90-vh-shortfall` + `.sh90-vfix` class to move the `overflow:hidden` clip line; scroller got `minHeight:0` | **fix never armed: probe shows `vfix:false`, `bodyH:873`** — see §5A. Mechanism therefore UNTESTED, not disproven |

Also ruled out along the way: safe-area padding stacking (only 34pt, gap is 59), stale
service-worker HTML (verified live code via `curl` + in-page source checks), theme/color
issues (the band is painted by the root canvas — CSS *canvas painting* extends below 873,
which is why color camouflage partially worked; *element rendering* does not).

## 5. Open findings — start here

**A. The v3.28 vfix never ran on-device (probe: `vfix:false`).** The applier
(`applyVfix()` IIFE in index.html, near the top of the babel script) computes
`screen.height - window.innerHeight` **at script evaluation**. Evidently at boot
`innerHeight` is still 932 (or otherwise not 873), so shortfall=0 and the class is never
added; iOS shrinks the viewport to 873 afterwards **without firing `resize`** (listener is
attached; probe at +4s still sees no class). **First thing to try: re-run `applyVfix` on
`setTimeout` (e.g. 500ms/2s/5s), on `visibilitychange`, and in a React `useEffect` after
mount — then read the next probe (`vfix`, `bodyH`). If `bodyH` becomes 932 and the bar
still crops, the clip is compositor-level and CSS height games are dead.**

**B. Unknown: does iOS deliver touches between y=873 and y=932?** Even if rendering is
fixed, the reclaimed strip may be visually present but touch-dead. Test on-device: make a
tab occupy the strip and tap it. Fallback design if touch-dead: keep the bar's *content*
above 873 and only extend its *background* to 932 (what v3.22 approximated).

**C. Why does CredentialDOMD look right on the same phone?** Its architecture (see
`/Users/whit_1/Desktop/CredentialDOMD/src/App.jsx` ~line 1036 and `src/styles/base.css`):
- NO `overflow:hidden`/`height:100%` jail on html/body/#root — a normally scrolling document
  (`minHeight:100vh` shell, sticky header, content padding-bottom, `position:fixed` bottom
  bar with solid background + `height:64 + paddingBottom:env(safe-area-inset-bottom)`).
- Same metas as SH90 (`black-translucent`, `viewport-fit=cover`, `display:standalone`).
It has NOT been verified whether Credential's bar is truly at 932 or whether its solid
bar + identical canvas color merely hides the same 873 crop (its band and bar are nearly
the same dark color). **Worth measuring: temporarily point the probe at a Credential-style
scrolling shell, or just instrument Credential.** If Credential's bar is also at 873, then
"the Credential look" (indistinguishable seam) is the real acceptance criterion, and SH90's
remaining delta is styling: SH90's current slab uses `t.card` on a `t.bg` shell; check the
owner's screenshots — the seam is visible because the strip below 873 is canvas-painted
`t.card` while the SLAB is also `t.card` but the shell behind the labels is `t.bg`… i.e.
match Credential by making the slab's full column (bar + strip) one continuous color and
putting the TAB CONTENT at the same height Credential does.

**D. The nuclear options, in ascending cost:**
1. Adopt Credential's shell wholesale (scrolling document, sticky header, fixed solid bar,
   no root overflow lock). Most likely to just work — it demonstrably looks right on the
   owner's phone. Watch for scroll-bounce/rubber-banding regressions the overflow lock was
   protecting against (the app previously used inner-scroll to avoid iOS body-scroll quirks).
2. `position:fixed; top:calc(100vh - <barH>)` variants (100vh=932 is trustworthy) — but
   fixed elements may be clipped/positioned against the 873 viewport regardless; the
   in-flow experiment already proved layout can reach 932, so this adds little.
3. Wrap the app in a native shell (Capacitor) → App Store. Solves this AND the nephews'
   no-browser restriction (see conversation of 2026-08-17). Needs the owner's Apple
   Developer account ($99/yr).

## 6. Verification protocol (do not skip)

1. Make the change; bump all THREE version places; push to main; wait for the GitHub
   Actions run to succeed; `curl https://sh90.netlify.app/version.txt` to confirm.
2. The owner opens the app (tell him only "open the app when you get a chance") — the app
   self-updates, then auto-probes ~4s later.
3. Query the probe row (SQL above, filter `version = 'vX.Y'`, his device_id) and check:
   `vfix` (did the mechanism arm), `bodyH`/`shellH`/`navBottom` (layout), and then ask the
   owner for a screenshot ONLY if the numbers look right. Numbers first, eyes second.
4. Do NOT declare success from desktop previews — this bug does not exist there.

## 7. Owner context (important)

- He has iterated on this for days and is (justifiably) frustrated; multiple "fixed!"
  claims turned out wrong on-device. Never claim success until the probe + his screenshot
  agree. Understate, over-verify.
- Standing instruction: **"stop making me do stuff"** — no manual steps beyond "open the
  app" / "send a screenshot" unless truly unavoidable (the icon-reinstall ask burned trust
  AND orphaned his data — recovered, but don't repeat that class of mistake: if you change
  device identity, migrate `device_id` rows server-side FIRST, see git message v3.26).
- Other agents/routines touch this repo nightly (local scheduled task `sh90-nightly-
  maintenance` at 4am Denver processes support tickets; it is told to IGNORE `area='layout'`
  telemetry rows). Don't be surprised by its commits.
- The probe fires once per version per device and writes to `app_errors` — bump the version
  every attempt or you get no fresh data.

## 8. Current relevant code (v3.28, index.html)

- `applyVfix()` IIFE — near top of the babel script, right after `DEVICE_ID` (search
  `sh90-vfix`). Suspected boot-timing bug (§5A).
- `.sh90-vfix` CSS — in the `<style>` block (search `--sh90-vh-shortfall`).
- Shell: `.app-shell` / `.app-shell.standalone` CSS + the root div
  `className={"app-shell" + (navigator.standalone ? " standalone" : "")}`.
- Root lock: `html, body, #root { height: 100%; overflow: hidden; }` in the `<style>`
  block — **this is the clip suspect**.
- Nav: `<div id="sh90-nav" …>` — in flow, last flex child, solid `t.card`, borderTop,
  `paddingBottom: calc(6px + env(safe-area-inset-bottom))`.
- Page paint: `useEffect` setting `document.body/documentElement.style.background =
  THEMES[theme].card` (search `sh90 layout` comments).
- Probe: `useEffect` with `sh90_layoutProbe_` key; reports via `reportAppError("layout", …)`.
