# Rolling Ball Fillet Composition

## Purpose and Scope

Child of [CADKernel](../DESIGN.md), with no children. Constructs a complete
solid sewing request from an existing selected edge, without regenerating its
source feature. Current construction domain is an open tangent chain with distinct
terminal neighbors or a complete closed partner loop. A plane retains partner
precedence when paired with a finite Bezier lateral chart. Two original finite
B-spline incident supports use the lower original FaceID as their fixed partner;
the same original offset contacts and source-chart loop replacement apply.

## Responsibilities and Boundaries

Owns treatment ordering, source-face partition composition, terminal closure,
and retention of unaffected shell faces. Geometry owns contact/intersection
certificates; CADModeling owns directed sewing patches. The builder does not
mutate input. `KernelRollingBallFilletEvaluator` implements the injected ordinary
fillet contract and owns admitted selection, sewing, target-body replacement,
removed-subshape lineage and closed-solid/global validity before publication.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | source extraction, face arrangement, sewer | Existing topology composition owner. | Do not use Boolean recovery tolerance for machining. |
| [Modeling RollingBall](../../CADModeling/RollingBall/DESIGN.md) | depends on | chain resolver, blend and cap patches | Reuses boundary construction. | A patch is not a valid solid. |
| [Geometry RollingBall](../../CADGeometry/RollingBall/DESIGN.md) | depends on | offset contacts and native implicit trims | Retains curved supports and certified correspondence. | Multiple or inconclusive intersections fail. |
| [Finite Face Containment](../FiniteFaceContainment/DESIGN.md) | depends on | original connected UV-box strict containment | Classifies retained original intersection cells against finite trims. | Patch admission and complete query accounting remain required. |
| [Source Face Patch](../../CADModeling/SourceFacePatch/DESIGN.md) | depends on | retained original face copying with work and byte callbacks | Copies unaffected and partner source patches under the crossing request owner. | Copying is not paid patch validation; inner provenance temporary forwarding remains required. |

## Architecture

```text
Exact input body + selected edge + radius
    -> cap incidence -> ordered tangent chain
    -> original lateral arrangements + blends
    -> temporary support continuation -> terminal neighbor arrangements
    -> trimmed cap + retained source faces + blends + unaffected faces
    -> solid sewing request -> existing sewer -> replacement -> volumetric feature admission
```

## Contracts and Invariants

- Input must have an exact certificate at the operation tolerance. Modeling-only
  certificates, invalid radii, foreign edges and ambiguous incidence fail.
- Offset side is selected from the complete original edge dihedral. The second
  source face's parameter normal crossed with its directed boundary tangent
  points into its loop's left side. Original whole-loop signed UV area and the
  outer/hole role select the material side independently of raw loop winding;
  numerical probes and assumed positive winding cannot choose that sign.
  The material-side vector's dot product with the first
  outward source normal is negative at a convex edge and positive at a concave
  edge. Whole original pcurve boxes, source surface derivative bounds and
  original directed `SurfaceLift` boundary tangent bounds must prove one strict sign over every retained
  edge subinterval. Convex treatment offsets inward; concave treatment offsets
  outward. Midpoints only propose subdivision. A varying or unresolved dihedral
  cannot choose a successful constant-side blend; source-bound zero strata remain
  required for the mixed-sign domain.
  The material tangent differentiates the second original surface composed with
  its directed native coedge pcurve. The tolerance-close standalone 3D edge
  representation cannot replace this exact original material-boundary direction.
- Each source face is retained or replaced exactly once. Unaffected geometry,
  face orientation, shell orientation, and original subshape ancestry survive.
- Tangent selection is ordered by the cap's coedges, never dictionary order.
  A two-B-spline selection chooses its partner once from immutable original face
  IDs; support failure does not retry the other partner. Original contact rails
  and replacement loops retain that partner's native pcurves even when the
  partner is curved. Partner choice changes construction roles, not the sphere
  touching the two original oriented offset supports.
  A connected chain may contain one or more spans. An open chain
  requires two distinct terminal neighbors. A closed chain retains every cap-loop
  edge in cyclic order and verifies the final rail joins its first rail; it has
  no invented terminal neighbor or support continuation. A face visited twice
  fails explicitly.
