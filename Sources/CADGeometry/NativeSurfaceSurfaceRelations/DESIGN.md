# Native Surface Surface Relations

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md). Own complete finite closed nonperiodic
positive-weight single-native-span SSI parameter relations, including isolated,
curve, branched, coincident and mixed components.

## Responsibilities and Boundaries
Publish immutable original four-coordinate cell and component authority. Original
closure/incidence owns connectivity. A retained rational XYZ graph owns image and
fiber dimensions, independently of parameter dimension or Jacobian rank. Numerical
SSI arrays cannot represent these relations and reject positive-dimensional results.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | rich SSI result | All rich routes retain relations | Legacy arrays reject non-discrete coverage |
| [Native SSI Points](../NativeSurfaceSurfacePointRelations/DESIGN.md) | coordinates with | source preparation and isolated publication | Same sources and caller ledger | Isolated fast path remains authoritative |
| [Intersection Algebra](../IntersectionAlgebra/DESIGN.md) | depends on | original decomposition, cells, closure/incidence | Exact full-domain proof | No rank or sample joins |
| [Query Admission](../SurfaceSurfaceQueryAdmission/DESIGN.md) | coordinates with | cumulative work/storage | One invocation | Independent source and algebra depths |

## Architecture
```text
rich normal / admitted / domain-pair / prepared session
 -> unchanged original source laws and requested closed domains
 -> original four-coordinate decomposition + closures + connected components
 -> original rational XYZ graph (XYZ,u1,v1,u2,v2)
 -> graph cells bound by exact original four-coordinate cell conditions
 -> immutable relation receipt + isolated component numerical points
```

## Contracts and Invariants
Every selected original cell, original connected component and closure attachment
is retained. All original equations, denominator guards, real-zero certificates,
raw Jacobian and native/requested/effective domains remain in the decomposition.
Graph equations retain the original homogeneous source map and strictly nonzero
denominators. Original cell conditions partition the graph; exact condition
membership binds each graph cell to exactly one original cell. XYZ-prefix cell
dimension proves image dimension; total graph-cell dimension minus that prefix
proves fiber dimension, including exceptional fibers. Component image dimension
is the maximum of its graph image-cell dimensions. Parameter dimensions remain
independent. No numerical proximity, representative rank or sample matching
establishes connectivity or coincidence. Graph sample coordinates are witnesses
of exact sign-invariant cells, not a coverage substitute.

Exact rational tuple membership checks retained original cell conditions. Exact
first/second UV fiber queries intersect the original requested domains with the
specified singleton UV domains, reuse the original source system and return a
complete independently owned receipt. Stations outside the retained requested
domain are invalid input in both rational and algebraic query overloads. Retained
algebraic stations use the existing ordered coefficient compiler, preserve their
independent parameter/coefficient depths, and return a source-owned complete
OriginalRealRelation. Fixing both source UV coordinates proves its image dimension
is zero while its opposite parameter fibers can have any admitted dimension. Foreign cell/component handles fail.

## Runtime Flows
All source preparation, decomposition, graph, retained maps, samples and publication
charge the same caller ledger before allocation. Graph-cell owners are counted before
reserving each retained image array; polynomial witness capacity uses the checked
original-condition upper bound. Isolated component indices reserve their actual
selected cell count. Any graph or publication failure
rejects the entire result. Existing component ceilings count original connected
components, not auxiliary subdivision cells. Cancellation is checked immediately
before publication. An array adapter rejects any positive-dimensional original
component before exposing isolated subsets. Query-time membership and fibers have
their own explicit caller admission and cannot reset retained source depth.

## State, Ownership, and Lifecycle
The receipt is immutable Sendable and retains both raw sources, original
source-domain decomposition, graph, the original graph ideal and cell conditions.
Rational fiber receipts retain their source receipt and accumulated query depth. Handles retain their
receipt; no shared mutable state or target-specific isolation is introduced.
Query work is value-local, including accounting and graph construction.

## Failure, Concurrency, and Constraints
Original source/domain, depth, work, bytes, cell/component ceilings and cancellation
failures propagate atomically. Empty success requires the entire requested product
exclusion proof. Unsupported source families retain existing dispatch; this
component does not claim whole general SSI or proximity/repair semantics.

## Verification and Change Impact
[NativeSurfaceSurfaceRelationTests](../../../Tests/CADGeometryTests/NativeSurfaceSurfaceRelationTests.swift)
verifies transverse/contact/branched curves, coincidence, mixtures, collapsed
images and multiple UV fibers, strict exact membership and foreign owner failure,
normal/admitted/domain/session publication, legacy rejection and independent
resource/cancellation failures. Existing isolated SSI tests guard the unchanged
fast path, weighted/nonclamped sources, real-zero proof and tuple localization.
Root composition and portable targets must execute these same production paths.
