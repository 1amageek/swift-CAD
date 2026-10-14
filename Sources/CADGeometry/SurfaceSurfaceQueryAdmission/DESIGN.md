# Surface Surface Query Admission

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), without children. Owns immutable caller
admission forwarded across one original surface-pair intersection invocation.

## Responsibilities and Boundaries
The caller owns cumulative work and retained-storage accounting. This adapter
borrows distinct work-visit and retained-byte callbacks, source depth and enclosure limits; it never creates or
resets a private allowance. Search, continuation, atlas and final source proof
keep their existing local option ceilings in addition to caller admission.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original intersection publication | Coordinates proof and numerical candidates | Numerical stations do not prove membership |
| [Original Geometry Source Validation](../OriginalGeometrySourceValidation/DESIGN.md) | depends on | paid original source traversal | Bounds preparation | Preserve exact source depth |

## Architecture
```text
caller callback and limits -> immutable invocation adapter
 -> original preparation -> search -> root candidates -> continuation
 -> original graph atlas -> completeness -> original curve publication
```

## Contracts and Invariants
Every source-sized loop forwards the same callback before inspecting its item.
Prepared closed enclosures use the exact caller source depth, subdivision depth
and span bound. Legacy entry points retain historical enclosure defaults and
cancellation checks without inventing a cumulative work ceiling. Numerical
evaluation remains a candidate; original closed interval proof is authoritative.
Predictor anchor coordinates enclose the original endpoint quotient and retain
its rounding uncertainty in every Krawczyk center bound. Rounded numerical
normalization is a search hint only and cannot authorize a graph certificate.
Graph normalization scales and predictor displacements enclose subtraction of
the original stored endpoints. Taylor second-direction coefficients multiply
those outward intervals, rather than treating rounded differences or squared
binary64 products as exact source coefficients.
Quadratic predictor ranges use Bernstein endpoint and tangent coefficients
formed from the original interval endpoints. A rounded midpoint cannot define
the middle Bernstein coefficient. Fixed-point radii use outward multiplication
and addition separately and a downward available-domain radius; a rounded
positive margin cannot authorize the contraction certificate.
Search-box transport encloses the complete requested normalized interval under
the original endpoint affine law, then intersects the enclosure with the authored
native domain. Numerical endpoint interpolation is a candidate operation and
cannot define a smaller box for completeness exclusion or graph coverage.
Root contractions are expressed in the actual proof box's local chart. They
must first map through that original proof box, then through the original
global domain inverse with outward division before intersecting the search
box. Reusing the search box's rounded normalized width would change the proof
chart and can incorrectly remove an endpoint root.
Krawczyk gauge and center-Taylor residuals evaluate the original affine chart
at their declared normalized station through a closed native enclosure. A
rounded native station is not substituted for that function value. Numerical
gauge refinement proposes dependent centers but cannot change the fixed free
coordinate of the proof.
Graph joins consume the retained Krawczyk root enclosure at the declared free
endpoint. Original position and tangent intervals over that enclosure authorize
distance and angular continuity; numerical anchor evaluations remain candidates.
The same gauge producer supplies both a numerical representative and its closed
root bounds, avoiding a second proof law or independent allowance.
Root candidate linear solves admit their augmented rows and result buffers before
allocation and forward the same work visit at each elimination stage.
Search domains require finite strictly positive parameter spans. Spatial distance
tolerance is not a minimum chart width: changing parameter units must not remove
a legal bounded support. Interval rank and caller exhaustion still authorize
explicit failure when a particular chart cannot be certified.
Implicit cell admission likewise requires finite ordered original endpoints
with positive spans; the modeling relative tolerance is not a minimum cell
width. Geometric containment, rank, uniqueness and resource proofs still apply.
Stored callbacks are Sendable and retain only the caller's isolated allowance.
Byte admission never flows through a source-depth callback. Preparation forwards
the same retained-byte callback through the native coefficients and nested
prepared curve/surface owners before those allocations. Query-local enclosure
coefficients and numerical candidate buffers must also use their actual allocation
owners; complete invocation storage admission remains open until those ports connect.

### Exact Authored Plane Boundary Graphs

For two direct planes with authored U directions, the source map is original
origin plus original U times u plus the exact original normal-cross-U times v.
The exact rational affine graph producer solves the original normalized
three-by-three dependent system with two right-hand sides. Nonzero exact pivots
prove a unique global affine graph. Exact endpoint signs prove whether its
dependent coordinates lie in the closed authored unit cube, including boundary
coordinates equal to zero or one. Gauge publication brackets the same rational
solution. Numerical normalizations and interval rounding slack cannot establish
incidence. Other surface families retain their separate proof owners; absence
of this producer's supported source law means unresolved, never empty.
The producer borrows the same work and optional checked UInt32-byte admission.
It creates no private allowance or algebraic extension and does not change
the legacy normalized plane-basis selection rule.

### Retained Original Domain Pairs

