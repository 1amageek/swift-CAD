# Native Surface Surface Relations

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md). Own complete finite closed nonperiodic
positive-weight SSI parameter relations from a genuine single-native-span decomposition
or a genuine common original-chart coverage, including isolated,
curve, branched, coincident and mixed components.

## Responsibilities and Boundaries
Publish immutable original four-coordinate cell and component authority. Original
closure/incidence owns connectivity. A retained rational XYZ graph, or a validated
[original chart injection proof](../NativeSurfaceChartInjection/DESIGN.md) for positive
common coverage, owns image and fiber dimensions independently of Jacobian rank. Numerical
SSI arrays cannot represent these relations and reject positive-dimensional results.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | rich SSI result | All rich routes retain relations | Legacy arrays reject non-discrete coverage |
| [Native SSI Points](../NativeSurfaceSurfacePointRelations/DESIGN.md) | coordinates with | source preparation and isolated publication | Same sources and caller ledger | Isolated fast path remains authoritative |
| [Intersection Algebra](../IntersectionAlgebra/DESIGN.md) | depends on | original decomposition, cells, closure/incidence | Exact full-domain proof | No rank or sample joins |
| [Multi-chart Native SSI](../NativeMultiChartSurfaceSurfaceRelations/DESIGN.md) | used by | genuine common original coverage | Geometry prepares Native meanings and source bindings | The coverage owner stays below producer |
| [Native source zero set](../NativeSurfaceSourceZeroSet/DESIGN.md) | depends on | exact source-bound real-zero factor laws | Necessary constraints for common coverage | Keep raw equations/rank and all original chart witnesses |
| [Chart injection](../NativeSurfaceChartInjection/DESIGN.md) | depends on | full closed original source-map proof | Exact cell image dimensions without graph when proved injective | Retain and validate both roles and every chart; single-positive path unchanged |
| [Query Admission](../SurfaceSurfaceQueryAdmission/DESIGN.md) | coordinates with | cumulative work/storage | One invocation | Independent source and algebra depths |

## Architecture
```text
rich normal / admitted / domain-pair / prepared session
 -> unchanged original source laws and requested closed domains
 -> original four-coordinate decomposition + closures + connected components
 -> original rational XYZ graph or validated common chart injection proof
 -> exact image strata bound to every original four-coordinate cell
 -> immutable relation receipt + isolated component numerical points
```

## Contracts and Invariants
Every selected original cell, original connected component and closure attachment
is retained. All original equations, denominator guards, real-zero certificates,
raw Jacobian and native/requested/effective domains remain in the decomposition.
Graph equations retain the original homogeneous source map and strictly nonzero
denominators. For the graph path, original cell conditions partition the graph; exact condition
membership binds each graph cell to exactly one original cell. XYZ-prefix cell
dimension proves image dimension; total graph-cell dimension minus that prefix
proves fiber dimension, including exceptional fibers. Component image dimension
is the maximum of its image-stratum dimensions. For proved injective common charts,
each complete original four-UV cell maps to one image stratum of the same dimension
and zero fiber dimension; its retained proof is the authority, as defined by the
[chart injection child contract](../NativeSurfaceChartInjection/DESIGN.md).
Parameter dimensions remain
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
source-domain coverage, cell conditions and either the graph/ideal or genuine
source-map injection proof. The optional proof reference is admitted at its actual
stride before receipt allocation; rational common fibers reuse the full-native proof.
Its private common-graph guarded-equation array retains the original source-map
division evidence after publication and input release. The same ledger admits
the array's entire buffer and the receipt's additional array-header stride before
allocation; single-chart graph mathematics remains unchanged.
Rational fiber receipts retain their source receipt and accumulated query depth. Handles retain their
receipt; no shared mutable state or target-specific isolation is introduced.
Query work is value-local, including accounting and graph construction.

Common coverage is defined here, below the multi-chart Geometry adapter. The common
partition uses the exact original right-owner DNF on four coordinates. Algebra receives
only laws, predicates and domains; the adapter retains Native chart meaning. Each cell
publishes its canonical chart index, while sourceChart access retains every closed incident
chart and native knot index. Rational fibers rebuild this same coverage with singleton
requested domains; ordered fibers append station laws to every retained source branch.
The piecewise graph's necessary product equations are exact consequences of every active
source branch. Rational-unit-normalized equal factors are multiplied once, with original
raw laws and sign directions retained. These products reduce the ideal but never replace
the full original branch predicate or certify dimensions by ideal classification.
Common coverage It retains
original source bindings, full original laws/predicate/domains, the authoritative common
partition/incidence/components, raw ranks and canonical chart owners. A piecewise XYZ
graph uses each owner's original homogeneous law and the same exact boundary predicate.
Exact rational and ordered station fibers retain all owner branches. The single-span
decomposition remains genuine and its existing reduced-ideal graph path is unchanged.

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

