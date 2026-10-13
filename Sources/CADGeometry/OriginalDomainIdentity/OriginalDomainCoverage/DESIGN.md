# Original Domain Coverage

## Periodic Native offset domain composition

The periodic offset domain issuer consumes the sealed source fundamental family
and an existing Native child domain space from the same retained child owner and
scalar field. It checks every chart key and period against that space; source law
order need not equal DI template order. It retains a checked ordinal map rather
than copying chart laws. The original offset UV support is all real values on each
proved periodic axis and the original finite support on other axes. Requests are
intersected exactly, including open/disconnected/singleton/empty selections.

Member and enclosure-incident queries delegate arbitrary-size cycle arithmetic,
all seam sides and exact selected correspondence to the existing Native cover.
The occurrence retains original parent selection, child transport, cycle vector,
source family and law ordinal. Position queries evaluate the original offset guard
in the occurrence's fundamental coordinates; lifted queries additionally validate
the positive normal-length root. Nonowning upper knot/seam germs remain available
as occurrences but cannot claim canonical offset position. Every coordinate is
validated before exclusion, including empty requests and the auxiliary root.

```mermaid
flowchart LR
    S[Sealed periodic offset source] --> V[Check child/chart/period authority]
    N[Existing Native child space] --> V
    V --> C[Retained child request cover]
    C --> M[Member and all seam incidents]
    M --> G[Original normal/root guards]
    G --> R[Original UV and guarded occurrences]
```

