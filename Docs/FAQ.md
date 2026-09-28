# FAQ

## Using it

### macOS says the developer cannot be verified. Is it safe?

That warning means the app is not signed with an Apple Developer ID, which costs
$99 a year. It says nothing about what the app does.

Right-click Hangly in Applications, choose **Open**, and confirm. You only have to
do it once. If you would rather not take my word for any of it, the entire source
is in this repository and you can build it yourself in about a minute.

Signing and notarisation are the first item on the roadmap.

### Where is the window?

There isn't one. Hangly lives in the menu bar and has no Dock icon. Look for the
nazar in your status bar — the charm hangs from the top of your screen.

### The charm won't grab.

Only a small disc around the charm catches the pointer; everything else passes
clicks through to whatever is underneath. That is deliberate — an overlay that ate
clicks across a 740×420 region would be unusable.

The cursor turns into a hand when you are over the grabbable area.

### It disappeared.

Most likely one of:

- **The overlay is switched off.** Menu bar icon → Show Overlay (⇧⌘O). The icon is
  filled when the overlay is showing and outlined when it is hidden.
- **It is on another display.** Settings → Overlay → position.
- **Opacity is very low.** Settings → Overlay → opacity.

### Can I have more than one charm at a time?

Not today. One rope, one charm.

### Why does it launch at login?

A fresh install registers itself, because an ornament you have to remember to
start is not much of an ornament. Turn it off in **Settings → General** and it
stays off — the app only applies that default once, on first run, and respects
your choice from then on.

### Does it work on an Intel Mac?

No. Hangly is built `arm64`-only, so it will not launch on Intel hardware. A
universal build is on the roadmap; it roughly doubles the binary size, which is
the only reason it has not been done already.

### Does it work on macOS 13 or earlier?

No. macOS 14 Sonoma is the minimum, because the app relies on `@Observable` and on
`MenuBarExtra` behaviour that arrived with it.

## Privacy

### What does Hangly collect?

Nothing. No telemetry, no analytics, no tracking, no accounts.

### Does it make network calls?

None at all. The binary links no networking framework and contains no request
code. There is no setting to turn this off, because there is nothing to turn off.

### What does it store, and where?

Two things, both plain files on your Mac:

- **Settings** in `~/Library/Preferences/com.hangly.Hangly.plist`
- **Charms you import**, as images in the app's Application Support folder

Delete either at any time. Nothing leaves the machine.

### Why is it not sandboxed?

A sandboxed app cannot register itself as a login item from an arbitrary location.
That is the whole reason, and it is the trade-off that also keeps Hangly out of the
Mac App Store. The app requests no privacy-protected resource: no camera, no
microphone, no location, no contacts, no screen recording, no accessibility access.

## Performance

### Will this drain my battery?

When the rope is settled — which is nearly all the time — Hangly uses about 0.6%
of one core and 26 MB of memory. The solver stops working when nothing is moving,
no snapshot is published, SwiftUI never invalidates, and the canvas is never asked
to draw.

While the rope is actually moving it costs more, around 15% of one core, most of
which is the cost of compositing a transparent window at the display's refresh
rate rather than anything in the simulation. The rope settles within about forty
seconds of being nudged.

### Why does it use more CPU on my ProMotion display?

Because it draws at the display's rate. The physics is fixed at 240 Hz regardless,
so the rope behaves identically — only the number of frames drawn changes.

## The charms

### Can I add my own?

Yes. Drop any PNG, JPEG, WebP or HEIC onto the charm, or open the Charm Studio
with ⌘N. It removes the background, finds the subject, and hangs the result on the
rope. Imports are unlimited and live in the Library alongside the built-ins.

### Where are the collection charms from?

They are protective and lucky charms from around the world — a Turkish nazar
boncuğu, a South Indian drishti bommai, a Japanese daruma, a Finnish himmeli,
among others. They were drawn for this project.

### Can I use the artwork in my own project?

The code is MIT. The artwork is not — see [the licence](../LICENSE). Fork the app
freely; please leave the charms and the branding out of it.

### Why do the charms have different weights?

Because a bell should not swing like a straw ornament. Each charm has its own mass
and size feeding straight into the solver, so a heavy ghanta hangs steeper and
swings slower than a himmeli.

## Building and contributing

### How do I build it?

```sh
git clone https://github.com/sharancreatedthis/Hangly.git
cd Hangly && open Hangly.xcodeproj
```

⌘R. The project file is committed, so there is no generator or package manager
step and no dependencies to fetch.

### How do I see the physics debug overlay?

```sh
defaults write com.hangly.Hangly HanglyDebugRope -bool YES
```

It draws every node, every bead and a read-out of the solver's state. It exists in
Debug and Release builds only — it is compiled out of the build that ships.

### Can I contribute?

Please do — see [CONTRIBUTING.md](../CONTRIBUTING.md). Open an issue first for
anything larger than a bug fix.
