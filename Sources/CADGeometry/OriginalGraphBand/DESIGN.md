# OriginalGraphBand

## Purpose and Scope

This CADGeometry child owns bounded, mesh-only original rational graph-band
certificates. The [parent module](../DESIGN.md) owns its index. The consumer is
CADKernel mesh tessellation under the [CADIR geometric-fidelity contract](../../CADIR/DESIGN.md).
This scope does not repair a pcurve, assert exact UV closure, or complete general
trimmed-surface tessellation. GeometryConversion is an independent sibling.

## Responsibilities and Boundaries

Geometry owns original coefficient enclosures, strict graph monotonicity,
separation, native support regularity, reference-cell coverage, endpoint and
inverse uncertainty, and continuous facet error bounds. Topology owns ordered
coedge-use orientation and shared spatial vertex identity. Kernel owns actual
mesh allocation, FaceRun provenance, compatible grids, facet emission and the
existing TessellationBudget. No BRep ID or caller-provided closure Boolean is a
Geometry proof. No input curve, support, trim or topology is mutated.

## Related Designs

| Design | Relationship | Contract used | Summary | Caution |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original selected native-span jets and strict normals | Owns the support authority used by graph cells | Use the exact original support and preparation tolerance |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | Mesh fidelity, retained preflight/emission, checked budgets | Consumes retained graph receipts for actual mesh facets | This receipt does not admit arbitrary trim or replace rectangle identity |
| [CADIR](../../CADIR/DESIGN.md) | depends on | Facet approximation to original curve/surface | Defines the geometric approximation authority | Reference uncertainty is not source UV identity |
| [CurveSurfaceOverlap](../CurveSurfaceOverlap/DESIGN.md) | coordinates with | Whole correspondence evidence | Keeps spatial-edge evidence separate from graph coverage | Correspondence alone does not prove planar closure or winding |

## Architecture

```text
Topology: ordered original coedge uses + actual shared vertex points
    -> OriginalRationalGraphBandCertifying
        -> original native rational graph coefficients
        -> exact entry/exit inverse ownership and join uncertainty
        -> selected original support panels / shared proof usage
        -> immutable OriginalGraphBandReceipt
            -> Kernel compatible reference grids / actual mesh stations
            -> receipt whole-facet admission
            -> Kernel checked preflight + emission + FaceRun
```

## Contracts and Invariants

### Input and receipt boundary

The package protocol is `OriginalRationalGraphBandCertifying` with
`certify(input:fidelity:tolerance:using:) throws -> OriginalGraphBandReceipt`.
The input retains an exact BSplineSurface3D, the original oriented
SurfaceParameterCurve values in an ordered loop, the graph-chain assignment,
and numeric shared-join indices with the actual Point3D vertex. Kernel verifies
ordered original edge-use endpoint IDs, including last-to-first, before passing
these points; Geometry verifies the geometry itself. Coedge pcurve fraction
0/1 already follows use direction and is not reversed again by edge orientation.
A graph-chain reversal is a view of the original law, not a reconstructed curve.

The consumer separately owns a whole spatial-edge correspondence receipt bound
to the actual original curve, directed trim, pcurve, support and tolerance. Its
proven requested deviation ceiling is reserved from the original mesh linear
allowance before Geometry receives the remainder. Geometry certifies
S(original pcurve) versus reference facets; it does not mint a 3D spatial-edge
certificate from a success Boolean. The existing correspondence owner and its
65536 limit are not migrated into this components 262144 proof usage.

The bounded family is finite nonperiodic clamped positive-weight native
piecewise Bezier pcurves of degree at most four, plus original affine constant
coordinate segments, on a regular original nonperiodic selected-span support.
Each interior pcurve knot has multiplicity equal to its degree. Other valid
families refuse explicitly; no rounded generic Bezier extraction is authority.
The support is exactly clamped with one native linear V interval and at least
C0 U continuity; original U intervals may be C0 and retain
separate one-sided normal owners. Every native coefficient and interval is paid
and retained. Required U derivative signs come from outward original homogeneous
Bernstein coefficients, not control-point order or samples.