The multi-chart guarded refinement reuses OriginalGuardedIntersectionEquations to
remove only factors certified nonzero by the retained original denominator guards.
Each chart retains that exact division receipt and its normalized equation ideal.
Raw Jacobian minors first remove only certified original guard factors, before
chart-ideal reduction can hide their polynomial divisibility. Those quotients are
reduced by the chart's exact ideal as in existing original strata, then remove any
remaining certified guard factors for their zero/nonzero rank tests. Raw equations,
Jacobian, ideal and all three guarded division receipts remain retained. A quotient's
sign need not equal a raw minor's sign; rank uses only exact zero versus nonzero.
Every chart-owner branch still enforces all original nonzero guards and closed bounds.
The positive 4-UV partition remains unpruned for original incidence. The separate
7-coordinate graph has no incidence consumer and admits existing necessary-equation
prefix exclusions; the exact necessary products and full DNF certify these exclusions.

The common XYZ graph first normalizes its three raw homogeneous graph equations
with the retained remapped original nonzero denominator guards. Each selected
chart branch therefore zeros its normalized graph equations exactly when it zeros
the raw graph equations. Necessary products contain these normalized factors;
the original full source DNF and graph zero conditions remain the selection
contract. The graph receipt retains all raw graph equations, remapped guards and
exact divisor identities through the immutable public relation owner. Common
denominator factors certified nonzero on each selected chart do not add their unrelated
zero loci to the necessary graph ideal.
This equivalence is used only for equality, without any quotient-sign inference.

The finite nonperiodic common graph uses an exact closed XYZ enclosure derived
from original control-point extrema across all retained first-source charts.
Source validation requires finite strictly positive weights. On each validated
closed native span, the original Cox-de Boor basis is nonnegative and partitions
unity; after positive-weight normalization its homogeneous quotient is a convex
combination of the original control points. Each selected span polynomial retains
its interior partition-of-unity identity at both closed endpoints; the canonical
right owner selects the corresponding original span at an interior knot. Thus
every selected original graph point lies in this enclosure, including native joins
and endpoint singletons.
Only ordering of finite source Double values chooses the extrema; exact dyadic
endpoint conversion performs no rounded coordinate arithmetic or tolerance growth.
The retained original chart sources and graph domains bind this enclosure proof.
Existing exact domain-prefix exclusions retain the violated endpoint/sign witness
before later lifting. No graph point in the requested original UV product is
excluded, and XYZ-prefix image dimensions and remaining fiber dimensions retain
the same meaning. The four-UV incidence partition is unchanged. This changes only
the common graph's auxiliary domains; single-chart graph construction and retained
owner allocation remain unchanged. Every source visit and actual buffer capacity
is admitted by the same cumulative ledger before use.

The common graph condition-witness tail uses the immutable four-UV tower as its
source authority. OriginalIntersectionCellCondition constructs every full tuple
condition by visiting the same tower.levels[3-axis].sources for all four parent
axes. Exact duplicate removal yields that shared polynomial vector, while only
the retained cell.signs distinguish conditions. The graph therefore admits one
exact union of those global derivative-closed sources and remaps/reduces each
unique source once. It never reuses one cell's signs as another cell's authority.
All original conditions and their signs remain retained for exact graph ownership.

The condition-witness tail follows the existing single-graph normalization:
on the retained graph ideal, a zero or constant remainder has a fixed sign and
requires no additional sign cut. Exact matching nonconstant remainders require
one shared sign-invariant partition law. The complete original condition can
still be evaluated on every graph leaf because its original law differs from
that remainder by an ideal element, which is zero on every selected graph cell.
The coverage-law prefix, graphStart and every graph-clause logical ordinal stay unchanged;
all original DNF, guards, source owners, necessary graph constraints and image/fiber
coordinates remain authoritative. Buffer capacities use the checked full tower
source-count upper bound and are charged before allocation. Source comparisons,
remapping, ideal reduction and append visits consume the same cumulative ledger.

