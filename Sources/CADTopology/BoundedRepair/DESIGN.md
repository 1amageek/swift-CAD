# Bounded Repair

## Purpose and Scope
The component is a child of [CADTopology](../DESIGN.md). It owns representation reconstruction, tolerance-bounded vertex sewing, duplicate wire removal and shell orientation reconciliation requested through `DefaultBRepRepairer`.

## Responsibilities and Boundaries
The original model remains unchanged. Every candidate representation passes whole-curve correspondence before publication. Geometry owns reconstruction and interval certificates. Repair owns incidence changes and the before/after audit ledger.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Topology](../DESIGN.md) | parent | repair requests and scoped validation | Publishes repaired candidates and unresolved diagnostics | Invalid candidates remain explicit failures |
| [Geometry](../../CADGeometry/DESIGN.md) | depends on | exact surface lift and correspondence | Reconstructs representations without sampled success | Successful endpoint samples are insufficient |

## Architecture
```text
Requested action -> immutable source -> candidate geometry/incidence
    -> whole correspondence and final validation -> change ledger and residual defects
```

## Contracts and Invariants
Edge classification validates the complete original world-space source once.
Classification then traverses retained spatial/parameter wrappers without
revalidating their raw local coefficients under the world-space SI tolerance.
A scaled tiny local conic can therefore retain its valid complete-world
admission. Physical angular transports retain their own endpoint authority and
never inherit a binary intrinsic period merely from their primitive source.
- Candidate vertex sewing and collapsed-curve admission use the audit owner's
  outward scaled displacement norm. The accepted action and final original
  source audit therefore use one bound, including finite tiny/large coordinates;
  rounded squared-length underflow never authorizes a change.
  The shared original displacement magnitude primitive also serves the distance
  and mesh position proofs; repair retains its own unchanged physical allowance.
Vertex sewing moves references only within the requested distance tolerance and records the maximum displacement. Curve replacement preserves every incident directed pcurve by whole-interval proof. Shared edges have one canonical 3D curve. Shell face orientation propagation rejects contradictory incidence. Solid component repair retains explicit outer/void ownership, restores its forward/reversed shell law and uses original signed volume intervals to orient each shell boundary outward before applying its material role. A zero-straddling signed-volume proof leaves an explicit unresolved diagnostic. Generated/deleted topology and geometry are identified explicitly; tolerance is not silently increased. Each action is staged against its pre-action immutable snapshot. Surviving edge endpoint references are compared to the task-original source points; a sequence whose cumulative displacement exceeds the one requested allowance is rolled back with an explicit diagnostic. Each accepted action publishes exact generated/deleted source entity IDs and its cumulative maximum displacement.

## Failure, Concurrency, and Constraints
Cancellation propagates. A missing or ambiguous reconstruction leaves an explicit diagnostic. No partially proved candidate is reported as repaired.

## Verification and Change Impact
Behavioral repair tests must exercise missing representations, reversed correspondence, seam preservation, vertex gaps and contradictory shell incidence. This implementation batch precedes all build and runtime verification.

The edge geometry classifier distinguishes open, complete closed-period and exact
singular surface-lift edges. A singular edge has nonzero original UV extent but
one model-space vertex; its constant-V curve must lie exactly at a Geometry-owned
sphere pole or cone apex parameter. A tensor B-spline constant-U/V boundary is singular when its exact clamped owning control row/column has one identical Euclidean control point under positive original weights; this proves homogeneous constancy throughout the nonzero other coordinate. Collapsed edges own parameter incidence and
zero metric length; they are not paired physical shell boundaries. Complete
periodic edges retain a nonzero directed interval no wider than one period.

Original parameter-image pole classification consumes Geometry's exact native singleton bounds. A rounded foreign-to-native parameter estimate cannot authorize a collapsed edge. Parameter gains, offsets and spatial frames remain retained original source; nonzero constant-chart spans remain face-local. Foreign directed trim spans use exact original rational coefficients of retained binary, ratio, product and difference gains, including nested images, to enforce the original native family minimum and periodic maximum; they do not require their native endpoints to be representable as standalone Doubles.

