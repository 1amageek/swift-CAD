# Original Root Span

At the user-requested implementation freeze, parameter-polynomial incidence
constraints retain their actual common source and portable identity, but their
Native polynomial codec is unfinished. Native encoding/decoding refuses this
case explicitly while preserving the existing plane/axis wire fields. This is
an incomplete capability, not a substitute root law. Closed native jet covers
retain one-sided owners; taking their componentwise hull does not establish join
continuity or grant a mean-value proof.

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns exact original
curve incidence roots and normalized traversal charts whose endpoints retain
original authored values or original algebraic root witnesses.

## Responsibilities and Boundaries

Original curve coefficients, constraints and isolated source roots determine
endpoint authority. Numerical root events propose isolating intervals but do
not establish incidence. Revolution construction and boundary publication are
owned by Modeling; source normals and surface jets remain Geometry contracts.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original curve laws and intervals | Integrates source traversal. | Preserve original parameters. |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | original homogeneous polynomial, GCD, Sturm and root signs | Establishes exact incidence. | Original bits are rational authority. |
| [Original Higher Curve Jets](../OriginalHigherCurveJets/DESIGN.md) | depends on | original interval Taylor derivatives | Supplies whole closed derivative bounds. | One-sided knot ownership remains explicit. |

## Architecture

```text
original curve/span + raw axis or plane coefficients
    -> exact original homogeneous incidence polynomials
    -> common polynomial GCD + Sturm unique root certificate
    -> source-bound immutable root endpoint
    -> original normalized endpoint traversal + closed derivative intervals
```

## Contracts and Invariants

Axis roots satisfy all three original cross numerators simultaneously; a plane
root satisfies its original dot numerator. Positive original rational weights
exclude denominator poles inside the selected native span. Each endpoint binds
the original curve, span, constraint, isolating interval and preparation tolerance.
An exact root sign witness establishes incidence independently of a numerical
parameter or point. Equal source roots at adjacent spans retain both owning sides.
Whole-span coincidence is distinct from isolated roots. No transformed rounded
coefficient net or root midpoint supplies original source authority.

## State, Ownership, and Lifecycle

Public source fields and preparation caches live in one immutable, checked
`Sendable` storage owner. A traversal value retains that owner and a direction
view; copies and `reversed()` share it without another payload allocation.
Reversal exchanges endpoint/start/end enclosures and negates the retained slope,
while preserving source, native side, tolerance and all independent ceilings.
Equality, hash ordering and Native wire keys still use the directed original
fields only; owner identity, caches and direction implementation are not source
identity. This non-frozen type has no promised stored-field ABI or library-evolution
layout. Public reads and the existing fallible construction API are preserved.

Every constructor, including retained-native preparation and Native decoding,
reserves the concrete storage payload stride before creating its immutable owner.
The original caller execution owns checked payload-byte reservation directly.
There is no slot-stride adapter or copied admission. This is retained payload capacity, excluding
allocator metadata, rather than a claim about arbitrary runtime allocation costs.
Existing source/preparation owners are shared, and their previous admissions are
not repeated for this copy. Query endpoint/capability rebinding creates and admits
one new payload on its existing query ledger; reversal never does so. Exhaustion
prevents the new traversal from being published. Cancellation is checked after
the final payload reservation and before owner creation, including cancellation
requested by a successfully returning admission callback. Exact polynomial and Sturm data
remain immutable retained caches; the caller supplies work, storage, cell and
depth admission.

The ordinary Native cooperative worker stack is a required execution boundary:
large Coons/boundary-corrected aggregate values must not inline-copy every RootSpan
payload through interval-provider frames. This owner representation is identical
on Native, normal WASM and Embedded; it adds no mutable cache, unsafe concurrency
conformance or target-specific storage.

```text
source + endpoints + admitted preparation
    -> reserve retained payload on caller ledger
    -> immutable traversal owner
        -> forward view / reversed view / copied view
    -> stricter query localization + same-ledger new owner when required
```

## Failure, Concurrency, and Constraints

