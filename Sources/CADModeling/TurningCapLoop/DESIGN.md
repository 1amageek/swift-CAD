# Turning Cap Loop

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. Builds the sewing request that rounds or
chamfers every edge of one loop of a planar cap whose walls rise from the cap at some edges and
fall from it at others — a boss's foot running into a step's straight edges, Plasticity's Fillet
(Y-blend video, Attempt to create Y-Blend off).

## Responsibilities and Boundaries

| Owns | Does not own |
|---|---|
| Admission of a whole selected loop of lines (beside planes square to the cap) and arcs (beside coaxial cylinders) with walls on both sides of the cap | Choosing the treatment path (`EdgeBlendFeatureEvaluator.evaluateFillet`) |
| Each edge's band, the joints, mitres and turning corners between bands | Sewing, body replacement and volumetric validation (CADKernel sewer, evaluator) |
| The corner patch and the descent it rests on along the rising wall | The Coons construction itself (`ExactHermiteCoonsSurfaceBuilder`) |
| Rewriting the cap, the walls and the edges leaving the loop's corners | Loops turning at tangent joints, mitres beside arcs, corners whose falling wall is a cylinder (refused, `FIXME(INCOMPLETE_IMPLEMENTATION)`) |

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | `CapLoopBlendBuilder.Section`, `SourceBRepFacePatchBuilder`, `ExactFacePcurveBuilder` | Fillet dispatches whole turning loops here after cap loops. | `admits` must stay false for loops other paths own (walls all one way). |
| [SquareSurface Coons builder](../DESIGN.md) | depends on | `ExactHermiteCoonsSurfaceBuilder.buildAllSides` with curved and planar supports | Builds the corner patch tangent to both bands and the falling wall. | Curved supports are certified within an angular allowance, refined until met. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | `BRepSewingRequest` | Sews bands, corner patches and rewritten faces. | Each edge use carries its own stable identity. |

## Architecture

```text
selected edges ──► loop(of:) ── segments (edge, wall, rise ±1, arc?) + cap normal + inward sense
                       │
                       ▼
corners: joint (tangent, same rise) │ mitre (sharp, same rise, lines) │ turn (sharp, rise changes)
                       │
     rows at each corner (section; carried onto the bisecting plane; at the cap point's foot)
                       │
     bands: line → ruled rational B-spline (exact cylinder/plane), arc → turned rows (exact torus/cone)
                       │
     turns: P (cap contacts meet), Q, T (band ends on the walls), S (edge between walls, distance down)
            descent Q→S on the rising wall (rational quartic, vertical at S) + Coons corner patch
                       │
     faces: cap → its contacts; walls → contacts (+ S→T or descent); edges leaving corners cut
```

## Contracts and Invariants

- Input: every edge of one loop of a planar face of a single-shell solid; each a line whose other
  face is a plane square to the cap, or an arc whose other face is its coaxial cylinder; the wall's
  side of the cap read beside the edge's middle (a wall may cross the cap's plane elsewhere); at
  least one edge rising and one falling.
- Bands are exact for a round: a line's rows translate (cylinder), an arc's rows turn (torus); at a
  mitre the row is the section carried along the edge onto the bisecting plane, which is the other
  edge's carried there too (checked).
- At a turn the cap point `P` is the meeting of the two cap contacts nearest the corner; each band
  ends on its section at `P`'s foot, which must lie strictly within its edge. The edge between the
  walls runs down from the corner (straight, along the cap's normal) and is cut at `S`.
- The descent lies on the rising wall exactly and arrives at `S` straight down the edge, so the
  corner patch can be tangent to the falling wall's plane along `T→S`. The corner patch is tangent
  to both bands within `TurningCapLoopCornerPatchBuilder.angularAllowance` (the bands ask opposite
  twists at `P`, so the stray concentrates in the first spans from `P`) and meets the rising wall
  along the descent at the angle the walls meet along the edge.
- The patch's sides are cubic splines through the exact curves' points and tangents within an
  eighth of the distance tolerance; the sewn edges keep the exact curves.
- With Fillet's Attempt to create Y-Blend (`FilletFeature.yBlend`, `splitsCorners`) each corner
  patch is three faces of the same surface meeting at its middle: its isocurves u = ½ (from the
  rising section's middle to the falling wall contact's middle) and v = ½ (from the falling
  section's middle) are their shared edges, and the bands' end sections and the falling wall's
  contact beside the patch are split at their middles to meet them. The shape and volume are
  those without it; only the topology changes, as the page states ("better topology").
- Every edge use carries a stable identity unique in the request; edges leaving the loop's corners
  are cut to the corner's image (the blend's wall distance along them) and must be longer.

## Failure, Concurrency, and Constraints

Unsupported shapes throw `unsupportedCapability` before any patch is built; geometric failures
(contacts that do not meet, a blend too large for its edges, a side that cannot be followed within
64 spans, a patch that cannot meet its bands within the allowance) throw typed errors. The builder
is a value type without shared state. A corner patch is a bicubic of at least 16 spans per
direction; evaluation of the whole feature takes about two minutes in debug builds.

## Verification and Change Impact

`StepBossFilletTests.aStepsTopLoopRoundsIntoTheBossRisingFromIt` rounds the step's top loop (two
arcs and three lines) beside a cylinder and checks volumetric validity, the volume against the
bands' exact sections (the corner patches within their cells), every band at the radius from its
axis, and the cut upright edges and seam; with Y-Blend the same volume, four more faces and the
six trivalent vertices of the two Ys. Changes to `ExactHermiteCoonsSurfaceBuilder` (corner jets,
curved-support rows) or to `CapLoopBlendBuilder.Section` re-run this test and `SquareSurfaceTests`.
