# The physics engine

How Hangly's rope is simulated: a Verlet solver with position-based constraints,
running at a fixed rate independent of the display.

Part of the [architecture documentation](Architecture.md).

---

## The rope

### Why Verlet

Verlet stores no velocity. A node's velocity is implied by the gap between where it
is and where it was. Three consequences shape the whole design:

- **Momentum after release is free.** Letting go of the charm simply stops writing
  its position; the gap the drag left behind *is* its velocity.
- **Constraints are positional.** Satisfying a link means moving nodes, with no force
  to integrate and no stiffness term to tune into instability.
- **It is stable at large constraint counts**, which an explicit spring solver is not.

### Step order

```
enforce anchor  →  integrate  →  drive held node  →  relax  →  clamp stretch
```

The anchor is pinned first so a moved anchor drags the rope this step rather than
next, which is what makes resizing the overlay look physical.

### Fixed timestep

Physics advances in fixed 240 Hz slices; the display only decides how often
`step(deltaTime:)` is called. At 120 Hz that is two slices per frame, at 60 Hz four.
Behaviour is therefore *identical* across refresh rates, which is asserted directly:
two 120 Hz frames match one 60 Hz frame to within 1e-9.

The accumulator is clamped, so a stall or a wake from sleep cannot trigger a burst of
catch-up steps that would look like the rope teleporting.

### Inextensibility

Three mechanisms, in increasing order of severity:

1. **Relaxation** pulls each link toward its rest length. It runs adaptively: up to a
   large pass budget, exiting as soon as no node moved more than a tolerance. A
   settled rope exits in a pass or two, so the large budget costs nothing except in
   the rare frame that needs it. The budget must exceed the segment count, because
   corrections propagate roughly one link per pass — below that, yanking one end
   leaves the far end unaware and the links between absorb the difference by
   stretching.
2. **A one-sided projection** then forces any remaining over-long link back to the
   ceiling, sharing the correction between its ends. An earlier version snapped the
   offending node straight onto the limit; that oscillated rather than converged,
   because with the chain pinned at both ends each sweep undid the last one's work.
3. **The drag target is clamped** onto the circle the rope can actually reach, and the
   held node follows it at a bounded speed. Without the first, pulling past the rope's
   length holds both ends further apart than the rope can span and the links have
   nowhere to go but stretch. Without the second, a teleporting node leaves the chain
   an unsolvable configuration for one frame.

Measured worst-case link stretch:

| Input | Worst stretch |
|---|---|
| Free swinging | 1.0009 |
| Hard flick, 3000 pt/s, reversing, yanked past reach | 1.0115 |
| Synthetic torture, ~7 revolutions per second | 1.027 |

The first two are within the 1.02 ceiling and are asserted as such. The third exceeds
it briefly and is asserted only to stay bounded and recover, because no pointer can
produce it and relaxation cannot fully converge inside one frame at that rate.

### Sleeping

A settled rope is indistinguishable from a still image, so the solver stops. After
half a second with every node below the rest speed, `step` becomes a no-op, the view
model stops publishing snapshots — so Observation never fires and SwiftUI never
redraws — and the display link drops from 120 to 30 per second. It still ticks,
because the same tick polls the cursor for a grab.

Measured on a 120 Hz display:

| State | CPU |
|---|---|
| Swinging | ~14% of one core |
| Settled | ~0.6% of one core |

Grabbing the charm, moving the anchor or resizing wakes it.

### Interaction and click-through

AppKit cannot pass a click through part of a window and keep the rest, so
`ignoresMouseEvents` is toggled on the whole panel once per frame based on whether the
cursor is within the charm's grab radius. `NSEvent.mouseLocation` is polled rather
than monitored: it needs no event tap and therefore no Accessibility permission. The
assignment is guarded on change, because writing it unconditionally every frame talks
to the window server often enough to keep a settled overlay measurably busy.

SwiftUI's side is narrowed by a `contentShape` of the same disc, so the gesture only
fires on the charm.


---

## Beads

Charms hang on a cord with beads threaded above them, and those beads are
simulated too. The rules they follow, and why the bead pass cannot disturb the
rope, are described in [the charm system](Charm-System.md#beads-on-the-cord).