Nonunique isolation, wrong source binding, singular denominators and exhausted
caller admission fail explicitly. Algorithms check cancellation and forward the
same exact ledger. Curve families whose original algebraic angular chart is not
yet supplied remain explicit incomplete branches, never rational image authority.

## Verification and Change Impact

[RootSpan ownership tests](../../../Tests/CADGeometryTests/OriginalRootSpanOwnershipTests.swift)
exercise directed value/hash identity, reversal without retained-storage mutation,
owner lifetime, payload refusal before publication and Native codec reconstruction.
The composed Native worker counterexamples are owned by the
[Loft factory suite](../../../Tests/CADModelingTests/LoftPlaneDerivativeOwnershipTests.swift)
and [Modeling dependency suite](../../../Tests/CADModelingTests/NativeModelingDependencyContractTests.swift):
actual plane-derivative publication and original projection/trim must run on normal
Swift Testing workers, including parallel execution. A main-thread or serialized
success does not satisfy this boundary. Changed representation also requires
actual complete Core/Geometry normal and Embedded WASM compile/link/runtime.

After the source phase, exercise exact rational axis/plane multiple roots,
continuous incidence, roots at both original endpoints, reversed traversal,
source binding rejection and same-budget exhaustion through actual Revolution
and split-section consumers. Verify analytic conic nonlinear charts separately.

Root endpoint records retain original isolator lower/upper endpoint exclusion
flags and isolation depth. Rebuilding a unique-root witness preserves these
conventions; an excluded endpoint root is never reintroduced and refinement
starts at the original consumed depth. Native source encoding and equality
include the flags and depth alongside exact rational stations.

An optional original native span index binds authored knot endpoints as well as
algebraic ones to one original side. Closed jets evaluate only that retained
source coefficient span, so a native C0 join does not impose higher continuity
on a side-owned traversal. Exact endpoint ordering is proved from rational
isolation stations before any outward Double slope enclosure is considered.

Traversal preparation retains immutable original homogeneous owning coefficients
and refined endpoint/slope enclosures under the same caller admission. These
derived caches never enter equality or source codecs. Fixed closed jet evaluation
uses these retained coefficients without a new root solver or private proof ledger;
point results remain numerical representatives with a complete source enclosure.

The package preparedDerivatives port exposes closed normalized D0-D3 intervals
to Modeling from retained coefficient preparation. It forwards the same callback
without reconstructing native spans or refining source roots for each orbit cell.

Native root traversal preparation refines each algebraic endpoint until its
complete original spatial value enclosure meets the position preparation target,
using the same exact caller depth/work/storage. Initial parameter resolution is
only a native-unit proposal. Retained owning coefficients are prepared once and
reused during refinement. Exhaustion, irreducible coefficient rounding or an
unrepresentable narrow enclosure fail rather than publishing a root midpoint.

Closed authored generator endpoints are recognized only from exact original
clamped endpoint controls and the original authored native endpoint stations.
Zero-offset exact negation parameter images recurse without composing rounded
coefficients. Algebraic endpoint equality requires its separate exact source
value authority and is not inferred from coincident numerical points.

Prepared native traversal endpoints and slopes are normalized by the exact rational
original knot difference before conversion to outward floating intervals. This
retains an exact rational root between adjacent representable native stations.
Closed jets evaluate the retained homogeneous law directly in this local chart;
global native parameter intervals remain output bounds, not evaluation authority.

Retained root endpoints expose exact polynomial signs in their original native
parameter using the existing immutable algebraic witness. The caller composes
original scalar incidence or monotonicity expressions; signs forward its original
work/storage/cell/depth allowance without rebuilding an endpoint root solver.


### Whole Original Traversal Preparation

An authored traversal without a selected native owning span retains one immutable
`PreparedCurveDifferentialEncloser` for the complete original source. Its closed
queries forward the composing callback, constructor subdivision ceiling and
original owning-span cover. No rounded spline conversion becomes source authority.
Selected native spans retain the exact local endpoint chart described above.
Whole traversal queries enclose all incident source-owning sides; their hull does
not certify higher continuity at joins. Requested higher Taylor queries consume
the same original source and caller admission, and require the higher provider's
actual continuity/partition premise rather than padding a D3 cache. Preparation
introduces no new span/source-depth ceiling beyond existing producer limits.

