# Native Curve Surface Point Relations

## Purpose and Scope
Child of [Curve Surface Overlap](../DESIGN.md). Owns complete isolated original
parameter tuples for nonperiodic, positive-weight, single-span Bezier B-spline
curve and tensor B-spline surface products on finite closed native domains.

## Responsibilities and Boundaries
Admit original sources, prepare exact homogeneous laws and consume complete
three-coordinate decomposition. Publish only when every selected cell has
zero dimension. Any positive-dimensional cell fails with nonDiscreteIntersection;
no subset is returned. Other families retain existing dispatch. After admission,
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
| [Query Admission](../../CurveSurfaceQueryAdmission/DESIGN.md) | coordinates with | independent depth, work and bytes | Shared caller allowance | Check word to byte arithmetic |

## Architecture
```text
public rich/discrete entry -> source eligibility -> query-local allowance
  -> original laws -> complete native decomposition -> all cells zero dimensional
  -> exact lexicographic tuple order -> localization -> points + immutable receipt
```

## Contracts and Invariants
Intersect requested and native closed domains exactly, including singleton and
excluded products. Empty success retains complete exclusion coverage. Repeated
roots yield one tuple; distinct UV tuples at the same XYZ and close roots remain
distinct. Ordering follows exact decomposition stack coordinate order.
The receipt retains raw sources, complete decomposition, cell identities and
exact ordered-field coordinates. Foreign receipt identities are rejected.
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
The same allowance admits preparation, decomposition, retention and localization.
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
callback for both a point result and complete empty coverage.
Review the actual public entry, preparation, decomposition, all-cell dimension
gate and exact-root publication paths when this contract changes.