The immutable receipt binds the complete input, fidelity, tolerance and directed
loop winding. It
retains every graph cell, every original boundary parameter interval, every
uncertain inverse band and every join cell. No caller can mint or modify the
receipt. Materialized mesh stations are approximations with explicit enclosures;
they never become exact source stations. An immutable station carries its unique
receipt owner, selected reference cell, parameter, actual point/normal and
original position/normal error. Facet admission verifies actual positions and
normals against those stations; caller-provided numeric errors are not proof.
A shared mesh point candidate may be reused at a neighboring cell only after
independent original point enclosure admits it there, with separate one-sided
normal ownership. This changes no source station or topology identity.
Kernel must bind the actual facet
positions/normals to the receipt before publication.

### Original homogeneous affine-coordinate inverse bracket

The original piece preparation already consumes the invocation-local ledger
before bounded degree-at-most-four coefficient work and allocation. It retains
an outward homogeneous residual against the endpoint affine U law: elevate
original X to degree d+1 and subtract the exact-endpoint linear Bernstein law
multiplied by original W. The Bernstein hull and strictly positive original
weight minimum prove a whole closed-domain U residual. No sampled agreement,
rounded coefficient equality, fitted law or new source coordinate is authority.

For a requested exact stored U, dividing the residual-enlarged original
endpoint difference by the outward original endpoint delta encloses its unique
normalized inverse. The original monotonicity proof owns uniqueness; the
existing charged monotone contraction refines this retained bracket under the
same depth and 262144-cell ceiling. Nonuniform weights and a one-ULP deviation
retain their nonzero residual rather than being labelled exactly affine.
A zero-width graph query reuses its identical inverse enclosure for both
endpoints; each actual inverse and every surface station/facet still consume
the original ledger. Failure of finite arithmetic is explicit resource failure.

Independent inverse tests own degree-two/four forward and reversed original
coordinates, common nonunit and varying positive weights, one-ULP nonaffinity,
finite closed inverse containment and exhausted/cancelled work. The original
Kernel nonconvex/C0 facet suite and frozen Draft public fixture remain required
upper evidence; the lower bracket alone completes neither M1 nor M2.

### Immutable original U-row proof

`stationRow(cellIndex:u:using:)` produces an opaque immutable nested
`OriginalGraphBandReceipt.Row`. It requires finite U within the complete closed
retained cell, consumes the same invocation-local usage before preparation, and
encloses that cell's original lower and upper graph jets exactly once. The row
retains the receipt's unique immutable identity, exact cell index and U, both original jets, and the opaque selected-native surface row evaluator. These values have no caller-settable initializer or mutable cache.
The row's identity remains alive through the row; materialization also requires
the originating receipt, whose immutable input owns the original source arrays.

`station(row:w:pointCandidate:using:)` checks exact receipt identity,
retained cell and closed U membership, and finite W in [0,1]. It consumes the
same usage before each station's original surface point, selected native normal,
closed original value/first-tangent enclosure and position/normal error proof.
The row additionally retains the selected-native evaluator supplied by the
parent owner: original U point/derivative bases and original U-localized
first-order homogeneous nets are prepared once, with all added work and retained
slots prepaid through the same usage. Original global point accumulation and
selected-side normal accumulation retain their original ordered numeric laws.
Per-station V evaluation, independent original error proof and whole-facet
admission remain mandatory and unchanged. Rows at a C0 station are distinct for
the two selected cells. A neighboring cell needs its own row and its own original
point/normal admission even if the actual point candidate is shared.

The existing `station(cellIndex:u:w:pointCandidate:using:)` delegates through
this factory and materialization path. Preparing one row and using it at several
W values avoids repeated original inversions without changing source parameters,
proof ceilings, tolerance or error arithmetic. Each row factory and each station
consume separately; no helper resets usage. A foreign receipt row is
`invalidInput`, and exhausted usage after successful row preparation still
refuses station materialization as `resourceLimitExceeded`.

### Immutable graph derivative preparation