Structural traversal identity compares original source, selected owning span,
directed original endpoints and tolerance after charging their complete stored
payload through Structural Geometry Work. Prepared caches and constructor
resource ceilings do not enter source identity. This witness proves identity only,
not equality of geometrically equivalent distinct source graphs.

The package retainedRootEndpoint accessor borrows the immutable admitted exact
algebraic root witness for original coordinate transport. It rebuilds no GCD,
Sturm sequence or isolation, and introduces no allowance. Subsequent coordinate
image/sign operations must use the composing exact ledger and original depth.

### Original Authored Endpoint Position Relation

The endpoint relation issuer retains two original curve values and authored
stations. Original rational knot spans evaluate homogeneous XYZ/W at the exact
station, then compare all three reduced coordinate values. Lines and original
parameter/spatial images compose their original rational coefficients under the
same caller depth/work/storage ledger. No clamping, point candidate, tolerance
coincidence or rounded affine composition establishes equality. Unsupported
angular/procedural coordinate authority and uncovered periodic stations fail
explicitly rather than publishing an unequal or equal success witness.

The package coordinates source port returns exact rational XYZ values for an
admitted original station. Corner algebraic-coordinate consumers reuse this
authority instead of duplicating rational basis or affine-image evaluation.
It preserves the supplied source-depth and exact caller ledger.

Endpoint relation records may retain explicit first/second native owning indices.
Their exact station must lie in the selected positive span; a shared knot never
changes the supplied side. Coordinate consumers forward that owning index through
original parameter and spatial image descendants without replacing the raw law.

The bounded prepared first-order query reuses retained original native/local endpoint preparation or the whole-traversal token with explicit remaining source depth, span and subdivision admission. It publishes only position and first derivative bounds. Native owning-side unions remain piecewise bounds; the composing embedding owner must separately prove C0 and may not infer higher continuity.


Prepared original root traversals retain explicit constructor span/source-depth
capabilities alongside the existing subdivision capability. Legacy defaults
retain the previous no-added-ceiling policy. Bounded callers supply their own
limits; recursive validation and whole-traversal preparation forward them, and
queries use the lesser retained/requested capability. Native selected-span
preparation and requested-order Taylor queries accept actual byte admission;
prepared local exact endpoint/slope authority is reused without renewed root
isolation. Generic higher providers lacking query byte admission fail explicitly
when that accounting is required. Capability caches remain outside persistent
source identity and Native fields.

When a rational-ledger query adapts actual bytes into abstract retained-storage
slots, the composing caller supplies the positive slot byte stride. The adapter
uses checked ceiling division; it does not infer that storage words mean bytes,
Double slots, or source depth. When concrete native preparation byte admission
is supplied, the previous conservative coefficient-slot precharge is omitted
for that same physical payload; exact endpoint/algebra source retention remains
independently charged.


The whole-traversal higher route forwards byte admission to the original higher
provider for ideal conics, lines, nonperiodic native laws and supported images.
The provider retains its own explicit refusal for periodic/implicit/lift byte
families; a root chart cannot turn an unsupported provider into success.


The constructor and first-order/Taylor query ports pass the original execution
directly into Native preparation and coefficient arithmetic. Every concrete
Native/Taylor payload is admitted in bytes on that execution. Query ceilings are
bounded by retained constructor capabilities; retained coefficients are proof
inputs rather than a second budget. Piecewise D0/D1 bounds add no join continuity.

Authored endpoint equality may follow exact structural identity of the entire original source, identical finite authored station and identical selected owning side. Both source payloads are charged before value equality. This proof does not evaluate transcendental coordinates and does not equate different native sides or different charts. Domain and selected-side admission remain required.

A normalized native construction traversal may expose its retained closed owning-jet receipt directly only when its raw source has domain [0,1] and its exact authored endpoints are 0 and 1 in that direction. The original parameter law is identity, so per-owner domains, side metadata and piecewise D0-D3 bounds are retained without a smooth join claim. Caller and constructor span/source/subdivision capabilities both apply; actual query bytes use the same composing execution.

