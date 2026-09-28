# Changelog

All notable changes to Hangly are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-09-12

First public release.

### The app

- **A charm hangs from your menu bar on a simulated rope.** Twenty segments,
  twenty-one nodes, anchored at the top and weighted at the charm.
- **Menu bar only.** No Dock icon, no main window. The overlay is transparent,
  click-through everywhere except the charm, and floats above other apps.
- **Settings** for overlay visibility, size, opacity, position, offsets,
  click-through, Spaces behaviour, sound and launch at login.

### Physics

- Verlet integration with Gauss-Seidel distance-constraint relaxation.
- Fixed 240 Hz timestep, so behaviour is identical at 60 Hz, 120 Hz and
  ProMotion's variable rates.
- Inextensible: no link exceeds 1.02× its rest length under any reachable input.
- Grab, drag and throw, with momentum preserved on release.
- Beads above each charm simulated as their own particles — they ride the cord,
  keep their spacing, and slide as the rope moves.
- Sleeps after 60 still frames and stops drawing entirely.

### Charms

- Eleven collection charms drawn as SVG: Nazar boncuğu, Hamsa, Nimbu-mirchi,
  Ghanta, Drishti bommai, Pánchángjié, Daruma, Maneki-neko, Horseshoe, Scarab
  and Himmeli.
- Five geometric classics: Bead, Camera, Star, Heart and Diamond.
- Each with its own mass, size, sound and palette, feeding straight into the
  solver — a heavy bell hangs steeper than a straw himmeli.
- Artwork rendered from vector at the display's real pixel density and cached
  per size.
- Charm and beads separated by measuring the artwork rather than editing it.

### Charm Library and Studio

- Browsable library with search, categories, favourites, live previews and
  one-click switching.
- Import any PNG, JPEG, WebP or HEIC by dropping it on the charm or opening the
  Studio. Background removal via Vision's foreground segmentation, with a flood
  fill fallback for flat backgrounds.
- Staged import with subject detection, method choice, live preview on a rope,
  and undo.

### Craft

- Synthesized per-material sounds — bell, metal, glass, wood, soft — with a
  volume control. Nothing plays unless you moved something.
- Reduce Motion honoured live. VoiceOver labels and full keyboard access.
- Recovery from corrupt settings, corrupt manifests and missing charm files.
- 0.6% of one core and 26 MB when settled.

### Known limitations

- **Not signed with an Apple Developer ID.** macOS will refuse the first launch;
  right-click → Open once to get past it.
- **Apple Silicon only.** Intel Macs are not supported.
- **macOS 14 or later.**
- The rope debug overlay exists in Debug and Release builds only.
- On macOS 26, large icon sizes are drawn inside the system's icon container,
  which double-frames an icon that has its own rounded background.

[1.0.0]: https://github.com/sharancreatedthis/Hangly/releases/tag/v1.0.0