The common graph compiles that logical prefix and the witness tail into a unique
physical partition-law vector. Logical coverage and per-chart graph ordinals retain
their original source meaning; Cells physical ordinals are an internal compiler
representation. Every logical prefix law is remapped/reduced by the same retained
graph ideal. A zero or constant remainder records its exact fixed sign; every
nonconstant remainder records the physical ordinal of an exact matching retained
law, or appends that law once. The tail shares the same physical union.

For a coverage sign atom, the original rational-unit sign reversal is applied
first, with the same original negative/zero/positive direction. The compiler then
emits either an exact literal comparing the requested sign with the fixed sign,
or the same requested sign at the mapped physical ordinal. Graph zero atoms use
the same compiler. Every literal, not, and, or, chart-bound and guard operation
retains its original position and meaning; no clause is dropped or reordered.
Every selected graph cell zeros the retained ideal, so each original logical sign
equals the remainder sign there. The rewritten entire DNF therefore selects
exactly the same original graph. Exact duplicate laws and fixed signs add no
projection roots or derivative cuts. Original cell conditions and all raw source,
guard, division and domain evidence remain retained for publication and queries.
Both ordinal and fixed-sign maps, the full physical buffer upper bound, comparisons,
exact constant signs, remapping, reduction and append visits use the original
checked cumulative ledger. No public type, API, failure, limit or solver changes.

## Common Necessary-Law Composition
Before original cell preparation, Geometry retains every nonzero normalized source
equation shared by all active chart branches. It also retains common factor laws
issued by the [Native source zero-set proof](../NativeSurfaceSourceZeroSet/DESIGN.md).
Each necessary law has one retained original equation or proved consequence witness
per active chart. Partial coupled constraints remain necessary even when they do
not prove all four coordinates finite. Independent-coordinate product witnesses
remain valid additional necessary constraints. Only a proved zero-dimensional or
inconsistent necessary ideal allows finite-prefix exclusion; positive products
remain unpruned for full original closure and incidence.

The exact logical-sign compiler reduces each original unit-normalized law on this
retained necessary ideal. Fixed zero/constant remainders emit literal signs; exact
equal nonconstant remainders share a physical partition law. Original three equation
ordinals, guard +3 offsets, bound/minor starts, negative-unit directions and complete
DNF operator order remain unchanged. Source bindings retain the original normalized
laws and raw Jacobian; chart-local rank witnesses may reduce using proved real-zero
consequences, whose exact source proof is retained. No ideal classification asserts
actual selected dimensions or components. Every selected leaf zeros the necessary
ideal, so original signs equal their mapped remainder signs there. Owner selection
uses this same mapping and actual partitionSignOffset.

Common coverage retains logical units, physical ordinals or fixed signs, the necessary
ideal and all per-chart witness rows. The common graph adds remapped necessary laws
to its own ideal before consuming this compiled predicate; fixed logical signs are
therefore valid on every selected graph leaf too. Ordered station fibers append
the retained necessary basis as zero clauses before the exact station clauses;
a compiled physical predicate is never used without its necessary-ideal authority.
Full original source laws, guards,
domains and closure authority stay retained. All mapping, reduction, comparison,
array/header buffers and append work use the same checked cumulative ledger.

A retained closed-chart corner proof can replace only its source equation's zero
atom by two linear zero conjuncts inside that chart's original bounds. The original
equation keeps its raw logical ordinal and source authority, but has a distinct
domain-bound-zero marker, never a global fixed sign. Common owner checks and graph
clauses consume the same proof's factor atoms; ordered fibers retain the compiled
whole bounded DNF. These branch factors do not enter the global necessary ideal.
They may reduce chart-local rank witnesses, whose raw Jacobian remains authoritative
only when that exact bounded branch owns the selected cell. The algebra partition,
positive unpruned closure, incidence and connected components remain the one common
original refinement. See the [corner evidence contract](../NativeSurfaceSourceZeroSet/DESIGN.md).

Rational root extraction and rational field singleton isolation consume no new
subdivision depth. Depth-zero rational success is valid. The same authored irrational
multi-chart fixture must still reject depth-zero generation and retained querying,
while depth 32 succeeds. Query depth never resets inherited original cell depth.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