Endpoint connector literal 0/1 stations expose their retained original boundary endpoint, including its original owning side and constructor capabilities. This symbolic incidence is independent of the construction control point and of a numeric position. Exact rational-coordinate consumers peel authored boundary endpoints; algebraic endpoint consumers retain the original root witness and use exact coordinate transport.

The prepared third-order piecewise traversal query accepts actual byte admission and explicit caller span/source/subdivision ceilings. It reuses the same owning preparation and does not infer C3 continuity from the returned hull.

A retained scalar parameter-root constraint is distinct from spatial axis/plane incidence. The package retaining factory binds an already admitted exact algebraic root to one original positive native span, preserving its polynomial, isolation exclusions and consumed depth without repeating GCD, Sturm preparation or isolation. That endpoint proves a unique native station only; the planar contact owner retains the original pair equations to establish contact. Persistent constraints encode the original parameter polynomial, and Native reconstruction verifies the declared unique-root witness under its caller admission.

Construction-chart endpoint relation consumers reuse the child symbolic recipe issuer before rational-coordinate evaluation. A successful recipe identity proves the same original function station without promoting a rounded chart endpoint. Traversal charts expose their retained original endpoints, including algebraic owning-side receipts; unsupported coordinate comparisons remain explicit failures.

The shared traversal endpoint relation owns authored/algebraic position comparison for all callers. Original Coons consumes this package contract rather than retaining coordinate-root algorithms. Both traversal source/depth/subdivision capabilities remain independent and are intersected only when a comparison requires both. Construction recipe equality remains a sufficient proof; false does not prove unequal positions. Ideal periodic conic stations may establish equality through an exact integer multiple of the retained intrinsic full-turn chart label, independent of transcendental coordinate evaluation.

The authored endpoint issuer accepts an explicit positive retained-storage byte stride. Source validation forwards actual bytes to the same exact caller ledger with checked ceiling division, and each rational XYZ output buffer admits its concrete coefficient payload before allocation. Recursive coordinate images preserve the caller stride. The compatibility default is the original UInt32-word algebra ledger; composing owners with other slot units supply their actual stride explicitly.

Smooth-native interval admission uses the retained selected native side when present; otherwise it maps the normalized interval into the retained original source and requires exactly one positive-width native owner. Explicit smooth analytic source families retain their original smoothness law. Unknown lifted/implicit families provide no smoothness proof.

Retaining an already-issued native parameter root accepts an independent scalar
algebra depth (default32, selected caller0...32). Its isolation depth is checked
against that scalar authority, while geometric subdivision remains separate.
The factory retains the original polynomial/isolation/exclusion receipt without
re-isolation. Authored incidence constructors keep their existing policy.

Physical-radian arc endpoint equality consumes the retained original rational
start/end expressions. Integral full turns cancel only at literal normalized
endpoints, while the original gain must remain nonzero. Complete spatial image
identity and exact affine chart substitution preserve this witness. Coincident
numerical points and binary full-turn labels do not establish physical closure.

Traversal receipts retain a separate scalar-root localization capability. An
explicit maximumAlgebraicDepth controls retained parameter-root refinement and
endpoint coordinate comparisons; maximumSubdivisionDepth controls geometric
interval queries only. Omitting the additive algebra capability preserves the
legacy constructor's localization policy. Derived localization caps are not
source identity or serialized fields. All refinements continue on the original
root and caller ledger without rebuilding isolation.

Retained root position queries evaluate the three homogeneous coordinate
quotients in fixed scalar fields. They allocate no intermediate XYZ array;
exact polynomial enclosure scratch remains admitted by the original algebra
ledger. The original root and selected native denominator remain authoritative.

A retained base-native boundary may borrow an already-admitted homogeneous
span law, preserving its original raw source/index without repeating span
preparation. Spatially transformed or periodically translated polynomial laws
require their own persistent boundary carrier. Position localization keeps
exact rational isolation endpoints through Bernstein numerator/positive-weight
range division and performs only final outward component conversion.

