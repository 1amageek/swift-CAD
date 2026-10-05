# Certified Curved Path-Normal Sweep

## Purpose and Scope

Child of [CADModeling](../DESIGN.md). Builds a path-normal Sweep along a curved
path within an explicit positional allowance: the section moves rigidly with the
path's minimal-rotation frame. Its child
[ClosedSweepSectionCorrespondence](ClosedSweepSectionCorrespondence/DESIGN.md)
owns original seam matching and cyclic row transport.

## Responsibilities and Boundaries

Owns admission (allowance, corners, bend reach, self-overlap), path subdivision,
the frame, and the Hermite tensor rows with their error bound, plus the cap and
side face requests. Existing Sweep owns section resolution, path chaining and the
distance prefix, sewing and semantic topology, and Booleans. Exact routes keep
precedence: straight paths, and solid sweeps along one circular arc (the exact
revolve), never take this plan. One guide steers the section (`CurvedSweepGuideLaw`); two or
more guides and path corners are refused with `FIXME(INCOMPLETE_IMPLEMENTATION)` in the plan.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | Sweep evaluation | routing and body building | exact routes first |
| [CertifiedTwist](../CertifiedTwist/DESIGN.md) | coordinates with | allowance semantics | the same allowance bounds either approximation | an allowance alone no longer requests a twist |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | `OutwardScalarInterval`, `IntervalDerivativeJet` | derivative enclosures | order ≤ 6 |
| [OriginalCurveConstructionChart](../../CADGeometry/OriginalCurveConstructionChart/DESIGN.md) | depends on | exact fraction and original nonlinear parameter jets | Transports retained circular and hyperbolic sections into native frame derivatives. | A construction image or interval midpoint does not replace its source law. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | preflight planning | `SweepEvaluationPlanService` admits by building the plan | same admission as evaluation |

## Architecture