Each original degree-one-through-four graph piece retains its original
homogeneous first and second derivative coefficients for X, Y and W. These are
exactly the same outward differences used by the existing graph-jet evaluation;
only repeated coefficient preparation is removed. Native piece production admits each actual typed derivative array before allocation and records its original coefficient arithmetic directly. Fixed order-two quotient/product recurrences retain their original directed evaluation order in three-slot admitted buffers.
The existing native-piece and inverse operation charges remain unchanged.
A graph query evaluates these retained nets on its independently certified
original inverse interval and preserves all quotient, monotonicity and curvature
terms. Constant weights still follow the original exact constant law.

### Retained closed join-panel jets

Join construction evaluates each selected original panel's full closed interval
jet once. The immutable `JoinCell` retains that jet in the same index order as
its closed panel cover. Source, selected side, parameter box and preparation
tolerance are already bound by the owning receipt and native token; the jet
cannot be replaced through the package API. Every panel's jet preparation and retained typed array entry debit the same execution at their actual work and allocation owners. Failed candidate join
attempts retain their consumed work; no child invocation resets or refunds it.

Each actual join facet still consumes its existing operation, proves its actual
position displacement and all three edge lengths, and compares every actual
normal against the retained full-panel jet. Reuse is valid only for that exact
retained closed panel; it does not substitute a narrower unsupported parameter
query or discard original uncertainty. Preparation failure, exhausted usage,
invalid index and cancellation preserve typed refusal. Implementation is
source-only until the original cap, C0, aggregate-budget and public Draft paths
are executed after the current implementation phase.

### Simple reference completion and original uncertainty

Outside each retained closed join box B, the exact original graph is fixed.
Inside B, the reference family consists of all monotone-U simple graphs joining
exact coefficient/inverse-owned entry and exit points and confined to B. A
certified affine connector establishes that this family is nonempty: its exact
endpoints are in convex B, its entry U is strictly less than its exit U, and the
whole B is separated from every other chain and nonincident source arc. Entry
and exit values are original mathematical values enclosed by the original
inverse owner; interval representatives are not source identity.

Crossing original tail intervals inside B are retained as original uncertainty
cells, not mandatory reference-connector arcs. This distinction is necessary:
the frozen Draft packet upper join has endpoint differences du=dv=2^-53 and
whole original tail slopes greater than 9 and less than 0, which force an
interior crossing. No simple completion can contain both entire crossing arcs.
The component preserves these original intervals and their full geometric
coverage without claiming an exact simple UV boundary for the source loop.

The two outer tips have a separate cap case. At a coefficient/inverse-owned
common U station, a V-monotone vertical affine cap may close the band. It has a
nonzero V extent or a certified point collapse and is not an invertible strict-U
graph segment. The whole cap is disjoint from unrelated arcs except its intended
entry and exit. All original tip intervals remain in uncertainty coverage; a
collapsed tip does not authorize omission of unproved triangles or normalization
of F normals. Original selected support normals remain authority.

Every box and inverse band is retained closed, including all incident original
support spans. Strict coefficient graph separation and winding are proved
outside B. Tip boxes similarly retain both incident chains and complete source
intervals; their reference closure must have a proven simple connector. Boxes
may not overlap unrelated arcs or each other without a separately proven
complete reference cover. Unproved separation, domain, inverse ownership,
nonemptiness, normal or cell cover is a typed refusal. No tail is clipped away
merely to make U stations appear ordered.

Pairwise join admission consumes one operation from the same invocation-local
proof usage before each comparison, including already disjoint U ranges. This
bounds quadratic comparison work and checks real cancellation without a fresh
helper allowance. Closed U ranges with disjoint interiors retain the existing
admission. When U interiors overlap, only two non-tip joins with exclusive
opposite-chain connector ownership may be admitted: one has only the lower
connector and the other only the upper connector, and their complete closed V
boxes must be strictly disjoint. Same-chain joins, tips, mixed connector owners,
and touching or overlapping V boxes retain typed refusal.

