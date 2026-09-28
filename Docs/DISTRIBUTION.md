# Hangly — distribution report

Prepared 12 September 2026, against `MARKETING_VERSION 1.0.0 (1)`.
Measured on an Apple Silicon MacBook Air, macOS 26.6.2, Xcode 26.6.

This covers everything short of packaging. **The DMG has not been created**, and
there is one blocker to clear before the app can run on anybody else's Mac — see
[Before you ship](#before-you-ship).

---

## 1. What ships

| | |
|---|---|
| Bundle | `Hangly.app`, 5.2 MB |
| Executable | 1.14 MB, arm64, stripped |
| Bundle identifier | `com.hangly.Hangly` |
| Version | 1.0.0 (1) |
| Minimum system | macOS 14.0 |
| Category | Utilities |
| Resources | `Assets.car`, `AppIcon.icns`, `CharmLibrary.json` |
| Runs as | Menu bar accessory (`LSUIElement`), no Dock icon, no main window |
| Network | None. The binary links no networking framework and contains no request code |
| Privacy prompts | None required: no camera, no microphone, no location, no contacts |

The app asks the system for three things: a login item (only when the user turns
it on), an audio output node (only while a sound is playing), and Vision's
foreground-instance segmentation (only while the Studio is isolating a subject).

## 2. Configurations

A third configuration now sits beside the two that existed.

| Configuration | For | Optimisation | Development surfaces |
|---|---|---|---|
| **Debug** | Development | `-Onone`, testability, previews | All present |
| **Release** | Profiling, and testing what ships | `-O`, whole-module | All present |
| **Production** | Distribution | `-Osize`, whole-module, thin LTO | **All compiled out** |

`Release` deliberately keeps the development overlay and the diagnostic logging.
It is the configuration to profile in, because it is optimised but still
observable. `Production` is what gets archived — the scheme's Archive action now
points at it.

```sh
xcodebuild -project Hangly.xcodeproj -scheme Hangly -configuration Production build
```

## 3. What Production removes

Everything below is removed by the compiler, not disabled at runtime, via the
`HANGLY_PRODUCTION` compilation condition. None of it reaches the shipped binary.

| Surface | What it was | Evidence it is gone |
|---|---|---|
| Diagnostic logging | 19 `info`/`debug` call sites | `HANGLY ROPE DEBUG`, `bootstrapped`, `Overlay panel created` all present in the Release binary, all absent from Production |
| Rope debug overlay | Node markers, bead rings, the read-out panel | `RopeCanvasView+Debug` compiled out whole |
| Debug state polling | A `UserDefaults` read five times a second, forever, while the rope was awake | `refreshDebugState` and its two published properties compiled out |
| Debug default key | `HanglyDebugRope` | `AppConstants.Debug` compiled out |
| Artwork override | `HANGLY_CHARM_SVG_DIR` could repoint charm artwork at any folder | String absent from the Production binary; the bundle is the only source |
| Cache purge | `VectorImage.purge()`, used only by tests | Compiled out |
| Launch-time artwork audit | Loaded all eleven SVGs at launch to log any missing one | Compiled out; the test suite enforces the same thing at build time |
| SwiftUI previews | One `#Preview`, plus preview registration metadata in every file | `ENABLE_PREVIEWS` is now Debug-only; the preview is `#if DEBUG` |
| SwiftLint build phase | Ran on every build | Skipped for Production; it is a development gate, not a packaging step |

**Logging that stays.** All 13 `error` and 4 `warning` sites ship. They fire on
things a user might report — a settings document that would not decode, a charm
file that has gone missing, an import that failed — and they are what makes such
a report actionable. Only the moment-to-moment chatter was removed.

One caveat on the evidence: Swift stores strings of 15 bytes or fewer inline in
the instruction stream rather than as data, so `strings` cannot see them either
way. The literals verified above are all longer than that, which is why they are
the ones quoted.

## 4. Optimisation results

| | Release | Production | Change |
|---|---|---|---|
| Executable | 2,981 KB | 1,140 KB | **−62%** |
| Bundle on disk | 5.3 MB | 3.4 MB | **−36%** |
| Symbols in binary | 11,896 | 1,255 | stripped |
| Launch → overlay on screen | 218 / 229 ms | 211 / 213 ms | ~10 ms faster |
| CPU, rope moving | ~15% | ~15% | unchanged |
| CPU, settled | 0.60% | 0.56% | unchanged |
| Memory, settled | 26 MB | 26 MB | unchanged |
| Memory, peak | — | 42 MB | — |

Where the size went: `-Osize` over `-O`, thin LTO, stripping the binary (with a
dSYM kept aside for symbolication), asset catalogue compiled for space, and the
removal of preview metadata.

Startup is dominated by loading AppKit and SwiftUI, so the ~10 ms saved by not
reading all eleven SVGs at launch is real but small — two medians of eight runs
each, interleaved, both favouring Production.

Runtime cost is unchanged, and the honest reading of that is that there was
nothing much to win: idle was already at 0.6% of a core and 26 MB. The two figures
above were measured back to back with exactly one instance of the app running and
the rope asleep, and they differ by less than the run-to-run spread. Removing the
five-times-a-second `UserDefaults` read is worth having on principle — a settled
ornament should do nothing at all — but it is below what this machine can measure.
Anything drawn from earlier readings in this session should be discarded: several
were taken with two builds running at once, which inflates both numbers.

`-Osize` was chosen over `-O` deliberately. The only per-frame work in the app is
the rope solver, which measures 0.02 ms a frame — there is no hot loop here that
would rather have the code inlined than the download be smaller. The CPU figures
above confirm it cost nothing.

## 5. Verification

| Check | Result |
|---|---|
| Clean build, all three configurations | Succeeds |
| Compiler warnings | **None** |
| SwiftLint | **0 violations** |
| Test suite | **146 pass, 0 fail** |
| Asset catalogue | 11 charm artworks (all vector), 16 previews, AppIcon, AccentColor |
| Charm metadata | 16 entries, one per charm, enforced by test |
| Debug entitlements | **None.** `get-task-allow` absent |
| Entitlements total | One: `com.apple.security.app-sandbox = false` |
| Hardened runtime | **Enabled** (`flags=0x10002(adhoc,runtime)`) |
| Signature | Valid on disk, satisfies its designated requirement |
| dSYM | Produced; UUID matches the stripped binary |

The one build warning that existed — no app category set — was fixed by adding
`LSApplicationCategoryType`.

## 6. Before you ship

Four things stand between this build and a public download. The first is a
blocker; the rest are decisions.

**1. The signature is ad-hoc.** Gatekeeper will refuse this build on any Mac but
this one. Before distribution it needs a Developer ID Application certificate and
notarisation:

```sh
# In project.yml, replace CODE_SIGN_IDENTITY "-" with "Developer ID Application"
# and set DEVELOPMENT_TEAM, then:
xcodebuild -project Hangly.xcodeproj -scheme Hangly -configuration Production archive \
  -archivePath build/Hangly.xcarchive
xcrun notarytool submit ... --wait
xcrun stapler staple Hangly.app
```

Hardened runtime is already on, which notarisation requires, and there are no
debug entitlements to strip, which is the usual reason a submission is rejected.

**2. Apple Silicon only.** `ARCHS` is `arm64`. Intel Macs cannot run this build at
all. Change to `$(ARCHS_STANDARD)` for a universal binary — it roughly doubles the
executable size, to about 2.2 MB, which against a 3.4 MB bundle is a fair trade if
Intel reach matters.

**3. macOS 14 and later.** Sonoma or newer, which is the price of `@Observable`
and the `MenuBarExtra` behaviour the app relies on.

**4. One placeholder.** The category is set to Utilities — a menu bar accessory's
conventional home, though Entertainment is arguably the better fit for a desktop
ornament. It is a one-line change in `Hangly/App/Info.plist`.

**Not the Mac App Store.** The app ships unsandboxed, because a sandboxed build
cannot register itself as a login item from an arbitrary location. Direct
distribution only, unless that requirement is dropped.

## 7. Packaging

One command builds the app and the disk image:

```sh
./Scripts/build-dmg.sh              # Production — what ships
./Scripts/build-dmg.sh Release      # Release, for comparison
```

**Exact outputs**, both replaced on every run:

| Path | What |
|---|---|
| `dist/Hangly.app` | The built application, 5.2 MB |
| `dist/Hangly.dmg` | The compressed disk image, 5.2 MB |

The script uses only what ships with macOS and Xcode — `xcodebuild`, `hdiutil`,
`tiffutil`, `osascript`, `SetFile`. There is no packaging dependency to install.

### What it does, in order

```sh
# 1. Build, from clean
xcodebuild -project Hangly.xcodeproj -scheme Hangly \
  -configuration Production -derivedDataPath "$WORK/DerivedData" clean build

# 2. Stage the image's contents
cp -R "$BUILT_APP" "$STAGING/Hangly.app"
ln -s /Applications "$STAGING/Applications"
xattr -cr "$STAGING/Hangly.app"          # nothing of this machine travels with it

# 3. Draw the background at both resolutions and combine them into one TIFF
swiftc -O -parse-as-library -o background Scripts/GenerateDMGBackground.swift
./background "Assets/Charms/Nazar Boncuğu.svg" "$WORK/bg"
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" \
  -out "$STAGING/.background/background.tiff"

# 4. Writable image, so Finder can be asked to lay the window out
hdiutil create -srcfolder "$STAGING" -volname Hangly -fs HFS+ -format UDRW -ov rw.dmg
hdiutil attach rw.dmg -noautoopen        # must mount at /Volumes: Finder addresses
                                         # a volume by name and cannot see one
                                         # mounted elsewhere or hidden from browsing

# 5. Finder writes the .DS_Store — icon view, 112 pt icons, both positions,
#    the background picture, no toolbar, no status bar
osascript <<'…'

# 6. Compress, taking whichever is smaller
hdiutil convert rw.dmg -format ULFO -o lzfse.dmg               # LZFSE
hdiutil convert rw.dmg -format UDZO -imagekey zlib-level=9 -o zlib.dmg

# 7. Verify
hdiutil verify dist/Hangly.dmg
codesign --verify --deep --strict dist/Hangly.app
```

### The window

The background is drawn against the same numbers the script positions the icons
with, so the two cannot drift apart. Both live at the top of their files.

| | |
|---|---|
| Window | 620 × 420 points |
| Icon size | 112 pt |
| `Hangly.app` | (170, 238) |
| `Applications` | (450, 238) |
| Background | `.background/background.tiff`, 620 × 420 and 1240 × 840 in one file |
| Volume icon | The app's own `AppIcon.icns` |

The background is the shipped Nazar artwork hanging from the top edge of the
window, exactly as the app hangs from the top of the screen — the same SVG the app
draws, not a copy of it. Between the two icons is a dashed arrow, and beneath them
the instruction and the system requirements.

### Compression

LZFSE and zlib-9 come out close on this content, so the script measures both every
time and ships the smaller. This build went out as **ULFO (LZFSE), 5.2 MB**. Most
of the bundle is the asset catalogue, and most of the growth since the first build
is the photographic app icon: a full 16–1024 set of a 3D render adds about 1.8 MB
that flat vector artwork did not. The disk image carries a second copy at up to
512 px as its volume icon, capped there deliberately — the 1024 slice would add
another megabyte for a resolution nothing asks a disk for.

## 8. Verification of the built image

| Check | Result |
|---|---|
| `hdiutil verify` | Checksum valid |
| Image contents | `Hangly.app`, `Applications` → `/Applications`, `.background/`, `.DS_Store` |
| Background | Two representations in one TIFF: 620 × 420 and 1240 × 840 |
| `.DS_Store` | `backgroundType: 2` (picture), alias resolves to `Hangly:.background:background.tiff` |
| Icon positions | Read back from the image's own `.DS_Store`: app (170, 238), Applications (450, 238) |
| Icon size | 112 pt, arrangement none |
| Build cruft | `.fseventsd` emptied, `.Trashes` removed, extended attributes cleared |
| App inside | 1.0.0, arm64, signature valid, satisfies its designated requirement |
| Volume icon | `.VolumeIcon.icns` present, custom-icon bit set on the volume |
| Install | Copied to `/Applications` from the mounted image and launched: 0.75% CPU settled, 24 MB |

### Gatekeeper, tested rather than assumed

A copy of the image was given the quarantine attribute Safari applies to a
download, and then assessed:

```
$ spctl -a -vvv -t open --context context:primary-signature Hangly.dmg
Hangly.dmg: rejected
source=no usable signature

$ spctl -a -vvv /Volumes/Hangly/Hangly.app
/Volumes/Hangly/Hangly.app: rejected
```

**This is the blocker from section 6, demonstrated.** Anyone who downloads this
image will be told the developer cannot be verified. It is not a fault in the
packaging — the image and its layout are correct — it is the absence of a
Developer ID signature and notarisation. Everything else on this page is ready.

### What "a clean user account" could and could not be tested

Creating a second macOS account needs admin credentials and is an invasive change
to your machine, so I did not make one. What a clean account would exercise, and
where each stands:

| | |
|---|---|
| Gatekeeper on a quarantined download | **Tested. Rejected** — see above |
| Mounting and reading the image | Tested |
| Dragging the app to `/Applications` | Tested |
| Launching the installed copy | Tested |
| First-run defaults with no preferences | Verified separately in section 4 by decoding an empty settings document; not exercised as a live first launch, because that would mean deleting your own settings |
| A login item registered by an account that has never granted one | Not tested |

To close the last two yourself: `System Settings → Users & Groups → Add Account`,
log in as it, and open the DMG. Until the app is signed and notarised, expect the
Gatekeeper refusal above — right-click → Open is the workaround, and is exactly
what you do not want to ask strangers to do.

## 9. Distribution checklist

Ready:

- [x] Production configuration, development surfaces compiled out
- [x] Clean build, no compiler warnings, 156 tests passing, lint clean
- [x] Hardened runtime enabled
- [x] No debug entitlements (`get-task-allow` absent)
- [x] dSYM produced, UUID matched to the stripped binary
- [x] App category set
- [x] Copyright names its owner
- [x] `Hangly.app` and `Hangly.dmg` produced and verified
- [x] Custom Retina background, icon layout, Applications shortcut
- [x] Image compressed and stripped of build cruft
- [x] Installs and runs from `/Applications`

Before it goes anywhere:

- [ ] **Developer ID Application certificate** — replace `CODE_SIGN_IDENTITY "-"`
      and set `DEVELOPMENT_TEAM` in `project.yml`
- [ ] **Notarise**, then staple both the app and the image:
      ```sh
      xcrun notarytool submit dist/Hangly.dmg --apple-id … --team-id … --wait
      xcrun stapler staple dist/Hangly.dmg
      ```
- [ ] **Re-run `spctl`** against a freshly quarantined copy; it must say `accepted`
- [ ] Decide on **Intel**: `ARCHS = arm64` excludes every Intel Mac
- [ ] Confirm the app category — Utilities is set; Entertainment may suit better
- [ ] Test on a Mac that has never seen this app
- [ ] Decide where it is hosted, and whether the version in `project.yml` is the
      one you want to be 1.0.0 (1)