Later native traversal queries may select a stricter independent scalar algebra
cap. They re-admit the original source and re-localize both original endpoints
under that cap on the same work/optional byte ledger, sharing the already
prepared native owner. Cached endpoint brackets issued under a broader cap do
not themselves satisfy the later caller. Whole nonnative preparation cap
rebinding remains explicit unsupported until every retained nested owner can
forward the stricter cap; no renewed source preparation or private budget is
substituted.

### Reused Admitted Native Preparation

A package-only native traversal factory retains one already admitted original
`PreparedCurveDifferentialEncloser` for a direct B-spline. The issuing component
owns exact binding of both retained endpoint receipts to that same immutable
source owner. The factory derives the curve from the preparation, checks its
retained tolerance, and localizes original endpoints under the supplied independent
algebra policy. It shares the native atlas instead of replaying source validation
or coefficient preparation for each maximal component. Spatial/source caps and
optional byte callbacks remain those of the original invocation. Public raw-source
constructors keep their complete source and endpoint validation responsibility.

Smoothness queries accept an optional later caller algebra cap. Native endpoint
localization is rebound to the intersection with its retained scalar capability
using the same callbacks and preparation. Nonnative caches that cannot be
rebound to a stricter caller fail explicitly; smoothness never silently inherits
a broader coefficient or endpoint isolation allowance.

An authored identity [0,1] RootSpan over an original guide chain can transport
a stricter selected algebra cap without rebuilding geometric preparation.
Its outer endpoints and parameter map are exact authored constants. Each
selected inner traversal is rebound by the chain's actual query issuer under
that cap before using endpoint or coefficient caches. The outer derivative
provider forwards the retained selected cap, not the older aggregate cache.

Bounded closed-endpoint queries use the shared original traversal endpoint
relation under the caller's work/storage and independent algebra cap. Canonical
conic period identity or retained symbolic endpoints can prove positional
closure; positional closure alone does not declare a repeated surface chart or
prove draft tangent-dependent seam continuity.

### Direct Execution Ownership

High-level traversal construction, source validation and retained queries receive
the same original `inout OriginalQueryExecution`. Exact incidence and rational
endpoint operations retain generic `inout A: ExactScalarAdmission & ~Copyable`.
No copied allowance, callback forwarding admission or storage-slot conversion
creates a second budget. Actual payload bytes are admitted before materialization.
Retained immutable source preparation carries proof and original coefficients;
a later independent query re-admits its required proof on its own execution.

A source-owned Native-only Taylor port consumes the retained Native coefficients
with generic A. It preserves the original directed endpoint map, selected owning
sides, closed cover, derivative scaling and query guards, and exposes no general
source capability. The high-level port uses the same Native arithmetic.

```text
OriginalQueryExecution -> high-level construction/query -> retained source law
generic A -> Native-only source port -> same retained Native coefficients
```

Success, explicit refusal, independent depth/storage/work limits and cancellation
must execute through the real constructor and retained query paths. Signatures
and syntax alone do not establish completion.

The high-level constructor closes its actual common preparation scope before
creating the one immutable owner. That owner retains the original budget identity
and actual scalar/source/geometric/transport depth separately from all configured
capabilities. A standalone traversal is a parameter receipt rooted at its original source;
a Native leaf has source depth zero. Traversal/parameter transport depth remains
separate from source nesting. Drafted embedding owns its explicit traversal and
source edges. A reversed view shares this proof unchanged. High-level
queries consume the common retained-preparation port; a new execution rechecks
every depth and pays its actual ownership/verification bookkeeping, without
recharging historical arithmetic. The Native-only generic port re-admits attained
scalar and endpoint depth and checks its explicit source/geometric policy against
the same immutable preparation proof before using cached endpoint bounds.

| State | Native | WASM | Embedded WASM |
|---|---|---|---|
| Source/coefficients/depth/budget identity | Immutable Sendable owner | Same | Same |
| Query admission and local scopes | Exclusive original execution | Same | Same |
| Retained proof read | Common re-admission or explicit generic Native policy | Same | Same |
| Owner release | Reference ownership | Same | Same |