Spatial rigid/affine images preserve singularity on every nonzero original pole subspan. Vertex sewing may join endpoints of proved closed or singular edges, while small-edge removal excludes these parameter-incidence edges. Shell sewing obtains a reversal from the original directed trim, including one-vertex closed edges. Collapsed chart adjacency requires this same exact structural pole proof; proximity to a pole cannot close a wire.

Requested repairs run in dependency order: ownership cleanup and curve representation reconstruction precede vertex sewing, duplicate-use removal and bounded small-edge collapse; loop order/orientation is repaired after those incidence changes and before chart/shell reconciliation. This order is deterministic and independent of the request array order. Small-edge collapse additionally certifies every original curve point against the retained vertex using a whole-interval position enclosure; endpoint separation or total curve length alone cannot authorize the displacement.

The invocation retains each collapsed edge's immutable original curve and complete directed interval with its final retained vertex identity. A later collapse updates that identity but never discards the old curve receipt. Every subsequent action audits all retained original curve images against their current vertex, so a sequence cannot hide cumulative curve displacement by deleting intermediate edges. A failed action restores both the candidate model and this invocation-local ledger.

An original revolution constant-V boundary at normalized generator end `0` or `1` is singular only when `OriginalRevolutionSurface3D.hasOriginalAxisEndpoint` retains an exact source-bound raw-axis incidence witness. Original algebraic endpoint identity remains authority through surface images; a rounded endpoint or tangent-length comparison cannot create a pole.

Closed native and foreign chart periods compare exact rational differences against the original stored period, transporting signed rational gains and axis swaps before the comparison. A rounded numerical foreign period is not authority for closure. Finite original owning chart bounds remain separately validated by the lifted curve contract.
An intrinsic angular transport can retain its source closure classification.
Authored physical-radian transports retain their own source law and never inherit
a finite binary period from the underlying primitive. Exact canonical pole
incidence may still hold when latitude is intrinsic and longitude is physical;
that singular-boundary receipt is distinct from a periodic closure receipt.

Original revolution constant-U generator boundaries close only when the retained generator `hasOriginalClosedAuthoredEndpoints` proof binds the two complete normalized endpoints. The native angular parameter is identical at both endpoints. A nonperiodic generator domain or a sampled spatial coincidence alone cannot authorize closure.

An offset support inherits a collapsed boundary only through its exact chart-preserving equivalent support. Inherited parameter singularity metadata does not prove spatial collapse: a cone apex offset can produce an angularly varying image. Generator endpoint position closure likewise does not prove closure of its offset normals.

A missing directed pcurve may be reconstructed from the spatial curve's retained original SurfaceLift binding. Complete or partial normalized trims preserve that source parameter law; a spatial affine image on the matching original surface image retains the native source lift and image map explicitly. Each proposed pcurve passes whole directed correspondence before the coedge is replaced. An unrelated support or a spatial curve without hosting provenance needs the Geometry inverse-chart producer and remains an explicit unresolved repair diagnostic.

Exact gain composition uses the caller admission adapter owned by [OriginalSourceValidation](../OriginalSourceValidation/DESIGN.md). Product and difference cached exact coefficients remain derived proof data; their numeric evaluation pairs cannot authorize period closure.

Parameter-image trims validate retained native interval bounds and exact transported native span before admitting the foreign domain. A numeric inverse foreign period is a chart proposal; it cannot reject or certify an exact normalized traversal. Spatial image wrappers delegate the same original trim validation without changing the parameter law.

`restoreSingularBoundaryUses` restores an omitted chart use between consecutive directed pcurves sharing one topological vertex. The gap must be an exact constant-coordinate source boundary with nonzero tangential extent, classified structurally singular and covered by the original collapsed-position receipt. It creates one face-local SurfaceLift curve, one same-vertex edge and its directed pcurve; references, loops and pcurves are mandatory validation scopes. It preserves every existing use and records generated identities. A different endpoint vertex, a noncollapsed boundary or absent lower position authority leaves the defect explicit. No geometric proximity can authorize the new edge.

