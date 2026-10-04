# Certified Curved Path-Normal Sweep

## Purpose and Scope

Child of [CADModeling](../DESIGN.md). Builds a path-normal Sweep along a curved
path within an explicit positional allowance: the section moves rigidly with the
path's minimal-rotation frame. There are no child components.

## Responsibilities and Boundaries

Owns admission (allowance, corners, bend reach, self-overlap), path subdivision,
the frame, and the Hermite tensor rows with their error bound, plus the cap and
side face requests. Existing Sweep owns section resolution, path chaining and the
distance prefix, sewing and semantic topology, and Booleans. Exact routes keep
precedence: straight paths, and solid sweeps along one circular arc (the exact
revolve), never take this plan. One guide steers the section (`CurvedSweepGuideLaw`); two or
more guides are refused with `FIXME(INCOMPLETE_IMPLEMENTATION)` in the plan. A path with corners
takes `MitredPolylineSweepBuilder`, which hands this plan each smooth curved leg with the section
placed where the leg starts; the plan itself still refuses a corner.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | Sweep evaluation | routing and body building | exact routes first |
| [CertifiedTwist](../CertifiedTwist/DESIGN.md) | coordinates with | allowance semantics | the same allowance bounds either approximation | an allowance alone no longer requests a twist |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | `OutwardScalarInterval`, `IntervalDerivativeJet` | derivative enclosures | order ≤ 6 |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | preflight planning | `SweepEvaluationPlanService` admits by building the plan | same admission as evaluation |

## Architecture

```text
path spans (rational Bezier) ─► interval homogeneous jets per piece (order 5)
        │                          ├─ position, unit tangent (order 4)
        │                          ├─ least rotation R(t_ref → t)  (frame restarts where 1 + t_ref·t ≤ 0.5)
        │                          └─ moved control points p + R v  (order 4)
        ▼
 adaptive halving until Σ|S⁽⁴⁾|/384 ≤ allowance/2 and reach·κ < 1
        ▼
 Hermite rows (ends shared between pieces) ─► tensor patches ─► side faces
                                                        └────► start / end caps ─► sewer
 separation certificate over non-adjacent pieces
```

## Contracts and Invariants

- The section point `P` goes to `p(s) + R(s)(P − p(0))`; `R` maps the start
  tangent to the tangent at `s` by least rotations, restarting its reference where
  the tangent turns too far. For a planar path this is the rotation-minimizing
  frame; for a non-planar path the section's roll rate may change at a restart.
- A section point is its offsets along the start tangent and two lateral axes the frame
  carries: `S = p + s·(along·t + (a cosθ − b sinθ)·E1 + (a sinθ + b cosθ)·E2)`. The twist
  `θ` and scale `s` laws are read at the fraction of the path's arc length run (numerical
  quadrature) at every piece's ends and run linearly in the piece's parameter between them;
  their derivative enclosures (`δᵏ` times the enclosed cosine and sine) enter the jets, so the
  Hermite bound covers them. A twist lets the lateral extents turn within their radius and a
  scale grows the reach for the bend and overlap certificates.
- One guide replaces the laws (`CurvedSweepGuideLaw`, the straight-path guides' rules read in
  the moving frame): at each station the guide crosses the plane across the path (bisection on
  its spans, searching on from where it was last met) at a lateral offset `g`; Chord turns the
  section by `arg g − arg g₀`, Point also scales it by `|g|/|g₀|`, Curve turns it by
  `arg g − arg q` with `q` the section's point as far from the path as `g`, continued along the
  section. The law is read at every piece's ends and middle; a piece whose linear law strays
  from the middle's by more than a quarter of the allowance at the section's reach is halved
  (to depth 40, on a stack rather than by recursion), and one no longer than sixteen modeling
  distances that still strays is refused (a Curve guide starting square to the section's side
  turns it as the square root of the run). The bend and overlap certificates take the largest
  scale the accepted pieces reach. `CurvedPathGuidedSweepTests` own a Point guide scaling a
  square by `1 + t` and a Chord guide leaving it as it is (their exact Pappus volumes), a Curve
  guide turning a 30°-turned square so its side keeps touching it (volume, the guide's end on
  the end cap's outline), and the refusal from a side's square.
- Each piece's rows are the cubic Hermite interpolant of every moved control point
  in the piece's own parameter. Its error is at most `Σ_c sup|S_c⁽⁴⁾| / 384` (an L1
  bound) plus the rows' rounding, both enclosed, within the allowance. Positive
  weights repeat along the path, so the surface error is at most the control error.
- A piece's end row is the next piece's start row, so side faces share edges.
- The section never reaches past the path's bend on any piece (`reach · κ < 1`).
- Two pieces that do not touch are proved apart: their path boxes are farther
  apart than twice the reach, or the plane across the path at the middle of a piece
  between them has one wholly behind and the other wholly ahead. Each piece is
  judged in eighths, each bounding the path point, tangent and the frame's two
  lateral axes, with the section's extent along the start tangent and those axes
  (so a section spread along a planar path's binormal does not count as tilt).
  Otherwise the sweep is refused as possibly self-overlapping.
- A smooth closed path (`CertifiedCurvedPathSweepPlan.closed`, Plasticity's capless ring) runs
  the loop once with no caps, one shell per section loop. The path must be G1 where it closes; the
  frame comes back turned by the loop's holonomy (`closingTurn`, measured about the start tangent
  between the start lateral axis and the end piece's), so the plan is rebuilt with a twist law
  `[0, −turn]` and repeated (at most six times) until the end row lies within the allowance of the
  start row, then the last row is snapped onto the first so the seam shares one edge. Twist, scale
  and guides are refused on a closed path. The overlap certificate wraps: the last and first pieces
  touch, and the pieces between a pair are taken around the loop.
- Refusals of what the sweep asks for report the evaluation phase with the Sweep
  error codes; exhausted budgets report `resourceLimitExceeded`.

## Failure, Concurrency, and Constraints

Budgets are the twist plan's: at most 4096 patches and 262144 tensor controls,
and subdivision depth 20; they refuse, never degrade. A path corner refuses with
`sweepRoundCornerUnavailable`; a missing allowance, a bend or overlap failure with
`sweepPathNormalUnavailable`.

## Verification and Change Impact

`CurvedPathNormalSweepTests` own the planar-curve volume (Pappus, within the
allowance over the side), the end cap across the end tangent, and the refusals;
`SweepFaceTests` own a body's face swept along straight and curved paths and
united with its own body.
Changing the frame, the error bound or the separation certificate re-runs these
and the Sweep suites (`CADKernelTests`, `SweepEvaluationPlanServiceTests`).
`ClosedPathPipeTests` own the closed plan: a pipe along a circle (the torus' Pappus volume within
the allowance, no caps, volumetric validity) and a closed loop leaving its plane, whose frame turn
the plan corrects so the ring closes.