An explicit pair of finite closed UV boxes selects regions of the unchanged
original supports. Each box must be contained in any closed source domain;
the regular producer rejects singleton or nonfinite spans. Native isolated pairs use
the [Native point contract](../NativeSurfaceSurfacePointRelations/DESIGN.md) instead:
closed singleton selections and exact intersection with native domains retain complete
coverage or complete exclusion. The producer prepares each original
support once and uses the same domain map, completeness search, continuation,
atlas and final original curve publication as the whole-domain entry. It does
not construct or round a restricted surface. Completeness is scoped to this
requested box pair, and all local/caller limits and callbacks remain unchanged.
Same-support global self-contact composition owns its independent exclusion of
the diagonal and local injectivity proofs; a domain-pair entry never supplies
those proofs merely because its input boxes are distinct.
`OriginalSurfacePairIntersecting` is the public invocation-session requirement.
The prepared implementation retains the two admitted immutable original support
owners, their preparation tolerance and the same caller callbacks. Every box
query derives its sources from those owners and reuses them; callers cannot
replace a surface, tolerance or ledger after preparation. Single-span Native selection precedes the
[Native multi-chart producer](../NativeMultiChartSurfaceSurfaceRelations/DESIGN.md).
An applicability nil selects the next producer; an admitted producer failure
propagates. Both rich and discrete session queries pass the identical retained
admission, original supports and closed requested boxes. The rich path retains
complete point/relation authority; the discrete path rejects any positive
component atomically. Options remain local
query limits in addition to the session's cumulative admission. Unsupported
custom factories fail explicitly rather than allocating a legacy producer.

A self-pair preparation aliases one immutable admitted support owner for both
roles; it does not decode the same coefficients twice. The session exposes a
non-generic first-support closed differential enclosure using that owner and
the same caller admission. This receipt does not certify local injectivity or
contact absence by itself. An additive first-order continuity query consumes
the retained original prepared support and the same algebra/work/byte admission;
a missing original join issuer is not an affirmative continuity receipt.

## Failure, Concurrency, and Constraints
Cancellation and caller exhaustion propagate directly. Nonpositive span limits
and negative depth fail before preparation. This immutable adapter owns no shared
mutable state and introduces no platform-dependent isolation differences.

## Verification and Change Impact
After the complete implementation phase, exercise public success, failure and
one-less cumulative limits through preparation, root iterations, continuation,
atlas and final assembly. Recheck Geometry producers and drawing/Boolean callers
if callback semantics or original source limits change. Source wiring alone is
not behavioral completion evidence.

Atlas construction borrows traced sample slices, rather than copying the same
component at each graph candidate. It admits coverage and ordered-entry buffers
before allocation, checks concatenation counts for overflow, and sorts the four
free-coordinate candidates in place. Positive finite chart spans remain legal
regardless of the relative modeling tolerance; interval certification still owns
regularity and complete coverage.

A retained implicit graph exposes caller-admitted numerical parameter and point
queries using the same prepared support owners. Its Newton candidates keep the
existing 32 iterations and 12 line-search steps; seed, COW candidate, column and
cofactor-result arrays are admitted before allocation. These numerical points
do not replace closed original enclosures or root certificates.

Position-only root candidates consume original closed D0 boxes without requesting
higher derivatives. Published implicit point residuals are upper bounds against
both original closed singleton support positions; a rounded numerical zero alone
cannot authorize success. Candidate coordinates use finite interval midpoints to
avoid overflow while averaging large positions.

Implicit parameter derivative bounds forward the same prepared owners and caller
admission to the original graph prover. Bounded calls do not enter the legacy
opaque native decomposition shortcut. Native derivative scaling encloses the
original parameter endpoint subtraction and orientation product before outward
publication, with actual four-coordinate scratch/results admitted.

A Krawczyk image authorizes closed-domain existence only when every dependent
interval is contained in the exact unit cube and the map is a strict contraction,
or when the existing strict-interior theorem applies. An ulp allowance cannot
replace containment: a root just outside an authored boundary remains outside.
Unresolved original boundary incidence must remain explicit rather than clipping
an external root into the support. A restricted subcell inherits existence from
its already certified parent. Its gauge enclosure starts with that parent's
closed box, contracts the known root, and extends it by the original derivative
mean-value bound. Numerical endpoint samples do not own its range. Zero-width
closed restrictions are legal; original affine widths and reversal are outward
interval operations. All prepared owners, visits and typed buffers use the same
caller admission.

Caller work admission and byte policy are independent. A selected caller work
ledger retains its source/span/depth contract when storage admission is nil.
Only a nonnil byte callback selects bounded descendant allocation admission;
legacy work-only callers receive no no-op callback and no storage guarantee.

### Native Isolated Rich Publication

`OriginalSurfacePairIntersecting.intersectionResult` is a non-generic protocol
requirement, so existential session queries dispatch through a witness on every
target. The prepared pair keeps its original admitted support owners and ledger.
Native single-span pairs use the exact four-coordinate point producer before
regular search; the rich result retains immutable original coverage even when
empty. Array queries return this same result’s intersections. Positive-dimensional
Native selections fail atomically. Ineligible source families keep existing regular
search and return a nil Native receipt. Final result admission is followed by a
cancellation check; a cancelled callback cannot publish success. No synchronization
or Sendable contract changes across targets.

### Bounded Protocol Witness
The bounded intersector requirement carries optional byte admission and optional independent algebra depth in addition to source and spatial depth. Its concrete implementation has exactly the same optional storage signature. A selected algebra cap is forwarded unchanged to the existing original surface-pair producer. The compatibility admitted overload delegates with no selected algebra cap; an injected legacy conformer without the new admission witness fails explicitly rather than invoking an unmetered method. Nil storage stays nil throughout dispatch. [BoundedSurfaceSurfaceAdmissionWitnessTests](../../../Tests/CADGeometryTests/BoundedSurfaceSurfaceAdmissionWitnessTests.swift) verifies concrete and existential dispatch, separate depth/work/byte refusal and cancellation.

### Root-free sphere-cone preparation selection

Preparation selects the existing apex or bounded receipt before the broader
[source-issued full family](../OriginalSourceIssuance/DESIGN.md#g01-root-free-sphere-cone-family-consumption).
It prepares a full sphere-cone receipt only when neither specialized receipt
was selected. Array and rich session queries preserve that same order and
retain the chosen immutable owner under the original caller admission.