A native nonperiodic B-spline closed-use certificate requires exact equality of the original first/last controls and both authored endpoint clamping roles. A tolerance-close evaluated endpoint cannot establish exact singleton incidence. Original periodic full-domain closure is independent. Nonclamped/algebraic native endpoint equality requires Geometry’s exact original homogeneous endpoint producer before such a closed-use certificate can be issued.

Every accepted repair action audits the full task-original source delta, including changed retained identities as well as generated/deleted identities. Geometry tables, incidence, orientations, pcurves and vertex coordinates participate. Action-specific messages are not the authority for an exhaustive changed-entity list. The final displacement audit still compares to the immutable task-original geometry and rolls back an action exceeding the unchanged allowance.

Duplicate-face repair compares complete retained source supports and directed cyclic trim signatures within one shell, preserving face orientation and loop roles. Only an exact source match removes an occurrence; opposite material orientations remain distinct. It removes newly orphaned descendants of the removed occurrence while preserving unrelated existing source. General equivalent charts require the original correspondence/equality producer and remain a separate mandatory domain. Every removal is included in the generic source delta audit.

General native endpoint coincidence consumes Geometry’s OriginalCurveEndpointPositionRelation over the original homogeneous coefficients and stations, including nonclamped endpoints and exact signed/rigid/affine parameter images. A nil relation proves unequal positions; lower unsupported domains and resource failures propagate. Authored clamped equality remains a direct structural fast path. Angular/procedural and lifted-period endpoint relation domains still require their respective lower authority.

Missing pcurves on a flat spatial-word curve reconstruct from the retained source SurfaceLift only when the target word support has the identical source support and operation word. Directed complete and partial normalized fractions remain original carrier fields; whole correspondence admission precedes publication. Endpoint-corrected connectors retain their normalized curve law and never borrow construction-control equality as closed-edge authority.

Original polyline curves retain their adjacent-point Euclidean clock on zero
through one. Trim admission uses that normalized law and does not promote the
source to a fitted degree-one spline or add a closure segment from isClosed.

Displacement audits scale the original outward coordinate-gap bounds before squaring, then restore their original magnitude outward. Tiny or large finite coordinate differences do not authorize an inward rounded norm or create overflow solely from intermediate squares. The complete original collapsed-curve image and all surviving endpoint-reference displacements remain independently audited against the one unchanged caller tolerance.

Missing lifted-curve endpoint admission encloses the complete original singleton
curve position and compares the outward coordinate-gap norm to its retained
vertex. The numeric point evaluator cannot hide endpoint error by squared-norm
underflow. Small-edge owner-chain admission uses the same outward audit norm for
every task-original vertex, preserving the final cumulative-displacement law.

Curve trim exact native-span and period proofs retain the caller's independent
source-depth and algebra policy plus optional byte admission. Source image
traversal remains capped by its historical 16 entries; reduced caller depth
limits descendant traversal without becoming algebra depth. Exact rational
coefficients charge original word bytes through the same proof admission.
Parameter-image range mapping still requires its lower optional-byte/source
validation port before a complete bounded edge receipt can be asserted.

Bounded trim validation receives independent source, algebra and subdivision ceilings. Original parameter images request the bounded native-range producer with those exact policies and optional BYTE admission; recursive spatial images preserve them while decrementing source nesting only.

Duplicate-face cyclic use comparison may admit different same-directed native
or linear pcurves only through OriginalPeriodicSeamProof with
secondIsReversed=false. The source support, canonical spatial curve, authored
trim, endpoint coordinates and use orientation must still match. The whole
normalized pcurve law and exact original support-period displacement establish
equivalence; reversing materialized knot arrays is not authority. The helper
forwards independent source/subdivision/algebra limits and optional BYTE
admission to the proof. Existing public repair retains its legacy cancellation
policy; this local proof forwarding does not establish a whole repair storage
ceiling or complete arbitrary equivalent-chart repair.