```text
path spans + original chart ─► retained original owning traversal jets (order 5)
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

Original cumulative arc preparation forwards the invocation's independent source
and algebra capabilities together with geometric subdivision and work/BYTES.
Subdivision cannot reset or enlarge original source or algebra depth.
Original twist/scale trigonometric recurrences consume that same invocation's
work callback. Their three derivative buffers are admitted before allocation;
quadrant transport uses fixed scalar signs rather than a per-order array.

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
  the moving frame): at each station the guide crosses the plane across the path (the complete
  native curve/surface event port, searching forward from the retained prior contact) at a lateral offset `g`; Chord turns the
  section by `arg g − arg g₀`, Point also scales it by `|g|/|g₀|`, Curve turns it by
  `arg g − arg q` with `q` the section's point as far from the path as `g`, continued along the
  section. Sliding section contacts use that same complete native event port against the
  original radius cylinder, and ambiguous nearest contacts fail. The law is read at every piece's ends and middle; a piece whose linear law strays
  from the middle's by more than a quarter of the allowance at the section's reach is halved
  (to depth 40, on a stack rather than by recursion), and one no longer than sixteen modeling
  distances that still strays is refused (a Curve guide starting square to the section's side
  turns it as the square root of the run). The bend and overlap certificates take the largest
  scale the accepted pieces reach. `CurvedPathGuidedSweepTests` own a Point guide scaling a
  square by `1 + t` and a Chord guide leaving it as it is (their exact Pappus volumes), a Curve
  guide turning a 30°-turned square so its side keeps touching it (volume, the guide's end on
  the end cap's outline), and the refusal from a side's square.
  This midpoint rule remains incomplete: it does not certify the original guide law
  between stations. Full guided admission additionally requires the original
  guide/normal-plane implicit correspondence enclosure and nonrigid multiple-guide
  deformation; the current Hermite certificate covers only the retained interpolated
  angle/scale law. Source-only work must not treat these guide fixtures as full S4 evidence.
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
  between the start lateral axis and the bare transported end axis, before authored twist), so the plan is rebuilt with a twist law
  `[0, −turn]` and repeated (at most six times) until the end row lies within the allowance of the
  start row, then the last row is snapped onto the first so the seam shares one edge. An authored
  twist law is retained at every knot, with the holonomy correction added in proportion to the
  authored arc-length fraction. The closing turn excludes the authored end angle;
  the correction therefore removes only bare-frame holonomy. A nonperiodic
  authored final section is refused by the complete seam comparison, never
  silently canceled. Section symmetries require an original section correspondence
  proof and its parameter-chart transport; coefficient proximity alone is not
  permission to change authored twist. Original cumulative arc lengths are enclosed by
  the bounded lower producer with the same invocation callback and remaining
  depth. Authored endpoint twist is first checked by the child correspondence
  against every original section span at modeling tolerances. The actual end
  frame must certify that same unique cyclic shift before any seam row changes.
  A larger positional sweep allowance cannot authorize an asymmetric section.
  Intermediate authored knots remain unchanged. Bare holonomy correction is
  replaced by the current measured bare turn, rather than accumulated again when
  an unrelated seam refusal forces another attempt.
  Circular rational construction stations retain their original nonlinear angular
  law and D1/D2 labels. The original acceleration bound composes native
  C'' times label'^2 with C' times label'', including the child fraction scale;
  rational construction fractions cannot be treated as linear native angles.
  Whole piece acceleration bounds enclose the error of linear fraction
  interpolation. Every authored twist knot inside a candidate fraction interval
  contributes its exact piecewise-affine interpolation deviation; extrema occur
  at those knots or interval endpoints. The maximum original slope transports
  fraction uncertainty, including endpoint integration error, into an angular
  bound. The original linear scale is bounded in the same way. Their complete
  displacement bound is added to the Hermite and coefficient error before
  admission, so numerical quadrature and endpoint values alone cannot authorize
  the original law. Closed correction attempts borrow one cumulative source
  work allowance; Native, WASM and Embedded share the same Mutex owner. Endpoint scale must return to one. The correction and authored
  angles remain inside the same certified trigonometric domain; this does not extend that budget.
  Guides require their independently closed correspondence. The overlap certificate wraps: the last and first pieces
  touch, and the pieces between a pair are taken around the loop.
- Refusals of what the sweep asks for report the evaluation phase with the Sweep
  error codes; exhausted budgets report `resourceLimitExceeded`.

## State, Ownership, and Lifecycle

Original length receipts and station caches belong to one construction. The
source allowance is shared across closed-frame correction attempts by one
`CurvedSweepSourceBudget`; it has no global cache or persistence. Immutable
geometry and receipts retain their source values until the plan finishes.
Native owning traversal preparation and closed higher jets receive the request's
explicit 4,096 span ceiling, remaining 20-level source depth and byte callback.
The span ceiling follows the existing conversion control-count baseline; it is
not reset by a child frame query. Native coefficient and Taylor scratch payloads
are admitted by the same request owner before allocation. Generic nonnative
higher query payloads remain a separate lower producer dependency and fail
explicitly when that byte capability is unavailable.
Each native span retains its original curve and directed parameter chart from
SectionResolution. Arc-length preparation reads that original law once and
retains the paid partition across correction attempts; prefix queries reuse
whole cells and reprove only partial boundary cells under the same callback.
All spans carrying the same immutable original source owner share one prepared
receipt over their selected native hull. Grouping charges each owner comparison
and uses reference identity, avoiding recursive source hashing or a new cache.
Each span still proves its own smooth owning interval and integrates its own
inner/outer directed endpoint bounds. The complete-owner total is never used
as the length of an individual span. Each retained preparation receives the
same request's byte callback, including source coefficients, integration-cell
capacity and partial-query partitions. Closed native-jet and higher-Taylor
temporary allocation forwarding remains a lower completion obligation.
Caller-owned arrays reserve one bounded capacity after charging their maximum
element strides, including chart views, owner groups, receipt views, endpoint
intervals, cumulative intervals and group indices. Byte charges are rounded
upward into the unchanged scalar allowance. The lower receipt forwards its
coefficient and partition allocation admission to that same owner; temporary
native-jet allocation coverage remains an explicit lower source gap.
Original endpoint chart uncertainty bounds both inner and outer integrals.
Curved-path position, tangent, frame derivatives and Hermite remainders consume
`OriginalSweepPathPiece`, which retains a prepared original traversal independently
of candidate control nets. Authored scalar endpoint capabilities bind its directed
native chart; a native B-spline piece retains its positive owning knot span,
including both one-sided closed endpoints. Subdivision restricts the retained
normalized chart and scales every original derivative into the child parameter.
Taylor coefficients become derivative bounds through outward factorial products;
The original Euclidean derivative jet feeds the existing frame algebra directly.
It does not replace the source law. Nonlinear conic station charts
without exact endpoint/chain-rule authority remain typed unsupported.
Join admission uses both whole original one-sided unit-tangent intervals: the
cross-product norm upper bound must lie below the outward angle threshold and
the dot-product lower bound must be positive. A midpoint cannot certify G1.
An exact interval corner witness uses the corner failure; inconclusive endpoint
precision remains resource failure rather than an invented smooth join.
Original traversal preparation and query callbacks borrow the same request
allowance. Closed correction attempts prepare their original traversal array
once, then borrow the same immutable receipts alongside the retained length
law. Every reused piece checks source-owner identity, exact directed endpoint
capability, tolerance and request-budget identity before frame evaluation.
The request budget also implements exact algebra admission against its existing
Mutex counters; exact preparation does not create a second allowance.
Lower source-depth forwarding and temporary jet allocations remain
required lower obligations; this source path does not assert their completion.
The fraction interpolation remainder reads original native acceleration and
the complete affine chart gain, rather than acceleration of rounded split
coefficients. Nonlinear analytic charts need their lower original station law.
Cancellation is checked before entering the short counter critical section;
lower geometry calls and callbacks run outside it.

| Target | Storage | Isolation | Counter entry | Release |
|---|---|---|---|---|
| Native | `Mutex<State>` | `withLock` | `consume` / `retainScalars` | Request owner releases its reference |
| WASM | `Mutex<State>` | `withLock` | Same methods | Same owner lifetime |
| Embedded | `Mutex<State>` | `withLock` | Same methods | Same owner lifetime |

These are common source declarations, with no target branch weakening storage
or Sendable. Compiled declarations and target runtime behavior remain part of
post-implementation verification.

## Failure, Concurrency, and Constraints

Budgets are the twist plan's: at most 4096 patches and 262144 tensor controls,
and subdivision depth 20; they refuse, never degrade. The bounded original
arc-length calls share the existing conversion work and scalar ceilings through
one request owner. Lower arc-length partition storage retains its own existing
interval policy. Actual byte callbacks share the request scalar allowance,
while unforwarded original jet temporaries remain a required lower integration
gap. A path corner refuses with
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

### Terminal section collapse

An authored zero end scale retains the original linear scale law, positive before
the terminal station. The last Hermite row is one common numerical point chosen
from the original path endpoint enclosure; every coefficient error remains in
the existing original-law remainder and rounding bound. The exact constant-row
classifier admits the retained collapsed UV use. The source builder generates
no zero-area end cap, and semantic publication exposes a shared pole vertex
rather than an end-face identity. Closed-path periodic admission still requires
unit terminal scale. Mesh one-sided pole normals are a lower Geometry/Topology
obligation, not evidence supplied by this construction.

The invocation allowance retains GeometryConversionRequirements.maximumScalarCount
as Double-sized physical slots. RationalAlgebraAdmitting.retainExactStorage receives
UInt32 words: checked word-count times UInt32.stride is converted to bytes before
ceil(bytes / Double.stride) debits those same slots. Work units and subdivision
depth are distinct; this transport does not change either cap.

Original conic frame pieces retain the immutable construction chart. Native
D0-D5 jets are queried on its complete original angular image, then the closed
chart derivative jet is composed through the Bell recurrence. Piece normalization
contributes the signed original chart gain and positive subdivision width at
every derivative order. No construction coefficient supplies a path derivative.
The Bell table and coordinate outputs are paid byte payloads; native conic Taylor
preparation/query work and storage use the same invocation callbacks.

Exact algebra cell depth is independent of source nesting and curve subdivision.
`CurvedSweepSourceBudget.visitExactCell` admits the existing intrinsic 32-level
ordered-field/root limit and debits the same work owner. Structural curve
walkers separately check their 20-level source or subdivision guard before
charging an exact cell at depth zero. This does not enlarge either limit.

The closed seam consumes [ClosedSweepSectionCorrespondence](ClosedSweepSectionCorrespondence/DESIGN.md).
The child retains the original end-frame interval action, certifies all original
section spans against the proposed start boundaries, and returns a unique cyclic
correspondence and compatible tensor row transport. Coefficient proximity is
only the displacement allocation for an already certified correspondence.
