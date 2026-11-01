# Tier-2 geometry harness (SFOS 5.2 / Qt 5.6.3 aarch64)

Instantiates the REAL page (`qml/pages/DevicePage.qml` copied next to the
harness) with a fake `client` and dumps the item tree with RELATIVE and
**ABSOLUTE** (`mapToScene`) coordinates. Catches silent rendering bugs the
Tier-1 compile check (`tools/qmlcheck`) cannot see: rows that never appear,
anchoring that silently fails (a failed binding leaves x/y at 0), wrong
margins.

## Why sources live in the repo
An earlier copy lived in `/tmp` and was wiped by a reboot, losing the whole
harness. Sources are version-controlled here now; only build artifacts go
to a `/tmp` build tree.

## Build + run (proven recipe)
```bash
cd /mnt/2ssd/coding/tailscale
P=/tmp/tailscale-<n>-aarch64        # FRESH n (old dirs may have foreign-uid files)
rm -rf $P && mkdir -p $P/harbour-tailscale-0.0.14
tar cjf - --exclude=.git --exclude=dist -C repo . | tar xjf - -C $P/harbour-tailscale-0.0.14
mv $P/harbour-tailscale-0.0.14/rpm $P/rpm          # mb2 tree needs rpm/ at top
chmod -R a+rwX $P
# mb2 + toolchain only exist INSIDE the SDK container; the container rootfs
# IS the aarch64 target, so the harness binary runs natively in it:
docker run --rm -v "$PWD":/home/mersdk/proj \
  coderus/sailfishos-platform-sdk-aarch64:5.2.0.15 \
  bash -lc 'cd /home/mersdk/proj && mb2 build-shell bash -lc "
     cd tools/qmlgeom && qmake && make 2>&1 | tail -3 &&
     echo === PROBE ===  && ./testgeom probe.qml status.json 2>&1 | grep -E \"PROBE|Error|error\" | head -20 &&
     echo === HARNESS2 === && ./testgeom harness2.qml status.json 2>err2.txt | grep -vE \"QQml|QQuickState|QQuickProperty|QQuickSequential|QQuickNumber|QQmlComponent|QQmlTimer|QQuickBehavior|VerticalScroll|QQuickItem$\" | head -80
     grep -iE \"error|undefined|not defined|ReferenceError\" err2.txt | head -10"'
```
Notes:
- `mb2 build-shell` must run from the TOP of the mb2 tree (the dir with `rpm/`),
  otherwise: "Fatal: The command needs to be used from the top of a build tree."
- `make`/`qmake`/`g++` are only on PATH inside `build-shell`.
- The target root inside the image: `/srv/mer/targets/SailfishOS-5.2.0.15-aarch64/`
  (grep it for Silica QML / Theme facts; the real Silica QML lives at
  `usr/lib64/qt5/qml/Sailfish/Silica/`, NOT `usr/share/qml`).
- PROBE RESULTS (2026-10-31, run with `./testgeom probe.qml status.json`):
  - `Theme.pageHeaderHeight` → **undefined** (does not exist — never use it)
  - `Theme.itemSizeLarge` = 110, `itemSizeSmall` = 80, `paddingLarge` = 24
  - `Screen.topCutout` **EXISTS** (Jolla-patched Qt), `.height` = 0 in the
    harness (no notch headless); on the phone it is the real notch height
  - Silica's `PageHeader` already folds `topCutout.height` into its height
    in portrait (`_minimumTopMargin`) — bind content to `pageHeader.bottom`,
    do NOT add the cutout yourself
  - **Under minimal QPA there is no render loop → positioner layout (Column,
    Row) and anchor RE-RESOLUTION never run.** The harness can verify
    compilation, instantiation, and first-pass binding values, but NOT final
    geometry of positioner-managed children. Don't "verify" Row/Column
    layout in the harness — it is an artifact-free zone for instantiation
    only.
- `QT_QPA_PLATFORM=minimal` is set inside testgeom.cpp; `isVisible()` is
  always false there — use the `visible` property / geometry instead.
- Qt 5.6 QML gotchas: `Timer` has `repeat` not `repeats`; no
  `QJSValue::fromVariant`; `QString::arg` needs `%1`; `QQmlConnections`
  never fires without a scene (drive state from the harness QML).

## Verified facts (2026-10-31, see probe output)
- `Theme.pageHeaderHeight` — see probe result before relying on it.
- Binding failures in QML are SILENT: a bad binding leaves the property at
  its default (e.g. topMargin → 0) with only a console warning. Always dump
  ABSOLUTE coordinates, not just relative.