- A single original closed edge may produce a periodic offset intersection.
  Only this complete-cycle selection may retain exactly one original source
  period, with its original intersection pcurves and the normal correspondence
  certificate. Periodic intersections for an open or partial chain require
  original endpoint trimming and are not promoted to complete cycles.
- Temporary Bezier continuation retains chart coordinates. Its rounding
  allowance is one percent of the modeling distance; retained source faces
  never use the extended support. The initial search window extends the varying
  coordinate of the selected lateral coedge (V for constant-U, U for constant-V)
  and neighbor U/V by one quarter of their finite domain, with no retry or silent
  enlargement. Failure to close inside that window is explicit, not a success.
  The selected coedge must lie on a complete isoparametric chart boundary.
  Terminal retained-side selection belongs to the blend patch builder and is
  independent of intersection traversal direction. A single-span chain prepares
  one continued blend for both terminals. Its two original cap-coedge vertices
  identify distinct terminal neighbors; both original implicit boundaries must
  separate from one retained original interior section on that common support.
  The final cap rail starts at the first terminal's canonical cap-contact vertex
  and ends at the second, preserving the authored cap traversal. The two trims
  are composed together rather than replacing each other.
- Terminal partitions must produce exactly two regions and exactly one region
  excluding the removed original corner. Original supports and native spatial
  intersection curves remain authoritative; transferred UV curves are bounded
  correspondence representations, not exact intersection certificates.
- The output contains every retained face of the original shell and declares
  solid topology. No intermediate sheet is returned as a feature result.
- Final-patch crossing classification queries every nonadjacent pair containing
  a generated blend. A retained implicit graph cell supplies the nonempty
  original intersection witness. Its two original UV boxes must both lie
  strictly inside the corresponding finite trims before reporting
  `filletSelfIntersection`. A numerical anchor is not an intersection witness.
  Whole-box outside classification may discard an original graph subinterval
  only after every trim boundary has been excluded. A boundary-overlap result
  refines the original owning graph interval with its retained localizer state;
  children cover the complete parent interval and retain the same root law.
  Contraction phases and child subdivisions share the original query allowance.
  Failure to contain a whole box is not proof that its root graph misses the
  face. Nonimplicit nonempty results require their own retained parameter-box
  producer and fail explicitly until available. Sharing an original boundary
  never omits a support-pair query: another component may cross the interiors.
  Only a complete returned curve component with the identical original curve
  law on both admitted boundaries and authored trims covering its whole native
  domain may be excluded as declared contact. Nonlinear correspondence and
  partial contacts require full component separation; this positive-witness
  classifier does not certify absence or complete global validity.

## Runtime Flows

Construction is synchronous and fallible. It prepares contacts once per span,
replaces endpoint blends with continued/trimmed blends (one shared support and
two boundaries for a single span), updates cap
rails, then emits the request. A failure discards all request-local preparation.

## State, Ownership, and Lifecycle

The builder retains immutable source values and ancestry for one request. All
arrays, incidence indices and replacements are local to the invocation. Crossing
queries share one request-local `RollingBallIntersectionBudget` with immutable
limits and `Mutex<State>` work/scalar counters. Original SSI preparation and
trim exclusion callbacks charge this owner. Original patch copies create that
owner before copying and share it with final classification, paying source scans
and requested payload capacity; the classifier cannot reset those charges.
Finite-box classification receives the same byte callback for its pending-cell
buffer and original pcurve payload. Unchanged copies retain their original
FaceID and exact input receipt; their trim predicate consumes that original
receipt directly. Replaced and generated patches consume the bounded original patch-value
admission with independent source/algebra caps and the same work/byte owner.
This retains support, endpoint, closure and provenance invariants; complete
nonlinear spatial/pcurve correspondence remains a separate sewer premise. They
never inherit an unchanged face receipt merely by matching a support.
Callbacks and cancellation checks
run outside the lock. There is no global cache or alternate Embedded storage.