This case preserves complete simultaneous lower and upper reference laws.
Reference stations are the union of both connector endpoints and all original
support breaks; each chain selects only its own connector. Every retained cell
still proves strict separation of the full original lower/upper V covers and
uses its independently selected native support panel. Both original join boxes
and all original boundary intervals remain in the receipt. U-projection overlap
therefore does not imply geometric box overlap and cannot erase the vertical
strip between two opposite-chain connectors or merge selected C0 owners.

### Whole reference cells and joins

Away from join boxes, a cell uses the exact reference map
`F(u,w)=S(u,(1-w)L(u)+wH(u))`, with strict `L(u)<H(u)` and w in [0,1].
Whole native rational graph inversion encloses v, v_u and v_uu, where
`v_u=v_t/u_t` and `v_uu=(v_tt*u_t-v_t*u_tt)/(u_t^3)`.
Original support jets compose with these derivatives. In particular F_uu
includes `S_v*v_uu`; a flat support does not authorize dropping curved trim
interior error. Native support/pcurve breaks and all inverse uncertainty are
retained; no triangle crosses a C0 support knot. Compatible subdivisions retain
one grid at each shared station and separate selected normal owners at creases.

Reference stations partition active reference laws, separately from retained
original boundary intervals. A source-piece endpoint strictly inside its own
chain's certified affine connector does not partition the reference grid: that
chain uses the same connector law on both sides. Connector boundaries, every
original native support knot, and an opposite chain's active original-piece
break remain stations. This rule uses exact closed connector ownership and
strict comparisons, not an epsilon merge, source repair or removal of a thin
strip. Every original boundary interval, crossing tail and full-strip
uncertainty remains retained and proved. Selected C0 support owners remain
separate even inside a connector.

An internal join box only localizes boundary uncertainty; it cannot remove the
vertical strip beneath its U range. This strip retains complete F reference
cells using the coefficient-owned affine connector as the reference boundary.
For any admissible original tail/reference completion in B=[a,b]x[c,d], the
same-u,w V displacement is at most w*(d-c). Its selected original support
position displacement is at most Sv_upper*w*(d-c), computed outward and added
to the same remaining linear allowance with connector endpoint, inverse,
materialization and whole-facet Taylor errors. Original normal enclosures cover
the full strip UV range, not just the boundary box. All strips/caps and original
intervals retain their complete measure. Unknown separation, excessive
uncertainty or unproved full-strip normals refuse explicitly.

For each join cell, original selected support panel r, and actual shared vertex
P, the owner encloses `E_r=sup(q in B intersect r) distance(S(q),P)`.
For an actual candidate facet with vertices M_i it encloses
`D=max_i distance(M_i,P)`. Convex barycentric containment proves the universal
position bound `E_r+D` for every admissible reference completion and every
retained original tail point in B. Original inverse, correspondence and station
materialization errors are included in the same unchanged linear allowance.
A vertex-only mapping cannot omit the retained join cells or original intervals.

Original support normal enclosures cover every closed owning panel over B and
are compared to the actual mesh normals under the existing angular allowance.
No continuous normal law across a C0 knot is inferred. Actual triangle sides
and diagonals separately satisfy maxEdgeLength; axis-only checks are insufficient.

## State, Ownership, and Lifecycle

Source arrays, graph receipts and their preparation/contribution authorities are immutable Sendable values. The same exclusive OriginalQueryExecution owns actual traversal state. Standard OriginalGeometryPreparationReceipt stores only the observed scalar/source/geometric/transport depths, tolerance and original budget/contributions. Same-budget readers reconnect the original contribution; explicitly independent readers readmit immutable evidence under their own budget. Mesh plans retain the original immutable contribution across preflight and emission.

## Failure, Concurrency, and Constraints

One immutable contribution preserves the historical262144 work/cell and depth32 ceilings across graph preparation, inverses, selected panels, reference cells, joins and facet admission. Every actual cell visits the original execution; every requested typed coefficient, graph, station or facet buffer is admitted before growth. No derivative coefficient or storage entry is represented as a fake cell. Scalar, source, transport and geometric axes remain independent. The current allocation policy is inherited without changing parent secondary billing. Cancellation and failed admission propagate without publication or resetting counts.

