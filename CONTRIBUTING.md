# Contributing to Hangly

Thanks for looking. Hangly is a small, opinionated app, and contributions are
genuinely welcome — especially bug reports from Macs I do not have.

## Before you start

For anything larger than a bug fix, **open an issue first**. Hangly has a fairly
specific idea of what it wants to be, and it would be a shame for you to build
something well that turns out not to fit. A short issue saves that.

Good first contributions: new charms, bug fixes, accessibility improvements,
multi-display behaviour, and anything that makes the settled CPU cost lower.

## Getting set up

```sh
git clone https://github.com/sharancreatedthis/Hangly.git
cd Hangly
open Hangly.xcodeproj
```

The project file is committed, so there is no generator or package manager step.
Optional tooling:

```sh
brew install swiftlint   # runs as a build phase; the build warns if it is missing
brew install xcodegen    # only needed if you add or remove files
```

If you add or remove a source file, regenerate the project so the change is
reviewable as a diff of `project.yml` rather than of `project.pbxproj`:

```sh
xcodegen generate
```

## Coding standards

The house style is already in the code; read a neighbouring file before writing a
new one. The rules that matter:

**SwiftLint must pass with zero violations.** The configuration is in
`.swiftlint.yml` and it runs as a build phase. Do not add exclusions to make a
violation go away — restructure the code instead.

**Swift 6, strict concurrency, no warnings.** The whole project builds with
`SWIFT_STRICT_CONCURRENCY: complete`. Everything user-facing is `@MainActor`.

**Comments explain why, not what.** The code already says what it does. A comment
earns its place by explaining a decision, a trade-off, or a mistake that was made
once and should not be made again. If a comment would only restate the line below
it, delete it.

```swift
// Bad:  Increment the counter.
// Good: Assign only on change: an unconditional write would invalidate the view
//       several times a second even with the rope asleep.
```

**No dependencies.** Hangly links nothing but Apple frameworks, and that is a
feature. A pull request that adds a package will be declined unless it removes
substantially more code than it adds.

**Tests are not optional for logic.** Anything with a rule in it gets a test —
physics, settings decoding, charm selection, the launch-at-login policy. Views and
window plumbing are exempt. If you change the solver, include a test that would
fail without your change.

**Do not regress the idle cost.** The settled overlay runs at about 0.6% of one
core because nothing redraws when nothing moves. No timers, no polling, no
per-frame work that is not driven by actual motion. Filters in the render path are
effectively banned; see the note in `RopeCanvasView`.

## Pull request workflow

1. **Fork and branch.** Name the branch for what it does: `fix/rope-snap-on-resize`,
   `charm/finnish-himmeli`.
2. **Keep it focused.** One concern per pull request. A formatting sweep mixed into
   a bug fix makes both harder to review.
3. **Check it locally** before pushing:
   ```sh
   xcodebuild -project Hangly.xcodeproj -scheme Hangly -configuration Debug test
   swiftlint
   ```
4. **Write the commit message for whoever reads it in a year.** A one-line summary
   in the imperative, then a paragraph on *why* if the change is not obvious.
5. **Open the pull request** and fill in the template. Say what you changed, why,
   and how you verified it. Screenshots or a screen recording for anything visual.
6. **Expect a review.** I will be picky about naming, comments and tests — not to
   be difficult, but because this codebase is meant to stay readable by one person
   returning to it after six months away.

CI runs SwiftLint, a build and the full test suite on every pull request. It has to
be green before merge.

## Adding a charm

Collection charms are SVG. The pipeline expects a single tall artwork — cord at
the top, optional beads on it, then the charm — and measures where the charm
begins rather than requiring you to cut the file up. To add one:

1. Drop the SVG into `Assets/Charms/`.
2. Add an entry to `CollectionCharmCatalog`, including its mass, radius, sound and
   how many of the solid parts at the top are beads.
3. Add its metadata to `Hangly/Assets/CharmLibrary.json`.
4. Run `./Scripts/sync-charm-assets.sh` then `./Scripts/generate-charm-previews.sh`.
5. Run the tests — they will tell you by name if the artwork cannot be split the
   way the catalogue claims.

[Docs/SVG-Import.md](Docs/SVG-Import.md) explains the measurement in detail.

## Reporting an issue

Use the templates — they ask for the things that are always needed and never
volunteered. In particular:

- **Your macOS version and Mac model.** "It doesn't work" on an Intel Mac has a
  known answer.
- **Which build**, and whether it came from a release or your own compile.
- **What you expected and what happened instead**, in that order.
- **A screen recording** for anything about motion. Rope behaviour is very hard to
  describe in words and very easy to show.

For anything that looks like a security problem, use
[the security policy](SECURITY.md) instead of a public issue.

## Code of conduct

Be decent. Assume the other person is trying. Criticise the code, not whoever
wrote it. That is the whole policy; if it ever needs to be longer, something has
already gone wrong.