| Target | Storage | Read/mutation | Release |
|---|---|---|---|
| Native | `Mutex<State>` | `consume` / `retainScalars` through `withLock` | Request and its callbacks release their owner |
| WASM | `Mutex<State>` | Same methods | Same lifetime |
| Embedded | `Mutex<State>` | Same methods | Same lifetime |

Crossing work is capped by the existing 65,536 correspondence-cell allowance,
depth by the existing 20 correspondence levels, and retained scalar storage by
the Geometry conversion baseline. The allowance is shared across all final
patch pairs and is never reset per pair. Earlier construction and opaque patch
validation are not thereby certified as part of a complete request ledger.
Original coefficient/SSI storage ports report bytes; the budget charges their
ceiling in whole `Double` scalar equivalents, rounding upward. Graph DFS records
use one buffer with maximum live capacity depth + 1, charged by actual
`MemoryLayout` stride before allocation and reused across the original cell.
Original localizer preparation, restriction and advance receive the same work
and byte callbacks with explicit owning span/source/subdivision limits. Critical
and cross-cell continuity remain distinct source obligations; localization does
not infer them from a cell-local derivative hull.
The center-offset and terminal support intersection producers also borrow this
request allowance. Their existing configured subdivision and root ceilings are
retained and combined with the caller limits; no fresh intersection allowance is
created for another rail or terminal. Legacy contact-rail pullback validation
and finite arrangement remain separate accounting obligations.
Original dihedral sign classification forwards the same byte callback into both
surface normal boxes, every original pcurve cover and the owning spatial tangent
query. Its DFS buffer is bounded by depth + 1 live records. A union of one-sided
jets bounds the sign only and grants no smoothness across a native join.
Material-loop area uses the support-bound original UV flux issuer with the same
work and byte callbacks. Its existing source ceiling of 16 and algebra ceiling
of 32 remain independent of the request's geometric refinement depth. Original
linear UV laws use the exact rational Green integral; curved chart families must
provide their bounded original flux issuer before selecting a material side.

## Failure, Concurrency, and Constraints

Geometry calls use existing bounded intersection/correspondence options. Work
visits each cap edge and source face once outside geometry admission; storage
is proportional to source incidence and emitted patches. Existing source-patch
extraction additionally scans source ancestry for each emitted boundary use;
this component does not claim linear total runtime. Cancellation is checked
between chain/terminal/retained-face operations. Unsupported construction,
missing references and failed certificates throw KernelError; cancellation
propagates. No retry, tolerance widening or planar/mesh fallback is permitted.

## Verification and Change Impact

[InvoluteGearProfileTests](../../../Tests/CADKernelTests/InvoluteGearProfileTests.swift)
owns the native gear composition check. Completion requires a live-source
whole-body request sewn as a closed solid, preserved source surfaces/ancestry,
and typed refusal for invalid selection/radius. Existing isolated contact and
terminal fixtures establish only their respective lower-level contracts.
[RollingBallFilletRequestBuilderTests](../../../Tests/CADKernelTests/RollingBallFilletRequestBuilderTests.swift)
exercises the complete builder on a smaller curved extruded solid, including
untreated face retention, closed sewing, volume reduction and invalid requests.
Its focused continuation check compares swapped UV charts and reversed boundary
directions, including refusal of partial or interior chart boundaries.
Feature publication remains incomplete until solid/global validity, stable
selection, reevaluation and the existing application transaction path pass.

Whole intersection-component boundary exclusion remains an exact original-law
identity decision with complete original component parameter coverage on both
finite boundaries. Original structural comparison payload visits debit the same
rolling-ball request allowance before equality. A tolerance-bound coincidence
from the sewing matcher cannot exclude a separate nearby original component.
False/inconclusive matching never authorizes global absence.

The retained crossing owner distinguishes geometric depth 20, original source
nesting 20 and exact algebra depth 32. Equal historical numeric values do not
make source nesting a geometric recursion counter. Original graph refinement
reduces only the remaining geometric allowance; every subquery retains the same
selected source and algebra authorities. Generated finite-patch validation and
trim classification keep their stricter original source ceiling 16 through the
minimum with the owner. Exact native subdivision and all original visits still
charge the same cumulative work and Double-slot physical storage allowance.