New invalid provenance/input is invalidInput; existing source validation errors
retain their original typed contract. Valid unproved family/coverage is
unsupportedCapability; original singular, numerical, resource and cancellation
failures propagate. Depth/cell exhaustion is resourceLimitExceeded. No resource
ceiling, tolerance, width or private allowance is increased, and no failure is
retried through a rectangle or sampled path.

## Verification and Change Impact

Dedicated OriginalGraphBandTests must execute the actual package protocol and
receipt admission. Literal positive rational native graphs establish original
coefficient monotonicity, graph inversion, source-normal and full-cell fidelity.
An independent nonconvex lower graph on a flat support must reject a facet whose
trim interior error exceeds the linear allowance despite zero support Hessian.
Exact crossing tails test the distinction between reference completion and full
original uncertainty coverage; disconnected vertex geometry, unproved graph
sign, chain crossing outside B, domain escape and box interference refuse.
Forward/reversed uses retain the same geometric cover and winding ownership.
C0 selected support sides retain both normal owners and no crease-crossing facet.
Shared aggregate count, depth, cancellation and invalid/foreign receipt inputs
have behavioral refusal evidence with unchanged limits. Kernel separately owns
actual emitted triangles, all edge lengths, checked counts and FaceRun, then the
original frozen Draft public fixture. A lower receipt alone does not complete
M2 or establish that the real packet passes all admission conditions.

The initial implementation paths are the seven Swift files in this directory
and the native traversal handoff in `../SurfaceTessellationDifferentialBounds.swift`.
`Tests/CADGeometryTests/OriginalGraphBandTests.swift` owns the literal loop/cap,
reversal, flat nonconvex trim, crossing full-strip, unequal-weight rational,
selected C0 normal, actual station/diagonal, aggregate resource, invalid vertex
and cancellation declarations.
[OriginalGraphBandRowTests](../../../Tests/CADGeometryTests/OriginalGraphBandRowTests.swift)
owns independent literal row points/normals/errors, observed inverse-work reuse,
foreign receipt refusal, post-preparation budget refusal and separate selected
C0 row normals. Existing OriginalNativeSpanTessellationTests
owns compatibility of the original default traversal. Compile/runtime evidence
is required before this bounded component is complete.

The one-ULP crossing-tail fixture must retain every original interval and the
complete join strip while removing hidden same-chain reference partitions. An
opposite active original break at that same station and native C0 support
breaks must still partition reference cells.

### Original station first-order materialization

Mesh station admission consumes only original position and U/V tangents. The
selected native-span owner exposes an immutable first-order result containing
those three interval vectors and no second/third-order fields. It validates the
same source, preparation tolerance, finite closed box, selected knot side and
periodic lift as the existing full jet. The original prepared homogeneous value
and first derivative nets are localized once; positive-weight quotient
differentiation and original common-weight/polynomial-coordinate authority are
retained. Cancellation is checked before and after evaluation. No derivative
order is manufactured or filled with zero. Full-cell subdivision and facet
Taylor/normal-variation evidence continue to use the original full jet.

Station normals are certified directly from the first-tangent cross product
and its outward positive magnitude bound. Actual normal normalization and
whole-facet admission remain mandatory. The original rational curved-support,
C0 side, source/tolerance/box refusal and cancellation tests compare against
independent original laws; the same unchanged public nonconvex/C0 mesh suite
remains the completion evidence. The captured Native stack shows that prior
station emission localized unneeded derivative nets; only public runtime can
prove the resulting cost improvement.

### Direct Graph Execution

All graph preparation, original native panels, inverse/refinement, station materialization and facet admission receive the original inout OriginalQueryExecution. OriginalTessellationProofUsage and its private counter/callback are removed. One immutable OriginalQueryContributionHandle retains the original262144 cell/work and depth32 local ceiling on the shared budget across preflight and emission. Mesh plans retain this immutable handle and complete source-bound receipt; they do not retain mutable execution. Actual typed buffers debit cumulative bytes before materialization; scalar/coefficient arithmetic and geometric refinement retain independent axes.