Only Native serialization is conditionally present; no mutable storage or
Sendable/isolation contract is changed by that conditional. Target compilation
and runtime behavior remain separate verification obligations.

The package-visible `admitPreparation(using:)` operation exposes the existing
retained preparation readmission body to composing source owners. It checks the
actual immutable proof receipt and original budget through the common policy;
it does not reevaluate jets or substitute configured caps. Consumers install
their actual source-edge offset before calling this operation.


Native B-spline authored-station and physical-angular guards compare the complete
`BSplineCurve3D` payload after both existing structural charges. Its synthesized
equality includes degree, knots, control points, weights, periodicity and periodic
origin, exactly as the same `Curve3D.bSpline` enum case did. A private non-inlined
helper keeps the aggregate enum comparator off this Native worker path; all other
cases retain full enum equality. Source validation, station/side admission,
angular ordering and exact coordinate fallback are unchanged. No tolerance or
geometric equivalence becomes source equality. The ideal-periodic guard remains
unchanged because it does not return Native B-spline sources.

[Native endpoint equality tests](../../../Tests/CADGeometryTests/OriginalNativeEndpointPositionRelationTests.swift)
exercise same/unequal Native stations, foreign exact sources, COW lifetime,
cumulative N/N−1 work and cancellation on actual Swift Testing workers. The
standalone `OriginalNativeEndpointPositionPortable.swift` exercises the same
package issuer on ASAN, normal WASM and Embedded from real module products.


### Endpoint source comparison and coordinate phases

The endpoint relation keeps the original source validation, station/selected-side
admission, structural work charges, retained-endpoint theorem and physical-angular
test. A private non-inlined suffix owns the following ideal-periodic test, exact
coordinate computation and result publication, so its scratch lifetime starts
after the physical-angular phase declines.

```text
original validation and charged source comparison
 -> retained/physical-angular endpoint tests
 -> private suffix: ideal-periodic test -> exact coordinates -> relation or nil
coordinates: cancellation -> one work debit -> nonnegative depth
 -> typed parameter image / typed Native B-spline / remaining source families
```

The parameter-image phase multiplies the original exact gain and adds the original
offset before the same positive child-depth guard and depth-minus-one recursion.
The Native phase preserves selected positive knot-side admission, ordered span
search, per-candidate work, the original homogeneous polynomial, positive weight
guard, retained output capacity and ordered XYZ quotients. Its borrowed spline
argument is explicitly copied into the existing owning polynomial initializer;
the immutable/COW source buffers keep their original ownership. No new source,
array materialization, proof ledger, capability, public API or source law is issued.

The private source comparison handles parameter images by child-source equality,
then exact parameterGain equality, then offset equality, in synthesized stored-
property short-circuit order. Native B-splines retain the existing typed equality;
other source tags retain enum equality. Both complete payloads remain charged
before comparison. Source equality is structural authored equality; foreign
representations still use the existing exact-coordinate proof. No tolerance
becomes identity and no failure becomes nil or successful absence.

| Owner/state | Native | WASM | Embedded WASM |
|---|---|---|---|
| Source and retained relation | Same immutable/COW values | Same | Same |
| Admission and mutation | Original exclusive inout execution | Same | Same |
| Temporary coordinates | Function-local values | Same | Same |
| Release | Existing value/reference ownership | Same | Same |

The four [Native endpoint fixtures](../../../Tests/CADGeometryTests/OriginalNativeEndpointPositionRelationTests.swift)
cover exact same/unequal positions, changed child/gain/offset, nested images, COW
lifetime, cumulative N/N-1 work and cancellation. The
[portable fixture](../../../Tests/OriginalQueryExecutionVerification/OriginalNativeEndpointPositionPortable.swift)
checks the same issuer on real module products. These private phases require
fresh complete Main CADGeometry compile/link on Native, ASAN, normal WASM and
Embedded WASM plus focused runtime. Main's unchanged public BRepEdgeGeometryClassifier path additionally requires
original parameter-image open/closed fixtures that reach this endpoint issuer.
Integration-worktree results alone do not prove Main's different composed stack.
