# Native Curve Surface Point Relations

## Purpose and Scope
Child of [Curve Surface Overlap](../DESIGN.md). Owns complete isolated original
parameter tuples for positive-weight, source-valid B-spline
curve and tensor B-spline surface products across finite selected native knot spans,
including exactly represented periodic transports.

## Responsibilities and Boundaries
Admit original sources, prepare exact homogeneous laws and consume complete
three-coordinate decomposition or authoritative whole common refinement. Discrete publication requires every selected cell to have zero dimension.
Rich publication preserves globally isolated connected components and delegates complete
positive-dimensional coverage to [Native Relation](../NativeRelation/DESIGN.md).
Any positive-dimensional cell fails discrete queries with nonDiscreteIntersection;
no subset is returned. Rich preferIsolatedCells selects the existing isolated
rank path only when every actual selected real cell has zero dimension;
positive-dimensional real cells use full rank partition and incidence. Complex
ideal dimension does not determine the dimension of the requested real result. Other families retain existing dispatch. After admission,
all failures propagate. The existing exact prefix-exclusion port skips only
nonzero-constant original equation prefixes and retains their exclusion witnesses.
The native producer also selects the [guarded native equation normalization
contract](../../IntersectionAlgebra/DESIGN.md#guarded-native-equation-normalization)
before decomposition, retaining original laws, guards and exact division identities.
It selects [isolated native rank evaluation](../../IntersectionAlgebra/DESIGN.md#isolated-native-rank-evaluation),
which keeps complete guarded equation coverage and evaluates original rank only
on selected singleton cells; positive-dimensional coverage fails atomically.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Overlap](../DESIGN.md) | parent | complete result | Native receipt accompanies points | Legacy receipts remain nil |
| [Intersection Algebra](../../IntersectionAlgebra/DESIGN.md) | depends on | original system and decomposition | All equations, guards, closed-domain coverage | No sampled absence |
| [Rational Algebra](../../RationalBivariateAlgebra/DESIGN.md) | depends on | homogeneous laws, ordered fields, retained isolation | Exact coordinates and representatives | Retain immutable field owners |
| [Curve Chart Cover](../../OriginalNativeCurveChartCover/DESIGN.md) | depends on | original finite span/cycle owners | Exact translated curve laws | Every seam incident owner retained before publication |
| [Surface Chart Cover](../../OriginalNativeSurfaceChartCover/DESIGN.md) | depends on | original finite tensor span/cycle owners | Exact independent U/V transports | Selected closed support and source binding retained |
| [Query Admission](../../CurveSurfaceQueryAdmission/DESIGN.md) | coordinates with | independent depth, work and bytes | Shared caller allowance | Check word to byte arithmetic |

## Architecture
```text
public rich/discrete entry -> source eligibility -> query-local allowance
  -> original curve spans x source-issued surface chart tokens
  -> original laws -> local proof or common original refinement
  -> all selected cells zero dimensional -> exact source endpoint ownership
  -> exact lexicographic tuple order -> localization -> points + chart-indexed receipt
```

## Contracts and Invariants
Intersect requested and native closed domains exactly, including singleton and
excluded products. Empty success retains complete exclusion coverage. Repeated
roots yield one tuple; distinct UV tuples at the same XYZ and close roots remain
distinct. Each chart retains its immutable original laws and issuer-native domains.
Discrete and single-chart rich entries retain complete local decompositions;
multi-chart rich entries retain one complete common refinement and exact
source-owner exclusion evidence, including empty and domain-exclusion coverage. Source endpoint ownership follows the original
BSplineBasis knotSpan rule: lower inclusive, internal upper exclusive, final
nonperiodic native upper inclusive on the last positive span. Every periodic
upper seam is exclusive on its left chart and owned by the right translated
chart, including a selected final singleton. Periodic chart issuers retain both
incident owners, so this exact choice loses no selected endpoint. Exact field-to-authored-knot
comparison applies this rule independently to t/u/v before publication. Repeated
zero-length knot intervals are not charts. Closed singleton requests at a knot
therefore select the right original owner, including surface corners. Source
validation remains authority for admission: it currently rejects position
discontinuities with internal multiplicity greater than degree; no new admission
or smoothing is introduced here.
Within a decomposition, stack order is exact. Across charts, lexicographic order
uses the existing algebra owner's exact scalar comparison port, retaining achieved
parameter/coefficient depths. Chart indices, numerical representatives, XYZ and
isolation-overlap alone never establish cross-field equality or order. Boundary
ownership gives one chart for each admitted tuple; distinct UV stays distinct.
Periodic public nativeDomains have nil bounds for the whole parameter ambient;
nonperiodic axes retain closed native bounds. Requested periodic ranges are finite
explicit selections or the existing public [0, period] default. Effective domains
intersect only nonperiodic native constraints; they never wrap, restrict or
canonicalize distinct unwrapped parameter tuples. Immutable sourceCharts expose
issuer-bound native domains, span indices, independent cycles and original
translations. Original point handles select their chart descriptor through their
retained receipt. Publisher enclosures and representatives use translated
issuer-native bounds, never unshifted knot indexes.
The receipt's public native/requested/effectiveDomains describe the entire query,
preserving single-span semantics. Its retained source binding collection and each
point's chartIndex identifies the exact law and original span. Its cellIndex
addresses the retained common refinement for rich multi-chart queries, or that
chart's decomposition for the unchanged isolated path. The receipt records this
partition owner explicitly; cell indices never address a foreign partition. Raw sources and exact ordered-field
coordinates remain retained. Foreign receipt identities are rejected.
Numerical parameter isolation starts from the retained original zero-cell section
bounds, verified against the actual field coordinate. Exactly equal coordinates
reuse the same retained bounds; achieved localization depths survive publication
in the immutable receipt. Native localization may reuse a retained rational-coefficient
section root through the existing root refinement port. An exact affine field
identity binds that prefix root to the final coordinate; both the identity and
transported lower/upper signs are verified, with the original final field owner
retained. Linear tower fibers are substituted only by their original exact law.
The same primitive's refined interval can serve affine coordinates of that cell,
without independent bisection of a linear fiber. Original parameter and coefficient
causal depths, all work and all cumulative allocations survive transport. The
receipt retains these affine/root proofs together with the final scalar bounds.
Original curve interval
laws produce XYZ seeds, likewise verified against the exact original point.
Numerical XYZ and parameters lie inside outward exact-root enclosures; position
error and residual obey unchanged distance tolerance. Kind compares original
squared tangent/normal incidence to the exact represented angle threshold;
undefined tangent or normal is mixed. Point Codable stays unchanged.

## Runtime Flows
The same allowance admits preparation, source bindings, selected complete decomposition, exact ordering,
retention and localization. Product count uses checked multiplication and the
existing caller maximumSpanCount (ordinary maximumCandidateCount) as one cumulative
ceiling; it never resets for a curve span or surface axis. The result ceiling
counts source-owned tuples across the whole query after boundary ownership.
Rich multi-chart publication composes the retained chart products first, then
localizes only zero-dimensional global connected components. Local boundary cells
attached to a positive neighbor do not enter points. Every product is visited even
when earlier products yield points; any later
positive-dimensional, unresolved, resource or cancellation failure rejects the
entire query. All collection allocation is admitted before reserve/append.
Iteration limits bound publication. Geometric, source recursion and exact algebra
depths remain independent. Ordinary queries use local value option allowances;
selected queries forward caller callbacks. The ordinary allowance admits at most
maximumSubdivisionCells visited exact cells, maximumSubdivisionCells times
maximumIterations scalar work units, and scalar-work allowance times
retained Cell stride in cumulative storage bytes. These products use checked arithmetic;
all existing option ceilings, source degree and publication iterations remain
unchanged. This new scalar-work mapping does not change legacy overlap ledgers.

## State, Ownership, and Lifecycle
Receipt and retained field owners are immutable Sendable. Point handles retain
the receipt and original sources. Mutable accounting and refinement are local;
no shared state, target isolation branch or unsafe synchronization is introduced.

## Failure, Concurrency, and Constraints
Degree, span, source, work, storage, exact depth, result count, iteration and
cancellation failures propagate. Incomplete coverage never grants empty success.
Publication checks cancellation after the final storage-admission callback returns
and before exposing either points or complete empty coverage. A callback that cancels
the current task and returns normally must still produce CancellationError.
No tolerance equality, XYZ deduplication, fitted law or fallback grants authority.
Later public coordinate queries receive their own explicit allowance.

## Verification and Change Impact
[NativeCurveSurfacePointTests](../../../../Tests/CADGeometryTests/NativeCurveSurfacePointTests.swift)
owns public weighted/transverse, repeated/tangent, curved, multi-UV, close-root,
closed/singleton/exclusion, selected equality, lifetime and explicit-limit tests.
Selected rich and discrete entries also test cancellation inside their final storage
callback for both a point result and complete empty coverage. NativePeriodicCurveSurfaceRelationTests
owns curve-only, surface-only and both-periodic ordinary/admitted rich/discrete
coverage, independent translated tuples, closed seams/singletons, full positive
and mixed components, empty exclusion, retained lifetime and independent failure.
Review the actual public entry, preparation, decomposition, all-cell dimension
gate and exact-root publication paths when this contract changes.