The additive public protocol exposes cycle-aware member/enclosure/guarded queries
as requirements, including Embedded generic protocol dispatch. It does not
flatten the infinite family. Same-ledger storage/work, chart/family/source/transport
and coefficient depths, final cancellation and immutable source lifetime remain
mandatory. No geometry solver, new normal formula or unchecked coverage callback
is introduced. Existing finite offset APIs retain their scope. Final symbolic
CS/SSI/image/fiber output is still M7. Verification belongs to the focused periodic
offset fixture and retained finite-offset fixtures; see [source authority](../../OriginalSourceIssuance/DESIGN.md#periodic-native-offset-supply).

## Purpose and Scope

The composition handoff additionally owns `OriginalIssuedDomainBinding`: consume
immutable issued laws and an independently authoritative requested source frame,
prove every finite affine template correspondence, and retain the existing complete
cover together with the selected inverse images and law indices. A law support
union never defines the authoritative source support. Missing templates fail with
the existing incomplete-coverage error; periodic/unbounded and non-affine transport
remain outside this finite handoff. All original source/chart owners and both proof
depth axes survive. Verification composes the new binding with unchanged domain/lower
implementations using independent products; no production-target build.

`DefaultOriginalDomainCoverIssuer.issue` returns selected charts in input-template
order, preserving each retained local frame. Templates with empty selected images
are omitted. The issued-law binder uses this contract to associate template indices
in one forward scan; equal geometric or coefficient values never determine identity.

Child of [Original Domain Identity](../DESIGN.md), without children.
Own complete source/request coverage by charts or certified chart families.
Chart coverage is parameter coverage; it does not assert solution existence or
source-map injectivity. Shape producers remain responsible for authored laws.

## Responsibilities and Boundaries

Retain original support, original request, exact effective selection, every selected
chart's local support/transport and all overlap ownership. A separate numerical or
mesh chart width policy does not constrain this intersection issuer's source meaning.
Coverage construction consumes exact set/transport contracts and shape-source tokens.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | Source and completeness invariants | Common admission | No partial success |
| [Exact domains](../ExactParameterDomain/DESIGN.md) | depends on | Effective set and exact set equality | Verifies finite coverage | Closed-owner overlap is intentional |
| [Transport](../OriginalParameterTransport/DESIGN.md) | depends on | Whole-chart correspondence | Maps local support to authored space | Preserve unreduced cycles |
| [Native curve](../../OriginalNativeCurveChartCover/DESIGN.md) | coordinates with | Original span/law/source ownership | First existing adapter | Exact finite/Double subset only today |
| [Native surface](../../OriginalNativeSurfaceChartCover/DESIGN.md) | coordinates with | Tensor source spans | First existing surface adapter | Homogeneous-only preparation must be separate from jets |
| [Identity](../OriginalParameterIdentity/DESIGN.md) | used by | Chart support/overlap ownership | Scopes equivalence proofs | Coverage alone does not prove a seam law |
| [L5](../../RationalBivariateAlgebra/ExactParametricRelation/DESIGN.md) | used by, proposed | Complete chart domains and maps | Original equations consume domains | Current single-map implementation needs composition |

## Architecture

```mermaid
flowchart TD
 Q[Original support + original request] --> E[Exact effective selection]
 S[Source-issued chart templates / laws] --> B[Checked cover construction]
 E --> B
 T[Certified parameter transports] --> B
 B --> V[Whole-set equality / overlap correspondence / family proof]
 V --> C[Immutable complete cover]
```

## Contracts and Invariants

OriginalDomainCoverIssuing constructs a finite declared-frame cover.
OriginalDomainCoverQuerying exposes support/request/effective sets, a finite chart
view and incident indices. It does not expose symbolic family operations. Source
provenance is retained through its frames/transports. Specialized Native/sphere
issuers establish source support independently of the caller's declared frame.
No root/XYZ API is part of these protocols. Source-law references retain issuer
authority rather than unchecked callbacks.

### Protocol capabilities and implementation selection

| Contract | Status | Responsibility and implementation |
|---|---|---|
| OriginalDomainCoverIssuing / Querying | Implemented | Verify/read finite frame-relative coverage; DefaultOriginalDomainCoverIssuer does not inspect shapes |
| OriginalBSplineDomainIssuing | Implemented | DefaultOriginalBSplineDomainIssuer derives Native support/spans/periods through OriginalBSplineSourceReading and uses common DI verification |
| OriginalIntrinsicSphereDomainIssuing | Implemented | DefaultOriginalIntrinsicSphereDomainIssuer derives canonical intrinsic support and retains its certified longitude period |
| OriginalDomainBoundRationalChartIssuing | Implemented Native capability | DefaultOriginalDomainBoundBSplineChartIssuer combines the same source law, selected occurrence and local selection; it proves no intersection |
| OriginalChartFamilyQuerying | Implemented at M1 | Generic requirement dispatch for integer-indexed Native/sphere covers, retained support and explicit member/incident; no flattening or replacement owner |

The new family-query protocol is required because OriginalDomainCoverQuerying's
finite `charts` view cannot describe an unbounded set of occurrences. It is an
interface on retained covers, not another execution layer or a type-erased wrapper.
Use Source/Field associated types and an associated Occurrence type so different
source-issued chart keys remain statically typed. Its protocol requirements expose
the retained source, support/request/effective selection, finite template count,
integer-family rank, member lookup by template and exact cycle vector, and all
incident occurrences at an exact tuple. All fallible queries take the explicit
generic admission and DI limits. An occurrence retains its template owner, exact
unreduced cycles, selected image and original correspondence. A zero-rank cover
may implement the same query capability; this does not turn an infinite family
into a finite `charts` view.

The following declaration is a design contract, not an existing source symbol:

```swift
public protocol OriginalChartFamilyQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    associatedtype Occurrence: Sendable
    var source: OriginalSourceBinding<Source> { get }
    var support: OriginalParameterSelection<Source, Field> { get }
    var request: OriginalParameterSelection<Source, Field> { get }
    var effective: OriginalParameterSelection<Source, Field> { get }
    var templateCount: Int { get }
    var integerFamilyRank: Int { get }
    func member<A: ExactScalarAdmission & ~Copyable>(
        template: Int, cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> Occurrence
    func incident<A: ExactScalarAdmission & ~Copyable>(
        at tuple: borrowing [Field.Value], limits: OriginalDomainIdentityLimits,
        using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> [Occurrence]
}
```

The cycle vector has authored parameter arity, with exact zero on nonperiodic
axes; family rank counts only independently certified periodic axes. Member lookup
may return a valid occurrence with empty selected image. Incident lookup returns
every selected incident side, or no occurrences only after effective-membership
exclusion. Both operations reject foreign scalars/indices and obey retained depths.
The family-specific law issuer consumes that typed occurrence/cover with the same
Source and Field, so the query protocol need not erase different chart-key types.
No operation exposes an iterator that promises to finish over all integer cycles.

Family-query conformance verifies template/index ownership and complete family
authority. It cannot publish a new proof by adding an extension to an arbitrary
array. Native member/incident algorithms already exist; sphere incident queries
exist, while explicit template/member query conformance remains to be implemented.
The same fixture body must exercise both the concrete and generic requirement
calls, including Embedded witness behavior, before this capability is completed.

Specialized issuers receive the smallest required generic protocol dependencies
from their composition root: transport, cover verification, source-period/local-law
issuance as applicable. Match source and coefficient owners through associated-type
constraints and runtime binding checks. Current direct Default construction is
preserved until that injection migration is verified. Common DI does not select
shape enums, request a stronger coefficient field or import a hidden solver.

### Required source-family obligations

The following rows specify domain responsibilities, not newly completed source
formulas. A missing source law/correspondence remains an explicit upstream
implementation dependency under the unchanged full-family acceptance.

| Source capability | Specialized issuer must establish | Evidence handed to common DI | Current DI scope |
|---|---|---|---|
| Native curve/tensor B-spline | Every positive span, exact support, one-sided knot owners, independent cyclic axes | Original chart keys, complete fundamental cover and source-period receipts | Foundation implemented; public multi-span/periodic composition pending |
| Intrinsic sphere | Full two-coordinate support, longitude lifts, exact latitude boundaries | Canonical period/pole authority and all selected longitudes | Foundation implemented; general public consumers pending |
| Line / stored-N plane | Entire unbounded support and exact authored coordinate meaning | Original line law or exact plane-basis owner, support and chart correspondence | Plane basis/coordinate operations exist; full domain/public wiring pending |
| Physical-angle conics / analytic surfaces | Actual angular domains, all seams/branches, original UV and genuine periods | Exact phase/chart correspondence, period/collapse evidence | Image-only source receipts do not establish this capability |
| Spatial operation words | Unchanged parameter support through the retained spatial action | Descendant cover, original word owner and mapped local law | Domain composition pending; spatial action does not itself authorize new parameter identity |
| Affine parameter images / directed traversal | Pullback of the original descendant support, axis roles, reversal and all lifts | Original exact gain/offset word and verified descendant correspondence | Source laws exist in bounded capabilities; complete domain composition pending |
| Nonlinear / singular parameter images | Full supported correspondence, including every preimage and guard | Source-issued relational correspondence; never a guessed inverse | Pending beyond current affine transport; inverse refusal must not discard the required relation |
| Ruled / Coons / revolution / remaining procedural | Original construction domains, descendant restrictions and declared boundaries | Owned child charts/laws/maps and any genuine seam/collapse theorem | Pending complete DI issuance; derivative/normal work remains outside DI |
| Implicit / certified / lift / join / guide | The actual authored parameterization and supported relation to descendants | Original chart authority and full parameter correspondence | Pending where only image membership is issued |

For non-Cartesian restrictions, preserve the separately certified boundary/relation
predicate owner and its exact chart correspondence. DI's interval-product kernel
does not replace it by a bounding box. Pullback/selection must be discharged by
the owner of that restriction before a consumer claims complete restricted coverage.
Until the necessary correspondence capability exists, the required path fails
explicitly and remains incomplete; this is not an alternate approximation policy.

Finite/source-family issuers publish only after whole coverage, owner compatibility
and final cancellation checks. Source-issued local guards are retained when domain
selection is combined with a law; parameter coverage never implies denominator
validity or root exclusion. Converting an implicit image receipt into a complete
parameter cover is prohibited without an independent full correspondence proof.

For finite covers, mapped selected charts have union exactly equal to the effective
selection, and each is a subset of the authored support. An exact endpoint event
sweep or Cartesian refinement verifies inclusion/gaps against the retained request;
checking sample points, summed lengths/areas or an array count is insufficient.
Every overlap retains incident chart sides and parameter transports. A singleton
Native knot retains both one-sided owners; a tensor corner retains all applicable
owners. Zero-width knot spans are not ordinary charts. Empty effective selection
retains complete request-versus-support exclusion, not an empty candidate list.

The stored geometric support may be open or unbounded. One unbounded parameter
chart can cover a line/plane without any finite window. Periodic unbounded requests
require a finite template cover plus an exact integer-indexed family certificate:
source period law, complete fundamental support, integer index domain, exact lift,
selection predicate and a proof that every requested coordinate has a template/lift.
Merely storing a lazy generator does not establish these properties. Repeated root
families and original lifts must remain symbolically represented by downstream
results; a consumer demanding an infinite flat array fails explicitly rather than
truncating. Finite requests materialize only admitted charts with checked counts.
No signed-Int overflow is repaired by saturating or wrapping a cycle.

A pole does not shrink an ambient two-coordinate support into a one-coordinate set.
Its collapsed image is retained as a separate identity/fiber witness. The latitude
boundary and every selected longitude stay in the cover. Open pole boundaries exclude
the pole exactly; near-pole points are not collapsed. Infinite endpoint inclusion is
always false; limiting XYZ values are not extra domain points.

Native adaptation validates the original cyclic law, not just its isPeriodic flag.
Exact knots/control laws and original parameter meaning stay unchanged. General
shapes supply their actual supported chart law/transport tokens; unsupported required
coverage remains explicit unfinished implementation. Spatial transforms and parameter
images preserve the original source binding through checked transport, not conversion
of a bounding box or fitted rational surface.

## Runtime Flows

### Native rolling-ball graph domain consumption

The rolling-ball domain issuer consumes the sealed complete three-child graph
family from [source issuance](../../OriginalSourceIssuance/DESIGN.md#rolling-ball-native-child-graph-family).
It issues an authored UV frame over the original normalized square, verifies
source ownership/coordinate semantics/exact frame support, and intersects the
retained request with that enclosure. Per-template members use the existing graph
binder and retain all positive-root/normalization/regular-arc guards. A request box
does not prove those guards. Lifted incident queries preserve all five graph
coordinates while only U/V belong to the source domain. They validate all coordinate
fields before empty selection can short-circuit, then preserve every closed child
chart incident. No unique inverse, root search or Boolean UV-only validity callback
is introduced. Immutable members retain the same family/source/proof owners;
selection/member/query allocations use one caller admission and terminal cancel.
Focused rolling-ball source/domain verification owns request singleton, strict,
disconnected/empty and foreign-owner/semantics/frame counterexamples. Generic rails
and final ordinary CS/SSI publication remain separate open obligations.

Retain original support/request -> exact intersection -> validate chart templates ->
transport/select -> verify union and ownership/family theorem -> reserve receipt ->
final cancellation. Existing source extraction prepares only required homogeneous
laws. Jets/normals/silhouettes are prepared by separate consumers when necessary.

## State, Ownership, and Lifecycle

One immutable owner stores source, set receipts, chart templates, selected ranges,
transports and proof handles. Views use owner plus index/range; repeated operations
share original buffers. No callback is retained as a promise of coverage. Both source
release and a caller mutation of its COW copy leave proof authority unchanged.

## Failure, Concurrency, and Constraints

Missing chart boundaries, incompatible source tokens, unknown selection or missing
family theorems yield incompleteCoverage or the exact lower failure. Chart count,
family template count, source/transport depth, work and bytes are independently
admitted before allocation. All chart/event/index visits are charged; final cancel
prevents empty/partial successful receipts. Immutable concurrent readers use separate
explicit query admissions. Native/normal/Embedded keep identical owner semantics.

## Verification and Change Impact

Independent expected endpoint cells and open sectors refute holes/extra coverage.
Required cases include nonclamped/multispan/native joins, singleton seams and tensor
corners, negative/large independent cycles, reversed maps, open endpoints, disconnected
requests, exact empty support intersections and unbounded charts/families. Reject a
missing chart even when samples/length sum agree. Test source lifetime, foreign owner,
period-law mismatch, independent count/work/storage/depth and final cancellation.
Existing Native cover suites remain adapter regression owners. New cover acceptance
must include current limits and actual portable execution; source-only adapters do
not establish domain completion or whole-seven acceptance.

## Implementation Boundary

`OriginalDomainCover` certifies exact parameter coverage relative to a declared frame.
It is not an assertion that a caller's frame is a shape's whole support.
`OriginalBSplineDomainSpace` is issued only from a validated retained Native reader;
it derives original knots, positive spans, full support and independently proved periods.
`OriginalBSplineDomainCover` retains the original request and its exact support
intersection. Nonperiodic covers are finite. Periodic covers retain all-integer
Cartesian families over a verified complete closed fundamental cover; `member` and
`incident` materialize only the requested lifts, preserving both seam sides.
No operation implicitly flattens an infinite family.


## M0 implementation acceptance and ownership

This matrix fixes mandatory inputs, proof gaps and receiving consumers. Source
law issuance owns coordinate meaning; coverage never infers it from an image
polynomial. M0-M3 do not change L0-L5 authority, numerical tolerances or limits.

| Family / concrete input | Required domain and correspondence | Existing authority / owned repair | Acceptance / consumer |
|---|---|---|---|
| Native degree-one line and weighted multi-span curve | All positive spans; exact open, closed, singleton, disconnected and excluded requests | OriginalBSplineSourceReading, chart and period receipts; no new producer | member/incident preserve both knot sides; public CS includes all TUV |
| Native tensor surface with independently periodic U/V | Finite selections with independent arbitrary-size cycles; all seam sides | Same source receipts; NativeExactRelations owns multi-chart compilation/publication | CS/SSI cover every selected chart pair; folded fixture retains current work/storage ceilings |
| Infinite original line with nonunit direction | Entire real parameter axis, original origin/direction | OriginalLinearSourceReading; source owner supplies unbounded support, not a finite chart-window law | No intersection request invents whole support; exact selected position and exclusion |
| Stored-N plane, scaled and oblique N | Entire real UV product; exact normalized basis and inverse projection under N+origin authority | OriginalPlaneSourceReading / OriginalPlaneBasisReceipt; source provider and evaluation/UV handoff owned by OriginalSourceIssuance | Exact plane equation, UV roundtrip, owner retention; rounded old basis is not proof |
| Circle/ellipse, hyperbola/parabola | Full authored angular or real coordinate and branch; radius/axis positivity | Conic source-coordinate reading/law capability is missing and belongs to source owner | Original branch/all parameters retained, full support and exact boundaries; no image-only UV assertion |
| Cylinder / cone | Authored angular axis and unbounded axial/radial axis, apex fiber for cone | Primitive/cone image receipts exist; source angular coordinate/phase and branch law are missing | Period proof uses actual original angular map; all apex UV retained |
| Sphere | Intrinsic longitude family, closed latitude and both poles; physical-angle sources retain their distinct meaning | Intrinsic sphere period/pole receipts exist; physical angular source-law capability is separate | Generic family member and incident agree; near-pole cannot become pole |
| Torus | Two independent original angular axes and complete branch/fiber correspondence | Primitive image receipt exists; two-axis source-coordinate law is missing | Independent cycles, seams and all UV retained |
| Rigid/affine/parameter image/original word | Whole descendant support pullback, exact reversal and original axes | Existing OSI word/image/traversal receipts; M4 consumes them | Finite/infinite requests compose without invented inverse |
| Offset/rolling-ball/revolution/Coons/correction/derivative/draft/angular transport | Original construction domains, joins and child correspondence | Existing ruled/Coons receipts reused; remaining specific laws delivered by source owner at M4 | Every defined branch/guard retained; unsupported cannot complete a required cell |
| Implicit/certified/lift/join/guide | Certified original relation and non-Cartesian guards, complete preimages | Specific source relation capabilities delivered by source owner at M4 | Boundary/self/XYZ consume the same certified relation at M6/M7 |

Nonlinear or singular parameter correspondence is a relation, not
OriginalParameterTransport's invertible affine map. Its future receipt must retain
source/target bindings, original equations, denominator/branch guards, complete
selected domain and all preimages. Forward/inverse queries return complete fibers
or typed failure under a fresh explicit admission; no unique inverse is promised.
Non-Cartesian material restrictions stay certified predicates over an ambient
cover. Their implementation belongs to M4; this contract does not authorize
pretending a bounding box proves material membership.

A symbolic public result at M7 retains the family owner, template, independent
integer cycle vector, authored parameter correspondence and full requested
coverage. Its member/incident queries use explicit admissions and preserve all
UV/fibers. A finite convenience entry explicitly refuses an unbounded family;
it cannot silently select one cycle or a finite search window. M2 accepts bounded
requests only and enumerates their complete finite chart occurrences.

| Exclusive owner | Exact files / resources |
|---|---|
| Common DI | OriginalDomainCoverage/OriginalChartFamilyQuerying.swift; existing cover, bound-chart issuer and family methods; OriginalParameterTransport contracts only when required; Tests/OriginalDomainIdentityVerification family fixtures/proof/tests |
| Native composition | NativeExactRelations/*.swift and changed public consumer requirements; its DESIGN and Tests/NativeExactRelationVerification fixtures; separate Native composition scratch path |
| Source authority | OriginalSourceIssuance reading/law/provider/receipt files and original evaluation/UV handoffs; its DESIGN and Tests/OriginalSourceIssuanceVerification; shared source changes serialize |
| Linear/plane issuance | Dedicated linear/plane issuing protocols and implementations in OriginalDomainCoverage; dedicated primitive fixtures in domain verification |
| Angular issuance | Dedicated conic/analytic issuing protocols and implementations in OriginalDomainCoverage; dedicated angular fixtures in domain verification |
| Integration | PROGRESS.md, exact input/artifact receipts and independent latest-main worktree; no simultaneous edits of implementation owners' files |

The implementation task uses one isolated implementation worktree and a separate
main-integration worktree. Each source file has one writer: Native consumer and
source-family work proceed concurrently in disjoint files, while shared contracts
remain with the common DI owner. Production compilation starts after both source
owners freeze their shared module snapshot.
Independent Native, ASAN, ordinary WASM and Embedded scratch paths never mutate
the same build directory. Each milestone records actual behavioral evidence and
its commit before it is marked complete. The matrix itself is not evidence that
any missing source law is implemented.

### Public acceptance cell execution

M4-M8 work is scheduled by finite public acceptance cells, not by producer-only
slices or completion of every unrelated M4 family. The mandatory family/consumer
scope above is unchanged. Before changing a cell's production path, its record
must name one reproducible public input, one independently derived expected
result, the observed stopping operation, the necessary end-to-end change and the
accepted evidence reference. A missing observation or constructor is an unresolved
cell-definition task, never a passing cell or permission to narrow the family.

The finite mapping must explicitly distinguish the five certified-curve variants,
finite versus symbolic periodic publication, nonlinear/singular transport,
non-Cartesian material and the applicable boundary/self/XYZ/projection consumers.
A family name, generic success statement or product count is not an executable
cell. Each discrete variant/probe receives its own stable cell ID and exact input;
continuous parameter ranges and unbounded integer cycles stay within that cell's
complete symbolic proof obligation, rather than becoming an enumerated test window.
The existing acceptance scope is mapped, not extended. One passing example does
not prove a generic family theorem.

| Cell field | Required authority |
|---|---|
| Public input | Concrete original constructor/fixture, public API and exact request |
| Expected result | Independent tuples/geometry/material/contact or complete exclusion, with all UV/image/fiber obligations |
| Stop | Actual public-path diagnostic and source operation; distinguish observed behavior from a proposed explanation |
| Necessary change | The smallest causal source -> DI -> required identity/consumer -> public-result path |
| Receipt dependencies | Exact retained capabilities needed by this input; no dependency on all M4 |
| Evidence | Initial red, changed-path success/failure/boundary/resources/cancel/lifetime targets, one scoped review and latest-main delivery |

A new prerequisite is admitted only when this cell's concrete stop shows why an
existing receipt cannot satisfy the next operation. Internal source/field/adapter
commits may remain coherent checkpoints, but do not complete a public cell.
Unchanged lower evidence is reused under its original premises; unrelated
hardening and duplicate evidence acquisition are not additional cell work.
Boundary/self identity dependencies are the actual consumed receipts. Unproved
identity is left selected and cannot delay unrelated supported M5/M6 inputs.

The first frozen public input is CS-POLY-01. Its original host is the four-cell
planar Coons construction in
[PolylineAtlasLiftProof.shape(multi:true)](../../../../Tests/OriginalPolylineAtlasLiftVerification/Proof.swift),
and its authored pcurve is [(0,0),(0,0),(1/2,1/2),(1,1/2),(1/2,1/2)].
Call DefaultCurveSurfaceIntersector.intersections with that SurfaceLiftCurve3D,
the plane through (1/2,0,0) with normal unitX, default options and standard
tolerance. The two distinct authored roots are T=sqrt(2)-1 and T=1; both have
XYZ=(1/2,1/2,0). They must remain distinct with all original parameter/auxiliary UV
and source authority. The first root is shared by incident closed charts; those
representatives must not invent extra roots or erase the second traversal.

The Native public diagnostic is retained at
[CS-POLY-01 red](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-01-red/receipt.json).
The generation-bound cached public dispatcher reports the U-domain failure from
SurfaceParameterBox.validate. The
[Native trace receipt](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-01-trace/receipt.json)
binds the observed call chain: certifiedSurfaceLiftAnalyticIntersections -> bounds
-> surfaceLiftBounds -> surfaceBounds -> DefaultSurfaceDifferentialEncloser ->
SurfaceParameterBox.validate. On the candidate T interval
[0,0.41421356237309492], both UV bounds are
[-4.9406564584124654E-324,0.49999999999999983] against the original [0,1]^2.
The selected surfaceParameterBounds(polyline) calls parameterBounds(points:),
which applies outwardInterval and nextDown to the point minimum zero. This is
the concrete rejected enclosure, not a hypothesis based on the error string.

The observed branch is the legacy lifted-curve analytic search; it does not
consume the prepared complete lift/DI graph receipt. Repairing only that hull
would not establish the cell's complete source equality, original TUV or retained
identity/auxiliary correspondence. The end-to-end change must connect those
existing receipts to the public result while retaining the original plane's
whole UV domain and basis authority. No finite target window, tolerant source
equality or receiving-domain clamp can substitute for that connection. Existing
polyline/Coons lift and plane-source/domain receipts are the initial dependencies;
the distinct-polyline shared-field prerequisite is not needed by this input.
The trace proves this Native cached branch/stop only. It is not a current full
module build, a repair, four-target acceptance or completion of the cell.

CS-POLY-COINC-01 uses the same authored lift and full request, changing only the
target to the whole plane at the origin with normal unitZ. The independent oracle
is all T in [0,1], retaining the original polyline correspondence (x(T),y(T)),
target UV=(y(T),-x(T)) in the original plane basis, a one-dimensional image and
zero-dimensional station fibers. The bare public API must refuse a non-discrete
intersection; the rich API must retain the complete relation. The ordinary Native
initial diagnostic exhausted the unchanged 8,388,608 work ceiling in the first
template's three-variable decomposition. The complete alternative proof combines
whole-chart plane containment, source-issued UV elimination, exact affine-guard
preimages and the existing L6 map theorem, as owned by
[contained lift publication](../../NativeExactGeometricRelations/DESIGN.md#exactly-contained-polynomial-lift-families).
Raising the ceiling or replacing the continuous T domain by samples cannot close
this cell. Execution and evidence status belong to PROGRESS.md; it does not gate
supported point or boundary cells.

CS-POLY-NORMAL-SUBNORMAL-01 uses the CS-POLY-01 constructor and full request,
with target origin (1/2,0,0) and authored normal
(Double.leastNonzeroMagnitude,0,0). This positive axis scale preserves the exact
plane basis and independent two-root TUV/XYZ oracle; the raw saved normal remains
source authority. A retained, hash-admitted Native ordinary public probe returns two points and
twelve incidents for scales 2 and -2, then reports work allowance exhausted for the
subnormal input under the unchanged 8,388,608 ceiling. A changed-path Native trace
localizes the stop after complete geometric publication, at the angular-predicate
comparison for the second incident. Numerical classification repeatedly squares
the raw scale in the algebraic witness field. The causal change consumes the
existing sealed orthogonal unit plane basis for that scale-invariant angular
predicate, as specified by [geometric publication](../../NativeExactGeometricRelations/DESIGN.md#ordinary-retained-polyline-lift-against-an-axis-plane).
It preserves the raw source normal, incidence equation, every original guard/UV
and caller budget. Its diagnostic is separate
from acceptance of the unit-normal input. Evidence and execution state belong to
PROGRESS.md and the corresponding retained public diagnostic receipt.

The latest user execution instruction gates the next production implementation
on completion of the entire remaining acceptance mapping. After that mapping is
frozen, cell readiness is local: each implementation consumes only its own fixed
input, oracle, observed stop, causal change and receipt dependencies, without
waiting for unrelated source implementation. Mapping completion is not source
implementation completion and never establishes family-wide acceptance. An unobserved proposed stop remains a definition gap in
that cell. A source-signature limitation is identified as such and is not reported
as a reproduced runtime failure.

#### Accepted remainder crosswalk

This index maps the accepted remainder IDs to their existing contract owners and
finite public cells; it does not restate those contracts or certify their closure.
PROGRESS.md alone owns execution state and whole-seven/full87 accounting.
A mapped example closes only its recorded
source, construction branch, request and consumer. An unmapped row stays open. The latest execution instruction requires the full
remaining mapping to be frozen before the next production implementation.

The cell references below are CS-POLY-01, CS-POLY-COINC-01,
CS-POLY-NORMAL-SUBNORMAL-01, CS-NATIVE-PERIODIC-PARAM-01,
the three B-COONS-HOLE policy cells and S-COONS-PLANE-01 already defined here.
The following cells retain their defining input, oracle and observation
provenance; execution state is recorded only in PROGRESS.md:

| Candidate | Exact existing input, API and request | Independent oracle | Observation and next assignment |
|---|---|---|---|
| CS-POLY-CORRECTION-01 | Use [PolylineAtlasLiftProof.shape(multi:false).1](../../../../Tests/OriginalPolylineAtlasLiftVerification/Proof.swift) as the actual originalBoundaryCorrected host, SurfaceLiftCurve3D with [PolylineLiftProof.points()](../../../../Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift), and the whole stored-N plane through (1/2,0,0), normal unitX. Invoke ordinary DefaultCurveSurfaceIntersector.intersections and intersectionResult with full authored T=[0,1], default options and standard tolerance. | The independent correction law in the existing fixture is X=u, Y=v, Z=u(1-u)(1-H(v))/2, H(v)=10v^3-15v^4+6v^5. Exactly T=sqrt(2)-1 and T=1 meet the plane; both retain source UV=(1/2,1/2), XYZ=(1/2,1/2,1/16) and stored plane UV=(1/16,-1/2). Retain distinct T and every closed incident owner. | [Recorded Native entry stop](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-CORRECTION-01/STOP.md): the receipt-identified original producer snapshot declined both bare and rich modes with nil after the actual source/DI and independent oracle passed. This is a selected-entry decline; the complete ordinary fallback outcome remains unobserved. The cell consumes existing correction/polyline source, graph, DI and polynomial UV reduction; its [acceptance receipt](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-CORRECTION-01/VERIFICATION.md) binds the resulting public path. Execution state belongs to PROGRESS.md. |
| SSI-COONS-PLANE-01 | Use [PolylineAtlasLiftProof.shape(multi:true).0](../../../../Tests/OriginalPolylineAtlasLiftVerification/Proof.swift), the whole stored-N plane through (1/2,0,0), normal unitX, and ordinary DefaultSurfaceSurfaceIntersector.intersections / intersectionResult. Original Coons request is the full square; plane UV is unbounded. | All tuples are (U,V;planeU,planeV)=(1/2,v;0,-v), v in [0,1]; XYZ=(1/2,v,0), image dimension 1 and station-fiber dimension 0. Every closed Coons chart side remains incident. | [Assembly observations](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/STOP.md) record a cached PlanePlane signature mismatch, then a 120-second compile timeout after adding only its current body. Neither attempt reached bare/rich runtime. The ordinary dispatcher has a bounded parametric fallback; absence from the Native exact selector is not a geometry failure. A missing source/DI/publication receipt is not yet established as the causal runtime stop. |
| S-COONS-OFFSET-CALLER-01 | Use the same four-chart planar Coons support and the outer unit-square face construction from [CoonsHoleBoundaryProbe.face](../../../../Tests/OriginalPublicAcceptanceVerification/CoonsHoleBoundaryProbe.swift), omitting its inner hole. Retain exact constant-U/V edge pcurves, one shell and one sheet body; validate through ValidatedBRepModel(.exact), then call DefaultOffsetResultValidator.validate(bodyID:validatedModel:admission:) over the full original face. | The authored map (u,v)->(u,v,0) is injective on the full square; subtracting only its scoped authored diagonal leaves no cross-contact. This caller oracle is separate from merely querying S-COONS-PLANE-01. | No observed stop. The actual validator prepares retained Coons self bounds, proves continuity and whole-box differential contraction, then applies both trim callbacks only if contact remains. It does not call the issued-graph self query. The full raw oracle is u=p and v=q on all16 closed chart products; residual is empty, with raw image dimension2/fiber0. Its Void success alone does not publish a raw/refined material receipt or prove graph-receipt consumption. Exact model admission and one caller diagnostic remain to be recorded; do not introduce a new session before an actual stopping input establishes its necessity. |
| CS-DERIVATIVE-LIFT-PLANE-01 | Use [DerivativeHostShape.shape(weighted:true, projected:true)](../../../../Tests/OriginalDerivativeLiftHostVerification/Shape.swift), its existing [mode-0 Native diagonal pcurve](../../../../Tests/OriginalDerivativeLiftHostVerification/Proof.swift), SurfaceLiftCurve3D, and the whole plane through (1/2,0,0), normal unitX. Invoke ordinary intersectionResult with full authored T=[0,1]. | The specific row-constant weights cancel from the X quotient, and the existing U basis/control X gives X=u; projection changes only Z and the Hermite correction preserves X. Thus X=t and the complete root is T=1/2. Host UV=(1/2,1/2), XYZ=(1/2,1/2,5/32), plane UV=(5/32,-1/2). Pcurve/U/V knot sides give eight incidents at the same tuple. Image and coordinate-fiber dimensions are0; incidence count is distinct from fiber cardinality. The former65/512 was a derived-oracle arithmetic error, corrected against the original Hermite coefficient owner; the authored construction is unchanged. | [Native selected-entry observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-DERIVATIVE-LIFT-PLANE-01/STOP.md) records the historical exact producer returning nil and the actual rich entry reaching an explicit verification-only fallback tripwire. Complete production fallback behavior remains unobserved; the tripwire is not a geometric failure. Existing [derivative lift source/DI evidence](../../../../Tests/OriginalDerivativeLiftHostVerification/VERIFICATION.md) supplies the actual construction and eight incidents. Consume those existing Native-pcurve/retained-host capabilities to close the missing exact publication receipt; no new source prerequisite is inferred. |
| CS-REVOLUTION-AXIS-FIBER-01 | Use the actual [weighted reversed rational generator revolution](../../../../Tests/OriginalRevolutionSourceVerification/Sources/Proof/Proof.swift): degree1 generator origin to(1,0,0), weights[1,2], reversed authored[0,1], raw axis(0,0,2), U=[-B,B], V=[0,1], where B is the exact binary64 value2*Double.pi. Query the origin/unitZ line with T=[-1,1] through ordinary intersectionResult. | Radius r(v)=2(1-v)/(2-v), denominator in[1,2], zero only atv=1; Z=0. Complete tuples are{(T,U,V):T=0,U in[-B,B],V=1}, XYZ={origin}, parameter dimension1/image dimension0/XYZ fiber dimension1. Retain all U and generator-local parameter0. Fundamental[-B,0] yields cycles-1,0,1,2 with closed seam endpoints; each of U=-B,0,B has two incidents. B is not mathematical2pi. | The original ordinary call threw invalidVectorLength(0.0); its [red observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-REVOLUTION-AXIS-FIBER-01/STOP.md) is preserved. [Four-lane acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-REVOLUTION-AXIS-FIBER-01/VERIFICATION.md) now verifies checked source-owned axis sections and complement exclusion through the existing DI/L5/L6 publication and actual rich dispatch. Whole-terminal and geometric oracles preserve all U, reversed generator correspondence, guards, image/fiber strata and seam incidents; exact empty controls, bare non-discrete refusal, resource boundaries, cancel and retained/COW/readers are verified. Source authority remains the original revolution law and full guarded domain; M5.R period evidence is not a collapse theorem or added prerequisite. General axes, non-Native generators, unbounded requests and isolated bare numerical publication remain separate open capabilities. |
| SSI-ROLLING-BALL-PLANE-01 | Use the actual CADGeometry RollingBallBlendSurface3D construction recipe from [the existing shape/lift fixture](../../../../Tests/OriginalRollingBallGraphIntakeVerification/Proof.swift), default radius5, center(0,0,u), rails(3,4,u)/(3,-4,u), full authoredUV=[0,1]^2. Ordinary rich SSI compares this original rollingBall surface with the whole plane through(0,0,1/2), normal unitZ. Do not pass the independent adapter payload as the public shape. | Set q(v)=5-4v+4v^2, X(v)=(15+20v-20v^2)/q, Y(v)=20(1-2v)/q. Complete tuples are u=1/2, allv in[0,1], XYZ=(X,Y,1/2), planeUV=(Y,-X). q>=4 and Y'= -40(3+4v-4v^2)/q^2<0 prove complete exclusion elsewhere, image dimension1 and each station-fiber dimension0. Everyv retains16 closed child-knot incidents at childUV=(1/2,0). Full graph tuple=(1/2,v,1/2,0,1/2,0,1/2,0,5,5,3/5); the last three values are positive radial-length/half-angle witnesses, not additional intersection roots. | Original rich dispatch timed out once at30s on db7e496d. The checked section consumer now connects the original source/DI receipts, exact auxiliary reduction and affine-U section to existing real-cell selection and geometric map evidence; Native/ASAN/ordinary-WASM/Embedded each pass all9 actual complete-set/failure/resource/cancel/lifetime groups; scoped review findings are corrected. Implementationd90d1a27 is independently composed with latest main; source/product/protected-file audit and fresh Native/Embedded public success/empty replays pass. The accompanying delivery record closes main integration; general rolling remains open. Reuse [ff67aa6d source/DI scope](../../../../Tests/OriginalRollingBallGraphIntakeVerification/VERIFICATION.md) and its [main integration premises](../../../../Tests/OriginalRollingBallGraphIntakeVerification/Evidence/main-integration/integration.json). Preserve the original radius, regular minor arc, positive roots, child support/pcurve equations, denominators and owning-side guards. The original timeout is retained as a diagnostic; it is not rerun or given a larger ceiling. This cell exercises4-P1/P2/P3/P6/P7/P8/P10/P11/M7 for this input; M5 or boundary/self completion is not a prerequisite. |
| CS-DRAFT-ZERO-RULED-01 | Reuse the reversed degree1 weighted generator from [the revolution fixture](../../../../Tests/OriginalRevolutionSourceVerification/Sources/Proof/Proof.swift): knots[0,0,1,1], controls[origin,(1,0,0)], weights[1,2], authored[0,1]. Construct [OriginalDraftedCurve3D](../../OriginalDraftedSection/OriginalDraftedCurve3D.swift) with normal(0,0,2), raw axis=pull=(0,0,4), height1, angle=+0.0, remainingSourceDepth1; construct [OriginalDraftedRuledSurface3D](../../OriginalDraftedSection/OriginalDraftedRuledSurface3D.swift) with endHeight3 and depth2. Ordinary rich CS compares the line through(1/2,0,2), direction unitY, T=[-1,1], against the complete original wall[0,1]^2. | The exact zero branch has unitZ ruling and clearance1. S(u,v)=(2(1-u)/(2-u),0,1+2v), L(t)=(1/2,t,2). The complete set is the single tuple(T,U,V)=(0,2/3,1/2), original generator parameter1/3, XYZ=(1/2,0,2), image/coordinate-fiber dimensions0 and one interior chart incident. Denominator2-u is in[1,2] and derivative-2/(2-u)^2 is nonzero; the contact is transverse. | [Selected Native observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-DRAFT-ZERO-RULED-01/STOP.md) reaches the actual original constructor and real ordinary rich fallback: one transverse numerical pointT0/U0.6666666666666667/V0.5000000000000001/XYZ(1/2,0,2), overlaps0. Actual current lift selector declines; cached-ABI proof fields are nil. Newer issued fields are outside that diagnostic ABI; current resolver/default initializer statically retains no complete original proof. The concrete missing contract is source/domain/exactUV/incident/image-fiber publication, not numerical contact. Reuse generator/traversal premises and source-own the original zero-translation law; revolution period is neither required nor draft evidence. This cell exercises the draft zero branch and 4-P1/P2/P6/P7/P8/P10/M7 only within this input; nonzero angles, other roots, draft-curve publication and drafted-sheet caller migration remain separate. |


##### CS-OFFSET-PERIODIC-ZERO-GEOM-01: original infinite offset family candidate

Use the actual `twoAxes=true,distance=0` constructor in
[ActualPeriodicOffsetProof](../../../../Tests/OriginalPeriodicOffsetVerification/ActualProof.swift):
degree(1,1), both knot vectors[-1,0,1,2,3,4], both periodic, and controls
Pij=(xy[j].x,xy[j].y+yz[i].x,yz[i].y), with
xy=yz=[(0,0),(1,0),(0,1),(0,0)]. Retain the original
OffsetSurface3D(source:.bSpline(native),distance:0), including its normal guards.
The curve is the actual degree1 stationary Native construction in
[FamilyFixtures.stationary](../../../../Tests/OriginalDomainConsumerVerification/Sources/FamilyFixtures/FamilyFixtures.swift),
knots[0,0,1,1] and both controls(1/4,1/2,0). Invoke ordinary
DefaultCurveSurfaceIntersector.intersectionResult with full T=[0,1],
surface U/V ranges nil and standard tolerance; the periodic authored request is
all R^2.

| Cell field | Exact scope |
|---|---|
| Independent complete oracle | All(T,U,V,q)=(t,1/4+3k,1/2+3l,1), t in[0,1], k,l in Z. XYZ=(1/4,1/2,0). Each cycle pair has parameter dimension1, image dimension0 and coordinate-fiber dimension1; the constrained positive q witness adds no dimension. Each original UV has one interior position incident. |
| Full fundamental exclusion | On local s in[0,3), (a(s),b(s))=(s,0) on[0,1), (2-s,s-1) on[1,2), and(0,3-s) on[2,3). S(U,V)=(a(U),b(U)+a(V),b(V)). Z=0 restricts V to the first interval including its seam representatives. X=1/4 gives U=1/4 or7/4. At7/4, b(U)=3/4 forces a(V)=-1/4, impossible; at1/4, V=1/2. No knot/seam supplies another solution. All nine patches, rather than only the first patch, enter this exclusion. |
| Original zero-offset guards | NormalSquared by U/V patch is[[1,2,1],[1,3,2],[0,1,1]]. The law still requires normalSquared>0, q>0 and q^2=normalSquared at zero distance. The sole solution is first/first interior, D=1, normalSquared=1 and q=1. The degenerate patch is excluded by its original guard, not by replacing the zero offset with an unguarded child. |
| Consumed premises | Existing actual periodic offset binding, fundamental charts, period3 on each independent axis, nine templates and rank2 integer-domain/full-cover receipts in [OriginalPeriodicOffsetVerification](../../../../Tests/OriginalPeriodicOffsetVerification/VERIFICATION.md), actual Native/WASM/Embedded receipts and its main-integration record. Their source/DI/evaluator, signed/zero distance, cycle and COW scope remains unchanged. |
| Observation and assignment | The original ordinary rich call returned singularGeometry because its smooth derivative certificate requires splitting at a periodic C0 knot; the admitted red observation is retained in [cell evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-OFFSET-PERIODIC-ZERO-GEOM-01/red/receipt.json). The new ordinary dispatch consumes the existing periodic source/DI and all nine guarded original position graphs, retaining the complete Z^2 family, exact original UV/q, chart owner and XYZ/image0/fiber1 evidence. Native/ASAN/ordinary-WASM/Embedded each pass nine complete-set/request/empty/failure/resource/cancel/lifetime groups; scoped review findings are corrected and [four-target acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-OFFSET-PERIODIC-ZERO-GEOM-01/VERIFICATION.md) is fixed. Implementationc9b752ea is independently composed with latest main; source/product/protected-file audit and fresh Native/Embedded ordinary public success/empty replays pass. The accompanying [delivery record](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-OFFSET-PERIODIC-ZERO-GEOM-01/DELIVERY.md) closes main delivery. The original stopping path is not retried or given larger query allowances. General offset families and whole M4-M8 remain open. |

##### S-NATIVE-FOLD-01: retained nonstructural contact control

This named cell reuses the already recorded nonstructural control of
S-COONS-PLANE-01; it creates no new prerequisite or verification run.
[CoonsGraphSelfContactFoldScope](../../../../Tests/OriginalPublicAcceptanceVerification/CoonsGraphSelfContactFoldScope.swift)
constructs the actual degree(1,1) Native surface with U knots
[0,0,1/2,1,1], V knots[0,0,1,1] and X controls[0,1,0] in each V row.
Its authored map on D=[0,1]^2 is S(u,v)=(2u,v,0) for u<=1/2 and
S(u,v)=(2-2u,v,0) for u>=1/2. The public
DefaultOriginalIssuedGraphSelfContactQuery consumes the complete D x D,
all four ordered chart pairs and no declared identity; only the scoped
source-authored diagonal is subtracted.

| Cell field | Exact scope |
|---|---|
| Independent complete residual | {(u,v,1-u,v): u in[0,1] excluding1/2, v in[0,1]}. Same-chart products are empty; each cross-chart product retains its ordered branch and all distinct original UV. |
| Complete oracle | The existing fixture compares every full raw/refined cell against independent equations u-p or u+p-1, v-q, authored bounds and u-p!=0, including ordinals and coordinateMap[0,1,2,3]. It does not rely on samples or XYZ distances. |
| Image/fiber meaning | The complete law implies image[0,1) x[0,1] x{0}, image dimension2 and two ordered residual tuples per XYZ, fiber dimension0. This parameter query does not test geometric image/fiber publication fields. |
| Reused observation | [Existing self evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-COONS-PLANE-01/VERIFICATION.md) retains Native/ASAN/ordinary-WASM folded controls, raw484/refined484/retained12 and two empty same-chart pairs. Embedded folded runtime is explicitly historical with currentRootAccepted:false. Current source differs from some receipt inputs; these are historical scoped controls, not a new current-source four-lane acceptance. |
| Remaining assignment | This maps4-P1/P2/P7/P8,5-C10 and6-S1/S2/S4 for this exact parameter-query input. It supplies no declared join, collapse or nonlinear identity, trimmed material, embedding/caller migration, or ordinary geometric SSI result. Changed-path acceptance is required only if a later cell changes these premises. |


##### S-NATIVE-DECLARED-SINGLETON-01: directed boundary identity candidate

[The existing M6 folded fixture](../../../../Tests/OriginalDomainConsumerVerification/Sources/M6SelfFixtures/M6ExactSelfFixtures.swift)
constructs degree(2,1) Native G(u,v)=(u^2,v,0), D=[-1,1]^2, and uses
DefaultSurfaceSurfaceIntersector.exactParameterRelations on the full D x D.
The checked source-law issuer declares only left scope{(-1,0)} to right
scope{(1,0)} with identity axes/gains and offset(2,0). The public
DefaultOriginalExactNativeSelfContactQuery consumes that receipt together
with the authored diagonal. This is not a declaration of the whole U boundary.

| Cell field | Exact scope |
|---|---|
| Independent complete residual candidate | {(u,v,-u,v): -1<=u,v<=1, u!=0} excluding only(-1,0,1,0). The reverse tuple(1,0,-1,0), all V!=0 boundary tuples and other opposite-U contacts remain; the supplied receipt is directed and is not automatically symmetrized. |
| Germ and meaning | At the paired endpoints, Gu=(-2,0,0) and Gu=(2,0,0). The positional declaration cannot authorize equality of derivatives, normals or one-sided germs. |
| Existing observation | The original fixture checks selected opposite-U members, the declared singleton exclusion, an outside-scope boundary member, diagonal exclusion and retained source after COW mutation. It does not compare the complete residual oracle against every refined cell. Its original receipt snapshot/lanes remain the limit of that evidence. |
| Unobserved acceptance | Full residual-cell equality and reverse-direction retention for this exact candidate still require observation; membership success is not complete acceptance. The cell maps only the singleton scope of5-C4/C5/C8/C9 and6-S2/S4, not general join or whole paired-boundary completion. |

The [existing paired child identity fixture](../../../../Tests/OriginalAffinePairedIdentityVerification/PairedProof.swift)
checks the directed whole edge L(u,0)->R(1-u,0), u in[0,1], using an
OriginalParameterIdentity with its Parent source and exact-rational field.
Its two cover calls bind distinct Parent owners; the same Source type does not
make them one original parent. The transverse child derivatives differ, and the
reverse positional receipt is separately issued.
There is no corresponding public self/boundary consumption receipt. The current
[generic issued-graph self query](../../OriginalSurfaceEmbedding/DefaultOriginalIssuedGraphSelfContactQuery.swift)
is not Native-type-limited, but requires the same original source owner on both
raw sides and both identity scopes, with OriginalExactScalarDomain identity
values. The existing paired fixture instead uses ExactRationalScalarDomain and
two owners. These are static field/owner constraints, not an observed runtime
failure. A single-child OriginalImageSurface3D constructor does not supply an
aggregate parent for this pair. The still-unmapped concrete fields are one
actual parent binding with both original children, its complete request/laws,
a same-owner/same-field paired identity and an independent complete public
residual oracle. The existing receipt cannot fill those fields, and is not a new
prerequisite for other frozen cells.

The correction candidate's nonzero Z distinguishes its actual quintic host law
from the planar Coons input. Its source field and Euclidean arc-length owner must
be reused rather than rebuilding stations or host coefficients. The ordinary
publication contract remains with
[NativeExactGeometricRelations](../../NativeExactGeometricRelations/DESIGN.md#ordinary-retained-polyline-lift-against-an-axis-plane).
Candidate observations, implementation and evidence are recorded only in
PROGRESS.md and their named receipts; this index is not a second queue.

##### Domain and graph requirements

| Accepted ID | Canonical contract | Public cell / explicitly unmapped remainder |
|---|---|---|
| 4-P1 | [Required source families](#required-source-family-obligations) | Concrete bindings: SRC-RB-PERIODIC-01; SRC-DS-ANGULAR-01. CS-POLY-01 and CS-NATIVE-PERIODIC-PARAM-01 retain authored support; remaining source variants below need their own public inputs. |
| 4-P2 | [Contracts and Invariants](#contracts-and-invariants) | Concrete bindings: SRC-TRANSPORT-NONLINEAR-01; B-PCURVE-RATIONAL-01. Existing CS-POLY selection receipts and B-COONS-HOLE policies; general open/singleton/disconnected/excluded public requests remain unmapped per source/API. |
| 4-P3 | [Graph/request binding](#local-source-graphrequest-binding-b3) | Concrete bindings: SRC-LIFT-GENERAL-HOST-01; SRC-TRANSPORT-NONLINEAR-01. CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01 fixes one nonlinear original-host preimage and complete public point/empty oracle below; acceptance remains pending. Its unique forward bijection does not close general many-to-one, one-to-many or singular preimages. Finite affine/image/traversal receipts remain reusable premises. |
| 4-P4 | [Native lift domain](#native-surface-lift-domain-consumption) | Concrete binding: S-NONLINEAR-COLLAPSE-01 for coincident self tuples. S-NATIVE-ISOLATED-TANGENT-01 fixes a genuine isolated tangential self-contact and embedding caller. Other critical source families remain unmapped; a two-source SSI apex cell cannot substitute for self-contact. Existing constant/nonmonotone source premises and self controls; CS-REVOLUTION-AXIS-FIBER-01 now publishes one source-proved axis fiber with all original U and generator correspondence. Other rank-loss/singular/constant public branches remain unmapped; this is not an M5 collapse identity receipt. |
| 4-P5 | [Required source families](#required-source-family-obligations) | Concrete bindings: S-TRIMMED-FOLD-01; B-PCURVE-IMAGE-01. Three B-COONS-HOLE policy cells exercise exact material separately from square cover; other non-Cartesian domain predicates remain unmapped. |
| 4-P6 | [Guarded offset](#guarded-offset-domain-composition), [graph/request binding](#local-source-graphrequest-binding-b3) | Concrete bindings: SRC-OFFSET-GENERAL-01; SRC-DRAFT-A-ZERO-01; SRC-DRAFT-D-ZERO-01. CS-POLY-01 consumes existing lift guards. Offset normalization/root/branch and general owning-side guard public cells remain unmapped. |
| 4-P7 | [Contracts and Invariants](#contracts-and-invariants) | Concrete bindings: M8-SOURCE-DI-01; SSI-COONS-PLANE-01. Existing Coons four-chart / all16-pair self and Native symbolic-family cells; each remaining family's complete public cover needs its own mapping. |
| 4-P8 | [Finite selected-family query](#finite-selected-family-query) | Concrete bindings: SRC-JOIN-NONRATIONAL-01; I-DISTINCT-SHARED-CREASE-01. CS-POLY-01, S-COONS-PLANE-01 and periodic Native incidents; remaining join/seam/tensor source variants stay unmapped. |
| 4-P9 | [Native periodic public cell](#cs-native-periodic-param-01-unbounded-independent-native-cycles) | Concrete bindings: SRC-ANGULAR-TORUS-TWO-CYCLES-01; CS-OFFSET-PERIODIC-ZERO-GEOM-01. CS-NATIVE-PERIODIC-PARAM-01 covers its symbolic parameter result. CS-OFFSET-PERIODIC-ZERO-GEOM-01 defines one complete guarded Z^2 geometric-family oracle; ordinary runtime is unobserved. Other ordinary geometric infinite families stay unmapped. |
| 4-P10 | [Graph/request binding](#local-source-graphrequest-binding-b3) | Concrete bindings: SRC-RB-OFFSET-LIFT-01; SRC-LIFT-GENERAL-HOST-01. Existing lift/Coons self cells consume actual auxiliary layouts and retained depths; general graph/source theorem combinations remain unmapped. |
| 4-P11 | [Source-family obligations](#required-source-family-obligations), [source authority](../../OriginalSourceIssuance/DESIGN.md) | Concrete bindings: SRC-DC-ALGEBRAIC-01; SRC-JOIN-HYPERBOLIC-01; CERTIFIED-CONE-CONE-NEAR-APEX-01. Existing polyline algebraic station and subnormal-normal cells have scoped evidence. CS-ANGULAR-PHYSICAL-ARC-PLANE-01 below binds its exact Q(pi) phase/root/child-label oracle to scoped four-target ordinary-public evidence. Other physical maps retain separate inputs and correspondence obligations. Other algebraic/physical-angle public capabilities remain unmapped. |

##### Identity requirements

| Accepted ID | Canonical contract | Public cell / explicitly unmapped remainder |
|---|---|---|
| 5-C1 | [Affine child identity](../OriginalParameterIdentity/DESIGN.md#affine-child-identity-transport), [paired transport](../OriginalParameterIdentity/DESIGN.md#paired-affine-child-identity-transport) | Concrete bindings: S-IMAGE-PERIOD-01; S-IMAGE-COLLAPSED-OPEN-01. Existing paired child issuer/view receipts have no corresponding Parent-source public boundary/self consumption receipt, as described under S-NATIVE-DECLARED-SINGLETON-01. General child-to-parent consumption remains unmapped. |
| 5-C2 | [Identity composition](../OriginalParameterIdentity/DESIGN.md#protocol-composition-and-consumer-responsibility) | Concrete bindings: S-NONLINEAR-COLLAPSE-01; S-IMAGE-COLLAPSED-OPEN-01. [S-NATIVE-COLLAPSED-OPEN-SCOPE-01](#s-native-collapsed-open-scope-01-singular-product-with-an-open-scope) fixes one existing Native singular complete-product input and whole residual oracle. Current complete-cell acceptance is unobserved. Nonlinear transport and issued-graph auxiliary compilation remain unmapped. |
| 5-C3 | [Identity contracts](../OriginalParameterIdentity/DESIGN.md#contracts-and-invariants) | Concrete bindings: SRC-JOIN-NONRATIONAL-01; I-DISTINCT-SHARED-EDGE-01. S-RULED-CLOSED-GUIDE-SEAM-01 fixes one same-parent whole seam and complete directed residual. Its initial work/Native-type stops are retained diagnostics. Current checked solver reuse completes all49 original raw pairs and law-bound directed issuance succeeds. The subsequent exact domain-wide residual simplifier lets the focused Native prepared query pass its complete reverse-only residual oracle under the unchanged work cap. Final Native/ASAN/ordinaryWASM/Embedded each pass the10 bounded oracle/resource/cancel/lifetime/identity/Coons groups; one comprehensive review passed and [main integration](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-RULED-CLOSED-GUIDE-SEAM-01/integration.json) delivered commit d9abe057; recorded earlier work failures stay historical diagnostics. Other joins remain unmapped. |
| 5-C4 | [Identity contracts](../OriginalParameterIdentity/DESIGN.md#contracts-and-invariants) | Concrete bindings: I-DISTINCT-SHARED-CREASE-01. Closed germs retained by existing cells; positional identity must not authorize differential/normal equality. General germ consumer remains unmapped. |
| 5-C5 | [Whole relation view](../OriginalParameterIdentity/DESIGN.md#checked-whole-relation-view) | Concrete bindings: I-DISTINCT-SHARED-EDGE-01; I-DISTINCT-FALSE-EDGE-01. S-NATIVE-DECLARED-SINGLETON-01 fixes the directed Native singleton. S-NATIVE-DECLARED-WHOLE-EDGE-01 below fixes the same-owner whole-edge declaration and complete residual oracle; its dedicated acceptance consumes the checked declaration through the public self query. Distinct-owner/general variants remain separate; delivery is tracked in PROGRESS.md. Distinct-owner paired boundaries and general child consumers remain unmapped. |
| 5-C6 | [Analytic theorem consumption](../OriginalParameterIdentity/DESIGN.md#analytic-source-theorem-consumption), [revolution periods](../OriginalParameterIdentity/DESIGN.md#source-owned-revolution-period-consumption) | Concrete bindings: S-IMAGE-PERIOD-01. Period receipts exist; transported period identity in a concrete boundary/self public cell remains unmapped. |
| 5-C7 | [Analytic theorem consumption](../OriginalParameterIdentity/DESIGN.md#analytic-source-theorem-consumption) | Concrete bindings: S-NONLINEAR-COLLAPSE-01; S-IMAGE-COLLAPSED-OPEN-01. S-COONS-PLANE-01 scoped-collapse controls reuse proved subsets. [S-NATIVE-COLLAPSED-OPEN-SCOPE-01](#s-native-collapsed-open-scope-01-singular-product-with-an-open-scope) fixes one Native half-open collapse-product oracle with current whole-cell runtime unobserved; other constant-subset/collapse sources remain unmapped. |
| 5-C8 | [Checked implementation](../OriginalParameterIdentity/DESIGN.md#checked-implementation) | Concrete bindings: I-DISTINCT-SHARED-EDGE-PARTIAL-01; I-DISTINCT-FOREIGN-FRAME-01. Existing S-COONS-PLANE-01 scope/role controls; S-NATIVE-IDENTITY-COMPOSITION-01 below fixes one same-owner restricted/symmetric/transitive relation consumed by the public self query. Its four-target scoped evidence is linked below; review and delivery state is owned by PROGRESS.md. Distinct-owner/general intermediate-owner and nonlinear full-pullback combinations remain unmapped. |
| 5-C9 | [Whole relation view](../OriginalParameterIdentity/DESIGN.md#checked-whole-relation-view) | Concrete bindings: I-DISTINCT-SHARED-CREASE-01. S-COONS-PLANE-01 consumes only its retained proof meaning; remaining proof-kind consumers need explicit cell bindings. |
| 5-C10 | [Issued self-contact port](../../OriginalSurfaceEmbedding/DESIGN.md#issued-graph-residual-self-contact-port) | Concrete bindings: S-NATIVE-FOLD-01; S-TRIMMED-FOLD-01. S-NATIVE-FOLD-01 names the existing complete nonstructural same-XYZ/distinct-UV control with explicitly historical receipt scope; general folded/critical source cells remain unmapped. |
| 5-C11 | [Whole relation view](../OriginalParameterIdentity/DESIGN.md#checked-whole-relation-view) | Concrete bindings: I-DISTINCT-SHARED-EDGE-01; S-IMAGE-COLLAPSED-OPEN-01. Existing public self query consumes requirement-dispatched views; remaining boundary/intersection consumers remain unmapped. |
| 5-C12 | [Identity composition](../OriginalParameterIdentity/DESIGN.md#protocol-composition-and-consumer-responsibility) | Concrete bindings: I-DISTINCT-FALSE-EDGE-01; I-DISTINCT-FOREIGN-FRAME-01. Existing self failure/scope controls; each new caller must retain proved/counterexample/unsupported-scope outcomes. No general caller closure. |

##### S-NATIVE-COLLAPSED-OPEN-SCOPE-01: singular product with an open scope

| Binding | Fixed cell contract |
|---|---|
| Accepted slice | 5-C2 singular complete-product consumption, 5-C7/4-P4 collapsed subset and 6-S2 scoped exclusion only. General nonlinear transport (4-P3) and issued-graph auxiliary compilation (6-S3) remain open. |
| Actual public input | Reuse [M6ExactSelfFixtures.verifyCollapsedPole](../../../../Tests/OriginalDomainConsumerVerification/Sources/M6SelfFixtures/M6ExactSelfFixtures.swift:235): the original Native surface `G(u,v)=(u*v,v,0)` on `[0,1]^2`, effective self request `D=[0,1]×{0}`, the same prepared cover/source binding/frame/field on both sides, and checked `collapsed(law:raw.pieces[0].first.law,on:Q)` for `Q=[0,1/2)×{0}`. Call `DefaultOriginalExactNativeSelfContactQuery.contacts` with the retained raw collection and scoped receipt. This is an existing constructor and public route. |
| Independent complete oracle | Every raw tuple is `(u,0,uPrime,0)` with both free coordinates in `[0,1]`. Removing the authored diagonal and only `Q×Q` leaves exactly `u != uPrime && (u >= 1/2 || uPrime >= 1/2)`. Both ordered directions remain; `1/2` is outside the open scope. All retained tuples map to the origin. Image dimension0/fiber dimension2 describe the oracle and are not assertions about unexposed DTO fields. On the pole `G_u=0` and `G_v=(u,1,0)`; position identity grants no germ or normal equality. |
| Required receipts / causal change | Reuse the same prepared Native source/cover, complete retained raw self product, source-law-issued `.collapsedSubset`/`.completeProduct` receipt, authored diagonal and existing Native identity compiler/refinement. The existing compiler removes the entire scoped product without a fabricated inverse or axis equation. No production/API change is currently justified. |
| Observation and stop | The actual current public path passes its complete raw9/refined29 terminal iff with20 included and preserves both ordered directions/open endpoint. [Four-target acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-COLLAPSED-OPEN-SCOPE-01/VERIFICATION.md) binds seven groups per target, current source/products, exact N/N-1 resources, depth/count/foreign/nonconstant controls, detached/COW lifetime and nonempty/empty/later cancellation. The first empty-control oracle lacked a general sign invariant on its singleton partition; corrected exact-domain/terminal exclusion proves the complete empty request. Historical three-member checks and the independently closed issuer F1 failure remain diagnostic premises only. No production/API change was needed; review/commit/main delivery are tracked in PROGRESS.md. |
| Completion evidence | A bounded actual public observation must bind current source/generation/compiler/product/log authorities and compare every terminal cell with the whole residual oracle, including both directions and the half-open boundary; then applicable failure/resource/cancel/lifetime controls, scoped review, commit and main delivery. Existing three point checks are retained premises only. No zero-gain parameter transport is claimed: that owner rejects singular gain, and this Native receipt is not an issued-graph relation. |

##### Native intake and boundary requirements

| Accepted ID | Canonical contract | Public cell / explicitly unmapped remainder |
|---|---|---|
| 6-I1 | [Native M6 handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#m6-exact-family-handoff) | Concrete bindings: M6.PT. M6.PT owns the delivered Native consumer intake; no new general-family result is inferred. |
| 6-I2 | [Native M6 handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#m6-exact-family-handoff), [Topology wiring](../../../CADTopology/DESIGN.md#m6-portable-validation-wiring) | Concrete bindings: M6.PT. M6.PT owns direct dependency, cancellation, canonical identity and error portability evidence. |
| 6-I3 | [Public cell execution](#public-acceptance-cell-execution) | Concrete bindings: M8-PORTABLE-01. M6.PT snapshot receipts and each later cell's independent integration receipt; a changed premise requires its owning check. |
| 6-I4 | [Native M6 handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#m6-exact-family-handoff) | Concrete bindings: M6.PT. M6.PT coherent Native-limited main delivery; general boundary/self migration remains separate. |
| 6-B1 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Concrete bindings: B-PCURVE-IMAGE-01. Auxiliary rolling relation face input remains unmapped; its source-only rolling cell cannot discharge boundary admission. Three B-COONS-HOLE cells consume issued graphs; other source families and auxiliary layouts remain unmapped. |
| 6-B2 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Concrete bindings: B-PCURVE-IMAGE-01; B-PCURVE-RIGID-01. Existing validated Coons face/source correspondence; general exact face authorities remain unmapped. |
| 6-B3 | [Concrete boundary cells](#concrete-boundary-cells-using-existing-coons-receipts) | Concrete bindings: B-PCURVE-POLYLINE-01; B-PCURVE-IMAGE-REVERSE-01. Existing outer/inner loops, coedges and directed constant-U/V spans; other loop/span constructions remain unmapped. |
| 6-B4 | [Required source families](#required-source-family-obligations) | Concrete bindings: B-PCURVE-RATIONAL-01; B-PCURVE-CONTINUATION-01; B-PCURVE-WORD-01; B-PCURVE-IMPLICIT-CLOSED-01. B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01 below fixes one genuine rational quadratic and complete material oracle; its initial unsupportedCoverage observation is historical. The dedicated acceptance binds source-owned directed winding to the retained raw/refined public closed clip on four targets. Other rational/implicit/certified/nonrational pcurve branches remain unmapped. |
| 6-B5 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Producer dependency: SRC-RB-PERIODIC-01 identifies missing cylinder pullback pcurve. Its actual face-bound missing-pcurve consumer input remains unmapped; this source-only cell does not discharge 6-B5. Existing retained pcurves are consumed. Missing-pcurve producer branches remain unmapped; no reconstructed placeholder is authorized. |
| 6-B6 | [Native M6 handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#m6-exact-family-handoff) | Concrete binding: B-NATIVE-COLLAPSED-CLOSED-01. B-PCURVE-TRANSLATED-01 proves only an authored translation, not host periodicity. An actual pole/apex boundary face cell remains unmapped; standalone SSI apex fibers are not boundary acceptance. B-NATIVE-COLLAPSED-CLOSED-01 below has a scoped four-lane whole-cell parameter/material comparison with exact raw ordinals, all bottom/corner incidents and retained owner. Existing seam/collapse membership receipts remain historical premises only. General pole/apex/multicycle cells remain unmapped. |
| 6-B7 | [Concrete boundary cells](#concrete-boundary-cells-using-existing-coons-receipts) | Concrete bindings: B-PCURVE-RATIONAL-01; S-TRIMMED-FOLD-01. Exact hole material over every retained raw cell; other material predicates remain unmapped. |
| 6-B8 | [Concrete boundary cells](#concrete-boundary-cells-using-existing-coons-receipts) | Concrete bindings: B-COONS-HOLE-CLOSED-01; B-COONS-HOLE-STRICT-01; B-COONS-HOLE-BOUNDARY-01. B-COONS-HOLE-CLOSED-01, B-COONS-HOLE-STRICT-01 and B-COONS-HOLE-BOUNDARY-01 are separate policy cells. |
| 6-B9 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Concrete bindings: B-PCURVE-POLYLINE-01; B-PCURVE-IMAGE-REVERSE-01. Existing raw/refined ordinal and boundary-span controls; general lifted layouts remain unmapped. |
| 6-B10 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Concrete bindings: M8-MATERIAL-SELF-01. Existing cells retain L5 refinement; each new cell must identify the same owner rather than re-solve. |
| 6-B11 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Concrete bindings: B-PCURVE-IMAGE-01; B-PCURVE-RIGID-01. Existing cells reach validated Kernel parameter/material publication and lifetime queries; remaining source/caller combinations and M7 geometry stay open. |

##### B-NATIVE-COLLAPSED-CLOSED-01: collapsed material pullback

Use the actual constructors in
[M6ExactBoundaryFixtures.verifyPeriodicAndCollapse](../../../../Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures/M6ExactBoundaryFixtures.swift):
degree(1,1), both knot vectors[0,0,1,1], surface control rows
[(0,0,0),(0,0,0)] and [(0,1,0),(1,1,0)], and a degree1 Native
curve with both controls at the origin. Thus G(u,v)=(uv,v,0), C(t)=origin,
with the full closed T/U/V product[0,1]^3. The existing `face` constructor
retains one outer rectangle[1/4,3/4]x[0,1], four directed constant-U/V
pcurves and forward coedges, and validates its face/sheet/body with `.exact`.
Invoke `DefaultOriginalFaceBoundaryClipper.clip(.curveSurface(raw),to:in:selection:.closed,...)`
using the retained Native CS L5/DI relation and that validated face.

The independent complete oracle is
{(T,U,V)=(t,u,0):0<=t<=1,1/4<=u<=3/4}: equality forces v=0,
and the closed material predicate restricts only u. XYZ is the origin,
image dimension0 and original-coordinate fiber dimension2; these dimensions
describe the oracle and are not claimed as existing Kernel publication fields.
Retain every T/U, the bottom boundary and both corner incident sides, every
raw/refined ordinal and the existing retained refinement owner. No M5 identity
receipt is needed. This cell maps6-B6/B7/B9/B10/B11 within this input; rational
curved pcurves, general pole/apex/multicycle and M7 geometry remain separate.

The existing fixture checks inside/outside members and raw/refined correspondence,
not equality of every refined cell with this complete oracle. Historical
[M6 receipts](../../../../Tests/OriginalDomainConsumerVerification/Evidence/M6/VERIFICATION.md)
and Native/ordinary-WASM/Embedded seamPole logs retain their original snapshot;
the current fixture differs from that receipt. The [dedicated complete-cell proof](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-COLLAPSED-CLOSED-01/VERIFICATION.md)
compares every terminal raw/refined cell, exact raw ordinal signatures and every
bottom/left/right incidence through this actual Kernel route, after construction
locals are released. Its four-lane receipts bind one final portable fixture and
the selected current32-source adapter with admitted unchanged source/Kernel/lower
products. No production repair was required by this observation. Zero-budget and
positive-result cancellation controls have only their recorded scope; empty final
cancellation, whole-query N/N-1 and concurrency are not new claims. Review/main
execution state remains solely in PROGRESS.md; historical membership is not the
current complete oracle or a new prerequisite.

##### B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01: directed curved trim candidate

Use the existing [Native boundary fixture constructors](../../../../Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures/M6ExactBoundaryFixtures.swift)
for G(u,v)=(u,v,0), C(t)=(t,7/32,0), the full original T/U/V[0,1]^3,
the exact-validated lifted-edge face and public Kernel `.closed` clip. One
forward outer loop traverses bottom(0,0)->(1/2,0), right->(1/2,1/4),
then a genuine rational quadratic pcurve back to(0,0). Its actual public
`BSplineCurve2D` constructor has degree2, knots[0,0,0,1,1,1], controls
[(1/2,1/4),(1/4,1/4),(0,0)] and weights[1,3,1]. This is a new input
recipe; the existing graph-band fixture's unit weights are not its evidence.
No coedge orientation reversal is applied to the already directed pcurve.

Its original s[0,1] law is D=1+4s-4s^2>=1,
u=(1/2+s/2-s^2)/D, v=(1/4+s-5s^2/4)/D. The closed material is exactly
0<=u<=1/2, 0<=v<=1/4 and
F=9(1-4v)(u-v)-(2v-u)^2>=0. Equality with the original line gives
u=t,v=7/32, and F(t,7/32)=(t-1/4)(7/4-t). The complete tuple oracle is
{(t,t,7/32):1/4<=t<=1/2}, XYZ=(t,7/32,0), image1/fiber0. Boundary
incidents occur only at t=1/4 on curved coedge2, original s=1/2, and
t=1/2 on right coedge1, original affine parameter7/8. Interior tuples
have no boundary incident. Strict and boundary policies would be separate
cells with the open interval and its two endpoints respectively.

At the baseline main0422fa0c, the [boundary compiler](../../OriginalBoundaryClipping/OriginalExactBoundaryCompiler.swift)
did not compile the `.bSpline` pcurve case and its default threw
`NativeExactRelationFailure.unsupportedCoverage`. The [one-call Native observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01/native-observation-v1/receipt.json) at main0422fa0c reaches exact face validation and reproduces that typed failure in the actual public closed clip. Receipt434c08d8 binds unchanged admitted adapters, selected fixture/helper compiler inputs, product and runtime log; it is a refusal observation, not successful material clipping.
The missing consumer authority is the complete directed rational-pcurve
winding law, not another intersection solve or polygonal approximation.
The delivered collapsed Native receipt can supply unchanged lower premises
only. The causal cell change is a source-owned checked whole-arc theorem for this complete positive quadratic chart and its signed winding/material consumption in the existing compiler. The same retained L5 relation is refined; no additional intersection solve or polygonal boundary is needed. This observed stop selects the necessary cell change. The [dedicated acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01/VERIFICATION.md) now verifies this complete closed tuple oracle, directed winding/guard controls, original raw/refined correspondence, resources/cancel/lifetime on the four fixed targets. Its one scoped review passes; commit/main delivery remains tracked in PROGRESS.md. General multispan/implicit/nonrational pcurves and required issued-quadratic public cells remain open, so this cell does not complete6-B4 as a whole.

##### S-NATIVE-DECLARED-WHOLE-EDGE-01: same-owner directed whole edge

Use the actual [folded Native constructor](../../../../Tests/OriginalDomainConsumerVerification/Sources/M6SelfFixtures/M6ExactSelfFixtures.swift#L146):
degrees(2,1), U knots[-1,-1,-1,1,1,1], V knots[-1,-1,1,1],
and X controls[1,-1,1] in each V row. Its complete original map is
G(u,v)=(u^2,v,0) on D=[-1,1]^2. There is one closed chart and one ordered
chart pair; adding knots to obtain four pairs would change this input.

| Cell field | Fixed value or unobserved gap |
|---|---|
| Public request | Bind this source once in the existing exact rational algebraic field, prepare full D x D Native exact parameter relations, then call DefaultOriginalExactNativeSelfContactQuery.contacts(in:excluding:) with the single checked directed declaration below and the existing caller limits/admission. |
| Identity receipt | DefaultOriginalParameterIdentityIssuer.declaredBoundary over the same source/chart/frame, leftAxis/rightAxis0, lower/upper sides, left scope{-1}x[-1,1], right scope{1}x[-1,1], permutation[0,1], gains[1,1], offsets[2,0]. The declaration is a candidate; the existing issuer verifies the whole original boundary law before issuing declaredSharedBoundary. |
| Complete raw oracle | {(u,v,p,q) in D x D: (p=u or p=-u),q=v}, from u^2-p^2=(u-p)(u+p). |
| Complete residual oracle | {(u,v,-u,v): -1<u<=1,u!=0,-1<=v<=1}. Only the authored diagonal and directed{(-1,v,1,v)} are removed. The reverse edge remains. Both V corners and the one original closed-span incident remain. |
| Image and fiber | XYZ=(u^2,v,0), image(0,1]x[-1,1]x{0}, parameter/image dimension2 and fiber dimension0. For0<X<1 both ordered tuples remain; X=1 retains the reverse tuple only. |
| Proof meaning | Position-only declaration. Gu(-1,v)=(-2,0,0) and Gu(1,v)=(2,0,0); the positive U transport does not prove equal derivatives or normals. Half-edge scope excludes only that half; V reversal agrees only at V=0 and cannot authorize the whole edge. Distinct source owners remain a separate unmapped variant. |
| Public acceptance / exact limit | [Dedicated acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-DECLARED-WHOLE-EDGE-01/VERIFICATION.md) consumes the checked whole boundary through the actual public self query and verifies the complete terminal-cell iff residual plus half-scope, directed/reverse, invalid declaration, resource/cancel and retained lifetime controls. It retains unchanged L4 checked correspondence; ordinal alignment/range and full raw-ID order are checked, without independent lower reclassification. Image/fiber values above are oracle meanings rather than unexposed result fields. The historical singleton receipt alone does not provide this whole-edge evidence. |
| Receipt dependency / next observation | Reuse matched Native32, SourceGeometryAdapters and DI/L0-L5 premises; freshly compile only the current self query protocol/query/identity compiler/result and a dedicated complete-oracle fixture. All four current self bodies match the retained consumer-native-stable receipt9ce1b516. Its singleton fixture does not exercise this whole-edge scope, so old binary success is insufficient. Native32 receipt5de3eda0 and its retained source5 nominal dependency are separately matched; the dedicated whole-edge fixture must retain its exact compiled inputs. No new source type, aggregate parent or lower solver is required by this definition. |

This cell maps one same-owner branch of5-C5/C9/C10/C11 and6-S2/S4/S7.
The scoped verification binds the four fixed targets and a single review with
its F1 entry-isolation confirmation. Commit/main delivery is tracked only in
PROGRESS.md; this unit does not complete the general identity or self-contact families. Execution state stays in PROGRESS.md.

##### S-NATIVE-IDENTITY-COMPOSITION-01: consumed scoped symmetry and composition

Use the same existing one-chart G(u,v)=(u^2,v,0), full D=[-1,1]^2
constructor as S-NATIVE-DECLARED-WHOLE-EDGE-01. Bind/prepare it once and
retain the full D x D raw relation; every proof stage uses that same
prepared.space.frame and scalar owner. This definition consumes existing
receipts and does not depend on the whole-edge cell's acceptance.

| Cell field | Fixed input/oracle or explicit gap |
|---|---|
| Public identity input | Let A={-1}x[-1,1], B={1}x[-1,1], J=[-1/2,1/2]. Issue E:A->B using the existing checked whole-boundary declaration, permutation[0,1], gains[1,1], offsets[2,0]. Call restricted(E,left:A with V[-1,1/2],right:B with V[-1/2,1]); the complete pullback is R:A_J->B_J. Call S=symmetric(E), I=compose(S,R), then C=compose(I,S). |
| Verified relation to consume | C:B_J->A_J, permutation[0,1], gains[1,1], offsets[-2,0], depth3/proofCount5. The kind stays declaredSharedBoundary. Restricted/symmetric receipts share E's owner; compositions retain their parents. The scoped fixture reads these values from the actual issued relation and checks both closed scopes. |
| Public consumer | DefaultOriginalExactNativeSelfContactQuery.contacts(in:raw,excluding:[C],domainLimits:cellLimits:topologyLimits:using:). Pass only C, not E/R/S/I. The consumer adds the authored diagonal. Existing caller80m work/1GiB/depth32 and source/transport/proof/cell/topology ceilings remain fixed. |
| Independent complete residual | {(u,v,-u,v): u in[-1,1],u!=0,v in[-1,1],NOT(u=1 AND -1/2<=v<=1/2)}. Forward edge remains for every V. Reverse edge is removed only on closed J, including its endpoints; both V corners remain. Every terminal raw/refined cell and ordinal must satisfy this iff oracle. |
| Image/fiber and proof meaning | XYZ=(u^2,v,0), image(0,1]x[-1,1]x{0}, parameter/image dimension2 and fiber dimension0. X=1,V in J has only the forward ordered tuple; the other image points have both directions. Original one-span incidents remain. Opposite Gu(-1,v)=-2X and Gu(1,v)=2X forbid inferring derivative/normal continuity from the position-only receipt. |
| Owner/scope counterexample | All stages require the identical prepared frame owner. An independently rebuilt equal frame fails foreignOwner at the middle selection intersection. Scope restriction/symmetry/composition cannot widen J or strengthen the proof kind. Distinct-owner paired transitivity is a separate unclosed variant. |
| Receipt dependencies / actual path | Existing Native source/DI/full raw relation, checked declared boundary, restriction/symmetry/compose and relation-view/self compiler. DefaultOriginalParameterIdentityIssuer.swift owns complete middle-scope intersection and inverse pullback; OriginalExactSelfIdentityCompiler.swift consumes both scopes and the affine word in the original four-variable ring. Reuse matched Native32/source5/SourceGeometry/DI/L0-L5 and current self4 premises; no new source/solver or whole-M4 barrier. |
| Actual stop / evidence | The actual public query preserves the complete independent residual through every terminal cell. [Scoped evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/VERIFICATION.md) binds the initial Native complete observation, separate Native controls and all six groups on ASAN/ordinary-WASM/Embedded. Fresh upper/source/lower compilation is zero; the four unchanged self bodies reuse exact compiler/product/source receipts. Raw-cell alignment and ordinal range consume the existing checked L4 pullback guarantee; this cell does not independently reclassify each raw cell or publish image/fiber fields. Historical review F1 identified a missing compile-time binding between the current issuer and cached independent DI object. The [current-source finding confirmation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/F1/current/VERIFICATION.md) closes it through fresh single-primary issuer codegen on Native/ASAN/ordinary-WASM and admitted current Embedded WMO products; every target passes the same six full-oracle/control/resource/cancel groups. Historical packet and failure remain unchanged. Commit and main delivery are tracked only in PROGRESS.md. |

This cell maps the same-owner restriction/symmetry/transitive-consumer branch
of5-C8/C9/C11 and6-S2/S7. General nonlinear/paired-owner composition remains
open. Execution state is owned only by PROGRESS.md.

##### Self-contact, public output and integration requirements

| Accepted ID | Canonical contract | Public cell / explicitly unmapped remainder |
|---|---|---|
| 6-S1 | [Issued self-contact port](../../OriginalSurfaceEmbedding/DESIGN.md#issued-graph-residual-self-contact-port) | Concrete bindings: S-NONLINEAR-COLLAPSE-01; S-IMAGE-PERIOD-01. S-COONS-PLANE-01 all16 products and S-NATIVE-FOLD-01 all4 ordered products; complete products of every remaining source/auxiliary family stay unmapped. |
| 6-S2 | [Self cell](#s-coons-plane-01-complete-issued-graph-self-product) | Concrete bindings: S-IMAGE-COLLAPSED-OPEN-01. Existing scoped diagonal/subset controls; additional consumed M5 proofs need exact scopes per cell. |
| 6-S3 | [Issued self-contact port](../../OriginalSurfaceEmbedding/DESIGN.md#issued-graph-residual-self-contact-port) | Concrete bindings: S-NONLINEAR-COLLAPSE-01. Existing auxiliary-placement controls; nonlinear identity compilation remains unmapped. |
| 6-S4 | [Self cell](#s-coons-plane-01-complete-issued-graph-self-product) | Concrete bindings: S-NATIVE-FOLD-01; S-TRIMMED-FOLD-01. S-NATIVE-FOLD-01 retains both nonstructural ordered branches against an independent whole-cell oracle; general contact source branches remain unmapped. |
| 6-S5 | [Self cell](#s-coons-plane-01-complete-issued-graph-self-product) | Concrete bindings: S-NONLINEAR-COLLAPSE-01; SSI-CONE-CONE-COMMON-APEX-01. Critical, isolated-point, coincident and boundary complete classification requires additional public cells; unmapped. |
| 6-S6 | [Issued boundary handoff](../../../CADKernel/OriginalBoundaryClipping/DESIGN.md#issued-graph-boundary-handoff) | Concrete bindings: S-TRIMMED-FOLD-01. Exact trimmed material on both self tuples has no frozen complete caller cell. The current Native and issued boundary clippers each refine their raw relation; neither public input composes a retained self residual or a previous material refinement. Fixture-side AND of independent membership queries is not a published consumer receipt. This is a static composition gap, not a reproduced runtime refusal. |
| 6-S7 | [Issued self-contact port](../../OriginalSurfaceEmbedding/DESIGN.md#issued-graph-residual-self-contact-port) | Concrete bindings: M8-IDENTITY-SELF-01. Existing scope/resource/cancel controls; every new caller must retain unresolved remainder and policy without exclusion. |
| 6-S8 | [Self cell](#s-coons-plane-01-complete-issued-graph-self-product) | Concrete bindings: S-EMBEDDING-CALLER-01; S-DRAFTED-SHEET-CALLER-01; S-COONS-OFFSET-CALLER-01. S-COONS-OFFSET-CALLER-01 is an unobserved actual offset-validator candidate. Embedding and drafted-sheet callers remain unmapped. |
| 6-S9 | [Embedding contract](../../OriginalSurfaceEmbedding/DESIGN.md#contracts-and-invariants) | Concrete bindings: S-EMBEDDING-CALLER-01. S-COONS-PLANE-01 proves a residual query only; actual embedding certification remains unmapped. |
| 6-S10 | [Issued self-contact port](../../OriginalSurfaceEmbedding/DESIGN.md#issued-graph-residual-self-contact-port) | Concrete bindings: M8-LIFETIME-01; S-EMBEDDING-CALLER-01. Existing retained query/COW/lifetime evidence; actual caller reuse must be recorded independently. |
| 6-S11 | [Failure and constraints](#failure-concurrency-and-constraints) | Concrete bindings: M8-RESOURCE-01; M8-CANCEL-01. Existing typed self failures and empty-family controls; each new public caller owns binding/coverage/resource/cancel failure propagation. |
| M7 | [Public migration](../../NativeExactGeometricRelations/DESIGN.md#public-migration-boundary) | Concrete bindings: SSI-COONS-PLANE-01; SRC-ANGULAR-TORUS-TWO-CYCLES-01; PROJECTION-CONTINUOUS-01. Existing ordinary CS point/contained cells and symbolic Native parameter-family cell retain their exact scope. CS-POLY-CORRECTION-01 binds its historical selected-entry decline to its scoped acceptance receipt; SSI-COONS-PLANE-01 is unobserved. General ordinary CS/SSI, XYZ plus all UV, image/fiber dimensions and geometric infinite families remain unmapped per source variant. Prepared-port success is not ordinary dispatch evidence. |
| M8 | [Public cell execution](#public-acceptance-cell-execution), [Verification](#verification-and-change-impact) | Concrete bindings: M8-SOURCE-DI-01; M8-GUARD-GRAPH-01; M8-IDENTITY-SELF-01; M8-MATERIAL-SELF-01; M8-PERIOD-XYZ-01; M8-CALLER-01; M8-PROJECTION-01; M8-RESOURCE-01; M8-CANCEL-01; M8-LIFETIME-01; M8-PORTABLE-01; M8-LEGACY-01. Every changed cell owns applicable success/exclusion/equality/failure, resource boundaries/overflow/cancel, retained lifetime/concurrent independent queries/reuse and fixed Native/ASAN/ordinary-WASM/Embedded evidence, one scoped review, commit and receipt-matched main delivery. Cumulative interactions remain the task integration owner's obligation; this index authorizes no broad rebuild or duplicate lower proof. |

##### Remaining acceptance definition and execution gate

This section recovers the input/oracle investigation lost with the deleted temporary
worktree. It defines acceptance, not completion. PROGRESS.md owns execution state.
A STATIC stop is a source-read limitation, not a reproduced runtime failure.
UNOBSERVED means the exact requested public execution has not yet been accepted.
Every cell must retain original source owners, full UV/preimages, guards, scope,
incident germs, caller admission, explicit failure and result lifetime.

The fixed order after complete mapping is: positive Coons SSI; rolling-ball SSI;
periodic offset XYZ; identity composition/open collapse; trimmed self-contact;
actual embedding/offset/drafted-sheet callers; remaining source/certified branches;
general boundary and projection; complete CS/SSI/symbolic publication; M8 integration.
Receipt dependencies apply per cell, without waiting for unrelated M4 production.

###### Common angular and algebraic authored inputs

A is an actual OriginalAngularTransportCurve3D around the analytic unit circle,
center0/normalZ, physicalRadians gain1/offset0, retained by an authored root span
[0,1]. Its position is C_A(t)=(-sin(t),cos(t),0). The intrinsic circle label is
not a physical radian: B is the exact stored binary64 2*Double.pi and k=2*pi/B.
Q is a Native unit-X line with an OriginalCurveRootBoundary parameter-polynomial
t^2-1/2, positive-root isolator[1/2,1], and authored span from0 to that root.
Writing alpha=sqrt(1/2), its normalized position is C_Q(t)=(alpha*t,0,0).
Algebraic endpoints are retained as roots, never rounded into Native knots.

For C=A or Q, N(u,v)=(u,0,v) is an actual bilinear Native construction. Bottom C
and top C+Z are joined by OriginalEndpointConnectorCurve3D vertical constructions,
with original endpoint owners and quinticHermite correction. Their actual Coons
boundary and OriginalBoundaryCorrectedSurface3D(N,boundaries) define G_C.
Endpoint cancellation gives G_C(u,v)=(C.x(u),C.y(u),v) on the full square.
No rounded sin(1), cos(1) or alpha is substituted for a retained endpoint owner.

The derivative curve uses OriginalPlaneDerivativeCurve3D with planeZ0 tangent
and curvature constraints at both ends: its correction vanishes identically.
For the derivative surface, apply that constructor to the vertical connectors,
with endpoint planesZ0/Z1, then retain the resulting Coons boundary in
OriginalPlaneDerivativeSurface3D. The independent position is
D_C(u,v)=(C.x(u),C.y(u),H(v)), H(v)=10v^3-15v^4+6v^5.
H'(v)=30v^2(1-v)^2 proves the complete monotone height correspondence.
Constructor acceptance for these general branches remains UNOBSERVED.

| Cell | Exact public request and complete oracle | Static change boundary |
|---|---|---|
| SRC-DC-ANGULAR-01 | Ordinary CS, derivative A, planeX=-1/2, fullT: sole T=pi/6; XYZ=(-1/2,sqrt(3)/2,0), planeUV=(0,-sqrt(3)/2). | Retain angular derivative source law rather than rational-only provider. |
| SRC-DC-ALGEBRAIC-01 | Same with Q, planeX=1/4: sole T=1/(4alpha), XYZ=(1/4,0,0), planeUV=(0,0). | Retain algebraic root-span coefficients and guard. |
| SRC-BC-ANGULAR-01 | Ordinary SSI, G_A and planeZ=1/2: all(u,1/2), XYZ=(-sin u,cos u,1/2), planeUV=(cos u,sin u). | General boundary atlas authority. |
| SRC-BC-ALGEBRAIC-01 | G_Q against planeX=1/4: u=1/(4alpha), all v, XYZ=(1/4,0,v), planeUV=(v,0). | Same, algebraic coefficients. |
| SRC-DS-ANGULAR-01 | D_A against planeZ=1/2: v=1/2 uniquely, all u, same angular BC output. | General derivative surface source authority. |
| SRC-DS-ALGEBRAIC-01 | D_Q against planeX=1/4: u=1/(4alpha), all v, XYZ=(1/4,0,H(v)), planeUV=(H(v),0). | Same, complete algebraic correspondence. |
| SRC-RULED-GENERAL-01 | Actual ruled(A,A+Z), planeZ=1/2: all u, G_A(u,1/2). | Angular child composition; Q/mixed branches remain separate obligations. |
| SRC-COONS-GENERAL-01 | Actual angular Coons above, planeZ=1/2: all u, G_A(u,1/2). | Angular child composition; Q/discontinuous branches remain separate obligations. |
| SRC-REVOLUTION-NONRATIONAL-01 | Revolve A aroundZ, U[0,B],V[0,1], CS unitY line T[-1,1]. All n=1,2: U=(n*pi-V)/k,T=(-1)^n, all V; n=0 only(U,V,T)=(0,0,1). | Complete nonrational generator and angular preimage; retain both image points and one-dimensional fibers. |

All singleton curve results have image/fiber dimensions0/0. The nonconstant SSI
curves above have1/0. Every closed chart incident remains represented. These
independent mathematical oracles do not assert a passing constructor or dispatcher.

###### General offset and nonlinear lift

| Cell | Authored input, request and complete oracle | Required connection |
|---|---|---|
| SRC-OFFSET-GENERAL-01 | Actual OffsetSurface3D(G_A,d), d=-1,0,1. Original normal=C_A, squared norm1. For d=0,1, SSI planeZ=1/2 gives all(u,1/2), XYZ=((1+d)C_A.x,(1+d)C_A.y,1/2), planeUV=((1+d)cos u,(1+d)sin u). For d=-1, CS unitZ line T[0,1] gives all(T,U,V)=(v,u,v), image1/fiber1. | General child law; retain normal guard even for zero offset. Nonidentity child maps remain separate. |
| SRC-LIFT-GENERAL-HOST-01 | Actual lift on G_A with Native degree2 pcurve knots[-1,-1,-1,1,1,1], controls[(1,1/2),(-1,1/2),(1,1/2)], unit weights. Normalized T maps UV=((2T-1)^2,1/2). PlaneX=-1/2 gives both T=(1+-sqrt(pi/6))/2, same hostUV(pi/6,1/2), XYZ(-1/2,sqrt(3)/2,1/2), planeUV(1/2,-sqrt(3)/2). PlaneX0 gives sole double T=1/2. | Angular host receipt and complete many-to-one preimage, without merging T. |
| SRC-TRANSPORT-NONLINEAR-01 | Same actual pcurve: u in(0,1] has both T=(1+-sqrt u)/2; u0 has sole T1/2; other u have empty preimage. Pull back open, singleton and disconnected selections independently. | Actual nonlinear correspondence, rank loss and guards, not an invented parameter-image initializer. |
| SRC-LIFT-PRIORITY-CLAMP-01.CLAMP | Native unit-square plane, affine pcurve rawUV=(epsilon*(2T-1),1/2), epsilon=stored standard.relative/4, T[0,1]. Native nonperiodic basis clamping makes effectiveU=max(0,rawU). CS planeX0 has whole T[0,1/2], constantXYZ(0,1/2,0), image0/fiber1; retain raw and effective UV. | Preserve actual source clamp semantics. Pcurve constructor acceptance is UNOBSERVED; do not enlarge tolerance if rejected. |

The separate exact-image-priority branch must use the actual public
PolySplineFeatureEvaluator rounded-corner producer, which supplies
SurfaceLiftCurve3D.exactBSplineImage for local and merged patches. A hand-built
package-only image initializer cannot close that caller. Its exact public feature input and coefficient-based oracle are fixed in
[the rounded-feature cell](#real-rounded-feature-lift-priority-input); the actual
producer equality and public runtime remain unverified.

###### Actual self-contact caller inputs

The folded Native surface has degree1/1, U knots[0,0,1/2,1,1], V knots[0,0,1,1],
X controls[0,1,0] on each V row: F(u,v)=(2u,v,0) for u<=1/2 and
(2-2u,v,0) otherwise. Its whole ordered residual is (u,v,1-u,v), u!=1/2.
The planar four-chart Coons input is PolylineAtlasLiftProof.shape(multi:true).0;
its complete product contains only authored structural diagonal pairs.

| Cell | Public input and expectation | Current causal gap |
|---|---|---|
| S-TRIMMED-FOLD-01 | Build the exact validated Native-fold face using CoonsHoleBoundaryProbe.face topology, outer unit square, inner U[1/8,3/8],V[1/4,3/4], retained directed constant-U/V pcurves. DefaultOffsetResultValidator must consume residual pairs with M(u,v)&&M(1-u,v), both orders. Closed M excludes the open hole; strict M excludes the closed hole and outer boundary; boundary M is outer+inner boundary. Nonempty residual must reject embedding. | Exact model admission/runtime UNOBSERVED; current straddling-trim interval path is unresolved. Retained self-residual material consumer needed. |
| S-EMBEDDING-CALLER-01 | DefaultOriginalSurfaceEmbeddingValidator on planar Coons and Native fold, full square, local/pair depth14, local cell count65536, source depth32, unchanged bounded admission. Planar success requires complete residual exclusion; fold must return topologyFailure from actual contact. | Actual interval/package-session callers do not consume the complete scoped graph residual. Runtime UNOBSERVED. |
| S-DRAFTED-SHEET-CALLER-01 | Actual PlanarExtrudeFeatureEvaluator: weighted degree1 unit-X line weights[1,2], planeXY, directionZ,distance2,angle stored1e-12,sheet. Run both without and with DefaultOffsetResultValidator. r(u)=2u/(1+u); tau>0 solves (1-sin(theta)^2)*tau^2=sin(theta)^2. Forward tangentX gives W=(r(u),+2v*tau,2v). Strict X and Z make the whole product diagonal-only. Both branches must publish the validated sheet using retained proof. | Actual single-wall packageSession/offset caller receipt migration. Runtime UNOBSERVED; the reversed fixture has the opposite Y sign and is not this input. |

###### Directed draft, angular and join inputs

All following ordinary calls use full authored T, whole target-plane UV, standard
options/tolerance and the same caller admission. They are UNOBSERVED, not passing
examples. The selected root and all owning differential sides are part of input.

| Cell | Concrete input and independent full oracle | Required source/public change |
|---|---|---|
| SRC-DRAFT-NEGATIVE-01 | DraftZeroRuledAcceptance.input(angle:-1e-12), its reversed weighted line and unchanged raw normal/pull/height. With tau>0 defined above, CS planeX1/2 has sole T2/3, XYZ(1/2,+tau,1), planeUV(1,-tau). Wall SSI has u2/3, all v, XYZ(1/2,(1+2v)tau,1+2v), planeUV(1+2v,-(1+2v)tau). | Preserve the original angle-sign-selected root; do not reuse the positive root or round to zero. |
| SRC-DRAFT-ROOT-STATIONARY-01 | Native quadratic C(T)=((2T-1)^2,0,0), from degree2 Native controls[1,-1,1] with knots[0,0,0,1,1,1], retained by an OriginalCurveRootSpan3D with authored endpoints0 and1, original drafted curve with raw axis/pullZ, normalZ,height1. Nonzero stored theta=+-1e-12 requires speed guard T!=1/2; at T1/2 normalized tangent is undefined. Exact theta0 uses the source's direct translation before normalization and is defined there. Target planeX0 therefore has sole T1/2 for zero angle; nonzero input must report its undefined required coverage explicitly rather than return empty success. | Retain exact-zero branch, nonzero normalization guard, both signs and original singular cause. A=0 and discriminant=0 use the separate concrete inputs immediately below. |
| SRC-ANGULAR-INTRINSIC-01 | Actual angular unit circle with intrinsic transport, full T[0,B], target planeX0. Complete roots T=0,B/2,B, XYZ respectively +Y,-Y,+Y; keep both seam endpoints. | Preserve intrinsic scale k=2*pi/B and all original labels. |
| SRC-ANGULAR-REVERSE-TURNS-01 | Same circle, physicalRadianArc(start0,end1,additionalTurns:-1), normalized T[0,1]. g=1-2*pi<0. PlaneX0 gives T0 and T=(-pi)/g only; XYZ+Y and -Y. End phase1-2*pi is not an extra root. | Exact negative turn count/phase and finite arc selection, not a rounded physical period. |
| SRC-JOIN-NONRATIONAL-01 | OriginalGuideTraversalChain3D of retained A spans[0,1/2],[1/2,1], exact stations[0,1/3,1], ordinals[0,1], shared original endpoint owner. CS planeZ0 has all T[0,1], position C_A(phi(T)), phi=3T/2 on first segment, 1/4+3T/4 on second. Image1/fiber0, both join sides at1/3; derivatives have different speed and no C1 claim. PlaneX=-1/2 has sole T=2*pi/9-1/3. | General child source/DI, full declared position join and distinct germs. |
| SRC-JOIN-NONAFFINE-01 | Actual OriginalCurveConstructionChartImage parameterSource on intrinsic unit circle, circularRational law, source labels[0,1], fractions[0,1]. Put c=cos(k/2),s=sin(k/2), X(f)=c+2(1-c)f(1-f),Y(f)=s(2f-1). Source label ell=1/2+atan(Y/X)/k; source position C_A(k*ell). CS planeZ0 contains all f, image1/fiber0; X>0 proves one continuous chart and strictly positive derivative, with complete relational pullback, not an affine station. | Consume actual nonaffine chart law. Hyperbolic law and algebraic join remain separate mandatory variants. |

###### Actual offset-contact rolling inputs

Use the public RollingBallSectionEvaluator on actual offset surfaces and the
curve component produced by DefaultSurfaceSurfaceIntersector.intersections;
then blendSurface(fromCurveParameter:toCurveParameter:options:). Do not replace
its retained offsetSurfaceImage contact pcurves with hand-built exact rails.

| Cell | Public construction and complete output oracle | Exact stopping boundary |
|---|---|---|
| SRC-RB-OFFSET-LIFT-01 | First source planeX0/normalX offset+5; second planeY0/normalY offset+5. The actual intersection is center(5,5,q), q[0,1]. Contacts are(0,5,q),(5,0,q), radius5. SSI blend against planeX1 has V=sqrt(2)-1, all U=q, XYZ(1,2,U), planeUV(U,-2), image1/fiber0. Positive half-angle weight1/sqrt2 and both radius guards are required. | Child snapshot dispatcher currently refuses unmatched retained offset lifts (STATIC). Public constructor/runtime UNOBSERVED. |
| SRC-RB-GENERAL-01 | Source sphere0/radius4 offset+1 and source planeZ2/normalZ offset+1 give center circle radius4 atZ3. First contact=(4/5)*center; second=(center.x,center.y,2), radius1. Blend SSI against planeZ2 has V1, all U, XYZ(second contact), targetUV(center.y,-center.x). All interior short-arc points have Z>2. Retain original actual circle parameter/basis and all sphere/pcurve UV. | Actual sphere/plane producer exists in RollingBallSectionTests; general non-Native rail and algebraic normalization source receipt is missing. Runtime UNOBSERVED. |
| SRC-RB-PERIODIC-01 | Requested Native periodic center degree2, knots[-1,-1,0,0,1,1,2,2,3,3,4,4,5], controls[(25,0),(9,12),(0,75/4),(-9,12),(-25,0),(-9,-12),(0,-75/4),(9,-12),(25,0),(9,12)], allZ0, weights[3,5,4,5,3,5,4,5,3,5], period4. First cylinder radius20/axisZ offset-5 and second planeZ5/normalZ offset-5 require center radius15/Z0, q[-4,8]. Blend SSI planeZ3 has V=sqrt2-1, all U=(q+4)/12, XYZ((19/15)*center.x,(19/15)*center.y,3), targetUV((19/15)*center.y,-(19/15)*center.x). Keep all three traversals, seams and all cylindrical phase lifts. | ProjectedAnalyticSurfaceParameterCurve does not accept the Native-circle/cylinder pairing. A complete actual center-to-cylinder pcurve producer is required before the public blend can be constructed. This is a STATIC producer stop, not an observed blend failure. |

The periodic input's four rational Bezier arc identities Nx^2+Ny^2=225*D^2
were independently checked coefficientwise with rational arithmetic during
recovery; all weights are positive. This establishes only the requested ideal
arc equations, not Native periodic constructor acceptance or public behavior.
The exact cylinder correspondence is C.y=15*cos(k*s),C.x=-15*sin(k*s) with
all integer lifts, never a single atan-derived UV.

###### Continuous projection cell with an independent complete oracle

PROJECTION-CONTINUOUS-01 uses an actual Native tensor surface S(u,v)=(u,v^2,v),
U[0,1], V[-1,1]: degrees1/2, U knots[0,0,1,1], V knots[-1,-1,-1,1,1,1],
unit weights, each U column has (Y,Z) controls[(1,-1),(-1,0),(1,1)] and
X controls0 or1. Surface control rows are V-major. Its tangent cross product is
(0,-1,2v), so viewZ gives the full regular silhouette v0, all u[0,1];
normal never vanishes. The original silhouette position is(u,0,0).
The Native degree1 edge E(t)=(t,0,2), knots[0,0,1,1], unit weights,
T[0,1] is geometrically disjoint from that silhouette but coincides in screen.

Use DefaultSurfaceSilhouetteProducer.silhouette on the full stated UV domain,
viewZ, then each actual issued OriginalSurfaceSilhouetteCurve and its public
OriginalSurfaceSilhouetteTrimmedCurve retained-domain initializer. Frame is
OrthographicProjectionFrame(origin0,normalZ,horizontalHintX). Invoke
OriginalNativeSilhouetteProjectedContactProducer.partition(edge,spanIndex0,
over:[0,1],silhouette,frame,usage) under the same live allowance.
The independent complete projected relation is t=u, v0, t[0,1]; screen=(t,0),
edge-minus-silhouette depth is exactly+2 throughout. Image dimension1/fiber0,
with both closed endpoints and every issued chart incidence. A finite list of
isolated contacts, empty result, or XYZ intersection claim violates this oracle.
Reverse edge controls gives t=1-u; edgeZ0 gives exactly zero depth without
changing the continuous screen relation. These are separate directed/depth checks.

Current STATIC stop: partition catches positiveDimensionalOriginalIdeal,
retains OriginalProjectedNativeLocus, then throws OriginalProjectedNativeSectionFailure.
The necessary change is complete original lifted section publication, depth and
trim refinement, consumed by DefaultBRepDrawingProjectedContactPreparer and
DocumentDrawingProjectedContactPreparer. Actual producer/runtime is UNOBSERVED.
The concrete Geometry input above is fixed; the real validated drawing-model and
placed-projection caller input remains to be fixed before closing caller mapping.
This projected relation cannot replace the separate original XYZ intersection.

###### Closed and singular implicit positive inputs

SRC-IMPLICIT-CLOSED-POSITIVE-01 reuses the actual constructor
ImplicitClosedPlaneEmptyAcceptance.closedPlanePcurve(), including the weighted
Native plane, Native sphere builder, seam offset, exact isoparametric graph,
all four admitted cells and isClosed:true. Target is the SAME retained Native
plane atZ0, not its numerical projection and not an ideal unit circle.
Invoke all ordinary CS entries with wholeT[0,1] and whole target support.
The complete independent oracle is the four-cell union of the original Native
homogeneous equalities between the sphere source and weighted plane, original
cell branch/guard bounds, and the authored free-coordinate equation. On cell i,
local free fraction is 4T-i; T1 belongs to the last closed endpoint and all
incident owners at T=i/4 remain. TargetUV is that exact second-source coordinate,
XYZ is the same retained Native rational map. Every T is selected, image1/fiber0
away from any original source collapse; closed endpoints/incident UV remain.
This oracle uses the actual Native nets and original graph cell declarations,
not point(at:), residual thresholds, or analytic sphere equality. The existing
planeZ2 exclusion receipt proves none of this positive publication.
STATIC missing path: whole implicit relation/T-to-allUV issuance and continuous
ordinary publication. Constructor proof is reused; positive runtime UNOBSERVED.

SRC-IMPLICIT-SINGULAR-01 starts with actual ordinary SSI of Native bilinear
S(u,v)=(u,v,0) and Q(p,q)=(p,q,p*q), all four coordinates[-1,1]. Both have
degrees1/1, clamped endpoint knots[-1,-1,1,1], unit weights and their exact
corner controls. The complete independent relation is u=p,v=q,p*q=0:
two whole axes with four incident half-branches at the origin. XYZ image has
dimension1 and regular image fibers0; the origin is one geometric point with
all original branch/germ incidences. No tolerance merging is permitted.
Retain every public issued intersection curve and request ordinary CS against
the first source plane: every original curve parameter belongs to the result.
Its parameter law must be the actual source-owned branch parameterization
issued by SSI, not an arbitrary new origin-to-endpoint curve invented in DI.
The first SSI output therefore fixes the subsequent implicit-curve inputs.
The exact producer branch/T laws are not yet issued by an accepted current
receipt; STATIC missing contract is singular branch/source correspondence.
Ordinary SSI and subsequent CS runtime are UNOBSERVED. This cell does not
pretend the existing regular invertible-cell constructor admits the crossing.

###### Composed scoped identity cells

| Cell | Concrete source/request and independent complete oracle | Receipt path and stopping contract |
|---|---|---|
| S-IMAGE-COLLAPSED-OPEN-01 | Actual OriginalImageSurface3D of Native G(a,b)=(a*b,b,0), source square[0,1]^2, identity spatial transform, swapAxes:true,uGain:-1,uOffset:1,vGain:1,vOffset:0. Parent H(u,v)=(v*(1-u),1-u,0). Request parent edge U={1},V[0,1]. Consume the child collapse identity restricted to a[0,1/2),b0. Complete residual is(u,v,u',v')=(1,v,1,v'), v!=v', and(v>=1/2 or v'>=1/2), in both orders. | Existing actual image source/DI charts, affine lift/restriction receipts and general issued graph self consumer now close this input. Whole147raw/319refined terminal iff retain9raw/20residual cells and exact original parent UV. Four fixed targets each7groups PASS, exact N/N-1, depth4/count2/sourceDepth1, foreign owner, empty/nonempty/later cancel and detached/COW lifetime. One scoped review has no finding; Commit8c97bb78 is independently integrated with latest main, all2103source/8538products/13127external/protected12 match and fresh Native/Embedded complete/empty/finalcancel pass; accompanying delivery record closes this finite cell. [Current cell evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-COLLAPSED-OPEN-01/VERIFICATION.md) owns the actual accepted scope; general image periods/nonlinear identity and full-family coverage remain open. |
| S-IMAGE-PERIOD-01 | Actual parameter image of the existing two-axis periodic Native fixture, identity spatial transform, axis swap and U reversal above, full requested square[-3,6]^2. Each period3 child shift transports through the exact inverse axis map: child-a shift3 becomes parent-V shift3; child-b shift3 becomes parent-U shift-3. Exclude exactly authored diagonal plus those proved integer shifts in the request pair scope. Keep all other same-XYZ tuples. | Existing Native period proof, affine child cover and checked lift feed the public OriginalAffinePeriodicSelfContactQuerying consumer. The checked Native symbolic predicate compiler retains all81 fundamental pairs and unbounded independent integer indices; exact parent membership subtracts only the49 scoped period/diagonal relations and preserves nonperiodic contact. No topology, global absence or embedding assertion is inferred. [Cell evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-PERIOD-01/VERIFICATION.md) fixes the complete symbolic-set oracle and supported scope. Ordinary graph-bound dispatch and general image families remain separate open obligations. |
| S-NONLINEAR-COLLAPSE-01 | Native G(a,b)=(a*b,b,0), quadratic pcurve a=(2T-1)^2,b0, retained lift L(T)=0, T[0,1]. Actual ruled surface with both boundaries the same retained L, U/V square. Position is identically0 over the entire square; all original UV remain. A proved whole-square constant-map identity can remove the entire self product, but must retain the image point and the two-dimensional source fiber in geometric queries. | Source-owned complete nonlinear lift preimage plus ruled law and whole constant-subset theorem; no guessed inverse. Constructor/runtime UNOBSERVED; the current affine identity relation cannot encode this source theorem by itself. |

The image inputs exercise existing public constructors; no new unchecked identity
initializer is implied. A near-collapse control replaces child b0 by b=1/8:
then child position(a/8,1/8,0) is injective in a, and collapsed exclusion must be
refuted for nonidentical a. Foreign owner, disjoint middle scope and positional
boundary proof passed as differential equality are separate explicit failures.
These cells do not close all nonlinear joins or distinct-owner shared boundaries.

###### Real rounded-feature lift priority input

SRC-LIFT-PRIORITY-CLAMP-01.PRIORITY uses the actual CADDocument feature recipe
makePolySplinePatchNetworkDocument(centerZ:0,options:roundedCorners:true),
with mergePatches:false and true separately. Its public source mesh positions are
[(0,0,0),(1,0,0),(2,0,0),(0,1,0),(1,1,0),(2,1,0)], indices
[0,1,4,0,4,3,1,2,5,1,5,4]. DocumentEvaluator evaluates that real feature;
retain every resulting rounded surfaceLift edge with a producer-owned exact image.
Both actual local-patch and merged-patch paths must yield four such edges, not
an empty selected list. No package-only SurfaceLift initializer is the public input.

Ordinary CS target is planeZ0, whole authoredT[0,1], all four curve-surface entries.
Independent output position is the original retained exact-image homogeneous net
(Hx(T)/Hw(T),Hy(T)/Hw(T),0) with its original positive spans and denominator
conditions; every T is selected and every original pcurve/knot/join incident stays.
The source owner must independently establish the full image-to-host-pcurve
coefficient identity before attaching host UV. This is checked from the actual
original tensor net and pcurve substitution, not from SurfaceLift.point(at:) or
samples. If the producer's image coefficients differ, a residual bound does not
supply exact host UV: record that concrete producer mismatch and repair its
correspondence authority before completing the cell. The retained image remains
the curve's actual priority law; silently substituting host evaluation is invalid.
Complete XYZ publication is image1/fiber0 for each proven nonconstant edge, with
constant/rank-loss branches stratified from the original coefficients if present.
Current source/provider and ordinary runtime are UNOBSERVED. This input fixes the
previously missing public feature path and oracle obligations; it is not accepted
producer equality or a completed feature/whole-lift family.

###### Physical angular surface family inputs

Each uses the actual OriginalAngularTransportSurface3D public constructor, unit
coordinate axes, exact rational gain1/offset0 and no spatial fitting. Use ordinary
rich CS (including options-only entry) so symbolic requested support is retained;
a finite convenience result must explicitly refuse the non-finite UV collection.

| Cell | Original source, full request and independent complete oracle | Required connection |
|---|---|---|
| SRC-ANGULAR-SPHERE-POLES-01 | Sphere(center0,radius1), physicalRadians on U and V; CS line(origin0,directionZ), T[-2,2], whole source. All tuples(T,U,V)=(1,u,pi/2),(-1,u,-pi/2), u real. XYZ=+-Z, image0 on each stratum/fiber1. Latitude source guard is exactly[-pi/2,pi/2], despite the convenience transport's displayed unbounded vDomain. No other T is selected. | Existing exact physical-latitude source receipt, all longitude family, scoped pole identity, general public symbolic publication. Reject near-pole collapse. |
| SRC-ANGULAR-CONE-APEX-01 | Cone(apex0,axisZ,halfAngle stored1/2), U physicalRadians, V intrinsic scalar; CS lineZ T[-1,1], whole source. Sole XYZ0 with T0,V0 and all real U. Both signed scalar nappes are part of support; no normal is requested at the apex. | Physical cone position/guard plus all apex UV and scoped collapse; a normal singularity must not erase defined original position. |
| SRC-ANGULAR-TORUS-TWO-CYCLES-01 | Torus(center0,axisZ,R3,r1), both axes physicalRadians; CS lineX T[-5,5], whole source. All U=pi/2+n*pi,V=m*pi, T=-(-1)^n*(3+(-1)^m), n,m integers. Exactly four XYZ points +-2X,+-4X; integer-index fibers have dimension0 and are not finite windows. | Independent physical periods2*pi, all two-axis UV cycles, generic relation and image/fiber publication; binary B is not that physical period. |

The source guards and original topology determine support; displayed domain enums
and a fundamental bounding box are not replacement authority. All three public
runtime observations remain UNOBSERVED. These cells supplement the fixed finite
angular-cylinder SSI and intrinsic/reversed curve inputs, without counting them
as completion of arbitrary angular composition.

###### M8 finite cumulative interaction cells

These are cumulative obligations over the SAME fixed source/public cell inputs,
not another implementation family or a request to re-run unchanged lower proofs.
The concrete input is a retained accepted result/receipt from the named producer
cell, plus the exact mutation below. A missing producer receipt keeps that
interaction blocked by that receipt alone. Every new cell also owns its local
success/failure/boundary/resource/cancel/lifetime checks before delivery.

| Interaction cell | Concrete input and independent expected behavior | Required completion evidence |
|---|---|---|
| M8-SOURCE-DI-01 | SSI-COONS-PLANE-01 four-chart source with its exact request; drop each retained cover template separately while keeping original source support. Must return incomplete coverage, never omit a segment or accept partial output. The unchanged full cover retains all two/four incidents. | Changed source/DI/public call under one ledger; source-to-result receipt correspondence. |
| M8-GUARD-GRAPH-01 | SRC-OFFSET-GENERAL-01 d=-1,0,1 and SRC-DRAFT-ROOT-STATIONARY-01 zero/nonzero; preserve original normal/root/speed guards through graph and final publication. Zero multiplier does not erase a defining guard; an actually defined zero-draft direct branch does not acquire an invented guard. | Complete guarded relation and exact original failure causes. |
| M8-IDENTITY-SELF-01 | S-IMAGE-COLLAPSED-OPEN-01 and S-NATIVE-IDENTITY-COMPOSITION-01: consume proved restricted identities, then foreign-frame and disjoint-intermediate variants. Residual must match each whole ordered oracle; invalid composition fails without excluding tuples. | Actual scope/owner/role relation dispatch, retained raw/refined mapping, no re-solve. |
| M8-MATERIAL-SELF-01 | S-TRIMMED-FOLD-01 policies closed/strictInterior/boundary. Apply membership to both ordered tuples, not one point or the raw cell box. Compare the exact asymmetric-hole residual formula. | Real validated face, consumer and embedding rejection; all refined ordinals and boundary owners. |
| M8-PERIOD-XYZ-01 | CS-OFFSET-PERIODIC-ZERO-GEOM-01 and SRC-ANGULAR-TORUS-TWO-CYCLES-01. Query independent positive/negative huge integer cycle vectors and all seam incidents on retained symbolic results. Preserve every original UV, image and fiber dimension without fixed-width cycle truncation. | Same template/owner, fresh query admissions, exact cycle/lift arithmetic and overflow failure. |
| M8-CALLER-01 | S-EMBEDDING-CALLER-01, S-COONS-OFFSET-CALLER-01 and both S-DRAFTED-SHEET-CALLER-01 validator branches. Inspect consumed retained receipt and exact caller return; query-only success is insufficient. Fold rejects, completely excluded planar products certify. | Actual production callers, not fixture replacement callbacks. |
| M8-PROJECTION-01 | PROJECTION-CONTINUOUS-01, reversed edge and edgeZ0 controls through actual drawing consumers. Entire t=u or t=1-u sections remain, depth+2 or0, with no substituted XYZ intersection. | Geometry section publication plus Kernel/document drawing receipt consumption. |
| M8-RESOURCE-01 | Each fixed successful producer input, unchanged baseline allowance. Its accepted charge trace defines each exact required count N. Set only that cap to N, then N-1, independently for work/bytes/source/value/coefficient/transport/chart/family/identity/result counts. N succeeds; N-1 returns original resource failure. Count/byte/cycle overflow fails explicitly. | Baseline actual success and bounded charge trace; never raise an existing cap to create success. |
| M8-CANCEL-01 | Same fixed calls with checker cancelling at entry, inside the original producer/refinement, after the final external callback, during empty-result publication and on subsequent retained query. Every cancelled operation reports cancellation and publishes no complete value. | Actual callback order and atomic publication in each changed layer. |
| M8-LIFETIME-01 | Hold each fixed result, release inputs/prepared intermediates, mutate an independent COW input copy, then query old result with fresh independent admissions. Old source identity/geometry/coverage must remain unchanged. | Retained owner/array view proof and target-executable behavior; no layer-by-layer copying to hide lifetime defects. |
| M8-PORTABLE-01 | Same stable changed-source snapshot and the same oracle/controls on fixed Swift6.4.0 Native, ASAN, ordinary WASM and Embedded WASM. Logical state storage/isolation, protocol witness/Sendable and owner lifetime stay identical. | Source/toolchain/SDK/compiler-input/module/product/command/runtime receipts and actual lane execution. Missing product or unavailable target is unverified, not success. |
| M8-LEGACY-01 | Existing stored nonunit-plane source/UV fixture and its rejected old plane/B-spline intersection route, together with unchanged live legacy CS/SSI controls from affected source cells. Preserve source meaning and explicit rejection; do not count rejection as completed positive intersection. | Only changed assumptions are rechecked; preserve old successful dispatch until replacement safety is proved. |

Recovery observation: the tracked evidence contains no tracked .swiftmodule,
archive, object or WASM products. The ordinary CS-POLY retained product manifest
has14 entries and none existed after recovery; main .build was absent. Restore
source/log/receipt files does not restore these runtime products. Before any
execution, admit a matching surviving product by content/receipt or regenerate
only the authorized independent verification scope. The existing broad
CADCore/CADGeometry/Kernel and L2-L6 rebuild restrictions remain in force;
the previously allowed one-time Geometry Embedded WMO regeneration is consumed.
This concrete artifact loss belongs to M8 provenance, not a new lower redesign.

###### Certified authority decision and concrete counterexample

[SourceIssuance owns the chosen certified-pair authority](../../OriginalSourceIssuance/DESIGN.md#certified-pair-authority-for-remaining-acceptance).
The user delegated the decision; source-pair/branch/T authority is adopted rather
than treating regenerated binary coefficients as exact parent equality.
This resolves the acceptance judgment, not the missing producer implementation.

The actual Swift6.4.0 Darwin scalar probe atan(1/2),sin(angle),cos(angle) returned
binary64 bit patterns4602023952714414928,4601727903846100442,
4606231503473470937. Write alpha for the exact stored angle and sb,cb for the
exact imports of the latter coefficients. For a nonzero slant L and orthonormal
cone radial direction, the saved coefficient position has canonical cone image
residual L^2*(cos(alpha)^2*sb^2-sin(alpha)^2*cb^2).
An independent80-term alternating Taylor proof using exact rational arithmetic
bounds the parenthesized coefficient strictly above zero, approximately
1.347064742931945643715411839344316874236e-17. No CAD module was rebuilt.
Thus this regenerated coefficient position cannot receive exact original-cone UV
at nonzero slant. This is the concrete failed contract behind the positive
sphere-cone source receipt, not a reason to relax the residual tolerance.
The old planeZ2 whole-support exclusion does not test this parent equality.

###### Equivalent-boundary cells with independent traversal oracles

These cells use the actual `CoonsHoleBoundaryProbe.face` topology construction,
including surface-lift edge geometry and reversed coedges. The host is the
retained four-chart planar Coons source, not a replacement Native plane. Outer
loop is the unit square; inner loop is the square [1/4,3/4]^2. Replace the outer
left directed side (0,1) to (0,0) by the indicated actual public pcurve. Its edge
uses the reversed pcurve exactly once, as in the original builder. Other sides
and the hole are unchanged. Query the actual original Native line
C(t)=(t,1/2,0), t in [0,1], through the same graph resolver and public face issuer.
The independent material oracle is closed: [0,1/4] union [3/4,1]; strictInterior:
(0,1/4) union (3/4,1); boundary: {0,1/4,3/4,1}. Every tuple retains curve t,
host UV=(t,1/2), XYZ=(t,1/2,0), original raw pair and boundary incident. Closed
and interior regular components have image dimension1/fiber0; boundary points
have image0/fiber0. Reversal of coedge orientation must not reverse the retained
pcurve again. Constructor admission and runtime for these variants are UNOBSERVED.

| Cell | Actual replacement pcurve input | Independent whole-side law and boundary parameter at V=1/2 | Current stop / remaining implementation |
|---|---|---|---|
| B-PCURVE-AFFINE-01 | `.affine(origin:(0,1), direction:(0,-1), startParameter:0, endParameter:1)` | U=0, V=1-f; f=1/2 | Retained graph relation must reach actual face-bound consumer; preserve affine parameter role |
| B-PCURVE-CONSTANT-01 | `.constantU(u:0,vStart:1,vEnd:0)`; unchanged horizontal sides are constantV | U=0,V=1-f; f=1/2 | Existing Coons-hole accepted cell is the scoped baseline; use its proof only for its unchanged input |
| B-PCURVE-POLYLINE-01 | `.polyline([(0,1),(0,1/2),(0,0)])` | Both segments exactly cover the left side in order; at V=1/2 retain both original segment incidents | Do not flatten the knot incident into a single synthetic affine owner |
| B-PCURVE-RATIONAL-01 | `.bSpline` degree1, knots[0,0,1,1], controls[(0,1),(0,0)], weights[1,2] | U=0,V=(1-f)/(1+f), denominator positive; f=1/3 | Compile retained rational law/guard and all boundary correspondence without polygonization |
| B-PCURVE-CONTINUATION-01 | Degree1 unit-weight original controls[(0,1/4),(0,3/4)], knots[0,0,1,1]; `OriginalBSplineCurve2DContinuation(original:,startParameter:3/2,endParameter:-1/2,tolerance:.standard)` | Native label q=3/2-2f; V=1/4+q/2=1-f; f=1/2. Both endpoint-span continuations are required | Consume continuation outside original raw support rather than clamp to [0,1] or substitute a new spline |
| B-PCURVE-TRANSLATED-01 | `.periodicTranslation(base:.constantU(u:-3,vStart:1,vEnd:0),uShift:3,vShift:0)` | U=0,V=1-f; f=1/2. This is the declared translation law, not a theorem that the Coons host is periodic | Preserve both retained base coordinates and actual target coordinates; do not infer host identity from the enum name |

For each row run all three selection policies; wrong face/source and wrong SSI
side must be rejected. A second horizontal query V=1/4 retains the entire hole
bottom boundary for closed/boundary policies and excludes it for strictInterior.
A query V=2 has a complete empty intersection over the original host request.
These inputs bind 6-B2/B3/B7/B8/B9/B10/B11; they do not discharge the remaining
harmonic, sphericalGreatCircle, certified or image pcurve families. The existing
`OriginalNativeBoundaryDomain.Source` has only Native curveSurface/firstSurface/
secondSurface cases and fixed parameter layouts. Its static signature cannot
admit this Coons graph relation. The newer issued-graph adapters must be traced
separately; this signature observation alone is not a runtime failure receipt.

###### Exact draft guard-boundary inputs

Both cells use an actual degree1 unit-weight Native line and its original root
span with authored endpoints0,1, unchanged `.standard` tolerance, height1,
remaining source depth sufficient for the actual two-level constructor, and the
existing caller admission. They exercise original source guard behavior before
ordinary CS publication; required whole-support coverage failure must remain an
explicit failure, never an empty complete intersection.

| Cell | Actual source / public request | Independent guard oracle | Current source path and required completion |
|---|---|---|---|
| SRC-DRAFT-A-ZERO-01 | Generator C(t)=(t,0,0), raw normalZ, axisZ, pullX, angle exactly0; ordinary CS against planeZ1 over whole T[0,1] | Normal-dot-pull=0, sineSquared=0, hence quadratic A=0 exactly. The direct zero-translation branch does not apply because pull!=axis. No admitted selected finite quadratic ruling is defined by this source contract | `rulingJet` reaches `ruling`: qa.upper<=0 gives singularGeometry; verify real public failure propagation and zero successful publication. Constructor admission/runtime UNOBSERVED |
| SRC-DRAFT-D-ZERO-01 | Generator C(t)=(0,0,t), raw normal=axis=pull=Z, angle stored+1e-12, and separate negative control-1e-12; ordinary CS against planeX0 over whole T[0,1] | Unit tangentZ, q=tangent cross axis=0, across=tangent cross normal=0; A=1-sin(theta)^2>0, B=C=0, discriminant D=0 exactly. The source's strict selected-root guard D>0 is not satisfied. The sign cannot choose two distinct roots | Current source returns inconclusive at D=0 and eventually resourceLimitExceeded under unchanged subdivision limits. Preserve the explicit cause and full request; source owner must decide/prove whether a degenerate branch is defined before issuing any exact position receipt. Runtime UNOBSERVED; no arbitrary root substitution |

The A-zero input tests a defined rejection and does not require representing an
irrational normal as a binary vector. The D-zero input identifies an actual strict
guard boundary; a future source-owned degenerate-branch theorem would change its
source contract and would require updating the expected public result here before
implementation. These are guard cells, not positive draft-family completion.

###### Hyperbolic construction-chart cells

Construct the actual `Hyperbola3D(center:0,normal:Z,transverseAxis:X,
transverseRadius:1,conjugateRadius:1)` and wrap it as `.analytic(.hyperbola)`.
Use `OriginalCurveConstructionParameterSource` with law `.hyperbolicRational`,
startParameter=-1, endParameter=1, firstFraction=0,lastFraction=1; pass it to the
public `OriginalCurveConstructionChartImage(parameterSource:...)` with the same
bounded admission, tolerance and source-depth policy as the circular-chart cell.
Let c=cosh(1), s=sinh(1), d=c-1, X(f)=c-2d*f*(1-f), Y(f)=s*(2f-1).
The independent retained parameter is ell(f)=atanh(Y(f)/X(f)); whole original
position is (cosh(ell(f)),sinh(ell(f)),0). X>0 and |Y/X|<1 on [0,1],
ell is strictly increasing from-1 to1. Preserve these physical constants and
inverse-function guards; regenerated binary conic control points are not their
exact replacement. Actual source constructor/runtime is UNOBSERVED.

| Cell | Public input and full oracle | Concrete missing receipt / completion |
|---|---|---|
| SRC-JOIN-HYPERBOLIC-01 | Ordinary CS of this construction-chart curve against explicit Plane3D(origin:0,normal:Y,uDirection:X), full normalizedT. Unique T=1/2, original ell=0, XYZ=(1,0,0), targetUV=(1,0); image0/fiber0 | Source-owned hyperbolic coefficient/atanh correspondence, full preimage and positive guards must reach ordinary publisher; inspect actual returned plane frame rather than assume axes |
| SRC-JOIN-HYPERBOLIC-REVERSE-01 | Same chart with firstFraction=1,lastFraction=0. Position at T equals previous position at1-T. PlaneY0 again soleT=1/2; endpoint labels exchange, original source owner retained | Reversal must transport the whole nonaffine law and scope, not reverse only the numerical representatives |
| SRC-JOIN-HYPERBOLIC-CONTINUOUS-01 | Same curve against planeZ0, fullT. All tuples (T, targetUV(position(T))) for T in[0,1], image1/fiber0; endpoints included | Full continuous T/UV family, source guards and image dimension must be published; finite representative points are insufficient |
| SRC-RULED-HYPERBOLIC-01 | Actual ruled surface between this curve and its exact spatial translation+Z, full[0,1]^2; SSI against planeZ1/2 | Complete relation V=1/2, allU, XYZ=(cosh(ell(U)),sinh(ell(U)),1/2), target plane uses explicit normalZ/uDirectionX, so targetUV=(cosh(ell(U)),sinh(ell(U))); image1/fiber0, all child incidents retained. Needs existing ruled producer consuming the original chart receipt, not a newly generated conic net |

All rows require explicit empty controls using a target planeZ2 for curve CS or
ruled SSI, plus singleton T=1/2 and a disjoint request. The reverse continuous
case remains the same geometric image with a distinct original traversal, not
an inferred identity between independent owners. Plane frame acquisition is an
input-derived deterministic field, not permission to omit targetUV from the oracle.

###### Certified coaxial cone-cylinder positive cells

Use the real `rootFreeCurves` source recipe from
`CertifiedConeCylinderSpatialDifferentialBoundsTests`: analytic cone apex0,
axisZ, halfAngle alpha=the stored binary64 `atan(0.5)`; analytic cylinder origin0,
axisZ,radius1. Construct each actual `CertifiedConeCylinderIntersectionCurve`
with lowerAngle0, upperAngle B=stored2*Double.pi, `.standard` tolerance, then the
actual `.certifiedIntersection(.coneCylinder(...))` curve route. Do not replace
alpha by an ideal angle with tangent1/2. The source-owned exact quadratic has
Q=-tan(alpha)^2<0, halfLinear0, C=1, discriminant tan(alpha)^2>0.
The existing selected-root formula is (-halfLinear+signedRoot)/Q. Consequently
negativeFullBranch has height +cot(alpha), and positiveFullBranch has height
-cot(alpha); the enum name alone does not specify the sign of height.

The actual final evaluation delegates cylinder position to
`cylinder.surface.differentialGeometry(u:angle.value,v:height.value)`. Preserve
this original cylinder's intrinsic angular label U=B*T: its canonical physical
phase is 2*pi*T. Regenerated libm discriminant coefficients are candidates only.
For this coaxial input the exact discriminant is angle independent, so preserving
the actual cylinder label and selected quadratic root determines the exact full
source traversal without a rounded endpoint/root assumption. Both endpoints
T0 and T1 remain distinct authored parameters and share a proved cylinder seam.

Let sigma=+1 for negativeFullBranch and-1 for positiveFullBranch,
z=sigma*cot(alpha). Complete original position is
P(T)=(-sin(2*pi*T),cos(2*pi*T),z). Cylinder UV includes
(U,V)=(B*T+n*B,z) for every source-domain-admitted integer lift n. Cone slant
V=sigma/sin(alpha); cone U is B*T+n*B for sigma+1 and B*T+B/2+n*B for sigma-1.
All lifts are restricted to the actual requested source domains. No UV is
reconstructed from numerical XYZ.

| Cell | Ordinary public input / independent complete oracle | Static missing implementation and acceptance gate |
|---|---|---|
| CS-CERTIFIED-CONE-CYLINDER-NEGATIVE-01 | NegativeFullBranch, target `Plane3D(origin:0,normal:Y,uDirection:X)`, fullT[0,1]. Exactly T=1/4 and3/4, XYZ=(-1,0,z) and(1,0,z), targetUV=(-1,-z) and(1,-z), image0/fiber0 each, all parent lifts above | Source owner must issue exact physical half-angle/root and cylinder-label traversal plus allUV; ordinary dispatch/publisher must retain them. Actual constructor/runtime on recovered snapshot UNOBSERVED |
| CS-CERTIFIED-CONE-CYLINDER-POSITIVE-01 | PositiveFullBranch with same target/request. Same two T values and XY, height z=-cot(alpha); targetUV=(-1,-z),(1,-z) | Separate selected root receipt; never reuse negative branch by a tolerance sign test. Actual runtime UNOBSERVED |
| CS-CERTIFIED-CONE-CYLINDER-CONTINUOUS-01 | Both variants separately against their retained cylinder, fullT[0,1], whole cylinder U and axial request covering z. All (T,U=B*T+n*B,V=z), image1/fiber0 locally; seam T0/T1 and all admitted n retained | Continuous curve-on-surface family plus all original cone UV auxiliary witnesses; preserve original closed seam without merging authoredT |

Each point cell also restricts T to[0,1/8] for a complete empty control and to
{1/4} for singleton coverage. These close no bounded/apex/rulingParallel variant.
They require coefficient and source-depth/cancel/lifetime checks under the same
caller admission. The expected result does not certify the current regenerated
configuration or numeric runtime as an exact equality proof.

###### Boundary image composition cells

Reuse the full outer/hole topology and all three exact material oracles of the
six equivalent-boundary cells. Transform every retained coedge pcurve through
the actual image constructor, including its source surface-lift owner; transform
edge geometry and vertices consistently. A synthetic target surface plus
unchanged pcurves is not the input. No row below has an observed constructor or
runtime result on the recovered snapshot.

| Cell | Actual constructor input / complete parameter oracle | Required source-to-public completion |
|---|---|---|
| B-PCURVE-IMAGE-01 | `OriginalImageSurface3D(source:Coons,uGain:-1,vGain:1,uOffset:1,vOffset:0,transform:identity,swapAxes:true)`; for each original directed boundary pcurve construct `OriginalImageSurfaceParameterCurve(source:SurfaceLiftCurve3D(surface:Coons,parameterCurve:p),targetImage:image)`. Child(a,b)=(v,1-u), so every original(a,b) maps to parent(u,v)=(1-b,a). Query C(t)=(t,1/2,0) retains parentUV=(1/2,t), childUV=(t,1/2). Outer/hole material t sets are unchanged | Compose the existing affine map and every boundary preimage/incident under the new face authority. Foreign child or different image must reject, including identity spatial transform with wrong parameter map |
| B-PCURVE-WORD-01 | Actual `OriginalAffineWordSurface3D` of Coons with a flat operation word of the exact translation+Z; every boundary uses `OriginalAffineWordSurfaceParameterCurve(source:sourceLift,target:wordSurface,startFraction:0,endFraction:1)`. Query C(t)=(t,1/2,1), targetUV=(t,1/2), childUV identical; material t sets unchanged | Consume retained word and source equality without flattening/regenerating its coefficients; original owner/depth and all boundary spans survive |
| B-PCURVE-RIGID-01 | Exact rigid translation+Z applied through `RigidTransform3D.applying(to:Coons)`; each `RigidImageSurfaceParameterCurve(source:sourceLift,targetSurface:actualTransformedSurface,transform:translation,startFraction:0,endFraction:1)`. Query and material oracle as WORD | Actual constructor compares target with transformed original; preserve that authority through face issuer and boundary refinement. A different translated target is a negative control |
| B-PCURVE-IMAGE-REVERSE-01 | Same IMAGE input with each wrapper startFraction1,endFraction0 and reverse loop traversal/edge endpoints consistently. Boundary set unchanged; wrapper parameter f maps original fraction1-f. The rational left-side boundary V=1/2 moves from originalf1/3 to wrapperf2/3 | Retain directed traversal and both coedge/edge roles; do not double reverse or erase original boundary parameter |

Each row retains all raw-to-refined correspondences and checks boundary-only
continuous components, hole corners, exact empty requests, invalid owner,
publication cancel and lifetime after dropping source inputs. These rows bind
word/image/rigid pcurve variants only; offsetSurfaceImage requires its actual
public offset image/pullback factory and owning normal guard and remains a
separate mandatory cell. Parameter image identity is not implied by spatial
identity or by unchanged material sets.

###### Distinct-owner shared-boundary and germ cells

Construct two independently bound degree(1,1) Native patches with unit weights
and both knots[0,0,1,1]: F(u,v)=(u,v,0) and G(s,t)=(1+s,1-t,0).
Use the actual source binding/domain issuers and
`DefaultOriginalParameterIdentityIssuer.declaredBoundary`; declaration pairs
F's u-upper chart side with G's s-lower chart side. Left scope u={1},v=[0,1];
right frame is G's actual independent frame; affine permutation[0,1],
gains[1,-1],offsets[-1,1] maps (u,v) to(s,t)=(u-1,1-v).
Read the resulting relation through its protocol requirement, never private
proof storage. The issuer's current declaration port is Native rational-chart
specific; its availability does not establish general Coons/graph support.
Actual distinct-owner construction/consumer runtime remains UNOBSERVED.

| Cell | Exact complete oracle / controls | Required connection and completion |
|---|---|---|
| I-DISTINCT-SHARED-EDGE-01 | Ordinary SSI of F and G over whole squares is exactly (u,v;s,t)=(1,v;0,1-v), v in[0,1], XYZ=(1,v,0), image1/fiber0. The declared identity is valid only on the stated boundary scope. Ordinary SSI retains the intersection even when structural identity is known | Preserve independently bound owner frames, complete paired boundary map and requested scope into the public relation; identity must not remove an ordinary intersection |
| I-DISTINCT-SHARED-EDGE-PARTIAL-01 | Same pair, left scope u1,v in[0,1/2); proof applies only to corresponding t in(1/2,1]. At v1/2 and above the ordinary SSI remains present without this declaration's proof. Reverse proof must reverse both map and open scope | Verify restriction, symmetry and consumer applicability through relation requirement; do not enlarge the theorem to closed or whole boundary |
| I-DISTINCT-SHARED-CREASE-01 | Replace G by G(s,t)=(1+s,1-t,s). Shared boundary is unchanged, but transverse derivative G_s=(1,0,1) differs from F_u=(1,0,0), and face normals differ. Both boundary traversal tangents are opposite before the declared reversal | Issue position-only boundary proof; reject attempts to use it as transverse differential, normal or global-source equality. Preserve each incident owning germ in SSI/consumer results |
| I-DISTINCT-FALSE-EDGE-01 | Replace G by the actual degree(1,2) unit-weight Native patch with s knots[0,0,1,1], t knots[0,0,0,1,1,1], and, for each s endpoint0/1, t controls[(1+s,1,s),(1+s,1/2,s+1/2),(1+s,0,s)]. Its whole law is (1+s,1-t,s+t*(1-t)). Only t0 andt1 agree with F boundary; at t1/2 Z=1/4. Whole-edge declaration is refuted for this relation. Ordinary SSI retains exactly the two endpoint tuples (1,0;0,1) and(1,1;0,0) | Whole-boundary polynomial comparison must detect the interior counterexample; endpoint samples cannot authorize the proof. Refuted declaration is not absence of endpoint intersections |
| I-DISTINCT-FOREIGN-FRAME-01 | Bind an equal-valued third patch independently and substitute its frame while retaining G's law. The binding is foreign even though all coordinates match | Explicit invalid binding before publication; same values/hash/name cannot replace owner identity |

These concrete inputs bind 5-C3/C4/C5/C8/C9/C10/C11/C12 for a Native declared
boundary and ordinary SSI consumer. Joined nonrational self consumers and
nonaffine shared-boundary maps remain separate obligations; no claim that these
five rows close the general identity family is permitted.

###### Certified apex authority counterexample and exact apex success input

The existing `CertifiedConeConeSpatialDifferentialBoundsTests.apexReducedCurves`
uses reference cone apex0/axisZ/halfAngle stored atan(0.5), and parameterized cone
apex(2,0,4)/axisY/halfAngle stored atan(0.375). This is not an exact nonzero apex
contact of the original physical reference cone. For alpha with the observed
fixed-toolchain bits4602023952714414928, independent 80-term alternating rational
Taylor bounds at that exact binary value prove
sin(alpha)-cos(alpha)/2 > 0, with bound approximately
3.66853491357008918099522085245042700e-17. Therefore
2*cos(alpha)-4*sin(alpha)<0; the point(2,0,4) is not on the original cone.
The check uses no CAD build and does not certify the numeric fixture runtime.

| Cell | Public input / complete oracle | Concrete stop / required implementation |
|---|---|---|
| CERTIFIED-CONE-CONE-NEAR-APEX-01 | Actual existing apexReducedCurves input above through ordinary SSI and the emitted certified-curve CS path. Require an exact parent-pair branch receipt; the proposed apex relation to(2,0,4) must be refuted. Do not assert the entire pair is disjoint: its other intersection branches remain required | `apexContactTopology` currently admits apexReductionResidualUpperBound<=tolerance.distance, then classifies roots using tolerances. This is a numeric candidate classifier, not an exact apex theorem. Exact publication must verify the retained source equality and recompute the correct branch selection or explicitly fail required coverage; it must not publish a falsely apex-reduced original relation |
| SSI-CONE-CONE-COMMON-APEX-01 | Actual analytic cones both apex0, axesZ andY, both halfAngle stored0.5. Ordinary rich SSI requests U in[-B,B], V in[-2,2] on both. Complete tuples (U1,0,U2,0) with both U independently in[-B,B], XYZ0; parameter dimension2/image0/fiber2. All seam/lift incidents retained | For any nonzero point, normalized direction would require wZ^2=wY^2=cos(0.5)^2. Rational Taylor bound cos(0.5)>7/8 proves their sum>1, impossible. The only intersection is the common apex. Both source parameter fibers must survive. This is an isolated-point source outcome, not a fabricated certified curve with arbitraryT |

The second row supplies a genuine binary-authored exact apex success input and
whole complement exclusion. It does not supply a nonzero apexReduced curve loop.
The old near-apex test cannot discharge isolatedPointAndLoop or nodeIntervals
under the selected original-pair authority. Their positive source constructors
must retain an exact constructed apex-on-cone correspondence; a rounded point
and a tolerance residual are insufficient. This concrete input is the causal
reason for that missing source receipt, not permission to relax equality or to
redesign L0-L5.

###### Sphere-cone exact node-loop positive input

`SSI-CERTIFIED-SPHERE-CONE-NODE-01` uses actual ordinary SSI with analytic sphere
center0/radius1 and analytic cone apex(1,0,0),axisZ,halfAngle stored0.5.
The cone apex belongs to the original sphere exactly: its squared distance is1.
This avoids the rounded nonzero cone-contact premise above. The existing actual
`SphereConeApexContactIntersector` calls `apexContactTopology`, creates each
node interval through `CertifiedSphereConeIntersectionCurve`, then the original
builder emits certified analytic truth. No hand-made curve truth receipt is used.

Let s=sin(0.5), c=cos(0.5), g(phi)=(-s*sin(phi),s*cos(phi),c).
The complete sphere equation for cone point A+lambda*g is
lambda*(lambda-2*s*sin(phi))=0. Preserve both the constant apex root with all
original cone U and the nonconstant root lambda=2*s*sin(phi); removing the
constant numeric root does not remove its full original UV fiber. The nonconstant
root has exact incident critical angles0,pi,2*pi and two node intervals.
The source producer must retain those exact selected critical roots and normalized
traversal, with phi=pi*T on the first and phi=pi+pi*T on the second. Existing
rounded interval bounds are candidate localizations, not exact root endpoints.
This is an explicit required producer migration. A direct constructor with
explicit physical endpoint labels must retain those labels and cannot inherit
this normalized root traversal without the source-owned receipt.

| Cell | Public input / full expected result | Required implementation and stop |
|---|---|---|
| SSI-CERTIFIED-SPHERE-CONE-NODE-01 | Whole ordinary sphere/cone SSI: original cone UV U=phi/kappa, V=2*s*sin(phi), sphere UV from its exact canonical inverse relation, phi in[0,2*pi], plus Vcone0/allU at apex. Nonconstant regular image1/fiber0; apex image0 with source-UV fiber1. kappa=2*pi/B. For finite requested source U keep every admitted integer lift | Exact node/root traversal receipt, canonical parent maps and full apex fiber; current apex intersector's numeric root removal and original builder are not proof of complete UV. Constructor/runtime on recovered snapshot UNOBSERVED |
| CS-CERTIFIED-SPHERE-CONE-NODE-UPPER-01 | Feed the actually emitted upper interval curve into ordinary rich CS against explicit plane(origin0,normalY,uDirectionX), wholeT[0,1]. Exactly T0,1/2,1. At T0/1 XYZ=A=(1,0,0), targetUV=(1,0), sphereUV=(3B/4,0) plus periods, coneV0/all admitted U. At T1/2 XYZ=(cos(1),0,sin(1)), targetUV=(cos(1),-sin(1)), sphereUV=(3B/4,1/kappa), coneUV=(B/4,2*s), plus admitted periodic lifts | Three authored T tuples must survive even though two share XYZ. Endpoint owning node germs and all collapsed cone UV remain. Missing exact source branch/T receipt blocks complete publication; runtime UNOBSERVED |
| CS-CERTIFIED-SPHERE-CONE-NODE-LOWER-01 | Feed the emitted lower interval separately into the same plane/query. T0,1/2,1 only. Endpoints as above; middle XYZ=(cos(1),0,-sin(1)), targetUV=(cos(1),sin(1)), sphereUV=(3B/4,-1/kappa), coneUV=(3B/4,-2*s), plus admitted periodic lifts | Preserve signed slant, separate interval owner and incident germs; do not fold the two loops together or infer structural identity from apex XYZ |

The plane-Y equation on either nonconstant branch is
2*s^2*sin(phi)*cos(phi)=0, giving exactly the stated endpoint/midpoint roots;
s>0 and the specified critical interval prove complement exclusion. For ordinary
CS request T in[1/8,3/8], there is a complete empty result. For SSI, singleton
coneV0 still retains both independent source U selection and sphere seam lifts.
Position-only apex publication does not need an undefined normal. Numeric
regeneration, exact endpoint migration and source/T compatibility require their
own focused checks; historical apex-planeZ2 emptiness does not accept these cells.

###### Isolated tangential self-contact input

`S-NATIVE-ISOLATED-TANGENT-01` constructs an actual unit-weight Native tensor
surface of degree(5,2), U knots[-1,-1,-1,-1,-1,-1,1,1,1,1,1,1], V knots
[-1,-1,-1,1,1,1]. Its exact binary-integer control net, in V-major rows, is:

```text
[(10,-1,-125), (2,-1,21), (-2,-1,-105), (-2,-1,105), (2,-1,-21), (10,-1,125)]
[(10,0,35), (2,0,117), (-2,0,-73), (-2,0,73), (2,0,-117), (10,0,-35)]
[(10,1,-125), (2,1,21), (-2,1,-105), (-2,1,105), (2,1,-21), (10,1,125)]
```

The independent position law on original U/V in[-1,1]^2 is
S(u,v)=(10*u^2,v,80*u*((u^2-1/4)^2+v^2)). The listed net is obtained by exact
power-to-Bernstein coefficient identities; all coefficients are integers, so no
rounded conic/polynomial coefficients enter the public input. A standalone exact
rational check verifies the tensor net against this law; CAD constructor/runtime
is UNOBSERVED.

Use the actual Native source/domain issuer, complete self product and public
`OriginalSurfaceEmbedding` residual query, excluding only authored diagonal.
The complete residual consists of exactly the two ordered tuples
(u,v;s,t)=(1/2,0;-1/2,0) and(-1/2,0;1/2,0), XYZ=(5/2,0,0), image0/fiber0 per
ordered tuple. Equality of Y gives t=v; equality of X gives s=u or s=-u.
After removing diagonal, u!=0 and the Z equality requires
(u^2-1/4)^2+v^2=0, hence u=+-1/2,v=0. This proves both isolated contacts and
whole complement exclusion. Both incident tangent planes are XY, with opposing
parameter normals; each source is regular at the contact. No distance threshold
or small-cell absence test enters the oracle.

The actual `DefaultOriginalSurfaceEmbeddingValidator` caller must reject this
surface as topologyFailure after consuming the complete contact receipt. A
singleton query scope containing only one of the two points has an empty residual
after diagonal exclusion; this does not assert that the embedding validator admits
a zero-width rectangle. A query request containing both retains the two ordered contacts. Pending implementation is
complete isolated/tangent residual classification and actual caller consumption;
resource/cancel/coverage failure must not become empty embedding success. This
cell binds the isolated/tangent part of6-S4/S5/S8/S9 and5-C10. It does not replace
trimmed-fold, continuous coincidence or general singular-family acceptance.

###### Closed implicit pcurve as an actual face boundary

`B-PCURVE-IMPLICIT-CLOSED-01` reuses the exact actual constructor body
`ImplicitClosedPlaneEmptyAcceptance.closedPlanePcurve`: the retained Native
sphere/weighted-plane pair, all four issued cells and isClosed=true. Its helper
is private; the fixture must share that original constructor body through its
own test owner, not introduce a second geometry producer. Construct the actual
public `CertifiedImplicitSurfaceParameterCurve(intersection:original,role:.second,
startFraction:0,endFraction:1,tolerance:.standard)` on that exact retained plane.
Build one outer Loop containing one forward Coedge with that retained pcurve;
its Edge retains the actual `.implicit(original)` curve with trim[0,1], start
and end vertex referencing the same vertex. Use the actual original point
candidate atT0 for the stored vertex and validate the real BRepModel with the
existing exact validation entry. The vertex candidate is not exact pcurve root
or closure authority: closure and parent equality come from the original graph
owner. No constructed model/face receipt is asserted successful before runtime.
If exact model admission rejects this source, retain that concrete stop; do not
bypass the real validator or substitute a polygon boundary.

Query the same original implicit curve against the same retained plane through
ordinary rich CS, then the actual validated face issuer and boundary consumer.
The complete raw relation includes every T in[0,1], its second-source UV and all
four-cell incident witnesses. Because this exact original curve is the retained
boundary itself, closed and boundary policies retain every raw tuple; strictInterior
excludes every raw tuple with whole-domain boundary evidence. Retain both authored
T0/T1 and all incident cells at T=i/4. The image is the original boundary curve,
image1/fiber0 on its regular pieces; never replace it by an ideal unit circle or
by the analytic sphere that originally produced the retained Native sphere.
A reversed coedge control reverses edge traversal exactly once while preserving
the original pcurve owner and its complete boundary set.

The required implementation is original implicit T/allUV source supply, graph
relation admission with actual auxiliary layout, retained closed-loop authority,
face-bound refinement and raw/refined correspondence. Current Native-only
`OriginalNativeBoundaryDomain.Source` cannot accept this raw curve family;
issued-graph adapter support and real model validation must be observed separately.
The prior planeZ2 empty result proves none of this positive boundary path.
This cell binds6-B1/B2/B3/B4/B7/B8/B9/B10/B11, plus the closed-implicit part ofM7;
interior winding for arbitrary implicit loops, singular boundary branches and
certifiedAnalyticImplicit/Pair pcurves remain separate mandatory cells.

###### Additional pcurve inputs with independently fixed position laws

The actual constructor probe is
[PcurveSourceMappingProbe](../../../../Tests/OriginalPublicAcceptanceVerification/PcurveSourceMappingProbe.swift).
Its [Native receipt](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/PCURVE-CONSTRUCTOR-MAPPING-20261012/receipt.json)
binds the five successful constructors and wrong-directed-host rejection to the
restored, source-hash-matched Swift6.4.0 products. The numerical position checks
establish reproducible inputs only. They do not prove source equality, complete
CS, boundary winding, four-target portability or acceptance.

Use full normalized T[0,1], standard options/tolerance, whole target-plane UV,
and actual `Curve3D.surfaceLift` with the following inputs. Target plane X=a has
origin(a,0,0), normalX, explicit uDirectionZ, hence UV=(z,-y).
Target plane Z=a has origin(0,0,a), normalZ, explicit uDirectionX, hence UV=(x,y).

| Cell | Actual source constructor and complete independent positive CS oracle | Current location / remaining change |
|---|---|---|
| PCURVE-PROJECTED-PARABOLA-01 | Original planeZ0 with its default (+Y,-X) basis; `ProjectedAnalyticSurfaceParameterCurve` of parabola(vertex0,normalZ,axisX,focalLength1/2), source parameter[-1,1]. q=2T-1, sourceUV=(q,-q*q/2), XYZ=(q*q/2,q,0). Against planeX1/8 exactly T1/4 and3/4, XYZ=(1/8,-1/2,0) and(1/8,1/2,0), targetUV=(0,1/2) and(0,-1/2). Against planeZ0 allT, image1/fiber0. | Constructor and numerical law observed. Ordinary exact CS runtime unobserved. Consume the original conic and exact plane-basis transport; numerical `parameterProjection` is not a source correspondence theorem. Preserve both roots and all parent UV. |
| PCURVE-HARMONIC-01 | Same plane; `.harmonic(center:0,cosine:(1,0),sine:(0,1),startParameter:0,endParameter:1)`. SourceUV=(cosT,sinT), XYZ=(-sinT,cosT,0). Against planeX=-1/2 exactly T=pi/6, XYZ=(-1/2,sqrt3/2,0), targetUV=(0,-sqrt3/2). Against planeZ0 allT, image1/fiber0. | Constructor and numerical law observed. Original physical-radian coefficient and full preimage receipt are absent from the retained rational lift port. Preserve authored endpoint1; do not replace it by a full-turn or close this open arc. |
| PCURVE-SPHERICAL-GREAT-CIRCLE-01 | Analytic sphere(center0,radius2), `.sphericalGreatCircle(cosine:Y,sine:-X,startParameter:-1/4,endParameter:1/4)`. theta=T/2-1/4, XYZ=(-2sin(theta),2cos(theta),0). Against planeX0 exactly T1/2, XYZ=(0,2,0), targetUV=(0,-2). Against planeZ0 allT, image1/fiber0. Every admitted intrinsic source longitude is theta/(2*pi/B)+kB and latitude0, with independent integer k and seam incident sides; B is the stored intrinsic label. | Constructor and numerical law observed. Source must prove the original great-circle position, continuous lifted longitude and complete seam preimages; sampled angle unwrapping is not proof. Ordinary exact CS runtime unobserved. |
| PCURVE-OFFSET-FORWARD-01 | Original planeZ0; offset distance2; actual `parameterCurveImage` of affine origin(1/8,-1/4), direction(1/2,1/2), endpoints0/1. Original source and destination UV both(1/8+T/2,-1/4+T/2), XYZ=(1/4-T/2,1/8+T/2,2). Against planeX0 exactly T1/2, XYZ=(0,3/8,2), targetUV=(2,-3/8); planeZ2 retains allT. | Constructor and numerical law observed. Ordinary constructor selects a materialized plane destination. Its complete original directed offset/source equality must be issued; the current original-relation validator explicitly declines unproved materialized targets. Do not change the public input to a procedural target to conceal that gap. |
| PCURVE-OFFSET-PULLBACK-01 | Native degree1/1 unit-weight surface F(u,v)=(u,v,u*v), unit-square clamped knots, actual offset distance1/4 and `parameterCurvePullback` of affine UV=(1/8+T/2,1/4+T/2). Destination is the unchanged Native F, not an offset by -1/4. Against planeX3/8 exactly T1/2, XYZ=(3/8,1/2,3/16), targetUV=(3/16,-1/2). | Constructor, numerical law and rejection of the procedural-offset wrong host observed. Original directed UV authority exists at the source validator, but source/DI/lift/public exact consumption remains to connect. Retain the offset owner even though destination XYZ uses F. |

For every row the isolated contacts have image0/fiber0. Reverse the actual pcurve
subcurve T[1/4,3/4] once: the new normalized r maps to original T=3/4-r/2.
Retain endpoint roots and reverse incident roles accordingly. A request containing
no listed root must publish complete exclusion, not a missing candidate array.
Full acceptance also requires unchanged work/storage/depth, terminal cancel,
detached-source lifetime, wrong host, all four lanes, review/commit/main.

The initial ordinary-rich CS calls have now been observed once on the same
hash-admitted Native snapshot. [Per-cell runtime receipts](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/PCURVE-CONSTRUCTOR-MAPPING-20261012/ordinary-cs/compile.json)
retain the command, executable/source/log hashes and bounded wall time.
PCURVE-PROJECTED-PARABOLA-01 fails before publication with
"A certified surface-lift representation requires its structural curve root solver."
The other four cells return the expected single numerical point, but all fourteen
original-result receipt fields are nil. They therefore stop at missing complete
source/UV/coverage publication rather than at root discovery. The five calls all
finish within their30s observation limit; none reuses or retries the Coons timeout.
Their expected whole-set laws above remain independent of those numerical values.
No family is accepted by these initial observations.

The pcurve inventory must retain separate `offsetSurfaceImage` forward and
pullback cells. Neither this open-arc CS mapping nor the successful constructors
discharges face-bound material membership: harmonic/great-circle/conic boundary
loops still require exact endpoint connection and a concrete validated face.

###### Historical definition gaps before the final finite expansion

The following are mandatory, not optional follow-ups: remaining rolling-rail producer branches beyond the fixed inputs; remaining positive/negative draft branch and stationary-domain consumers; angular
surface variants beyond the fixed inputs;
remaining nonrational/algebraic guide and hyperbolic construction-chart inputs;
word/image composition with every new child; discontinuous ruled/Coons ownership;
every certified constructor variant and branch; all17 SurfaceParameterCurve cases
and missing-pcurve producer; all applicable boundary/self/ordinary CS/SSI pairings;
remaining projected-contact variants and all M8 changed-contract interactions.
IMPLICIT-SINGULAR-AXES-01 fixes the formerly missing singular issued-T oracle,
and PROJECTION-DRAWING-CONTINUOUS-01 fixes the actual continuous drawing caller.
Their implementations and runtime acceptance remain open; these are no longer
undefined input/oracle fields.
Existing crosswalk IDs 4-P1..11,5-C1..12,6-I1..4,6-B1..11,6-S1..11,M7,M8
remain mandatory overlays on those concrete cells, not a substitute denominator.
No full-family gate is closed by this reconstructed section. The finite expansion
below supersedes these inventory-level "unmapped" labels; it does not supersede
the recorded runtime failures or turn an unobserved cell into an accepted cell.

##### Cone-torus candidate constructor admission

A coaxial cone0/axisZ/halfAngle:stored atan(6) and torus0/axisZ/R3/r1
candidate was checked using the actual current public
CertifiedGeneralConeTorusIntersectionCurve constructor. It rejects branchIndex0
with KernelError.invalidInput: "A general cone-torus curve requires non-coaxial
source surfaces." No regular branch is constructed. This is constructor admission
failure, not a geometric exclusion or a positive general-certified cell. The
simple four-circle mathematical oracle cannot be assigned to that constructor's
branch indices, normalized T or parent UV. The candidate is not added to the
required positive-cell denominator. Use the existing non-coaxial tilted-cone
constructor for the remaining regular certificate branch mapping; its exact
whole branch/T/UV oracles remain open. Coaxial parent SSI belongs to its own
existing analytic source path and does not close the general certificate.

##### CERT-CONETORUS-TILTED-01: complete regular branch oracle

Use the actual existing non-coaxial fixture from
[CertifiedGeneralConeTorusSpatialDifferentialBoundsTests](../../../../Tests/CADGeometryTests/CertifiedGeneralConeTorusSpatialDifferentialBoundsTests.swift):
cone(apex0,axis:stored normalize(.05,0,1),halfAngle:stored atan(6)),
torus(center0,axisZ,R3,r1), constructor depth24/cells65536, standard tolerance.
Let (a,0,b) be the exact binary64 axis values passed by that fixture and
n=(a,0,b)/sqrt(a*a+b*b) the original canonical unit axis. Retain that
normalization law; the stored candidate's near-unit length is not an equality
proof. Put s=sin(alpha), c=cos(alpha), alpha=the exact stored halfAngle,
e=(0,1,0), f=(-n.z,0,n.x), and
 d(theta)=c*n+s*(e*cos(theta)+f*sin(theta)).
Then |d|=1 and zDirection=c*n.z+s*n.x*sin(theta).

The exact original torus equation on P=lambda*d is
 lambda^4+(36*zDirection^2-20)*lambda^2+64=0.
For the actual fixture, |zDirection|<1/4 on the whole turn, so
A=20-36*zDirection^2>71/4>16 and D=A*A-256>0.
There are exactly four distinct nonzero ordered roots on every phase:
 lambda0=-sqrt((A+sqrt(D))/2),
 lambda1=-sqrt((A-sqrt(D))/2),
 lambda2= sqrt((A-sqrt(D))/2),
 lambda3= sqrt((A+sqrt(D))/2).
This independent quartic/root oracle supplies every regular certificate index;
numeric root traces cannot change their order or omit a branch.

| Cell | Actual public request / complete expected result |
|---|---|
| CS-CERT-CONETORUS-TILTED-B0-01 | Direct general-certified constructor branchIndex0, whole T[0,1], ordinary CS against planeY0/origin0/uDirectionX. Exactly T1/4 and3/4, P=lambda0(theta)*d(theta) at theta=pi/2,3*pi/2; targetUV=(P.x,-P.z). |
| CS-CERT-CONETORUS-TILTED-B1-01 | Same, branchIndex1 and lambda1; exactly the same two T labels with that branch's independent XYZ/UV. |
| CS-CERT-CONETORUS-TILTED-B2-01 | Same, branchIndex2 and lambda2. |
| CS-CERT-CONETORUS-TILTED-B3-01 | Same, branchIndex3 and lambda3. |
| SSI-CERT-CONETORUS-TILTED-01 | Ordinary rich SSI of the exact original parent pair retains all four curves P_i(theta), full turn and all independently admitted parent UV lifts; no other component exists by the quartic factorization and |d|=1. |

The normalized closed certificate constructor has no authored physical-angle
endpoints. Its authoritative source T law is theta=2*pi*T, explicitly retained
with the full-turn closure theorem. Migrating its binary phase evaluation and
T1 reset to this exact normalized-turn source authority is required; this does
not reinterpret direct constructors' caller-authored binary physical endpoints.
At theta=pi/2, d=(c*n.x-s*n.z,0,c*n.z+s*n.x); at3*pi/2 replace s by-s
in these radial terms. Thus the two CS contacts are isolated and cannot be
merged across different lambda indices.

Every cone UV is(B*T+k*B,lambda_i(theta)), where B is the exact stored intrinsic
period label. For each P, every torus UV is
(atan2(-P.x,P.y)/h+m*B,
 atan2(P.z,sqrt(P.x*P.x+P.y*P.y)-3)/h+j*B),
h=2*pi/B, independent arbitrary integers k,m,j and declared atan2 branches.
All source endpoint incidences and any seam sides are retained. Each isolated
CS stratum has image0/fiber0; each regular SSI curve has image1/fiber0 before
symbolic integer indexing. Restriction T[1/8,3/8] retains onlyT1/4;
T[0,1/8] has complete exclusion.

Current constructor/ordinary runtime for these exact cells is unobserved.
The actual existing fixture identifies the admitted non-coaxial constructor;
it is distinct from the rejected coaxial candidate. Missing implementation is
source-owned exact unit-axis/physical-angle coefficient capability, all-root
selection, normalized closed T and complete parentUV theorem, then existing
DI/ordinary publication. Retain the existing certificate producer and its
caller admission; no parallel shape generator, rounded coefficient equality or
finite UV lift window. Acceptance requires all four positive branches, whole
parent SSI, restrictions/exclusion, wrong owner/root, limits/cancel/lifetime,
four lanes, review/commit/main. Apex-reduction remains a separate required cell.

##### IMPLICIT-SINGULAR-AXES-01: full singular set and authored branch T

Use actual unit-weight Native tensor surfaces on[-1,1]^2:
S(u,v)=(u,v,0) and Q(p,q)=(p,q,p*q), each degree(1,1), both knot
vectors[-1,-1,1,1]. Store the four actual corner values of each law in its
control net. Ordinary rich SSI must retain exactly u=p, v=q, p*q=0,
including the origin and all four incident half-axis germs. The image is the
union of both closed coordinate axes in the square, not a regular graph across
the origin. Away from the origin each branch has image1/fiber0; the origin
stratum has image0/fiber0 and four incident branches.

The required branch-source operation consumes that retained exact Native
relation and selects an authored directed branch as follows. This operation is
currently absent; it is a source-owner implementation gap, not authority for
creating an unchecked CertifiedImplicitIntersectionCurve. The ordinary Native
surface constructors and SSI query already exist. A regular interval graph
constructor cannot substitute for a singular-source connection: its connection
validator requires finite nonzero compatible tangents.

| Finite branch cell | Authored T[0,1], all parent coordinates | Positive / isolated complete CS oracle |
|---|---|---|
| CS-IMPLICIT-SINGULAR-XPLUS-01 | (u,v;p,q)=(T,0;T,0) | PlaneZ0 retains allT, XYZ(T,0,0). PlaneX0 retains onlyT0, XYZ0. |
| CS-IMPLICIT-SINGULAR-XMINUS-01 | (-T,0;-T,0) | PlaneZ0 retains allT, XYZ(-T,0,0). PlaneX0 retains onlyT0, XYZ0. |
| CS-IMPLICIT-SINGULAR-YPLUS-01 | (0,T;0,T) | PlaneZ0 and planeX0 retain allT, XYZ(0,T,0). |
| CS-IMPLICIT-SINGULAR-YMINUS-01 | (0,-T;0,-T) | PlaneZ0 and planeX0 retain allT, XYZ(0,-T,0). |

All target planes have origin0, their indicated unit normal, and explicit
uDirectionX for planeZ0 or uDirectionZ for planeX0. Thus planeZ0 UV=(x,y)
and planeX0 UV=(z,-y). Target coordinates are fixed independently of the
consumer. The singleton origin on each X branch retains that branch's owner,
T0 and parent UV0; relation grouping may retain the four incident source germs
but cannot identify their one-sided derivatives. Reversed traversal uses the
same selected branch with T replaced by1-T, not a different half-axis.

Current location: the complete original polynomial oracle and directed T laws
are fixed; source-issued singular branch selection/connection and ordinary
curve publication are absent and runtime is unobserved. Required change is
source-owned factoring/branch incidence from the retained solved relation,
checked T/parent-UV binding, then existing DI/geometric consumers. No new solve
of the same pair, interval callback declaring equality, or fictitious regular
connection is permitted. Acceptance requires the complete SSI axes and all four
branch CS cells, origin incidences, direction controls, same limits/cancel and
detached-owner use, followed by review/commit/main. This closes the formerly
undefined singular T field without claiming the implementation exists.

##### PROJECTION-DRAWING-CONTINUOUS-01: producer-bound drawing caller

Construct one CADDocument with two ordered FeatureNodes, each operation
`.bSplineSurface(BSplineSurfaceFeature(surface: ...))` and sheet output, and
obtain the actual EvaluatedDocument with DocumentEvaluator.evaluateExact.
The existing producer entry is exercised in
[KernelIndependentItemCharacterizationTests](../../../../Tests/CADKernelTests/KernelIndependentItemCharacterizationTests.swift).
Do not attach or copy a validatedSourceReceipt manually.

The first surface is the degree(1,2), unit-weight parabolic surface
S(u,v)=(u,v*v,v), U[0,1], V[-1,1], with U knots[0,0,1,1],
V knots[-1,-1,-1,1,1,1] and each U-column's YZ controls
[(1,-1),(-1,0),(1,1)]. The second is the degree(1,1), unit-weight
sheet R(a,b)=(a,b,2), both parameters[0,1], clamped knots[0,0,1,1].
Its b=0 boundary is the actual native edge E(t)=(t,0,2); select it by its
source feature/subshape correspondence, not iteration order. Other sheet edges
remain in the actual drawing input and retain their independent partitions.
Use the original orthographic frame(origin:0,normal:Z,horizontal:X), call
BRepDrawingProjector.projectEdges, then DefaultBRepDrawingPlacer.place with
identity placements for both actual body IDs, BRepDrawingSilhouetteProducer
on that same producer-bound evaluation, and
DefaultBRepDrawingProjectedContactPreparer.prepare with the same frame and
caller admission.

| Field | Required result / present stop |
|---|---|
| Complete selected-pair oracle | First face silhouette is v=0, all u[0,1]. Against the actual second face b=0 edge, the whole relation is t=u, v=0, screen=(t,0), signed source-edge minus silhouette depth=+2. Image dimension1, fiber dimension0, both endpoints retained. This is a contact partition, not a visibility classification. |
| Reverse and zero-depth controls | Reverse the selected coedge traversal: edge-local directed t maps to u=1-t without changing the whole image or depth. In a separately evaluated document replace second surface height2 by0; the same selected pair has depth0. Do not edit the evaluated B-rep under a stale receipt. |
| Current location | Actual producer, projector, placer and preparer are identified in production source. Model admission, silhouette output and contact runtime are unobserved. The previously fixed positive-dimensional Native projected-locus refusal is a downstream static stop, not a reproduced failure of this complete caller input. |
| Required implementation | Preserve producer-bound source, real Native edge span, exact trimmed silhouette, positive-dimensional retained relation and whole depth correspondence through the preparer. Preserve every unrelated actual edge partition; no hand-created placed projection, visibility label or replacement silhouette. |
| Acceptance | Actual caller succeeds for the whole selected interval and both controls; source release, foreign/stale evaluation, same admission limits and cancel remain explicit. Four-lane changed-path evidence, one review, coherent commit and latest-main integration close this cell only. |

##### Remaining source and construction variants

These rows preserve accepted variants while exposing the next missing cell fields.
Unless a named cell above supplies them, the public request, independent complete
oracle, consumed receipts and actual stop are unmapped. A source signature limit
is static evidence only; an available numerical fallback may succeed and must
not be reported as a reproduced failure. Links identify actual constructors and
producer boundaries, not a proposal to regenerate their original equations.

| Required variant | Existing constructor / first source boundary | Public mapping or missing fields |
|---|---|---|
| Offset: finite Native, periodic Native, general child | [OffsetSurface3D](../../OffsetSurface3D.swift); [Native law issuer](../../OriginalSourceIssuance/DefaultOriginalOffsetLawIssuer.swift) requires an OriginalBSplineSourceReading child. [Periodic DI](#periodic-native-offset-domain-composition) retains integer cycles; [issued offset graphs](../../NativeExactRelations/DefaultOriginalOffsetGraphFamilyPreparer.swift) currently consume the finite Native cover. | Source/DI receipts are scoped premises. CS-OFFSET-PERIODIC-ZERO-GEOM-01 fixes the two-cycle geometric oracle with runtime unobserved. General children and other periodic inputs remain unmapped. S-COONS-OFFSET-CALLER-01 observes a result validator, not periodic-offset SSI publication. |
| Revolution: rational and nonrational generator | [OriginalRevolutionSurface3D](../../OriginalRevolution/OriginalRevolutionSurface3D.swift); [finite preparer](../../OriginalSourceIssuance/DefaultOriginalFiniteRevolutionLawPreparer.swift) consumes complete rational generator chart receipts. | CS-REVOLUTION-AXIS-FIBER-01 is main-delivered in11f4e9fd/0422fa0c with its full original axis-fiber CS oracle, four-lane evidence and one review. Other rational ordinary inputs, nonrational generator supply and SSI cells remain unmapped. |
| Rolling-ball: Native, mixed retained graph rails, periodic/non-Native rails, actual offset pullback contacts | [RollingBallBlendSurface3D](../../RollingBall/RollingBallBlendSurface3D.swift), public [RollingBallSectionEvaluator](../../RollingBall/RollingBallSectionEvaluator.swift); actual contactCurve emits offsetSurfaceImage pcurves. [Child source dispatcher](../../OriginalSourceIssuance/OriginalRollingBallCurveSnapshotProvider.swift) has an explicit unmatched-lift refusal. | SSI-ROLLING-BALL-PLANE-01 defines one all-lift child input and complete oracle, now connected to checked section publication; general rolling-family cells remain open. Existing supported child receipts do not cover automatic polyline/offsetSurfaceImage dispatch or all periodic rails; those public cells remain unmapped. |
| Plane-derivative curve and surface: rational versus angular/algebraic child | [Curve constructor](../../OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeCurve3D.swift), [surface constructor](../../OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeSurface3D.swift); [curve provider](../../OriginalSourceIssuance/OriginalPlaneDerivativeCurveSnapshotProvider.swift) and [surface provider](../../OriginalSourceIssuance/OriginalPlaneDerivativeSurfaceSnapshotProvider.swift) reuse the original rational producer. | CS-DERIVATIVE-LIFT-PLANE-01 fixes the weighted/projected rational host and Native diagonal pcurve; existing source/DI/lift/rolling child premises remain scoped. General ordered-field sources and other ordinary public cells remain unmapped. |
| Boundary correction: rational versus angular/algebraic boundary | [OriginalBoundaryCorrectedSurface3D](../../OriginalCoons/BoundaryCorrection/OriginalBoundaryCorrectedSurface3D.swift); [provider](../../OriginalSourceIssuance/OriginalBoundaryCorrectionSnapshotProvider.swift) refuses unavailable original rational atlas authority. | CS-POLY-CORRECTION-01 defines one rational-host input/oracle, historical selected-entry decline and scoped public acceptance receipt. General boundary variants remain unmapped. |
| Draft curve; drafted ruled surface | [OriginalDraftedCurve3D](../../OriginalDraftedSection/OriginalDraftedCurve3D.swift), [OriginalDraftedRuledSurface3D](../../OriginalDraftedSection/OriginalDraftedRuledSurface3D.swift). | CS-DRAFT-ZERO-RULED-01 defines one exact-zero wall input and complete oracle; actual constructor/real fallback return a numerical contact, with the complete original publication receipt missing. Its scoped [source-to-public acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-DRAFT-ZERO-RULED-01/VERIFICATION.md) consumes the original source-owned zero-translation atlas and retained DI/L5/L6. CS-DRAFT-POSITIVE-PLANE-01 and SSI-DRAFT-POSITIVE-PLANE-01 below fix one nonzero physical-angle curve/wall recipe and complete oracles; ordinary runtime remains unobserved and the retained physical-sine/selected-root coefficient receipt is absent. Negative-angle/other-root branches and other public requests remain unmapped. |
| Angular curve; angular surface: intrinsic, physicalRadians, physicalRadianArc | [Curve constructor](../../CanonicalSphereChart/OriginalAngularTransportCurve3D.swift), [surface constructor](../../CanonicalSphereChart/OriginalAngularTransportSurface3D.swift), [source maps](../../OriginalSourceIssuance/OriginalSourceAngularMap.swift). Physical maps require the actual pi-capable field; the intrinsic [coordinate issuer](../../OriginalSourceIssuance/DefaultOriginalAnalyticCoordinateIssuer.swift) explicitly refuses absent mathematical pi. | Source-coordinate/DI capabilities are separate from public geometric consumption. CS-ANGULAR-PHYSICAL-ARC-PLANE-01 below closes one positive-turn normalized circle arc against its complete physical-phase oracle through four ordinary public entries. Its reviewed implementation is main-integrated in commit6b8ea495. SSI-ANGULAR-PHYSICAL-CYLINDER-PLANE-01 below separately fixes a finite physicalRadians surface input and complete continuous oracle; runtime is unobserved. Other primitive/map branches remain open. |
| Implicit stored graph curve | [CertifiedImplicitIntersectionCurve](../../CertifiedImplicitIntersectionCurve.swift) retains source surfaces, validated graph cells, connections and closure. | CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01 below fixes one forward single-cell nonlinear input and complete isolated/empty oracle. One ordinary Native call returns a numerical point with all twelve original receipt fields nil; complete original correspondence remains unpublished. Split and reversed constructions now have separate finite input/oracle cells below with unobserved public runtimes. The closed-source inputs below and IMPLICIT-SINGULAR-AXES-01 now fix the closed/singular oracles and directed T laws; the singular source operation remains absent. Neither the input definitions nor the existing analytic/rational fallback complete those public paths. |
| Certified sphereCone | [CertifiedSphereConeIntersectionCurve](../../CertifiedSphereConeIntersectionCurve.swift): negativeFullBranch, positiveFullBranch, boundedAngularInterval, negativeOpenAngularInterval, positiveOpenAngularInterval, apexReducedAngularInterval. | CS-CERT-SPHERECONE-POSITIVE-PLANE-01 identifies one actual positiveFullBranch constructor/target and the exact original-pair coefficient/T-binding gaps below. It has no complete stored-curve oracle or observed stop. CS-CERT-SPHERECONE-APEX-EMPTY-01 below fixes the existing apexReduced recipe and target with a complete direct whole-T height-exclusion oracle. The baseline rich call returns numerical empty without retained exclusion. The source-owned whole-support separation theorem, exact selected T/UV binding and all four ordinary public entries now pass the complete empty oracle and applicable controls on fixed Native/ASAN/ordinary-WASM/Embedded; [frozen scoped verification](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance/VERIFICATION.md) binds all47 current production bodies. Review and main delivery are tracked in PROGRESS.md. Other four branch recipes and the positiveFullBranch complete stored-curve oracle remain open; existing CS reduction/fallback is not whole-family proof. |
| Certified coneCone | [CertifiedConeConeIntersectionCurve](../../CertifiedConeConeIntersectionCurve.swift): negativeFullBranch, positiveFullBranch, boundedAngularInterval, apexReducedAngularInterval. | CS-CERT-CONECONE-POSITIVE-PLANE-01 below identifies one actual positiveFullBranch input/target and its unresolved exact coefficient/branch/T-to-UV oracle. Other three branch inputs remain unmapped; no runtime stop is claimed. |
| Certified coneCylinder | [CertifiedConeCylinderIntersectionCurve](../../CertifiedConeCylinderIntersectionCurve.swift): negativeFullBranch, positiveFullBranch, boundedAngularInterval, apexLowerNodeInterval, apexUpperNodeInterval, rulingParallelLinear. | The actual rulingParallelLinear construction and its original-pair oracle gap are identified below. CS-CERT-CONECYLINDER-POSITIVE-PLANE-01 below separately identifies an actual positiveFullBranch input/target and unresolved coefficient/T/UV oracle. Other branches retain their own unmapped fields; numerical differential tests do not close them. |
| Certified coneTorus regular certificate; apexReduction constructor | [CertifiedGeneralConeTorusIntersectionCurve](../../CertifiedGeneralConeTorusIntersectionCurve.swift) has the branchIndex/certificate constructor and a separate branchCount/apexReduction constructor. | CS-CERT-CONETORUS-REGULAR-PLANE-01 below identifies one regular branch0 pair/target and its exact coefficient/root/T/UV definition gaps. Keep apexReduction and other branches visible and unmapped; no public runtime acceptance is inferred. |
| Certified parallelTorusTorus | [CertifiedParallelTorusTorusIntersectionCurve](../../CertifiedParallelTorusTorusIntersectionCurve.swift): certificate-owned regularClosed, nodalSelfLoop and nearNodalClosedLoop. | CS-CERT-PARALLELTORI-REGULAR-EMPTY-01 below fixes one regularClosed branch0 input with a whole-T height exclusion oracle; ordinary runtime is unobserved. Positive contact/T-to-UV and nodalSelfLoop/nearNodalClosedLoop remain unmapped. The dedicated plane solver is neither a reproduced stop nor general acceptance. |
| Lift: Native finite/periodic; retained Coons/correction/derivative hosts; Native/affine/constant/prepared polyline pcurves; other hosts/pcurves, priority images and clamp correspondence | [SurfaceLiftCurve3D](../../SurfaceLiftCurve3D.swift), [retained-host polyline provider](../../OriginalSourceIssuance/OriginalPolylineRetainedAtlasLiftSnapshotProvider.swift); priority image and out-of-support clamp inputs explicitly refuse at this source port. | Existing CS-POLY cells cover their Coons/polyline input; correction is its separately named cell. Remaining host/pcurve combinations and general rational/nonlinear UV elimination stay unmapped. |
| Join/guide: traversal chain, guide endpoint connector, original endpoint connector, affine/nonaffine construction chart | [Guide chain](../../OriginalCoons/GuideTraversalChain/OriginalGuideTraversalChain3D.swift), [guide correction](../../OriginalCoons/EndpointConnector/GuideCorrection/OriginalGuideEndpointConnectorCurve3D.swift), [endpoint connector](../../OriginalCoons/EndpointConnector/OriginalEndpointConnectorCurve3D.swift), [rational admission](../../OriginalCoons/OriginalSplineTraversalPolynomialPiece.swift). | S-RULED-CLOSED-GUIDE-SEAM-01 observes the actual closed rational guide/ruled source,7 laws/cover/graphs, all49 raw pairs with checked solver reuse and checked law-bound directed seam issuance. Its focused Native prepared query now proves the complete reverse-only residual with exact domain-wide simplification under the original cap. Final4lane10group acceptance, one review and independent main delivery in d9abe057 pass. Earlier raw/query-work and Native-only declaration diagnostics remain historical. Nonrational/algebraic joins, nonaffine charts and other consumers remain unmapped. |
| Ruled; Coons: rational, angular/algebraic, discontinuous boundaries | [RuledSurface3D](../../RuledSurface3D.swift), [OriginalCoonsSurface3D](../../OriginalCoons/OriginalCoonsSurface3D.swift), [Coons atlas provider](../../OriginalSourceIssuance/OriginalCoonsAtlasSnapshotProvider.swift). | Existing Coons boundary/self/CS cells retain their exact rational inputs. SSI-COONS-PLANE-01 has a source-hash-matched Native ordinary-rich runtime stop at120.014s in bounded completeness/gauge/Coons jets; its [current diagnostic](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/STOP.md) supersedes the historical unobserved status. Existing source/DI Coons graphs and whole-plane graphs remain disconnected at ordinary SSI publication. Other ruled/Coons source/public branches remain unmapped. |
| Spatial words; parameter images; directed traversal: finite affine versus nonlinear/singular/infinite correspondence | [Affine child composition](#m4-affine-child-domain-composition), [parameter/traversal graphs](#finite-parameter-image-and-traversal-graph-consumption). | Existing source/DI receipts remain premises. No representative receipt closes the general nonlinear/singular/infinite public branch; missing exact input/oracle/observation remains explicit. |

##### CS-ANGULAR-PHYSICAL-ARC-PLANE-01: exact physical phase candidate

The actual constructor is the circle arc in
[M3PrimitiveSourceFixtures](../../../../Tests/OriginalDomainConsumerVerification/Sources/M3Fixtures/M3PrimitiveSourceFixtures.swift):
OriginalAngularTransportCurve3D with source circle(center:origin,normal:unitZ,radius:3),
transport physicalRadianArc(start:zero,end:one,additionalTurns:1), standard tolerance
and the existing caller rational admission. Wrap it as Curve3D.originalAngularTransport.
Its normalized authored support is T=[0,1].

| Cell field | Fixed value or explicit definition gap |
|---|---|
| Public input | Ordinary DefaultCurveSurfaceIntersector.intersectionResult with that original curve, analytic plane(origin:origin,normal:unitX), curveRange[0,1], surfaceURange[-1,1], surfaceVRange[-4,4], otherwise default options and standard tolerance. |
| Independent source law | Let mathematical pi be the existing OriginalPiScalarDomain value and g=1+2pi. C(t)=(3cos(gt),3sin(gt),0), with exact normalized T support[0,1]. Circle basis is(+X,+Y); target plane basis is(+Z,-Y). |
| Complete result | Exactly t=pi/(2g) and t=3pi/(2g). The first has source physical phase pi/2, XYZ(0,3,0), targetUV(0,-3); the second phase3pi/2, XYZ(0,-3,0), targetUV(0,3). Each is an interior transverse point with relation/image/coordinate-fiber dimensions0 and one original arc incident. No overlap. |
| Original child labels | B is the exact binary64 import of2*Double.pi. Child intrinsic labels are exact field fractions B/4 and3B/4. They are not coefficients formed by the rounded Double expression3*Double.pi/2. The source-owned nativeLabel=conventionalPi/mathematicalPi*physicalPhase law establishes this correspondence. |
| Complete exclusion | cos(phi)=0 iff phi=pi/2+k*pi. On0<=phi<=1+2pi, the preceding phase-pi/2 is below support and the next5pi/2 is above support because pi>2. Derivatives dx/dt are respectively-3g and+3g, both nonzero. |
| Actual observation | The [single Native ordinary observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-ANGULAR-PHYSICAL-ARC-PLANE-01/native-observation-20261012-v2/receipt.json), receipt b78b854f, returns no result: KernelError.geometry/invalidInput, "Adaptive intersection requires an explicit finite surface U range." The actual rich resolver clears the supplied U/V ranges before its bare fallback. The current29 upper bodies and unchanged lower inputs/products were matched before and after this one call. Exact Q(pi) oracle checks are separate; no public source/TUV/coverage receipt was returned. |
| Next observed operation | After preserving same-frame U/V (synthetic affine B-spline proof planes retain their different-frame treatment), the [single fresh Native call](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-ANGULAR-PHYSICAL-ARC-PLANE-01/native-observation-20261012-v3/receipt.json), receipt38623bcb, reaches the actual nonrational candidate completeness check and throws KernelError.geometry/resourceLimitExceeded. Compile12.960s/runtime0.724s;28 unchanged and1 changed upper body,3681 checked premises, zero lower rebuild. No public result or source/TUV/domain/image/fiber receipt is returned. This is a reproduced completeness stop, not an accepted empty result. |
| Implemented change | The source-owned finite cosine-zero theorem, complete original incidence and unique UV proof retain every selected/excluded candidate and full original covers. Existing L5/L6 consume only selected singleton restrictions; a separate full-pair owner supplies whole-domain completeness. Four ordinary public entries retain exact Q(pi) T/phase/child labels/targetUV beside certified numerical representatives. Same-frame UV forwarding preserves the synthetic proof-plane rule. No ceiling, source equality or solver changed. |
| Receipt dependencies / evidence | Existing actual angular constructor, OriginalAnalyticCoordinateCurveSnapshotProvider, DefaultOriginalAnalyticCoordinateIssuer.issuePhysical, OriginalPiScalarDomain and OriginalAnalyticDomainIssuer. Source phase authority is owned by [CanonicalSphereChart](../../CanonicalSphereChart/DESIGN.md#contracts-and-invariants). [Four-lane changed-path verification](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-ANGULAR-PHYSICAL-ARC-PLANE-01/acceptance/VERIFICATION.md) binds45current bodies, exact resources/admission, cancellation/lifetime and resolver regressions; [one comprehensive review](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-ANGULAR-PHYSICAL-ARC-PLANE-01/REVIEW.md) passes without finding. Historical observation failures remain diagnostic. Commit6b8ea495 is main-integrated after [independent source/compiler/product/log and protected-draft comparison](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-ANGULAR-PHYSICAL-ARC-PLANE-01/integration.json), without lower rebuild or runtime replay. |

This candidate maps the physical-arc/positive-turn branch of4-P1/P2/P6/P7/P8/P10/P11
and M7/M8. It does not close intrinsic/physicalRadians maps, negative or multiple
additional turns, surfaces, transported periodic identity or nonlinear image
consumers. Execution state remains solely in PROGRESS.md.

##### CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01: single-cell nonlinear graph candidate

Use the existing [dyadicPlaneParabolaCurve constructor](../../../../Tests/CADGeometryTests/CertifiedImplicitIntersectionCurveTests.swift:588)
with direction forward and split false. Its original Native surfaces are
S1(a,b)=(a/32,b/64,0) and S2(s,r)=(s^2/32,s/64,(2r-1)/64).
The one closed stored cell uses free firstV in [1/4,3/4], forward traversal and
nonclosed support. Authored T in [0,1] has tau=1/4+T/2; the complete source
correspondence is (a,b;s,r)=(tau^2,tau;tau,1/2).

| Cell field | Fixed oracle or open public gap |
|---|---|
| Actual target / request | Native degree(1,1), unit weights and knots [0,0,1,1] on both axes; each Z row +/-1/64 has controls (0,1/128,Z),(1/32,1/128,Z). Thus H(U,V)=(U/32,1/128,(2V-1)/64). Ordinary rich DefaultCurveSurfaceIntersector.intersectionResult receives curve.implicit and surface.bSpline with closed T/U/V [0,1], standard tolerance/default ceilings. |
| Complete point oracle | Y equality fixes tau=1/2, hence sole (T,U,V)=(1/2,1/4,1/2), XYZ=(1/128,1/128,0). The original support UVs are (1/4,1/2) and (1/2,1/2). One stored-cell incident, one incident per original Native span and one target span; parameter/image/fiber dimensions 0/0/0. |
| Complete empty control | Restrict T to [0,1/4]. The whole curve has Y<=3/512<4/512=1/128, excluding every TUV tuple, XYZ/image/fiber and incident. No samples, residual test or finite root guesses supply the oracle. |
| Current path / observed stop | The actual ordinary rich entry returns one transverse numerical representative at T=.4999999999999998,U=.25000000000000006,V=.5 with all twelve original receipt fields nil. [Frozen observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01/observation/summary.json) binds its actual constructor, source/compiler/products and log. This is a reproduced publication-contract gap, with no numerical solver failure. Existing bare tests at lines986/1060 use another linear stored graph and do not accept this cell. |
| Receipt dependencies / necessary change | Reuse the original Native coefficient/domain authorities, stored graph cell whole-domain root authority and original forward T transport. A source-owned complete graph must bind T and all four host UV auxiliaries, then use the existing DI/L5/L6 path and an auxiliary-aware ordinary publisher. Preserve every lifted witness and original owner under the same admission; no new solver or all-M4/M5 prerequisite is inferred. |

This maps one implicit source construction and applicable public CS point/empty
behavior. Split cells, reverse traversal, closed connections, singular branches
and other mandatory public consumers retain separate open obligations.

The first source-bound public attempt retains the full five-coordinate graph
and compiles the combined seven-coordinate relation, but both complete and empty
requests exhaust the unchanged default work allowance before publication. A
same-effective-budget callback trace locates the stop in L5/L3 decomposition
projection condition binding, before numerical publication. The causal repair
uses a source-issued checked reduction: retain the original graph, all guards
and the unique forward host-coordinate map; solve the equivalent three-parameter
CS relation through existing L5/L6; publish all five original curve coordinates
through `OriginalIssuedExactIntersectionPoint.originalFirstCoordinates`. The
complete tuple, host UV, incident, dimension and empty oracles above do not
change. This does not claim a materialized seven-coordinate solver partition.
The reduced public attempt next reaches raw root isolation and rejects value
depth33 at the unchanged limit32, before publication. The source repair retains
all original and substituted guards plus whole-T range witnesses, removing only
conditions proved true throughout the closed source support from solver input.
Unknown guards remain active and failures propagate. The
[four-lane changed-path packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01/acceptance/VERIFICATION.md)
now verifies the ordinary point/empty publication, original five-coordinate
restoration, continuous representation and bare refusal, exact resource/depth
boundaries, cancellation and detached/COW/independent-reader lifetime. The actual
current Draft ordinary/grouping controls verify the shared publisher on all four
lanes. The packet retains unsuccessful compiler/resource/depth/metadata attempts
as diagnostics; Embedded compiler staging and operational timeouts do not alter
public query ceilings. ASAN covers the fresh changed sources and fixture while
retaining the explicitly uninstrumented cached children. The
[comprehensive review](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01/REVIEW.md)
records its one comprehensive review and F1-only confirmation. The
[main delivery record](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01/DELIVERY.md)
binds the independent committed snapshot and normal fast-forward to main. The
Embedded Draft helper-object receipt gap is repaired by recording every frontend
output and readmitting all products through the actual link and two runtime
controls; other accepted paths are reused. This completes no other implicit
construction or aggregate M4-M8 obligation.

##### Remaining implicit construction cells

These cells use existing constructors. Each row distinguishes its observed public
result from a static capability rejection; an unobserved runtime has no failure claim.

| Cell | Public input and complete oracle | Observed or static stop / causal change / required receipts |
|---|---|---|
| CS-IMPLICIT-SPLIT-DYADIC-PARABOLA-PLANE-01 | Existing `dyadicPlaneParabolaCurve(direction: .forward, split: true)` at CertifiedImplicitIntersectionCurveTests.swift:64/588, same Native target and closed TUV request as the single-cell candidate. The unique TUV, XYZ and both host UVs are identical. The seam T=1/2 has both cell0/local1 and cell1/local0 incidents. T[0,1/4] is completely empty. | [Frozen observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-SPLIT-DYADIC-PARABOLA-PLANE-01/observation/summary.json) records the original missing-receipt/incident gap without inferring root loss from rounding. Source-owned sealed finite coverage now retains the ordered closed global spans, local maps, exact original-UV seam proof and both original5/27-guard graphs. Pair-indexed reduction/publication consumes that authority through existing DI/L5/L6 and exact TUV grouping. The [four-target acceptance packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-SPLIT-DYADIC-PARABOLA-PLANE-01/acceptance/VERIFICATION.md) verifies all12 groups, one point/two incidents, complete exclusions, one-cell compatibility and resource/cancel/lifetime controls under unchanged caller ceilings. The owning source and geometric designs define the limited forward one/two-cell capability; other cell counts, reverse, true closed and singular constructions remain separate cells. No new solver prerequisite is inferred. |
| CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01 | Existing reversed constructor at CertifiedImplicitIntersectionCurveTests.swift:429/588; target the actual `curve.firstSurface`, closed TUV[0,1]. Set tau=3/4-T/2. The whole result is `(T,U,V)=(T,tau^2,tau)`, XYZ=(tau^2/32,tau/64,0), host UV=(tau^2,tau)/(tau,1/2), parameter/image/fiber dimensions1/1/0. Target V[0,1/8] gives complete empty; bare publication must refuse the positive-dimensional relation. | The [frozen ordinary observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01/observation/summary.json) records a typed geometry/resourceLimitExceeded resourceExhaustion failure before any DTO: subdivision could not certify every remaining non-rational candidate. All13 receipt fields are unavailable, not observed nil. The causal change is source-owned single-cell reversed admission and checked original `upper-width*T` host correspondence with unchanged identity T transport, original five-coordinate graph, all27 guards and total T derivative. Existing family/consumer/publication contracts consume that receipt without a new solver or upper API. The changed source path has passed Native/ASAN/normal-WASM/Embedded twelve-group acceptance for the whole continuous relation, restricted-V complete empty, bare refusal, endpoints/derivative, forward one/two-cell regression and failure/resource/cancel/lifetime boundaries. The [frozen acceptance packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01/acceptance/VERIFICATION.md) and [comprehensive review](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01/REVIEW.md) record scoped PASS with no finding. The [delivery record](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01/DELIVERY.md) binds normal latest-main integration of implementation ce764223 after the independent audit. Other reverse profiles and multi-cell/closed/singular sources stay open. |
| CS-IMPLICIT-CLOSED-PLANE-EMPTY-01 | Reuse the actual `closedPlanePcurve()` recipe at CertifiedImplicitSeamTraversalTests.swift:193–286: Native sphere-builder first host, positive-weight rational plane second host and all four `.firstU/.forward` stored cells, passed to `CertifiedImplicitIntersectionCurve(...isClosed:true)`. Ordinary rich CS compares it with analytic plane(origin:(0,0,2),normal:unitZ), closed T[0,1] and targetUV[-2,2]^2, standard tolerance/default ceilings. Every second-host control has Z=0 and positive weight, so its homogeneous Z numerator is identically zero with positive denominator. Every source branch/cell/closed endpoint is therefore disjoint from Z=2: complete empty tuples, incidents and image/fiber. No mathematical-unit-sphere or physical-pi equality is assumed for the actual binary Native first-host coefficients. | Observed Native constructor failure before ordinary CS: `connectionSource` → `gaugeParameterBounds` returns nil at CertifiedImplicitIntersectionGraphCell.swift:1001–1010 (`geometry/intersectionFailure/numericalIndeterminacy`, unique closed gauge root enclosure required). Limited compile/link succeeds in42.592s; constructor1/ordinaryCS0/DTO absent, all13 receipt fields unavailable rather than observed nil. [Frozen observation](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/observation/summary.json) (summarya4b9dc11/manifest9f899cbb) binds source/product/runtime/prepost/cleanup0 with no source/lower regeneration or replay. The exact original-domain constructor repair is now observed in the [Native connection packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/connection/summary.json) (summary53935493/manifest09453d36): all four original, reversed and host-swapped closed constructors succeed; an upper-V boundary moved below the exact middle knot still fails typed gauge admission. The first ordinary rich call then reaches `geometry/invalidInput`: Original closed surface bounds extend beyond their retained support (PreparedSurfaceDifferentialEncloser.swift:726), with DTO absent and all13 fields unavailable. The actual incoming host/axis/interval is not recorded in that runtime. The [Native value packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/value/summary.json) (summary77fefcac/manifest5ab5cd96) verifies the minimal zeroth Taylor-coefficient repair, six exact-value/derivative-law controls and continued strict outside-support rejection. One next ordinary rich call passes the prior immediate bounds failure but returns neither result nor KernelError before its independent wall120 guard. DTO remains absent/all13 unavailable; its internal phase is not recorded. This guard does not prove geometry exclusion. The checked whole-Native-host separation capability is now implemented by the separate [source issuer](../../OriginalSourceIssuance/DESIGN.md#implicit-whole-host-plane-separation) and consumed by the [complete-empty domain owner](../../NativeExactRelations/DESIGN.md#implicit-host-plane-empty-pair-binding) and [ordinary public producer](../../NativeExactGeometricRelations/DESIGN.md#implicit-host-plane-empty-publication). The [Native adoption packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/acceptance/native-adoption.json) binds all11 successful groups across causally equivalent fixture revisions: complete empty authority through all four ordinary entries, all4cells/bothhostowners/distinct seam UVs, exact requests, same-admission N/N-1 resources, cancellation and retained independent readers. Three fixture-only diagnostics remain rejected evidence. Native, ASAN, normal-WASM and Embedded each pass all11 acceptance groups. ASAN instruments the changed constructor/value/source/public bodies; unchanged lower products are not claimed instrumented. The explicitly authorized fixed-generation1651 Embedded Geometry regeneration completes within aggregateGeometry wall20min/resident8GiB; no Core/Kernel/L2-L6 regeneration occurs. A fixture-only explicit-import repair reuses all successful Embedded products without regeneration and preserves the original test body. The [frozen four-target packet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/acceptance/VERIFICATION.md) binds current66 production bodies and44 successful runtime groups. The [scoped comprehensive review](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/REVIEW.md) passes with no finding. The [delivery record](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/DELIVERY.md) closes independent latest-main audit and normal integration of implementation57be04fa. No positive closed parameterization prerequisite or solver redesign is inferred. The current selector statically declines closed/multiple-cell/firstU sources; this is not the observed public stop. Reuse both original Native host authorities, all four stored-cell/closed-connection contracts and their original UVs, retaining distinct first-host U0/U4 endpoints. Missing positive closed-source correspondence/identity consumers remain separate obligations; an empty cell does not close them. |
| Singular implicit source branch coverage | Definition gap: existing `singularThirdBSplineContactFailsExplicitly` uses a regular implicit line and a tangent target; it does not construct a singular implicit source branch. The actual singular source constructor, branch connection and complete correspondence remain to be identified. | No executable singular-source cell or new prerequisite is selected from that contact control. |

The split, reverse and actual closed-source empty cells map separate construction
and public-result obligations; neither the single-cell implementation nor the
regular-source tangency control closes them. The closed constructor validates
the last-to-first connection, including both hosts and nonzero compatible
tangent enclosures (CertifiedImplicitIntersectionCurve.swift:136–144,337–402).
The affine forward/reverse false-closure control at
SurfaceAreaIntegrationTests.swift:1159–1171 is rejected and is not an alternative
closed source. Execution state remains solely in PROGRESS.md.

##### SSI-ANGULAR-PHYSICAL-CYLINDER-PLANE-01: finite physical surface candidate

Use the existing [M3 analytic cylinder transport recipe](../../../../Tests/OriginalDomainConsumerVerification/Sources/M3Fixtures/M3PrimitiveSourceFixtures.swift:196):
analytic cylinder(origin,axisZ,radius3), U physicalRadians(gain:2,offset:0),
V intrinsic, standard tolerance. Preserve its actual analytic basis (+Y,-X),
so G(u,v)=(-3*sin(2u),3*cos(2u),v). This is not the other direct cylinder basis.

| Cell field | Fixed oracle or open public gap |
|---|---|
| Target / request | Original analytic plane Y=0 has basis(-Z,-X), P(a,b)=(-b,0,-a). First original UV [0,1]x[-1,1], second original UV [-1,1]x[2,4]. Use the existing finite-box rich DefaultSurfaceSurfaceIntersector.intersectionResult overload in DefaultSurfaceSurfaceIntersector+Result.swift:46 with the original caller admission/cancel, default options and sourceDepth1. There is no callback-free finite-box rich overload; do not describe this as one. |
| Complete relation | u=mathematicalPi/4, v=s, secondUV=(-s,3), XYZ=(-3,0,s), -1<=s<=1. Because 2<pi<4, phase[0,2] contains exactly one cosine zero pi/2. All other original UV tuples are excluded. The closed segment includes both endpoints, parameter/image dimension1 and fiber dimension0; no isolated point or coincident surface component. |
| Child / period authority | Original child intrinsic UV=(B/4,s), B=exact binary64(2*Double.pi). The physical U period is mathematical pi, not B/2. Finite selection has no seam multiplicity. Preserve the original full source law and the actual parameter/phase correspondence. |
| Runtime / current path | UNOBSERVED. Static Native-only producers decline this procedural/analytic pair before the actual bounded parametric intersector. This is not an observed public failure and does not establish successful completeness or retained publication. |
| Receipt dependencies / necessary change | Existing OriginalAnalyticCoordinateSurfaceSnapshotProvider, issuePhysical C/S gains and cylinder V polynomial, OriginalPiScalarDomain, analytic finite domain cover and original plane basis/domain. Observe the actual public result before selecting a causal change. The recently delivered circle-only finite cosine-zero receipt does not attest this cylinder source. No new scalar, source or solver prerequisite is inferred. |

This maps a finite physicalRadians cylinder branch and one public continuous SSI
result. Other primitives, physical arcs, independent periods and unbounded
symbolic requests remain separate obligations.

##### Positive physical-angle draft curve and wall candidates

CS-DRAFT-POSITIVE-PLANE-01 and SSI-DRAFT-POSITIVE-PLANE-01 reuse the actual
[input(angle:1e-12) constructor](../../../../Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift#L108)
from the delivered zero-angle fixture. Its Native degree1 generator has
knots[0,0,1,1], controls[origin,X], weights[1,2] and reversed authored traversal
[0,1]. The raw normal is2Z, raw axis=pull=4Z, curve height1 and wall endHeight3.
The authored angle theta is the exact stored binary64 value1e-12, in physical
radians. The original constructor's zero branch uses angle==0; this input is
nonzero and is not clamped.

Let s=sin(theta) with the canonical physical meaning, and let tau be the positive
root of (1-s^2)*tau^2=s^2. Since0<theta<pi/4, 0<tau<1. The original selected
negative quadratic root is k=-tau and the ruling is Z-tau*Y. The evaluator's
[certified sine enclosure](../../CertifiedRotationTrigonometry.swift) and point
midpoint are numerical evaluation facilities; neither a midpoint nor a rounded
libm coefficient supplies exact source authority. Preserve the original speed,
positive quadratic coefficient, positive radicand and selected-root guards.
The [wall](../../OriginalDraftedSection/OriginalDraftedRuledSurface3D.swift)
uses the same start rulingJet at height h=1+2v, without reconstructing a new root.

| Cell field | CS-DRAFT-POSITIVE-PLANE-01 | SSI-DRAFT-POSITIVE-PLANE-01 |
|---|---|---|
| Ordinary public input | Curve3D.originalDrafted(wall.start) against plane(origin:X/2,normal:X), curveT[0,1], planeUV[0,2]x[0,1] | Surface3D.procedural.originalDrafted(wall) against the same plane, wallUV[0,1]^2, planeUV[1,3]x[0,3] |
| Complete independent oracle | Unique(T,planeU,planeV)=(2/3,1,tau), XYZ=(1/2,-tau,1), original generator parameter1/3 | Every(u,v,planeU,planeV)=(2/3,v,1+2v,(1+2v)*tau), v in[0,1], XYZ=(1/2,-(1+2v)*tau,1+2v), original generator parameter1/3 |
| Dimensions | Parameter0/image0/fiber0 | Parameter1/image1/fiber0 |
| Completeness | x(u)=2(1-u)/(2-u) is strictly decreasing, derivative-2/(2-u)^2; the unique x=1/2 preimage is2/3 | The same unique u; every closed v is retained and z=1+2v makes each image fiber singleton |
| Current stop/evidence scope | The existing nonzero capability-decline control and the static angle==0 gate reject this input from the rational zero atlas; ordinary adaptive/public result runtime is unobserved | The bounded parametric ordinary route remains; its actual runtime/result is unobserved |
| Required receipt / causal gap | Source-owned original theta/sine/selected-root constant-ruling receipt plus exact traversal/domain/point publication | The same retained root/ruling authority plus wall domain, complete continuous relation and image/fiber publication |

The plane basis is U=Z,V=-Y under the existing
[stored plane basis rule](../../OriginalSourceIssuance/OriginalStoredPlaneBasis.swift).
The current rational-only snapshot cannot represent this physical-sine/root
coefficient. The missing receipt is not permission to round it, sample the ruling,
fit a Native curve or add a new intersection solver. Constructor knowledge and
static decline are scoped premises; observing each ordinary input is still
required before adding implementation prerequisites. These two cells do not
cover negative angles, stationary generators, other selected roots, zero-angle
regression or drafted-sheet self-contact callers.

##### S-RULED-CLOSED-GUIDE-SEAM-01: directed whole-boundary identity cell

Use the existing original guide and ruled constructors rather than a new aggregate
parent API. At each z in{0,1}, form three degree1 Native segments with knots[0,0,1,1]
and weights[1,1] through the ordered vertices(0,0,z),(1,0,z),(0,1,z),(0,0,z).
For each segment construct OriginalCurveRootSpan3D with authored endpoints0/1,
nativeSpanIndex1, maximumParameterWidth=standard.relative, subdivisionDepth0,
maximumSpanCount4, remainingSourceDepth0, maximumAlgebraicDepth0 and UInt32 storage
stride under the existing rational caller admission. OriginalGuideTraversalChain3D
uses exact-rational stations[0,1/4,3/4,1], segment ordinals[0,1,2], sourceDepth2 and
standard tolerance. Wrap each as Curve3D.originalGuideTraversalChain. The one parent
is RuledSurface3D(startBoundary:z0Guide,endBoundary:z1Guide,uDomain:closed(0,1));
the observed provider binds this concrete parent directly at source depth3. Its
ordinary Surface3D.procedural.ruled dispatch is a separate unobserved entry.

| Cell field | Fixed value or explicit definition gap |
|---|---|
| Public input | Bind the parent once in OriginalExactScalarDomain, issue its complete rational ruled laws/fullUV[0,1]^2 cover and complete ordered self graph product. Call DefaultOriginalIssuedGraphSelfContactQuery.contacts with the authored diagonal plus a checked directed whole seam identity, original domain/cell/topology limits and one caller admission throughout that query. Preparation/raw resolution and the prepared contacts(in:raw) query are separate explicit public operations, as in S-COONS-PLANE-01; each keeps its caller ledger and the same fixed ceilings. Both frames and all scopes retain that one parent owner. |
| Required identity | Position-only relation(0,v)->(1,v) for everyv in[0,1], exact paired whole-boundary laws and affine map(U,V)->(U+1,V) restricted toU=0. The reverse relation needs its own checked proof. Closed guide endpoints alone are declarations, not a receipt. |
| Independent complete residual | The ruled source G(u,v)=(gx(u),gy(u),v) is injective except its closed seamu=0/1. After subtracting the authored diagonal and only the directed forward seam, the complete residual is{(1,v,0,v):v in[0,1]}. Every interior station's duplicate chart incidents represent the same authored UV and remain covered by the diagonal proof. |
| Germ counterexample | Endpoint U derivatives are(4,0,0) and(0,-4,0). The whole positional seam receipt cannot authorize derivative/normal continuity, equality of germs or a reverse/global identity. |
| Historical initial restriction | OriginalSourceBoundaryDeclaration and OriginalRationalParameterIdentityIssuing.declaredBoundary/chartBoundary require OriginalBSplineChartSelection. Actual ruled laws carry OriginalRuledChartSelection with retained guide child selections Int. The existing checked boundary issuer therefore cannot be called with these laws. The separate negative typecheck now reproduces this restriction with both actual ruled laws. Original constructors, all7 exact laws/full cover/graphs succeed; the full49 ordered raw-product attempt separately hits the original8,388,608 work allowance before returning a raw result. These initial diagnostics do not describe the completed changed path. |
| Implemented causal change | The owning [relation design](../../NativeExactRelations/DESIGN.md), [identity design](../OriginalParameterIdentity/DESIGN.md) and [self design](../../OriginalSurfaceEmbedding/DESIGN.md) define checked whole-input/predicate sharing, law-bound whole-boundary issuance and exact full-domain residual simplification. All49 original pairs/ordinals/guards/owners remain retained under the fixed ceilings. No identity is inferred from samples. |
| Receipt dependencies / evidence | Existing retained guide provider and FiniteRetainedCurveChartPreparer, FiniteRuledChartPreparer, original request binder, complete L5 graph product and same-owner OriginalExactScalarDomain self query. Existing open-guide and paired two-owner exact-rational fixtures do not prove this whole same-parent seam. [Native observation evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-RULED-CLOSED-GUIDE-SEAM-01/STOP.md) retains the successful source/cover and both distinct stops, original failed bytes and immutable selected inputs. [Final scoped verification](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-RULED-CLOSED-GUIDE-SEAM-01/VERIFICATION.md) records complete49 raw/reverse-only residual, all10groups in Native/ASAN/ordinaryWASM/Embedded, original resources/cancel/lifetime, checked identity counterexamples and fresh16pair Coons regression. Native partial receipts and fixture/admission diagnostics keep their original status. One scoped review and [independent main delivery](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-RULED-CLOSED-GUIDE-SEAM-01/integration.json) pass for d9abe057; other source families, ordinary ruled dispatch, embedding and M7 geometry publication are unproved. |

This fixes a concrete remaining5-C1/C3/C4/C5/C8/C9/C10/C11/C12 and6-S1/S2/S3/S4/S7
candidate. It does not close nonlinear transport, arbitrary joins, periodic or
collapsed identities, embedding certification or trimmed self contact. An absent
seam receipt leaves both seam directions selected; it never proves absence.
The observed combined preparation/raw/identity/self call with one8,388,608-work
ledger fails explicitly after rawwork6,176,077 and identitywork6,179,580; it is
a retained resource-failure control, not a successful result. Independent prepared
query admission follows the existing public API boundary and must re-admit every
retained proof. No operation may create or reset an allowance internally.

##### CS-CERT-SPHERECONE-APEX-EMPTY-01: complete direct height-exclusion oracle

The existing [apexReducedCurves constructor](../../../../Tests/CADGeometryTests/CertifiedSphereConeSpatialDifferentialBoundsTests.swift:602)
builds the original unit sphere at origin and cone(apex:(1,0,0),axis:unitZ,
halfAngle:authored binary64 bits0x3fddac670561bb50, originally stored from
atan(0.5)) through DefaultSurfaceSurfaceIntersector. Each target constructs that
same authored binary value; recomputing atan at runtime is a different input
when platform libm differs. Retain its two actual apexReducedAngularInterval
results and choose the component
with the smaller original lowerAngle; preserve its constructor-issued angular
bounds and certified wrapper unchanged. Query its actual certified curve with
ordinary DefaultCurveSurfaceIntersector against planeZ=2, authored T[0,1],
planeUV[-2,2]^2 and standard defaults. This is a separate branch from the
positiveFullBranch candidate below.

| Cell field | Fixed oracle or open public gap |
|---|---|
| Independent complete oracle | Preserve the actual regenerated binary64 coefficients: slope bits3fe0000000000001, quadraticA=5/4, cosine bits3fec9f25c5bfedd9, axial=radialCosine=0, radialSine=1. Evaluate the actual apex slant and position expression with all sin(theta),cos(theta) in [-1,1], keeping each denominator/product operation outward. For the actual binary coefficients, the full original closed T[0,1] has abs(z)<=7205759403792807/9007199254740992<13/16<2. Exact alternating Taylor bounds at the stored alpha also place mathematical physical cos/tan/A in the same independent rational boxes. Without cancelling source factors, the full-angle rational box gives abs(z)<=31581/35392<1; the binary outward box also lies below15/16. Thus both coefficient meanings share the complete abs(z)<15/16<1<2 exclusion. Every root, T/UV tuple, XYZ image and incident set is empty, independently of plane UV selection. No parent sphere equality, tan=sin/cos cancellation or point sampling is needed. |
| Oracle evidence | [Coefficient-only worksheet and original expressions](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/oracle-height-20261012/worksheet.json), SHAe701c731, fixed Swift6.4.0/arm64/macOS27 SDK; compile0.497s/scalar0.308s, 120s ceilings. The [exact Fraction semantic worksheet](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/oracle-semantic-20261012/worksheet.json), SHAa18d0488, proves the physical and binary coefficient boxes with zero libm, point samples or CAD builds. These are oracle evidence, not public CAD acceptance. |
| Required causal change | Observe the actual ordinary result, then connect the retained original position/root/closed-T source authority to a complete requested-domain exclusion/publication receipt. Full host UV recovery is not a prerequisite for this proved empty result. |
| Current public path | The existing certified reduction selects the original sphere section; its separated plane-sphere path can return an empty numerical array. Such a return alone does not establish the actual stored curve's whole requested-domain exclusion. |
| Observed runtime / concrete gap | The [one current rich CS call](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/native-observation-20261013-v2/observation-summary.json), receipt9e5082d2, uses the actual SSI constructor's minimumlowerAngle apex component [0,binaryPi]. It returns points0/overlaps0/positiveDimfalse, numericalRepresentatives and all11 original receipts nil. Thus cellCompletefalse: numerical empty matches the oracle but complete source/request-bound exclusion is not retained/published. One causal current PlanePlane body fixes a cached signature mismatch; compile14.375s/runtime0.856s,484 matched inputs, zero sourcephase/lower rebuild. The short runtime RSS/CPU sampling is not peak evidence. No parent sphere/allhostUV prerequisite is required. The first source-bound implementation compiles source6/upper41 but rich CS fails at the unchanged default8388608work (native-v3 STOPf9107b60/e4a22be4). One existing-product lldb diagnostic with no compile identifies the physicalA lower-bound comparison, exponent8, before denominator or readmission. Reusing already proved k/c intervals by rational monotone composition preserves the same strict height/clearance. The repaired publication passes the [complete scoped acceptance](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance/VERIFICATION.md) on all four fixed targets. The exact source/request-bound proof is retained through all four ordinary entries. Native/ASAN reuse only unchanged archived groups and add direct readmission coefficient-depth2/1; WASM/Embedded use the final authored-bit fixture for all10 groups. Diagnostic failures remain historical. Review and main delivery are tracked only in PROGRESS.md. |

The complete empty source-bound retention/publication path and its applicable
controls have scoped four-target evidence. Positive contact, other apex components and the other certified
families retain their own independent input/oracle/receipt obligations.

##### CS-CERT-SPHERECONE-POSITIVE-PLANE-01: original-pair authority gap

The [existing direct constructor](../../../../Tests/CADGeometryTests/CertifiedIntersectionCurveSurfaceIntersectionTests.swift)
uses sphere(center:(0,0,2),radius:stored sqrt(3.0)), cone(apex:origin,axis:unitZ,
halfAngle:stored Double.pi*0.25), kind positiveFullBranch, lowerAngle0 and
upperAngle=stored2*Double.pi. Fix the target as the whole planeY=0 and the ordinary
DefaultCurveSurfaceIntersector.intersections entry with authored T=[0,1], whole
target UV, otherwise default options and standard tolerance. The exact T-to-source
correspondence remains missing before this definition can become acceptance.

| Cell field | Confirmed value or unresolved authority |
|---|---|
| Primitive coefficient authority | Alpha is the exact authored binary64 radian, rho the exact stored binary64 radius. By [physical-angle source authority](../../OriginalSourceIssuance/OriginalPhysicalAngle/DESIGN.md), k is mathematical tan(alpha), not the rounded libm result. Neither k=1 nor rho^2=3 is permitted. The [actual cone issuer](../../OriginalSourceIssuance/DefaultOriginalConeImageIssuer.swift) builds cos^2(alpha)(qx^2+qy^2)-sin^2(alpha)qz^2=0 from its retained physical field. |
| Independent original-pair component | For A=1+k^2, let h+=(2+sqrt(4-A(4-rho^2)))/A and r=k*h+. The positive quadratic-root component meets Y=0 at exactly(-r,0,h+) and(r,0,h+), with targetUV=(-h+,r) and(-h+,-r) in the original unitY plane basis. This is a formula for that original source-pair component; it is not yet an oracle for the stored certified curve. |
| Missing T/UV authority | The certified full branch forms angle=(stored2*Double.pi)*T and evaluates raw sin/cos. A retained exact correspondence to the canonical cone label/phase contract is absent from this path. Do not infer authored T from the ideal component or assign rounded quarter/half-turn labels. |
| Missing position/branch authority | The curve configuration computes tan/products in Double and retains a residual certificate. It does not retain the exact physical coefficient/root binding of the original cone issuer. A complete source-pair equality theorem and its selected positive-root correspondence are needed to identify which original curve the public receipt proves. |
| Stop and next assignment | UNOBSERVED ordinary runtime. The missing original T<->sourceUV<->XYZ oracle is a definition gap, not a reproduced public failure or a new solver/field prerequisite. First resolve the actual source parameterization/branch authority; preserve the other sphereCone branch obligations separately. |
| Evidence scope | The cited existing constructor/differential tests verify their recorded numerical behavior. Source physical-angle and cone-law receipts establish their own primitive semantics; neither establishes this certified curve's exact original-pair equality/public acceptance. |

The public curve result, complete T fibers/incidents, source UV, failure/resource/
cancel/lifetime targets and main delivery remain open. The selected definition
maps only positiveFullBranch; it does not complete the other five sphereCone kinds.

##### Complete full-branch certified oracles

These definitions close the formerly unspecified nonzero full-branch T/root/UV
fields for the concrete inputs below. The [independent rational oracle check](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/CERT-FULL-BRANCH-ORACLES-20261012/oracle.py) proves the angle brackets, positive discriminant/quadratic guards, positive reference-cone height and physical quarter-subcurve root selection with exact fractions and Machin arctangent bounds. They do not establish source implementation
or query acceptance. B denotes the exact binary value produced by `2*Double.pi`;
h=2*pi/B is the intrinsic primitive angular scale. Direct constructors retain
their authored physical phase theta=B*T. In particular B<2*pi: T1 is not exactly
the same source point as T0 and no closure or seam identity follows from the
component name `FullBranch`. Parent SSI retains its own whole intrinsic support.
Source authority remains the original pair, declared root and authored T, as
decided in [SourceIssuance](../../OriginalSourceIssuance/DESIGN.md).

All direct CS cells use `Curve3D.certifiedIntersection`, full T[0,1], standard
options/tolerance and whole target UV. The canonical axisZ radial frame is(Y,-X),
and axisY radial frame is(-Z,-X), derived from [AnalyticBasis](../../AnalyticBasis.swift).
These unit-axis frames contain no rounded metric coefficients.

| Stable cells / actual constructor | Independent whole-source law and complete positive CS result | Necessary change / current stop |
|---|---|---|
| CS-CERT-SPHERECONE-FULL-NEG-01 and CS-CERT-SPHERECONE-FULL-POS-01 | Sphere(center0,R3), cone(apex(1,0,-4),axisZ,alpha:stored atan(1/2)); actual `CertifiedSphereConeIntersectionCurve` with corresponding negativeFullBranch/positiveFullBranch and authored angles0/B. s=sin(alpha), c=cos(alpha), L=-s*sin(theta)-4c, D=L*L-8. The two declared slants are lambda=-L-sqrt(D) and -L+sqrt(D), respectively. P=(1-s*lambda*sin(theta),s*lambda*cos(theta),-4+c*lambda). D>0 and both slants>0 on the whole support. Against planeY0/origin0/uDirectionX, exactly T=pi/(2B) and3pi/(2B), targetUV=(P.x,-P.z); neither source endpoint is an extra root. Each contact is image0/fiber0. All cone UV are(theta/h+kB,lambda); all sphere UV are(atan2(-P.x,P.y)/h+mB,asin(P.z/3)/h) with every admitted integer lift/atan branch. This input contains no sphere pole. | Actual direct constructors and branch enums exist; the ordinary Native CS runtime remains unobserved. Source-owned exact physical sin/cos, selected radical, original T and complete two-parent UV are missing; regenerated binary coefficients and numerical UV projection cannot supply them. Consume that receipt through DI and ordinary publication without replacing theta by2*pi*T. |
| CS-CERT-CONECONE-FULL-NEG-01 and CS-CERT-CONECONE-FULL-POS-01 | Reference cone(apex0,axisZ,alpha:stored atan(1/2)); parameterized cone(apex4Z,axisY,beta:stored atan(3/8)); actual `CertifiedConeConeIntersectionCurve` corresponding full-branch enum, angles0/B. Put sa=sin(alpha), ca=cos(alpha), sb=sin(beta), cb=cos(beta), q=ca*ca-sb*sb*cos(theta)^2, b=4*sa*sa*sb*cos(theta), k=-16*sa*sa. q>0, b*b-q*k>0. lambda=(-b-sqrt(b*b-q*k))/q or(-b+sqrt(b*b-q*k))/q according to the declared branch. P=(-sb*lambda*sin(theta),cb*lambda,4-sb*lambda*cos(theta)). Against planeX0/origin0/uDirectionZ exactly T0 and pi/B; T1 is not a root. TargetUV=(P.z,-P.y). Parameterized UV=(theta/h+nB,lambda). Reference slant is P.z/ca>0 and every reference U is atan2(-P.x,P.y)/h+mB. Source endpoints and both root owners remain distinct. Isolated contacts have image0/fiber0. | Concrete coefficient/T oracle is now fixed instead of an unspecified projection. Current source constructor uses rounded cos metric and reconstructed trigonometric coefficients; exact original metric, selected roots and UV theorem must be source-issued, then consumed by existing DI/L5/L6. Ordinary runtime unobserved; no false nonzero-apex claim is used. |

The parent SSI inputs for these same two pairs have all theta in[0,2*pi), all
listed root branches and every independent parent lift; the complete source
relation is obtained by the displayed quadratic equations and root signs. Each
regular curve has image1/fiber0. Use half-open phase only as a fundamental cover;
retain both seam incidents and all source-domain coordinates symbolically.
This parent support does not enlarge the direct curve's authored physical range.
CS restrictions T[1/8,3/8], singleton roots, disjoint intervals and reversed
traversal retain their exact preimages. Source/field/branch foreign owners,
unchanged resources, final cancel and detached-source lifetime remain required.

###### Certified analytic-pair pcurve role cells

PCURVE-CERTIFIED-PAIR-CONE-01 and PCURVE-CERTIFIED-PAIR-CYLINDER-01 use the actual
`rootFreeCurves` construction in
[CertifiedConeCylinderSpatialDifferentialBoundsTests](../../../../Tests/CADGeometryTests/CertifiedConeCylinderSpatialDifferentialBoundsTests.swift):
cone0/axisZ/alpha:stored atan(1/2), cylinder0/axisZ/radius1,
`positiveFullBranch`, physical angles0/B; wrap with
`CertifiedAnalyticAnalyticIntersectionCurve(coneCylinderCurve:firstSurface:secondSurface:)`.
Construct `CertifiedAnalyticPairSurfaceParameterCurve` with role.first and
role.second, respectively, fractions0/1, and lift on the selected actual parent.
Put theta=B*T, c=cos(alpha), s=sin(alpha). Both lifted source laws must be
P=(-sin(theta),cos(theta),c/s). Cylinder UV is(theta/h+nB,c/s), cone UV is
(theta/h+mB,1/s), independently lifted. Against planeY0/origin0/uDirectionX,
exactly T=pi/(2B),3pi/(2B), XYZ=(-1,0,c/s),(1,0,c/s), targetUV=(-1,-c/s),
(1,-c/s), image0/fiber0. Reversed fractions3/4 to1/4 use original T=3/4-r/2;
only the original pi/(2B) root lies in that subcurve and its r preimage is retained.
The other root is strictly greater than3/4 because B<2*pi; rounded quarter-turn
labels must not turn it into an included endpoint.
Neither role is authorized by the other role's owner. The corresponding negative
full branch uses height-c/s, cone slant-1/s and cone phase theta+pi; cylinder
phase remains theta. Keep those as separately indexed NEG controls, with the same
two physical T roots and independent target UV. The actual wrapper validates its
surface role but currently derives UV by numerical projection; exact source-pair
correspondence and ordinary lift publication remain missing, runtime unobserved.
These cells discharge the concrete pcurve-input/T definition, not the boundary
loop consumer or all cone-cylinder branches.

##### Remaining certified-construction input candidates

The following recipes use existing direct certified constructors and the ordinary
DefaultCurveSurfaceIntersector.intersections entry through Curve3D.certifiedIntersection,
authoredT[0,1], whole target planeUV, default options and standard tolerance.
Each is one limited branch; its runtime is unobserved. Later concrete cells above supersede an earlier definition-gap statement only for the exact input and explicitly selected authority they specify. Stored atan/normalize and
2*Double.pi below mean their actual binary64 outputs, not exact inverse
trigonometric identities or mathematical periods.

| Candidate / original branch | Existing reproducible pair and request | Complete oracle or explicit definition gap |
|---|---|---|
| CS-CERT-CONECONE-POSITIVE-PLANE-01 / positiveFullBranch | [Existing input](../../../../Tests/CADGeometryTests/CertifiedConeConeSpatialDifferentialBoundsTests.swift): reference cone(apex:0,axis:Z,halfAngle:stored atan(.5)), parameterized cone(apex:4Z,axis:Y,halfAngle:stored atan(.375)), lowerAngle0/upperAngle stored2*Double.pi; target planeY0. | Definition gap: rounded-cos metric/directions and stored-period T are not bound to exact physical-angle coefficients, the selected positive root and all source UV. Reference UV is numerical projection. An ideal source-pair root set cannot assign public T/incident labels. |
| CS-CERT-CONECYLINDER-POSITIVE-PLANE-01 / positiveFullBranch | [Existing direct input](../../../../Tests/CADGeometryTests/CertifiedConeCylinderSpatialDifferentialBoundsTests.swift): cone(apex:0,axis:Z,halfAngle:stored atan(.5)), cylinder(origin:0,axis:Z,radius1), lowerAngle0/upperAngle stored2*Double.pi; target planeY0. | Definition gap: rounded-cos cone metric, radialV constructed from the stored Double.pi/2 evaluation point, stored-period T and all sourceUV have no exact original-pair correspondence. The regenerated candidate does not establish either tan(atan(.5))=.5 or exact roots. The canonical cylinder-label/physical-cone-root oracle is now fixed in CS-CERTIFIED-CONE-CYLINDER-POSITIVE-01 above; it remains an implementation obligation, not evidence that the current candidate coefficients are exact. This branch is separate from rulingParallelLinear. |
| CS-CERT-CONETORUS-REGULAR-PLANE-01 / regular certificate branchIndex0 | [Existing input](../../../../Tests/CADGeometryTests/CertifiedGeneralConeTorusSpatialDifferentialBoundsTests.swift): cone(apex:0,axis:stored normalize(.05,0,1),halfAngle:stored atan(6)), torus(center:0,axis:Z,R3,r1), certificate constructor maximumSubdivisionDepth24/maximumCellCount65536; target planeY0. | Definition gap: rounded sin/cos cone direction, certificate-interpolated root initialization/refinement and apex guard do not retain exact original-pair branch selection, whole T correspondence or allUV. Point projection supplies current UV. The apexReduction construction is not covered. |
| CS-CERT-PARALLELTORI-REGULAR-EMPTY-01 / regularClosed branchIndex0 | [Existing input](../../../../Tests/CADGeometryTests/CertifiedParallelTorusTorusSpatialDifferentialBoundsTests.swift): primary torus(center:0,axis:Z,R3,r1/2), secondary torus(center:(stored2.2,0,0),axis:Z,R3,r3/2), certificate constructor maximumSubdivisionDepth24/maximumCellCount65536; target planeZ2. | Complete exclusion oracle for this request: primary height is in[-1/2,1/2]; the stored curve position also has Z=(1/2)*sin(angle) throughout its domain. Thus all T are excluded, and roots/XYZ/sourceUV/targetUV/incidents/fibers are all empty. This does not prove positive-contact or original-pair T/UV correspondence. |

The actual [ordinary dispatcher](../../DefaultCurveSurfaceIntersector.swift)
selects certified reduction for the three cone families and the dedicated plane
solver for parallel tori. The spatial-disjointness resolver does not use plane
bounds. These facts select the next observation; they are not observed failures
or accepted empty-publication evidence. For the parallel empty cell, observe
constructor success, certificate-owned kind/branch and the final public complete
exclusion receipt or actual stop. For the cone candidates, first resolve the
exact source/branch/T-to-allUV authority needed to define their complete oracle.
Existing primitive image receipts prove their own image laws only. No new solver
prerequisite is justified by these definition gaps, and none of the other listed
certified variants is removed or marked complete.

##### Certified cone-cylinder ruling-parallel definition gap

[CertifiedConeCylinderSpatialDifferentialBoundsTests](../../../../Tests/CADGeometryTests/CertifiedConeCylinderSpatialDifferentialBoundsTests.swift)
constructs alpha=atan(0.5), cone(apex:origin,axis:+Z,halfAngle:alpha), and
cylinder(origin:(0,0,4),axis:(sin(alpha),0,cos(alpha)),radius:1). Its ordinary
SSI fixture requires the rulingParallelLinear branch. The existing ordinary CS
test uses that curve's own t=1/4 position and normalized tangent to construct the
target plane, T=[0.2,0.3] and subdivision depth24. That target is not an independent
complete oracle. The adapter's actual curve is cylinder-hosted
surfaceLift(.certifiedAnalyticPair), rather than direct
certifiedIntersection(.coneCylinder), and follows the existing certified lift
CS structural solver. The direct certified curve is separately constructible;
its ordinary CS outcome is unobserved.

The source's ruling-parallel admission uses |q|<=quadraticTolerance, while its
linear height law uses h=-c/(2b) without the quadratic term. The current source-pair
UV path projects evaluated XYZ, and the constructor validates four residual
samples. These paths do not issue an exact zero-q theorem or whole original-pair
correspondence. A world plane y=0 with T=[1/8,3/8] is an independent target
candidate, but a canonical linear law's proposed sole t=1/4 cannot yet be adopted
as an original cone/cylinder acceptance oracle. The missing concrete fields are
the exact branch authority and whole-source correspondence for this actual
input, together with a complete oracle under that authority. Runtime remains
unobserved; this static definition gap neither reports a geometric failure nor
authorizes another solver, rounded equality or a prerequisite for other cells.

##### Finite expansion of the remaining acceptance cells

This is the final binding rule for the inventory above, not a second progress
record. A cell is a constructor branch and a consumer contract, rather than an
arbitrary Cartesian product of all shape names. Its status stays unaccepted until
the actual public input, complete oracle, failures and delivery have been checked.
The quantified source law in a row is an independent expected SET, including its
guards and original parameters; a numeric point list is not its substitute.
Instantiation never calls the production source issuer to construct the oracle.
Exact root isolation and sign conditions are allowed in an oracle; an approximate
root, unlabelled implicit curve or an unspecified projection is not.

###### Finite consumer expansion and result oracles

The named inputs above supply original position laws F and C, authored supports
D and J, transports and incident sides. The following six suffixes fix the public
consumer, expected result and remaining implementation for EVERY applicable row
in the source registry below. They are separate cells, even if they share a receipt.
An injective reparameterization uses the explicit forward law, never an assumed
inverse. A relation oracle retains ALL roots of the displayed equations.

| Suffix | Public input and independent whole-set oracle | Current stop and necessary change | Completion evidence |
|---|---|---|---|
| CS | Actual ordinary rich CS of the row's C and the named target plane. Use the explicitly listed isolated roots and contained control. For a surface-only row, use its retained diagonal lift C(t)=F(t,t), t in[0,1], and plane through the row's original origin with normalZ. Expected tuples are exactly t inJ, p inD, F(p)=C(t), and the target plane's exact basis coordinates. This includes every host preimage, not just p=(t,t). | Consume that row's source/DI/lift receipt in ordinary dispatch; the first source capability refusal is STATIC unless a runtime observation is linked above. | Complete equality/selection comparison, all UV, XYZ and image/fiber dimensions; ordinary bare must refuse a continuous result explicitly. |
| SSI | Actual ordinary rich SSI of F and the row's named plane, both source orders, whole support and closed quarter-box restrictions. Expected tuples are exactly the independently displayed F(p)=O+eU*qU+eV*qV with p inD and q in the selected original plane support. Plane coordinates are computed from its sealed original basis, not projected samples. For extruded G_C=(C.x,C.y,v), target planeZ1/2 gives p=(u,1/2), q=(C.y,-C.x). For D_C replace v by H(v), whose unique half-height preimage is v=1/2. | Reuse existing source charts/guards and plane graph compiler; retain the mixed-source owner through L5/L6 and publish it in ordinary SSI. No finite plane cover is invented. | Full chart/branch selection oracle on every retained cell; all incidents, dimensions, order, request and exclusion controls. |
| B | Build the actual face on F with outer unit UV rectangle and inner[1/4,3/4]^2, once-forward pcurve traversal and explicit coedges as in B-COONS-HOLE. Query the row's SSI relation, and additionally the retained curve F(t,1/2). Expected parameter/material result is the untrimmed oracle AND the authored winding predicate at EACH original UV. For the latter curve: closed t in[0,1/4] union[3/4,1], strict t in(0,1/4) union(3/4,1), boundary t in{0,1/4,3/4,1}; all other F preimages must independently pass the same predicate. | Bind actual face/source authority, retained pcurves and general/auxiliary relation layouts. A missing pcurve is the specific producer dependency, not an instruction to reconstruct it in the consumer. | Validated-model Kernel entry, all raw/refined ordinals, both incidence sides, three policies, empty result and retained membership query. |
| S | Actual prepared original-self/embedding query of F over D x D. Expected residual is every ordered pair(p,r) with the independent displayed position law F(p)=F(r), minus ONLY the scoped M5 relations and authored diagonal. For injective G_A/G_Q/D_A/D_Q on[0,1]^2 this is empty; H, periodic, fold and isolated-contact rows use their already displayed nonempty residual formula. | Compile the actual parameter/auxiliary layout and consume checked identity views. General-family refusal is STATIC; do not call a missing proof "no contact". | Whole ordered product comparison, exact scope rejection, nonstructural contact preservation and actual embedding caller. |
| I | Issue the row's applicable period/collapse/join identity, then restrict to the lower half-open scope, symmetrize and compose through the SAME intermediate owner. Use I-DISTINCT-* for distinct owners and false edge/crease controls. Expected relation is the explicit transported structural relation intersected with BOTH requested scopes, retaining role and germ. | Existing affine consumers are retained; nonlinear pullback and declared whole-boundary source proofs must be consumed, with no unchecked initializer. | Positive and false-boundary controls, foreign owner/role, empty/disjoint scope, proof-kind preservation, M6 consumption. |
| X | Publish the CS/SSI/B/S cell's complete relation through the corresponding existing public result. Expected XYZ is the independent row law, with ALL source tuples and auxiliaries retained. Infinite cycles remain integer-index families; image dimension is rank of the displayed position law on each selected stratum and fiber is parameter dimension minus image dimension. | Connect the row's retained geometric owner and existing ordinary caller; missing symbolic output is explicit failure, not finite truncation. | Detached-source/COW readers, unchanged caller resources/cancel, all four lanes, review, coherent commit and latest-main integration. |

These are finite instantiation rules, not a claim that arbitrary equations have
already been solved. A baseline equation-level oracle must be compared against
the complete returned cell selection; checking only returned candidates cannot
detect omitted roots and does not pass the cell. Surface-only CS is supplemental
to its mandatory positive SSI cell, not a substitute for it.

###### Remaining source branch registry

Each registry row uses the concrete constructors and exact position laws already
fixed above. The finite suffix set is part of its ID. "same" means byte-identical
authored child input, not equal sampled XYZ. Only row receipts are dependencies.

| Stable cell prefix / finite variants | Input and complete law binding | Applicable suffixes / first missing receipt |
|---|---|---|
| SRC-DS-GENERAL / A,Q | Existing plane-derivative Coons/Hermite/connector constructors applied to A or Q, endpoints0/1 and planesZ0/Z1; D_C=(C.x,C.y,H(v)). Include each closed cell at nonbinary cut1/3, singleton and outside-support request. | CS,SSI,B,S,I,X; source-owned angular/algebraic position and incident differential proof. |
| SRC-BC-GENERAL / A,Q | Existing corrected Native N(u,v)=(u,0,v), original bottom C and top C+Z, original endpoint connectors, as in the common input section; G_C=(C.x,C.y,v). | CS,SSI,B,S,I,X; retained nonrational correction atlas. |
| SRC-RULED-GENERAL / A,Q,HYPERBOLA | Existing ruled constructor with C and C+Z; G_C. Hyperbola C is the independently specified hyperbolic chart, not a rational replacement. | CS,SSI,B,S,I,X; child position and full nonaffine chart preimage. |
| SRC-COONS-GENERAL / A,Q,HYPERBOLA | Original four-boundary Coons using C,C+Z and exact endpoint vertical connectors. Whole original law G_C. Nonmatching connector direction is a refusal control, not a continuous positive surface. | CS,SSI,B,S,I,X; complete boundary-law source proof and nonlinear transport. |
| SRC-OFFSET-GENERAL / A,Q,PERIODIC / d=-1,0,1 | The fixed G_A, algebraic affine extrusion G_Q and periodic Native tensor inputs. Retain original unit-normal definition and normalSquared>0 guard even at d0. For G_A use the explicit (1+d)C_A collapse law above; G_Q has constant normal determined by the original cross product. | CS,SSI,B,S,I,X; general child differential owner, complete periodic graph family and symbolic XYZ publication. |
| SRC-REVOLUTION-GENERAL / A,Q,JOIN | Existing revolution constructor applied to the common original generator and its fixed closed guide/join variants, axis/origin unchanged. Independent law is axis projection plus exact rigid rotation of the generator's perpendicular component; angle is the original intrinsic/physical law, with every generator preimage and axis fiber. | CS,SSI,B,S,I,X; nonrational generator graph and exact axis/collapse receipt. |
| SRC-DRAFT-GENERAL / POS,NEG,ZERO,STATIONARY,A0,D0 | Fixed curve/wall recipes above, physical theta=+1e-12,-1e-12,0, selected original quadratic root and raw directions. POS and NEG differ by the sign of physical tangent; ZERO uses the actual direct branch. Nonzero STATIONARY and A0 require explicit failure; D0 is the positive constant double-root law defined below, not an invalid-guard control. | Curve CS,X; wall CS,SSI,B,S,I,X; exact physical coefficient/selected-root receipt. Invalid defining guards must fail before publication. |
| SRC-ANGULAR-GENERAL / CYLINDER,SPHERE,CONE,TORUS / INTRINSIC,PHYSICAL,ARC | Existing angular transport constructor, gain1/offset0; intrinsic labels B, physical radians, and physical finite arc[0,1], with reverse gain-1 and offset1. Sphere/cone/torus independent all-UV equations above; cylinder C=(cos u,sin u,v) up to the documented canonical basis. | CS,SSI,B,S,I,X; scalar-field-compatible physical law, support guards, independent periods and scoped collapse. Finite arc acquires no global period. |
| SRC-GUIDE-GENERAL / A,Q,HYPERBOLA / FORWARD,REVERSE | Existing two-child traversal chain with stations0,1/3,1 and the explicit piecewise maps above. For Q/hyperbola use the SAME station maps and original child law. Join sides are independently retained; position agreement does not prove tangent agreement. | Curve CS,X,I; translated ruled/Coons host SSI,B,S,X; child graph plus exact station/preimage and join receipt. |
| SRC-IMPLICIT-GENERAL / PARABOLA,CLOSED,SINGULAR | Existing forward/reverse/split parabola and closed source-pair recipes; singular axes with four independently authored T branches as above. Closed uses its actual retained graph cells/free-parameter anchors, not an invented circular phase. | Curve CS,I,X; lifted/face B where specified; original pair branch/T/allUV proof, and singular source-branch selection for the axes. |
| SRC-LIFT-GENERAL / QUADRATIC,CLAMP,ROUNDED | Existing nonlinear quadratic UV lift, actual Native clamp input and actual rounded-feature document input above. Full source preimage, including both quadratic roots and all knot/seam/pole incidents, is the independent oracle. | CS,I,X and host B,S; original pcurve/host correspondence and complete nonlinear restriction. |
| SRC-COMPOSE-GENERAL / IMAGE,WORD,TRAVERSAL / each preceding non-composition child | Apply existing image U->1-U; axis swap for surfaces; original affine word spatial translation+Z followed by X reflection; traversal first[0,1/3],second[1/3,1] with the fixed station maps. Apply the SAME spatial word to the comparison target. Oracle is the explicit forward transformation of the child's COMPLETE relation, not a new XYZ equality inference. Include two nested applications. | All applicable child suffixes; complete child receipt and checked transport/owner retention only. No new shape formula generator in DI. |

The draft boundary variants are fixed by the actual source quadratic in
[OriginalDraftedCurve3D.ruling](../../OriginalDraftedSection/OriginalDraftedCurve3D.swift).
Use the degree1 Native generator C(T)=(T,0,0), knots[0,0,1,1], forward
OriginalCurveRootSpan3D endpoints0/1, curve height1 and wall heights1/3.
A0 has normalZ, axisZ, pullX and EXACT angle0. Then n.p=0 and A=0;
the source's direct translation branch does not apply because pull!=axis.
The authored quadratic requires A>0, so curve CS and wall SSI must explicitly
report singularGeometry/invalid required coverage, never empty success.
D0 instead has normalZ, axisX, pullZ and stored angle1e-12. Its unit tangent
is X, q=tangent cross axis=0, linear=constant=discriminant=0 and
A=1-sin(theta)^2>0. Both selected roots are EXACT k=0; this is a valid constant
double-root position law, not an absent intersection. Curve position is
(T+1,0,0); CS planeX3/2 has sole T1/2, planeUV(0,0), image0/fiber0.
Wall position is(u+1+2v,0,0); SSI planeX2 has exactly u=1-2v,
v in[0,1/2], planeUV(0,0), XYZ(2,0,0), image0/fiber1, including both
closed endpoints and all original tuples. The current interval ruling rejects
a discriminant enclosure not strictly positive; the missing receipt is a
source-owned identically-zero double-root/position proof consumed by DI and
ordinary CS/SSI. No derivative order is inferred from this position proof.
A negative-discriminant refusal uses the SAME nonzero angle, generatorX,
normalZ, axisZ, pullX: np=0 already violates A>0 and is an A-negative control,
not evidence of a negative D under valid A. No impossible valid-A branch is
invented to satisfy a checklist label.

Discontinuous ruled/Coons ownership is a separate negative input: take the two
degree1 Native guide children C0(t)=(t,0,0), C1(t)=(1+t,1,0), stations0,1/3,1,
with no declared connector. At the join the left limit is(1,0,0), the right
limit(1,1,0). The source may retain two disjoint owned charts, but MUST NOT issue
a continuous whole-surface receipt or positional join identity. If its public
constructor requires continuity, invalidInput is expected. Add the actual
endpoint connector as a separate positive input, retaining its own T interval
and both germs; never fill the gap by a sample or bounding box.

The remaining rolling rail cases form a finite selector expansion. For Native,
parameterImage, affine-word, traversal, endpoint-connector, plane-derivative-curve
and guide selectors use the fixed straight center K(u)=(0,0,u), with rails
K(u)+(3,4,0) and K(u)+(3,-4,0), radius5. Transform center and BOTH rails together
for reversal/word selectors. For retained Native/Coons/correction hosts use
F(u,v)=(u,0,v), and for the derivative host use F(u,v)=(u,0,H(v)); retain affine
and degree1 Native diagonal pcurves, constantU1/2 with varyingV, and constantV1/2
with varyingU. The actual center K is that original lift; both rails are its
original affine-word translations. No endpoint fitting is used. Angular,
algebraic and hyperbolic selectors instead use the actual diagonal lift of
G_A/G_Q/G_HYPERBOLA: K(u)=(C.x(u),C.y(u),u), then the same two translations.
These are different valid authored inputs, not claims that an angular curve equals
a straight line. Polyline uses the fixed straight center split at1/3. The periodic
cylinder offsetSurfaceImage rail keeps its separate actual pullback-producer input.

For every such K the independent blend law is
F_K(u,v)=K(u)+(Rx(v),Ry(v),0), q=5-4v+4v^2,
Rx=(15+20v-20v^2)/q, Ry=20*(1-2v)/q, u,v in[0,1].
When K.z=u or H(u), SSI planeZ1/2 has exactly u1/2, allv; targetUV is
(K.y(1/2)+Ry,-K.x(1/2)-Rx), image1/fiber0. ConstantV host cases use planeY0
instead: K.y=0, v1/2, allu, XYZ=K(u)+(5,0,0). ConstantU cases retain their
constant X and monotone Z/H(Z), rather than inventing a varying X. Each selector
has CS/SSI/B/S/I/X suffixes, retaining all child charts, positive roots and original
half-angle/normalization guards. If a source guard actually fails, report its
required-domain failure, not empty success. A declined selector does not complete
rolling-ball support; only its missing source receipt is a prerequisite.

###### Certified branch expansion and source authority

Keep the five direct certified families and the finite constructor branch enums
listed above. The complete source-pair oracle is independent of regenerated
candidate coefficients. For each original cone let d(theta) be its canonical
unit ruling, alpha the stored physical half-angle, and A its apex. For a sphere
center O/radius R, put a=|A-O|^2-R^2, b=(A-O).d; the exact slant law is
lambda=-b +/- sqrt(b^2-a). For a reference cone axis n and physical alpha put
M=cos(alpha)^2 I-n*n^T. For a second cone use q=d^T M d,
b=(A-O)^T M d, k=(A-O)^T M(A-O), and q*lambda^2+2b*lambda+k=0.
For a cylinder replace M by I-n*n^T and subtract R^2 from k. Signed roots,
q!=0, discriminant sign and original source support are explicit constraints.
For q=0 the linear branch requires b!=0 and lambda=-k/(2b); an approximately
zero q is a REFUSAL control. Every apex lambda0 retains the full original cone U.
Cone-torus uses the explicit quartic/cubic and root ordering above.

For bounded producer-selected endpoints, define L and U as the consecutive EXACT
roots of that independent discriminant/branch-guard equation in the documented
candidate isolating interval, not as the binary root estimates. The source must
issue the uniqueness/ordering proof. Its migrated normalized traversal is
theta=(L+U)/2-(U-L)/2*cos(2*pi*T), root sign positive on T[0,1/2] and negative on
T(1/2,1]. Open traversal uses theta=L+(U-L)*g(T), with g=T for rootFree/double,
g=1-cos(pi*T/2) for lowerSimple, g=sin(pi*T/2) for upperSimple and
g=(1-cos(pi*T))/2 for twoSimple. These explicit migrations apply only to
producer-selected critical endpoints; direct authored physical endpoints and
their B*T law remain unchanged. Full parent SSI includes every ordered real root
and complete primitive UV; it does not depend on the success of a candidate curve.

| Prefix / finite branch inputs | Complete public input/oracle binding | Required implementation / completion |
|---|---|---|
| CERT-SPHERECONE / full-/full+, bounded, open-/open+, apex | Use the fixed rootFree, boundedR2, poleToPole, simpleRootToPole, doubleRootToPole and apexR1 recipes above; both open signs and both endpoint directions. Closed full branch T retains B*T. Bounded/open expected sets use the independent slant law and explicit exact L/U and g. Apex has lambda0 and lambda=-2b, only its declared loop/node intervals. CS planeY0 selects exactly cos(theta)=0 OR lambda0; planeZ2 supplies the independently proved empty control for the apex recipe. | Exact physical coefficients, critical root selection, T and all parent UV; ordinary CS/X and both parent SSI orders. Rounded double/apex premise that is false must be rejected, never labelled a positive branch. |
| CERT-SPHERECONE-ENDPOINT / nine enum kinds | Legal rootFree/lowerSimple/upperSimple/twoSimple/lowerDouble/upperDouble use the preceding recipes, reversal and exact discriminant multiplicity. twoDouble/lowerSimpleUpperDouble/lowerDoubleUpperSimple are explicit constructor-invalid controls, as required by the current constructor guard. | Test each legal branch's complete source correspondence; test each forbidden kind's refusal. A forbidden kind is not a missing positive capability. |
| CERT-CONECONE / full-/full+, bounded, apex isolated/loop/node | Full uses the fixed A4Z/axisY input. Bounded uses A(.51,0,1)/axisY, same angles; exact q,b,k above select all consecutive D>=0 intervals and both roots. CS planeZ1 selects exactly lambda*cos(theta)=0; q!=0 and the original guard decide zero/apex cases. Apex uses actual common apex0 for both cones, then the fixed shared-axis and different-axis controls: lambda0 full angular fibers plus every common ruling of the two exact cones. The old near-apex(2,0,4) input remains a false-premise rejection control. | Exact metric, root ordering, interval/T receipt and apex fiber; parent SSI all roots plus CS/X. Candidate topology kind must agree with exact source or fail explicitly. |
| CERT-CONECYLINDER / full-/full+, bounded, lowerNode,upperNode,linear | Full coaxial oracle and both pcurve roles above. Bounded cylinder(origin(0,0,1.5),axisY,R1); node cylinder(origin(1,0,0),axisY,R1), cone0/Z/alpha:stored atan(.5). Independent cylinder q,b,k selects both roots/consecutive valid intervals and lambda0 endpoint. CS planeY0 is exactly lambda*cos(theta)=0 in the canonical cone basis, retaining all T preimages. Linear uses the actual stored-sin/cos axis input above and requires exact q=0; if false, expected explicit invalid-branch refusal and the parent quadratic SSI remains required. | Original cylinder metric, exact node/root guards and branch/T/allUV; actual certified-lift caller as well as direct CS/X and parent SSI. |
| CERT-CONETORUS / regular branch0..3, apex | Actual tilted cone and torus input above, all four ordered quartic roots. Apex A4X retains lambda0 and ALL real nonzero roots of the displayed cubic, ordered on each exact critical interval. CS planeY0 requires lambda*cos(theta)=0, with full source T preimages and apex angular fiber. | Source-owned selected exact root/cubic branch cover and normalized T; ordinary CS/X and parent SSI all roots. |
| CERT-PARALLELTORI / regular0..3,nodal0..3,near0..1 | Actual offsets stored2.2,2,1.9999; primaryR3/r1/2, secondaryR3/r3/2. Let z=sin(theta)/2, r=3+cos(theta)/2, rho=3+epsilon*sqrt(9/4-z*z), x=(r*r+d*d-rho*rho)/(2d), y=sigma*sqrt(r*r-x*x). Expected XYZ=(x,y,z); guards rho>0,r*r-x*x>=0. epsilon=-1 for branches0/1 and+1 for2/3, sigma=-1 for even,+1 for odd. Regular theta=2*pi*T; nodal theta=base+2*pi*T, base0/pi according to epsilon, retaining every join side. Near theta=L+(U-L)*sin(pi*T)^2, sigma positive on first half and negative on second; L/U are exact adjacent radicand-zero roots around base. CS planeZ0 selects exactly theta in pi*Z with those full T preimages; planeZ2 is empty. Both parent torus UV are the independent atan2 radial/tube arguments plus every integer B lift. | Exact radius/radicand/critical roots, declared traversal and both UV; candidate certificate counts alone are not evidence. Ordinary CS/X, parent SSI and nodal distinct-T control. |

Exact critical root ordering and incidence constraints, including multiplicity,
are the oracle; they must be independently compared with the returned complete
selection. This closes input/expected-set definitions without requiring decimal
approximations of transcendental roots. It does NOT claim that current source
APIs can issue those receipts. Incompatible candidate kinds are explicit failures,
and their corresponding positive parent intersection cells remain mandatory.

###### All pcurve cases and actual boundary callers

The seventeen cases are bound as follows: affine/constantU/constantV/polyline and
originalBSplineContinuation use the existing six equal-side inputs; bSpline uses
the rational quadratic boundary input; originalAffineWord/originalImage/rigidImage/
periodicTranslation use the four directed image inputs; harmonic,
sphericalGreatCircle, projectedAnalytic and BOTH offsetSurfaceImage directions
use the five position-law inputs above; certifiedImplicit uses the closed
implicit face; certifiedAnalyticImplicit uses the fixed sphere/weighted-plane
closed pair; certifiedAnalyticPair uses BOTH cone/cylinder source roles and the
five-family certified expansion. None is dropped by a rational-only port.

For each remaining OPEN pcurve P(t), t[0,1], the concrete boundary input is the
authored P followed by the three exact UV segments P(1)->P(1)+(0,2)->P(0)+(0,2)
->P(0). These endpoint values are original source expressions, not projected or
rounded endpoints. If a segment intersects P, split at ALL exact intersections
and retain every winding cell. The material oracle is the directed winding of
these four explicitly given laws; closed includes winding-nonzero plus boundary,
strict excludes the boundary, boundary selects exactly the four laws. On a sphere
or periodic host apply the same construction in the original lifted chart and
retain all seam/pole preimages. This is the required source-owned endpoint/loop
producer dependency where the current Double-only topology builder cannot express
it; it is not permission for a consumer to invent connectors. The actual validated
model path must consume that producer before B/X is accepted. The closed implicit
cases use their actual single closed coedge rather than this open-arc construction.

Missing-pcurve cells delete exactly one retained coedge pcurve from each such
actual face input. Existing model admission must report the missing correspondence
until its original boundary/lift producer supplies the COMPLETE directed map;
after supply, its material result must equal the retained-pcurve oracle. Positive
producer completion and explicit missing-data rejection are distinct cells.

For B-POLE/APEX/MULTICYCLE, use the fixed physical sphere/cone/torus sources and
the lifted rectangular face construction above. Sphere bounds U[0,4*pi],
V[0,pi/2]; cone U[0,4*pi],V[0,1]; torus U,V[0,4*pi]. Query respectively lineZ,
lineZ and lineX. Expected tuples are their already fixed all-UV primitive oracles
intersected with the CLOSED/STRICT/BOUNDARY lifted rectangles; the polar/apex
edge retains every admitted U, and every incident seam side is retained. Near-pole
V=pi/2-1/8 must never acquire a collapsed identity. The missing receipt is exact
physical endpoint/lift/material authority, followed by general boundary intake.

###### Crosswalk closure and execution order

4-P1..11 bind the source-registry rows and CS/SSI/B/S request suffixes;
5-C1..12 bind their I suffix and distinct-owner/crease/collapse controls;
6-B1..11 bind B plus the seventeen pcurve expansions and missing-data variants;
6-S1..11 bind S plus folded/isolated/trimmed products and the three actual callers;
M7 binds X for every applicable row; M8 binds the twelve cumulative interaction
cells already specified. 6-I1..4 bind the existing Native consumer integration
records and each newly changed receipt prerequisite, not another lower rebuild.
Projected contact binds both existing discrete projected-contact cells and the
continuous producer-bound drawing cell with reversed and zero-depth controls.
The remaining variants are contact dimension0/1, same/different depth, tangent/
transverse screen contact, reversed traversal and distinct original XYZ; use the
independent screen equations (t,0)=(u,0) and (t,0)=(1-u,0), or vertical edge
(1/2,u-1/2) selecting t=u=1/2. A tangential screen edge
(u,(u-1/2)^2) has the sole t=u=1/2 double contact. Heights0/2 distinguish original
intersection from projected contact. The actual document/producer binding remains
the one fixed above; no hand-authored validation receipt is allowed.

Implementation order stays Coons SSI -> rolling SSI -> periodic offset XYZ ->
composed/open identity -> trimmed self -> actual callers -> source/certified
branches -> general boundary/projected contact -> all ordinary/symbolic results ->
M8. Within a prefix, issue its missing source receipt, consume DI/identity/M6 as
applicable, then close X, four lanes, one review, commit and latest main. Do not
wait for unrelated M4 receipts. Earlier "unmapped" inventory text is historical;
this expansion fixes its input/expected-set/dependency/remaining-change fields.
Runtime status is still UNOBSERVED unless the linked cell evidence says otherwise.
No full requirement is accepted by the existence of this mapping.

#### Concrete boundary cells using existing Coons receipts

These three cells use the same exact original constructor, with one public
selection policy per cell. Build the planar four-cell host with
[PolylineAtlasLiftProof.shape(multi:true)](../../../../Tests/OriginalPolylineAtlasLiftVerification/Proof.swift)
and retain its OriginalCoonsSurface3D as the actual face support. The query curve
is the degree-one Native curve with knots [0,0,1,1] and control points
[(0,1/2,0),(1,1/2,0)]. The validated face has one outer loop around [0,1]^2 and
one inner loop around [1/4,3/4]^2. Each loop uses four retained constant-U/V
pcurves in the traversal order of
[M6ExactBoundaryFixtures.rectangle/face](../../../../Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures/M6ExactBoundaryFixtures.swift),
with reversed coedges as in verifyHoleSelections. The face's surface and lifted
edge support must remain this Coons source, rather than a replacement Native
plane. Use the complete curve and surface requests; the authored incidence
relation is (T,U,V)=(t,t,1/2), 0<=t<=1.

| Cell | Public input / exact request | Independent expected public result |
|---|---|---|
| B-COONS-HOLE-CLOSED-01 | The above retained CS relation and validated Coons face through the Kernel face clipping route, selection closed | t in [0,1/4] union [3/4,1], XYZ=(t,1/2,0), original TUV and every retained raw/refined/boundary correspondence |
| B-COONS-HOLE-STRICT-01 | The same exact input, selection strictInterior | t in (0,1/4) union (3/4,1), with the same source/parameter authority; all four boundary values excluded |
| B-COONS-HOLE-BOUNDARY-01 | The same exact input, selection boundary | t in {0,1/4,3/4,1}; outer and inner boundary-span owners retained, with no interior interval selected |

The oracle is the exact unit-square material minus the open square hole on
v=1/2, with the requested inclusion policy. It is independent of the consumer's
winding/refinement implementation. These cells own material/parameter results;
their eventual XYZ publication remains an explicit M7 obligation.

For each cell the reproduced input binding stop is the public
[OriginalExactFaceBoundaryClipping.clip](../../../../Sources/CADKernel/OriginalBoundaryClipping/OriginalExactFaceBoundaryClipping.swift)
input OriginalExactNativeBoundarySource. Its cases accept only Native B-spline
relation collections; they cannot bind this retained Coons graph relation.
The Native control typecheck passes; constructing curveSurface with the actual
issued Coons relation is rejected at compile time. The original Coons face also
passes the actual exact Topology validator, and existing source/DI graph
preparation returns all four pairs. The
[binding-stop receipt](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/B-COONS-HOLE-01-stop/VERIFICATION.md)
owns this initial diagnostic. It does not prove clipping success or any of the
three material output oracles. The Native-only stored-support check and fixed
rational boundary coefficient field are inspected downstream connection limits,
not separately reproduced runtime failures.

The causal path is the existing original Coons/Native curve source issuance,
their DI-bound graph relation, the retained L5 refinement adapter, verified
Coons face-source correspondence, and the Kernel face-bound result. A complete
M4, a new Coons producer, or preparation of unrelated child families is not a
dependency. The policy cells share the relation preparation and immutable face
owner; they retain independent query admissions. Common code changes are one
serialized work unit, and all three public policies must pass before that unit
closes. Applicable scoped identity is consumed only where this actual boundary
requires it; a proof for another source or a global M5 completion is not required.

Reuse the unchanged Native material/Kernel behavior in
[Native consumer intake](../../../../Tests/OriginalNativeConsumerIntakeVerification/CONSUMERS.md)
and the retained Coons graph/source premises in
[Polyline atlas lift verification](../../../../Tests/OriginalPolylineAtlasLiftVerification/VERIFICATION.md)
only within their recorded scope. Neither receipt proves these general Coons
Kernel cells. Their new receipts must bind the concrete public diagnostic,
changed-path success/failure, raw/refined ordinals, source/face refusal, exact
resource boundaries, cancellation and detached-owner queries on the fixed target
lanes, followed by scoped review and latest-main delivery.

PROGRESS.md remains the sole execution/status record. The finite catalog is not
yet exhaustive: remaining family/variant/consumer definitions belong to its
mapping item. The explicitly defined cells do not stand in for missing inputs.
M7/M8 closure requires every applicable cell and the cumulative integration
evidence; historical source-only completions remain internal premises.

### M3 primitive issuer implementation boundary

Dedicated linear and plane covers retain the source-owned whole law/basis and
one identity-coordinate occurrence, with rank zero and full real support. Their
issuer reconstructs source support, verifies the supplied frame's full support
and coordinate meaning, and clips only the requested selection. Empty requests
produce empty incident sets without losing source coverage authority. Dedicated
analytic covers retain the complete polynomial symbolic-coordinate law, genuine
source periods, and collapse receipts. Their cartesian family has one closed
fundamental interval per periodic axis and unchanged nonperiodic source support;
member and incident use exact cycle displacement and return all seam combinations.
At a collapsed fiber the full original coordinate tuples remain represented.
Physical parameter wrappers do not pass this intrinsic issuing port.


## M1 implemented composition

Native and intrinsic sphere covers conform to OriginalChartFamilyQuerying.
The default Native issuer delegates to overloads accepting period, parameter
transport and cover-issuance protocols. Bound-chart issuance separately accepts
the rational source-law and transport protocols. Intrinsic issuance accepts its
source-law and transport protocols. All associated Source, Field and chart
Selection types must match statically. Defaults preserve existing call sites;
there is no existential erasure, global cache, mutable owner or new ledger.

Injected source receipts are checked for the retained source/chart owner and
original coordinate role before composing a result. Native period endpoints and
period length must match the authoritative knot interval; a receipt from another
binding fails even when original values are equal. Generic query tests exercise
zero-rank and independent families, arbitrary-size signed cycles, seam/pole
incidence, malformed cycles and terminal cancellation. Both source and transport
failures propagate through the existing typed failure contracts.

## Finite selected-family query

OriginalFiniteChartFamilyQuerying refines the symbolic query with an explicitly
finite selection operation. Native selectedMembers enumerates each original
positive-span template and the exact integer-cycle ranges whose closed template
can meet an effective request interval. Rational integer ranges are canonicalized
before traversal so disconnected requests do not duplicate an occurrence. The
actual selected image filters strict endpoints and excluded cells, preserving
both selected seam sides. Independent periodic axes form the complete product;
no fixed-width cycle conversion or binary64 estimate is used. Unbounded periodic
selection fails unsupportedSourceProof, while a bounded nonperiodic native support
can clip an unbounded request. Count/storage/work/depth/cancel admission remains
one cumulative caller query. Publication occurs only after all templates finish;
result limits and any unresolved arithmetic invalidate the entire returned array.

### M4 affine child-domain composition

`OriginalAffineChildDomainIssuing` prepares an immutable
`OriginalAffineChildDomainCover` from a retained source command and an existing
child `OriginalChartFamilyQuerying` contract. The parameter-image, spatial-action
and directed-traversal implementations exclusively read their source-owner
protocol. The parent support is the exact affine image of child support; traversal
first intersects that support with the authored directed endpoint interval.
Requests are intersected with support, then pulled back. Every selected preimage
must be covered by the child's effective selection or preparation fails with
`incompleteCoverage`. No root solving, coefficient regeneration or arbitrary
caller-supplied support certificate is involved.

The cover retains the child family, original parent binding, source depth and a
checked affine correspondence. An occurrence retains the child's occurrence and
this parent correspondence restricted to the selected request. Consumers must
intersect the child's occurrence scope with the correspondence's local scope;
the correspondence alone is not the individual chart's support. Member cycles
use original parent axis roles; permutation and gain sign map them to the
child-family cycles without narrowing their integer magnitude. Incident transforms original parent tuples and preserves every child incident,
including both closed seam sides. No XYZ deduplication is performed. A composed
occurrence is not interchangeable with a source law or a geometric solution.

All storage and work use the caller admission; source and correspondence depth
are re-admitted on queries. New output owner/index payloads are admitted while
existing immutable family storage is shared. Zero gains, repeated axes, foreign
child bindings, uncovered pullbacks, invalid roles, exhausted limits and cancel
remain failures. Nonlinear correspondence and non-Cartesian material restrictions
remain M4.P responsibilities, not affine fallback cases. Verification owner:
`Tests/OriginalDomainIdentityVerification/Sources/Fixtures/ComposedDomainFixtures.swift`.

## Sealed finite revolution family consumption

OriginalRevolutionDomainIssuing consumes the source-owned
OriginalFiniteRevolutionLawFamily. The source producer owns whole normalized generator
coverage, original U bounds, exact normalized axis, homogeneous Rodrigues law,
denominator/radial guards and intrinsic period; see
[source issuance](../../OriginalSourceIssuance/DESIGN.md). DI never reconstructs that
shape or accepts a caller-edited receipt array as proof of complete support.

OriginalRevolutionDomainCover retains that family, full authoritative support,
requested/effective selection and every chart side. Occurrences retain the original
family/template index and a checked local-to-authored transport. Template angular
support is the source fundamental period and V support is the original chart range.
Only U can carry an integer lift. Before a map enters bounded authored support, its
exact pullback is intersected with the selected request and template. Empty and
singleton supports keep endpoint inclusion and original two-parameter arity.

Incident queries use exact integer reduction and retain both closed angular seam
sides and every generator knot side. Different parameters/XYZ are never deduplicated.
No root solver, trigonometric sample or new generator coefficient preparation occurs.
The family and all laws are admitted once per top-level query; internal occurrence
construction uses that admitted immutable witness and the same caller budget.
Source/scalar depth, chart/family count, generated storage/work and terminal cancel
apply on every query. The guard remains attached to the retained source law; this
domain cover does not claim an evaluated XYZ intersection or erase collapsed UV.

Independent RevolutionDomainFixtures and actual production revolution handoff own
M4.P.R evidence. Generic/non-rational generators, remaining procedural/non-Cartesian
covers and full M4/M5/M6 acceptance remain separate open obligations. New cover state
is immutable on every target, with no conditional ownership or shared mutable cache.


## Guarded offset domain composition

OriginalGuardedChartFamilyQuerying is the non-Cartesian sibling of the existing
OriginalChartFamilyQuerying contract. It exposes enclosingSupport and
effectiveEnclosure explicitly. These are exact requested Cartesian bounds, not
an unconditional position domain. Member occurrences retain their source-owned
law and enclosing selection. Position/lifted-position incident queries apply
all mandatory source predicates before returning an occurrence or complete empty
result. Consumers must retain the law/guard when constructing a relation; a bound
alone cannot certify material membership or domain exclusion inside the enclosure.

OriginalNativeOffsetDomainIssuing consumes only the sealed
OriginalFiniteNativeOffsetLawFamily from the source owner. Source authority owns
all child charts, differential knot ownership, D/transport-D exclusions, C^2>0,
and q>0 with q^2=C^2. DI owns request/frame compatibility and exact clipping,
complete chart traversal and atomic result-count/cancel publication. It does not
solve for q, regenerate a normal or interpret a sampled offset. The positive root
is an auxiliary source relation; the original parameter domain remains two-dimensional.

Public queries use one admission and retain immutable family/law/frame owners.
A selected tuple outside the enclosing request is excluded by exact bounds; an
inside tuple is excluded only after all retained chart predicates reject it.
Singular fibers remain distinguishable from work/storage/cancel failure. Foreign
frames, malformed tuples/templates, source/transport/chart/depth limits propagate
failure. Only nonperiodic Native child identity UV is currently supplied; generic
child/periodic/nonlinear coverage remains an explicit source-owner obligation.

Verification is owned by OffsetDomainFixtures and the actual production
OriginalOffsetSourceProof domain handoff. It checks signed normal branches,
interior singular exclusion at nonzero and zero offset, owning knot faces,
positive/negative/wrong q, exact empty/singleton clipping, immutable lifetime,
independent resource bounds and final cancellation on success and exclusion.
All state is immutable let or exclusive query-local inout on every target.

## Sealed guide station domain composition

OriginalGuideDomainIssuing consumes the source-owned OriginalFiniteGuideChartFamily.
The source issuer owns complete normalized partition, exact C0 join authority,
all child laws/guards, local support and exact aggregate station correspondence.
DI creates a source-bound authored-scalar frame, clips the requested selection,
and verifies the supplied affine correspondence from retained rational transport.
It uses existing OriginalParameterTransporting and OriginalDomainCoverIssuing
for map restriction/inverse and whole-request coverage; no coefficient producer,
root search or independent source continuity proof is introduced.

Each occurrence retains the whole sealed family, original template index and exact
selected local-to-aggregate map. The cover preserves every original closed join
side, including reversed child parameterizations. It exposes nonperiodic finite
family witness requirements; nonzero cycles fail. Empty requests require complete
source/selection proof. Member/incident/selectedMembers admit the retained source
proof and depths under the same caller ledger and perform final cancellation.
All owners/maps/laws are immutable and shared by COW; generated maps, indexes and
result payloads are admitted once when generated. No shared mutable state, global
cache, target-specific synchronization or unchecked ownership is added.

Verification is owned by GuideDomainFixtures in the independent DI graph and the
actual GuideProof source-to-domain handoff. Test exact non-binary station, reversed
weighted child, both closed join sides, disconnected/open/singleton/empty requests,
retained lifetime, foreign source, inherited scalar-owner checks, malformed tuple/template/cycle, independent
work/storage/chart/source/depth and final success/exclusion cancellation. Generic
non-rational traversal/derivative identity coverage remains outside this capability.

## Sealed retained surface domain composition

OriginalRetainedSurfaceDomainIssuing consumes only the source-owned complete
OriginalFiniteRetainedSurfaceCharts witness. The existing producer owns original
XYZ/D, nonzero-denominator cell authority, identity authored UV and complete square
coverage. DI owns frame compatibility and exact request clipping, preserving every
closed original cell side through existing affine transport and whole-domain cover
contracts. It does not reinterpret a bounding box as a guarded material domain.

The immutable cover and occurrences retain the complete family, original cell
index/law and selected identity UV map. Queries use the same caller admission and
retained causal depths; nonzero cycles, foreign sources, wrong dimensional or
coordinate frames and resource/cancellation failures propagate. Empty success
requires the complete source witness plus full effective-selection exclusion.
No original coefficients are regenerated and no independent relation is solved.

RetainedSurfaceDomainFixtures owns independent public issuer/query coverage for
nonbinary cell cuts, all closed sides, clipped/strict/singleton/disconnected/empty
requests, original laws/lifetime and independent source/transport/chart/family/
work/storage/cancel failures. Actual CorrectionProof verifies the genuine
boundary-correction source-to-DI handoff; derivative surface sources can consume
this same contract only after their source owner issues a complete witness.

## Sealed retained curve domain composition

OriginalRetainedCurveDomainIssuing consumes the sealed complete normalized curve
family from the retained source owner. Original XYZ/D, original cell boundaries,
identity normalized T and complete closed support are the source contract. DI
owns only frame compatibility, exact requested selection and existing map/cover
composition. Each occurrence retains its whole family, original law index and
selected authored T map. Empty success requires full coverage evidence.

The same immutable ownership and admission/depth/cancel contracts as retained
surface composition apply. RetainedCurveDomainFixtures verifies nonbinary cell
cuts, both closed sides, strict/singleton/disconnected/empty requests, original
position/lifetime and independent failure bounds. Actual DerivativeCurveProof
consumes the genuine original Hermite/plane-constraint source witness; generic
non-rational derivative sources remain the source owner's open capability.

## Local source graph/request binding (B3)

The additive OriginalParametricGraphDomainBinding protocol binds one sealed source
position graph to an original requested parameter selection. The issuer checks
shared source provenance, parameter arity, source limits and inherited graph/frame/
selection depth. Its immutable receipt retains both values and is a local relation,
not a claim that this one chart covers the whole request. Complete coverage remains
owned by existing rational and guarded family receipts. NativeExactRelations consumes
this receipt without reinterpreting its source or inventing an inverse transport.

The binder neither solves guards nor turns enclosing rectangles into material
domains. The consumer pulls the original request through the retained forward
rational parameter map and conjoins all position guards and source-owned chart
sides. Nonlinear and many-to-one forward maps do not require an inverse. Work,
storage, source/proof depth and cancellation use the same caller admission.
Behavioral verification belongs to OriginalGraphRelationVerification and includes
foreign owners, empty/closed/strict/disconnected selections and inherited limits.


## Native surface lift domain consumption

The Native lift domain issuer consumes only the sealed complete family from
[source issuance](../../OriginalSourceIssuance/DESIGN.md#native-surface-lift-graph-supply).
It derives the original normalized one-coordinate T frame, checks owner, exact
whole support and authored coordinate meaning, and intersects the request exactly.
Members use the existing `DefaultOriginalParametricGraphDomainBinder`, retaining
T as the only source parameter and U/V as auxiliaries. Lifted incident queries
import every compatible coordinate into the retained field once before exclusion,
reject foreign algebraic fields, and apply every graph equation,
UV chart bound and denominator guard. The selected T enclosure alone never proves
UV/material membership. Closed pcurve knots and surface corners return every
incident owner; equal XYZ or auxiliary coordinates do not merge distinct T.

All new state is immutable and target-common. One caller admission accounts for
new selections/members/results, source and proof depths, chart limits and terminal
cancel, including successful empty selection. Existing child storage and graph
preparation are retained without recomputation. The focused lift verification owns
this source-to-DI interaction. General/periodic lift sources and automatic public
geometric results remain required open work, not a finite API fallback.


## Retained pcurve lift domain consumption

The retained lift issuer consumes the sealed retained-pcurve/Native-surface family
from [source issuance](../../OriginalSourceIssuance/DESIGN.md#retained-pcurve-lift-composition).
Its source remains one normalized T coordinate. UV are auxiliary witnesses, never
new authored dimensions. Frame/source semantics and exact whole T support are
checked before selection; members use the existing graph binder, and lifted
incident queries retain all source equations, UV chart bounds and denominators.
Importable rational coordinates are normalized once, foreign algebraic fields fail
even for empty selections, and all closed tensor sides survive. This additive
retained capability preserves the existing Native issuer and its source semantics.
Focused affine-lift and existing Native-lift fixtures own the changed interaction.
No new solver, shared mutable state or alternate caller budget is introduced.


## Rolling-ball generic child graph domain consumption

Consume the sealed child-graph rolling-ball family from
[source issuance](../../OriginalSourceIssuance/DESIGN.md#rolling-ball-child-graph-composition).
Frame authority and effective selection remain the original UV square. Variable
count follows the actual disjoint child auxiliary layout plus radial/root witnesses;
auxiliaries never become authored axes. Validate and import every query coordinate
before empty selection can short-circuit. Member issuance uses the existing graph
binder and retains every child equation, support/branch guard, source owner and depth.
Exact selections, complete empty results and all closed incidents use the caller's
same admission. No predicate callback, inverse reconstruction or second solver is
added. The existing Native domain capability remains available. The focused generic
rolling-ball verification owns this interaction and Native compatibility.

## Periodic Native surface lift domain consumption

The lift-specific DI issuer consumes the sealed periodic Native lift source family
from [source issuance](../../OriginalSourceIssuance/DESIGN.md#periodic-native-surface-lift-supply).
Its authored frame is one-dimensional normalized T with exact enclosing support
[0,1]. The effective enclosure is support intersected with the request, preserving
open/closed, singleton, disconnected and empty selections. Auxiliary U/V remain
inside the graph's three-variable layout; they do not increase authored dimension.

```mermaid
flowchart LR
 F[Sealed periodic lift family] --> S[Retained Native surface cover and periods]
 F --> T[Authored T frame and exact request]
 S --> I[Every UV incident and exact cycle]
 I --> G[Original source graph member]
 T --> B[Existing graph binder]
 G --> B
 B --> R[Selected relation and original owners]
```

The immutable prepared space retains one full Native surface cover with the
source-issued period receipts, a checked bijection from its chart keys to original
source-law ordinals, the lift family and the authored-T frame. It reuses existing
Native member/incident algorithms; it does not prove periods again or solve the
lift/geometry problem. Issuing another T request shares the same prepared surface
cover and family arrays. No finite selected-members enumeration is used.

The public lift-family querying protocol exposes template count, surface cycle
rank, retained source/request/effective enclosure, explicit member lookup with a
two-axis exact cycle vector, and lifted-position incidents for [T,U,V]. It does
not conform to a source-period family protocol: auxiliary surface cycles are not
periods or identities of T. No T-only method guesses UV, unique inverse or the
finite enumeration of all surface lifts.

Explicit members retain their exact cycle indices, original family and selected
bound graph. Incident queries first validate every coordinate field, including
U/V even for an empty T request. Existing Native incidence supplies every closed
surface side and cycle; each is paired with every original pcurve chart, issued
through the source owner and filtered by the complete original graph conditions.
The existing graph binder retains the exact T request. Hence a singleton seam,
corner or pcurve knot retains all applicable sides, and same-XYZ wrong authored UV
cannot become a position. Empty membership requires exact request/guard exclusion,
not a missing candidate or failed calculation.

All source/proof/transport/chart/family limits, new output and scratch allocations,
work and terminal cancellation use one explicit caller admission. The prepared
space, cover and occurrences are immutable and Sendable on all targets. Occurrences
retain source/period/pcurve owners through their family and graph after preparation
or cover release. There is no mutable shared state, cache, callback or unsafe path.
Foreign frames/owners, malformed indices/tuples, unsupported scalar fields, budget
exhaustion and cancellation propagate the exact lower failure, never empty success.

Verification owner: `Tests/OriginalPeriodicLiftDomainVerification`. Expected seam,
knot/corner counts, exact request sets, wrong UV and huge independent cycle cases
exercise the actual source/DI/binder path. The real lift provider and public point
evaluation are checked using matching retained numerical products. Fixed Native,
ASAN, normal Wasm and Embedded compile/link/runtime validate the changed DI/fixture
boundary with admitted unchanged source/L0/L1 products. Broad CAD/L2-L6 rebuilding
remains prohibited. General lifts and graph CS/SSI/image/fiber publication remain
M4/M7 obligations; this port does not complete those consumers.

## Retained pcurve periodic lift consumption

The existing periodic Native-host lift DI protocols and implementation accept
OriginalLiftSourceReading, including sealed retained pcurves. Native callers keep
their existing signatures and typed child access. Source family pcurveLaws is a
shared immutable view; incidence combines every source law with each checked Native
surface incident and uses the existing graph binder. No new domain formula or
second family consumer is introduced. Source preparation owns complete pcurve
support and coefficient/proof authority; DI preserves the original authored-T
request and all guarded auxiliary U/V cycles. See the
[source contract](../../OriginalSourceIssuance/DESIGN.md#periodic-native-host-with-retained-pcurves).

The same owner/request/field/depth/resource/cancel/lifetime acceptance applies to
Native and retained pcurves. A surface period does not establish a T period.
Verification reuses the original Native domain fixture body with current source
and adds actual affine/constant/reversed/multiturn retained-pcurve paths. General
surface sources, nonlinear correspondence and final CS/SSI/image/fiber are still
separate unfinished obligations.

## Retained atlas host lift consumption

The existing retained-pcurve lift domain issuer/cover accepts the shared sealed
finite lift family with either Native or retained-atlas hosts. Only the source
reading bound widens; request construction, exact enclosure/support intersection,
all-coordinate validation, graph binding, guarded lifted incidence and same-ledger
admission remain one implementation. It never inspects producer cell internals,
infers UV from T, or classifies the T enclosure as material membership. Occurrences
retain the entire source family and both original child laws. Native callers keep
their existing API and typed child access.

The [source owner](../../OriginalSourceIssuance/DESIGN.md#retained-atlas-hosting-surface-lifts)
issues complete charts and guards. Tests/OriginalRetainedHostLiftVerification owns
actual boundary-correction atlas source-to-DI, nonbinary singleton/
strict/disconnected/empty requests, all incident sides, foreign owner/field,
resource/depth/cancel and detached lifetime checks on fixed target lanes. General
nonrational/preimage capabilities and final CS/SSI/image/fiber publication remain
separate M4/M7 obligations.

## Retained host Native pcurve domain consumption

The retained lift domain issuer accepts the common checked lift graph source reader.
Its sealed family may now contain a Native pcurve with authored knot support as well
as a normalized retained pcurve. The original graph producer already transports
normalized T to that support; DI still sees one T parameter and two UV auxiliaries.
No membership/request/guard algorithm changes. Empty queries validate every scalar,
all closed host/span incidents survive, and retained source/graph owners and proof
admission are unchanged. Native-only and retained-pcurve APIs remain compatible.
Source authority and focused verification belong to the
[source component](../../OriginalSourceIssuance/DESIGN.md#retained-atlas-hosts-with-native-pcurves).
M7 automatic/symbolic publication and general nonrational coverage remain open.


### Finite parameter-image and traversal graph consumption

The source-owned relational pullback retains parent T as its parameter and every
child local coordinate/UV as an auxiliary, with a univariate identity parameter
transport. The existing graph binder and rolling-ball domain consumer therefore
retain complete preimages and original guards without a DI algorithm change.
A closed ambient parent support does not imply material membership: source child
bounds, denominator and correspondence equations remain required predicates.
Complete source coverage comes from the sealed finite child family, not a graph
support union. See the [source owner](../../OriginalSourceIssuance/DESIGN.md#parameter-images-and-traversal-over-complete-finite-curve-graphs).
Verification is owned by `Tests/OriginalParameterCurveGraphVerification`, including
all closed incidents, exact singleton/open/disconnected/empty selections and same
caller resource/cancel/lifetime. A diagnosed legacy nested lifted-traversal point
failure remains separate from this parameter-domain proof and blocks that caller's
full acceptance; this additive source/DI handoff does not claim M7 publication.

#### CS-NATIVE-PERIODIC-PARAM-01: unbounded independent Native cycles

This cell owns the existing explicit public source-bound CS parameter query;
ordinary `intersectionResult`, final XYZ/image/fiber publication and other
family/consumer combinations remain separate mandatory cells. The constructor
is `FamilyFixtures.stationary()` and `FamilyFixtures.periodicSurface()` in
OriginalDomainConsumerVerification: degree-one curve knots `[0,0,1,1]`, repeated
control `(1/4,1/2,0)`; degree-one tensor surface knots `[-1,0,1,2,3]` on both
axes, controls `(x,y,0)` for rows/columns `[0,1,0]`, both axes periodic. The source
bindings, original domain spaces and full requests are issued by the existing
Native issuers in one exact rational/algebraic field. Curve support is `[0,1]`;
surface support and request are all R squared, with independent authored periods 2.

The independent complete result is all original tuples
`T in [0,1]`, `U in {1/4+2k,7/4+2k}`,
`V in {1/2+2l,3/2+2l}`, `k,l in Z`. The source image is the constant
`(1/4,1/2,0)`; parameter dimension is 1 per component. Distinct U/V, every
closed incident owner and arbitrary-size signed cycles survive. The oracle is
derived from the two exact affine laws on each Native fundamental axis, with
all integer translates, not a sampled cycle window.

The initial call is `DefaultCurveSurfaceIntersector.exactParameterRelations`
with those full covers, the existing FamilyFixtures domain/cell/topology/count
limits and caller ledger. Its finite occurrence consumer reaches
`OriginalBSplineDomainCover.selectedMembers` and rejects the unbounded periodic
axis with `domain(.unsupportedSourceProof)`. The accepted M0-M3 production proof
already exercises this exact input. Reuse requires the unchanged constructor,
public entry, resolver, selected-members body and bound runtime log; the receipt
in Evidence/CS-NATIVE-PERIODIC-PARAM-01/stop.json records their match.

The missing public capability is a complete symbolic parameter family. Preserve
the finite collection API and add the explicit `exactParameterRelationFamily`
entry, rather than presenting a finite array as the unbounded result. Its sealed
family retains both whole source/request covers, fundamental L5 relations,
original template owners, exact integer periods and per-member request predicates.
Member queries transport original tuples with the retained DI correspondence
and consume the already-resolved L5 relation. No chart-law regeneration, source
repreparation, solve replay, integer enumeration or fixed-width cycle conversion
is a prerequisite. M5 identity exclusion is unnecessary for this cell: all
structurally distinct UV tuples remain in the public relation.

Completion requires the actual public family entry, the independent whole-cell
fundamental oracle and symbolic all-integer coverage, exact request restrictions,
seam incidents/huge signed cycles, typed failure/resource/depth/cancel/lifetime
checks, four fixed target lanes, one scoped review and coherent latest-main
integration. This cell does not complete general M7 dispatch or M4-M8 aggregates.

#### S-COONS-PLANE-01: complete issued-graph self product

| Acceptance field | Frozen contract |
|---|---|
| Original input | `PolylineAtlasLiftProof.shape(multi: true)` supplies the original four-chart planar Coons map `S(U,V)=(U,V,0)` on `[0,1]^2`. Bind it once with OriginalCoonsAtlasSnapshotProvider; prepare its existing retained rational chart/domain/graph family once; resolve the same family against itself as surfaceSurface, all 16 chart pairs. |
| Independent complete oracle | The complete raw original relation is `U0=U1` and `V0=V1` within both original chart domains. Every raw full cell must satisfy the corresponding sign oracle. Subtracting the scoped authored-coordinate diagonal leaves the empty relation on the entire requested product. Closed chart sides/germs remain distinct retained owners. |
| Initial public stop | DefaultOriginalExactNativeSelfContactQuery.contacts accepts NativeExactParametricRelations of BSplineSurface3D. The actual issued Coons graph relation cannot enter that public consumer. The controlled Native compiler rejection and actual all16-pair whole-cell oracle establish this stop in [S-COONS-PLANE-01 stop evidence](../../../../Tests/OriginalPublicAcceptanceVerification/Evidence/S-COONS-PLANE-01/STOP.md). Public residual-query implementation remains open. |
| Causal change | Add a public issued-graph self-contact consumer, consuming existing scoped identity relation views and exact forward original-parameter laws in the actual lifted variable placement; use retained L5/L4 refinement, not a second source producer or equality solve. |
| Required receipts | Existing source/retained rational atlas, exact DI graph binding, complete graph-family relation, scoped M5 authored-coordinate identity and immutable identity relation view. Each is consumed independently of aggregate M4/M5 completion. |
| Evidence owner | Tests/OriginalPublicAcceptanceVerification/CoonsGraphSelfContactProbe.swift and Evidence/S-COONS-PLANE-01; changed-path Native/ASAN/ordinary-WASM/Embedded compile/link/runtime, complete oracle, failure/resources/depth/cancel/lifetime and one scoped review, commit and independent main delivery. |

The public result is a complete residual parameter-contact receipt. This cell
does not certify embedding, complete trim-material selection or migrate the
existing offset/drafted-sheet caller. Those remain separate mandatory cells;
a query-only success cannot satisfy their acceptance. Additional nonstructural
same-XYZ tuples must remain selected unless an applicable scoped identity proves
their exclusion. Missing identity authority, budgets and cancellation cannot
become an empty result. Existing Native and interval routes remain available.
