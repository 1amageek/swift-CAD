# Native Exact Relations

## Purpose and Scope
Parent: [CADGeometry](../DESIGN.md). Connect the independent L0-L5 foundation to
actual authored B-spline CS/SSI inputs in the existing production module. The
scalar input remains finite, nonperiodic, positive-weight and single-span. The
additive M2 collection accepts every selected positive Native span and finite
periodic lifts. No new production package or module is added.

## Responsibilities and Boundaries
This component owns source/domain protocol composition, checked exact coefficient
transport to L5 and retained query publication. SourceIssuer owns original
homogeneous laws; DomainIdentity owns whole support, request intersection and
chart correspondence. This consumer uses their receipts and does not clip the
same domains again. L5 owns equations and complete parameter topology. Public
`exactParameterRelation` requirements and the existing default intersectors return
a source-bound receipt; this explicit query accepts an L0 admission and lower
limits. Existing `intersectionResult` XYZ representatives, classification and
image/fiber publication are unchanged: parameter dimension does not establish
geometric dimension. The new query does not run the legacy solver or post-process
its roots. Unsupported source coverage is a typed failure, never a fallback.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | Native source types and public intersectors | Actual production integration | Preserve existing numerical APIs |
| [Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | Original homogeneous curve/surface issuers | Exact stored coefficient authority | No fitted map |
| [L0](../RationalBivariateAlgebra/ExactScalar/DESIGN.md) | depends on | Scoped numeric admission, exact import | One exclusive caller ledger | Checked words-to-bytes |
| [L1](../RationalBivariateAlgebra/ExactPolynomial/DESIGN.md) | depends on | Checked ordered construction | Retain final canonical terms | Strict descending slot order and exact nonzero validation |
| [L5](../RationalBivariateAlgebra/ExactParametricRelation/DESIGN.md) | depends on | Compile, resolve and tuple membership | Complete parameter relation | Preserve denominator guards and all UV |
| [Domain and Identity](../OriginalDomainIdentity/DESIGN.md) | depends on | Source-verified covers and selected domain-bound laws | Retains original request/support and correspondence | Current preparation is nonperiodic single-span; full-family and generic injection migration remain open |
| [Source Issuance](../OriginalSourceIssuance/DESIGN.md) | depends on | Validated source binding and original local laws | Shares one source authority with DI | Image-only capabilities do not establish all UV |
| [Verification](../../../Tests/NativeExactRelationVerification/DESIGN.md) | test owner | Full production Core/Geometry | Public Native and WASI routes | No subset build as integration evidence |

## Architecture
```mermaid
flowchart LR
 Q[Existing intersector exactParameterRelation] --> N[Native source and closed request]
 N --> H[Source and domain issuers]
 H --> T[Exact coefficient and domain transport]
 T --> L[L0-L5 complete relation]
 L --> R[Immutable original source and parameter receipt]
 A[One caller admission] --> H
 A --> T
 A --> L
 A --> R
```

## Contracts and Invariants

### Retained surface family against an original plane

`OriginalSurfacePlaneRelations` retains the already issued complete surface graph
family and `OriginalIssuedPlaneGraph`, with explicit source order. Its sealed
resolver compiles each selected chart/plane pair through existing L5 once. Plane
UV may be unbounded, empty, singleton or disconnected; no rational finite chart
or invented inverse is introduced. Pair indices and parameter roles follow the
public order, including plane-first. Both source/DI owners and every auxiliary,
guard and chart incidence live as long as the result.

The resolver borrows the same admission, field and source/chart/cell/topology
limits. Count overflow and any started failure are atomic failures. Array storage
is charged before allocation. It changes no source formula, domain theorem or
L0-L6 solver. The upper geometric owner consumes these retained relations and
does not solve the original problem again. Verification uses the independent
four-chart Coons/whole-plane oracle and reversed-source/request/empty controls
owned by [Coverage](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md).

### Retained lift against the whole original plane

CS-POLY-01's observed public stop and acceptance are owned by
[the coverage cell](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md#public-acceptance-cell-execution).
The additive prepared route consumes an OriginalRetainedSurfaceLiftDomainCover
and an OriginalPrimitiveDomainCover retaining the issued original plane basis.
OriginalPlaneGraphCompiling translates that basis and the exact effective UV set
to an L5 graph with genuinely unbounded UV support. It retains the original
plane cover; it does not fabricate a finite OriginalParametricGraphReceipt.
OriginalLiftPlaneRelationResolving compiles every retained lift template through
the existing graph compiler and solves every selected pair with that plane graph.
It preserves all lift auxiliary equations, guards and original T transport.

Only the sealed issuers construct the new immutable preparations and relation.
The caller supplies the shared coefficient field and the same admission and
existing domain/cell/topology/count limits. Foreign fields, source depth,
missing coverage, cancellation and resource failure propagate atomically.
Disconnected, open, singleton and empty plane selections remain exact. Empty
results retain both source covers and L5 exclusion; there is no legacy retry.
Every new buffer and receipt is charged before allocation, including checked
template counts. Owners and Sendable contracts are identical across targets.
This route's public result and ordinary entry migration are owned by
[geometric publication](../NativeExactGeometricRelations/DESIGN.md).

- Validate input and degree before indexed source access. Count every visited knot
  with the same admission; require one positive span on each entire native axis.
- Import original rational coefficients directly into one shared L2 coefficient
  field. Do not convert coefficients to Double or use tolerance to assert equality.
- Requested bounds are finite ordered stored binary64 values. Clip with exact
  ordering of those values. Out-of-domain selections become L2 empty domains;
  singleton and native closed endpoints remain closed. The original requested
  bounds remain retained even when the effective domain is empty.
- Preserve all selected tuples, closure/incidence and denominator guards. Empty
  success includes L5 full exclusion evidence, never just an empty point array.
- Return source snapshots by value. COW buffers and proof owners survive original
  input release/mutation. One field is shared by both map sources and result.
- All extraction, preparation, import, resolution, result reservation and final
  checkpoint use the same admission. No internal budget defaults/resets exist.
- Explicit caller degree/extension, L3 cell/root and L4 closure/piece/component
  ceilings remain independent. Preparation failure aborts the query atomically.

## Runtime Flows
Validate and admit source -> issue original homogeneous laws -> import exact laws
and clip domains -> compile CS/SSI relation -> resolve L3/L4 -> reserve complete
source-bound result -> terminal cancellation -> publish. Later membership queries
receive their own explicit admission and consume retained L5 receipts.

## State, Ownership, and Lifecycle
Only invocation-local arrays mutate. No shared mutable state, cache, unsafe pointer
or callback owner is introduced. Source snapshot providers validate stored Native data using the same caller
admission. No legacy homogeneous producer or second clipping authority is used.
All published owners and Sendable contracts are identical across targets.

## Failure, Concurrency, and Constraints
NativeExactRelationFailure preserves scalar, root, cell, L5 and original geometry
causes, plus explicit unsupported coverage and invalid request/degree failures.
No caught error is interpreted as empty, absence or applicability fallback.

### Protocol composition destination

The existing public intersector remains the composition root. It supplies matching
source/domain/law protocol conformers to generic preparation, preserving default
public behavior. The preparation implementation consumes the selected cover and
law; it neither reads knots to rederive whole coverage nor creates another binding.
Checked ring import remains its responsibility because the L5 ring has a distinct
owner. Consumer-specific degree/capability checks remain at this boundary.

At main5de88ec1 the helpers instantiate concrete Default issuers and enforce
nonperiodic single-span capability before preparation. The protocol injection and
broader cover-consumption changes described here are planned, not implemented.
On migration, a supported capability must be selected before solving; an admitted
failure aborts atomically. A finite-only consumer rejects a required symbolic
family rather than materializing a guessed window. Family-aware compilation and
publication must preserve every selected chart/lift and complete exclusion.

Only the existing exactParameterRelation path is currently DI-composed. Do not
infer that legacy intersectionResult, boundary clipping, self-contact or L6 image
publication consume DI receipts. Their required contracts and evidence are listed
in the [DI consumer matrix](../OriginalDomainIdentity/DESIGN.md#di4-consumer-acceptance-and-migration-boundary).

## Verification and Change Impact
Compile all production CADCore/CADGeometry sources together and execute public
CS/SSI weighted isolation, contact, continuous overlap, multiple UV, endpoint,
singleton, clipped empty, source lifetime and independent failure/cancel paths.
Use fixed Swift 6.4.0 and matching normal/Embedded SDKs. Reuse unchanged lower
proofs; verify optimized L5 composition in this integrated module. Changes to
coefficient/basis, domain or admission contracts require these owning tests.
This milestone is not completion of the full CS/SSI/seven requirement families.
The integrated checkpoint executes the shared public fixtures and unchanged
legacy public smoke in Native, normal WASM and Embedded WASM, plus the shared
fixtures under Address Sanitizer. All lanes compile the complete production
module inventories; [retained evidence](../../../Tests/NativeExactRelationVerification/VERIFICATION.md)
owns exact source hashes, compiler inputs, runtime logs and proof limits.

## Integration Findings Closed
The complete production build exposed the parent/L0 filename collision and the
old provenance writer's geometric root assumption. Both are handled by their
owning parent helpers and scalar-authority provenance record, with actual tests.
Legacy scalar error normalization is specified by the CADGeometry parent and
IntersectionAlgebra designs; no original mathematical result is substituted.
The full existing public portability proof remains required beside this new path.

## Homogeneous Preparation and Ordered Import
The parameter-only surface path selects its original nonperiodic positive knot
span and consumes OriginalRationalSurfaceHomogeneous. This immutable issuer owns
stored-source validation, native indices/domain and exact Cox-de Boor laws. It
does not prepare interval jets, derivatives, normals or silhouette equations.
The existing differential law uses this same issuer after validating its existing
native token, including periodic translations; its normal/view behavior remains.

Native import consumes the source issuer's four exact homogeneous polynomials
through L1's checked importing contract. No legacy dictionary conversion,
normal/silhouette preparation or separate source reconstruction is performed.

## Domain Receipt Composition
Native single-span/nonperiodic capability is unchanged. The adapter binds a
validated source, prepares its full domain, issues the exact request cover, and
consumes its selected domain-bound rational chart. The published result retains
both covers even for empty selection. Source depth is zero for these direct
snapshots; there is exactly one chart and no family/identity proof. Its fixed
transport word is identity (depth one) followed by inverse (depth two); this is
an adapter construction bound, not a replacement for any caller scalar depth.
All preparation still passes through caller work/storage/depth/cancel admission.

L3 owns its polynomial ring. Import across that distinct ring is an explicit
checked coefficient transfer; domain intervals are consumed as owner-backed
views, preserving emptiness and inclusion. No binary64 clipping is repeated.

Verification compiles the changed production consumer files against fresh
independent lower modules and validated unchanged Native DTO/intersector cache.
This proves this adapter composition, not a fresh build of the whole module.
The cached module premises and runtime artifact are checked against retained
full-production evidence before reuse. Legacy XYZ APIs remain outside this change.

## Verified Issuer Composition
Preparation retains the selected source-law receipt with the L5 map in
NativeExactPreparedMap. curveMap/surfaceMap also return the complete domain cover;
publication retains both covers and keeps both source laws alive through terminal
cancellation. DomainBoundBSplineChartIssuer remains the sole request-clipping
owner. The generic bound-map helper returns its already-issued law; it does not
issue or solve the same relation again. All work/storage/depth/cancel operations
use the existing caller admission. Original source and domain failure wrappers
remain explicit, while scalar admission causes preserve their existing public
classification. Independent source/domain composition verification reuses checked
lower modules and unchanged geometry DTOs without an upper-target build.


## Planned Composition Consumer Migration

Status: finite source/domain map binding, complete pair aggregation and exact original
TUV extraction are implemented. Existing public family receipt migration remains open.
Generic internal composition consumes family source/domain receipts. Existing rational Native public types remain unchanged; algebraic families use their retained original scalar Base.
The [common consumer handoff](../OriginalSourceIssuance/DESIGN.md#composition-consumer-handoff-design)
owns coefficient transport, complete-cover, publication and migration acceptance.


### Complete Issued-Pair Resolution

`OriginalIssuedRelationResolving` owns aggregation of every selected map pair.
It calls the existing L5 compiler/resolver once per pair under the same admission;
it retains both complete covers and all pair receipts. Discrete mode rejects any
positive-dimensional or mixed result before output. Pair and isolated-cell ceilings
are checked with overflow-safe counts. Empty output retains full domain exclusion
or all solved pair exclusions. A failed pair invalidates publication; no alternate
solver is invoked. Exact tuple reconciliation and public numerical/receipt assembly
remain owned by the consuming publisher, and are not established by this aggregate.

The isolated CS tuple port consumes the retained aggregate without resolving any
pair again. It samples only certified zero-dimensional cells, evaluates each issued
source parameter correspondence in the retained selected-root field, and transports
one flat batch of original T/U/V values into the L0 original field. Exact tuple
ordering coalesces only identical original T/U/V triples and retains every chart/cell
incidence. In-place heap ordering allocates no implicit sorting scratch; comparisons
and heap visits consume the same admission. Distinct UV fibers remain distinct. The immutable point owner retains the
complete relation and scalar transfer; numerical XYZ/classification and existing
public family receipts remain responsibilities of the consuming publisher.

Tuple extraction forwards the caller admission through the existing scoped proof
tracker, admits retained effective-domain/component/source-law proof depth, and stores both reached
depth axes on its immutable result. Later parameter access inherits this depth even
when an original coordinate simplifies to a depth-zero rational scalar.

The independent consumer proof executes weighted issued-map construction, complete
domain exclusion, mixed-result rejection, selected algebraic T, native seam
reconciliation and distinct UV at one XYZ. Exact work/storage and both depth axes,
result ceilings and cancellation are exercised on the tuple consumer. These tests
prove the issued contract; they do not establish existing public CS dispatch or
family receipt compatibility.

## M2 Finite Family Publication Contract

The additive `exactParameterRelations` entry consumes source-bound B-spline
covers, retaining their original support, request, effective selection and chart
family. The scalar single-map API remains compatible. The family entry admits
all positive Native spans and exact finite selections over independently periodic
axes. `OriginalFiniteChartFamilyQuerying.selectedMembers` owns exact cycle
enumeration; the consumer never infers periods or clips original support.

```mermaid
flowchart LR
  C[Complete selected covers] --> E[DI finite chart occurrences]
  E --> B[Domain-bound original laws and inverse transports]
  B --> P[Cartesian local interval pieces]
  P --> R[L5 exact relation for every chart pair]
  R --> O[Atomic complete collection with all chart and lift owners]
```

Each occurrence is prepared once. Each disconnected local axis interval produces
an exact Cartesian map piece retaining open/closed/singleton boundaries. Every
pair is compiled and resolved once, including complete empty relation evidence.
The collection retains the bound laws and original/local correspondences beside
each TUV or UVUV relation. Equal XYZ, adjacent sides and closed periodic seam
lifts are never deduplicated. Empty effective source selection returns an empty
collection with both complete covers retained. Unbounded selected periodic
families fail explicitly at DI enumeration, rather than inventing a window.

All enumeration, chart issuance, map import, Cartesian expansion, pair resolution
and publication use one caller admission, caller domain limits and unchanged L3/L4
limits. Caller `maximumMaps` bounds each source preparation and `maximumPairs`
bounds their complete product. L3/L4 ceilings apply to each distinct relation;
the noncopyable admission owns aggregate work, storage, depth and cancellation. Checked counting precedes allocation; partial collections cannot escape
on failure or cancellation. No derivative, normal, legacy solver or L0-L5 change
is needed. Verification builds the actual production CADCore/CADGeometry graph because the
Native surface DTO names the original span/jet owner in its signature. It executes
the new public family entry on actual source snapshots. No other CAD targets are
required. Prior scalar/lower evidence is retained on unchanged premises.

## Issued graph and DI connection (B3-B4)

The additive graph consumer ports compile sealed domain-bound source graphs and
resolve complete finite graph families. Existing issued-map APIs remain unchanged.
No new production module, solver or geometric publisher is introduced.

```mermaid
flowchart LR
  S[Sealed source graph and original parameter map] --> D[DI local graph/request binding]
  C[Existing complete rational or guarded offset cover] --> D
  D --> I[Checked coefficient import and canonical variable placement]
  I --> P[Original request pullback plus every source guard and owning side]
  P --> L[L5 graph pair and L4 existential parameter projection]
  L --> R[Immutable complete family result retaining all input owners and lifts]
```

| Owner | Input | Output and guarantee |
|---|---|---|
| DI | Source graph, original request, same limits/admission | Sealed local binding; source provenance and inherited depth, no whole-cover claim |
| Graph compiler | Local binding, explicit L2 field | One canonical graph with parameters before auxiliaries; exact coefficient import, source guards, chart boundaries and forward request pullback |
| Family preparers | Existing complete issued rational/guarded offset cover | Every required chart compiled once; empty selection retains its complete cover |
| Family resolver | Two complete preparations, query kind/limits | Every original chart pair retained; identical complete solver inputs may share one checked L5 result, preserving projected topology and all lifted correspondence |

The compiler accepts OriginalExactScalarDomain coefficients through checked L2
import. Physical-angle fields and XYZ-only implicit receipts do not satisfy this
capability; protocol conformance is not a coefficient or UV compatibility proof.
Each original homogeneous law and guard is imported once with checked coordinate
placement. Requested interval membership of N/D is encoded by D!=0 and exact
signs of (N-bound*D)*D, so negative denominators and nonlinear/many-to-one maps are
handled without sign assumptions or inverse maps. Axis intervals are disjoined;
axis conditions are conjoined. Infinite ends add no invented finite bound.
Local source support and its owning upper sides are independent solver domains.
Auxiliary coordinates remain unbounded unless the original guards restrict them.

Constant guards are folded only by exact coefficient sign. When the compiler
proves N == D*localParameter and the requested axis has one interval, its
intersection with source support is represented directly in the solver domain;
disjoint support becomes a false predicate. Other maps and interval unions keep
the forward predicates above. The existing scoped admission tracks all reached
decision depths even when these proofs remove a polynomial or predicate.

A prepared graph retains the original DI binding and source receipt, reached
proof depth and L2 field. Family results retain both full covers, every prepared
graph, each exact L5 result and all original parameter maps. Local tuple labels
are not relabeled authored coordinates; the retained forward correspondence is
the authority. Cross-chart structural identity and numerical XYZ publication are
outside this foundation. Auxiliary lift multiplicity is not parameter dimension.

Preparation and resolution use one caller admission, with no budget reset or
legacy solver fallback. Caller maximumGraphs/maximumPairs and existing L3/L4
limits remain separate. Source/DI limits and retained depths are re-admitted on
reuse, including empty results. Checked products precede allocations. Every
unresolved chart/pair or terminal cancellation aborts the whole publication.

Verification: [OriginalGraphRelationVerification](../../../Tests/OriginalGraphRelationVerification/DESIGN.md)
executes actual source issuers, existing DI covers, these public consumer ports and
L5 projection on Native/ASAN/matching ordinary and Embedded WASM. It checks original
TUV/UVUV membership, positive offset branch, nonowning chart sides, exact request
pullback (including negative denominator and nonlinear correspondence), complete
empty/lifetime and independent work/storage/depth/source/chart/pair/cancel failures.
Unchanged lower evidence is reused. Main integration checks the exact verified
inputs against latest main in a separate worktree. Full-seven completion and new
shape publication remain separate.

### Checked equality of complete compiled predicates

A sealed OriginalIssuedGraphPredicateEquivalence retains both complete predicate
owners and the attained exact-comparison depth. Its checked internal issuer
compares variable count, every ordered polynomial term/power/exact coefficient,
every predicate instruction and every domain bound, infinity tag, closure and
emptiness under compatible coefficient fields and the live caller admission.
No public unchecked initializer is provided. Solver-graph equality also compares
parameter/auxiliary layout before consuming this predicate witness. A reused
parameter refinement retains its predicate witness and re-admits its depth on
later membership queries, including empty selection. Arrays and witness owners
are caller-accounted; immutable retained storage and Sendable are uniform across
targets. This contract changes no L3/L4 construction or decomposition operation.

### Invocation-local reuse of identical complete graph inputs

The observed [closed-guide seam cell](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md#s-ruled-closed-guide-seam-01-directed-whole-boundary-identity-candidate)
prepares seven graphs and attempts all 49 ordered pairs. Under its unchanged
caller ledger, 48 pairs complete and the final pair exhausts work during L5
decomposition. Closed station charts include identical prepared solver inputs.
This stop permits a local reuse change in this resolver; it does not change the
source cover, M5 identity, requested pairs, lower solver or caller ceilings.

Reuse requires a checked witness of equality of the entire prepared solver
input: parameter and variable layout, ordered polynomial coefficients, complete
predicate instruction program and every domain endpoint, infinity tag, closure
and emptiness. Every comparison uses the exact coefficient field, with checked
field compatibility and caller admission. Equal XYZ samples, residuals, chart
names, hashes or equal parameter images do not establish this witness. A changed
guard, domain, auxiliary layout or coefficient prevents reuse.

The resolver may solve each ordered class of equal inputs once through the
existing L5 compiler and resolver. Its published pair array still has every
original pair in original order, retaining the actual original preparations,
their maps and all chart incidents. A reused pair retains its checked equality
witness, canonical solver indices and immutable L5 owner; later admission
re-admits the attained comparison depth as well as all source and relation
proofs. Sharing solver work establishes no structural parameter identity and
does not remove UV tuples or chart sides. Each canonical solve has a private
immutable Sendable owner containing its actual L5 relation; checked aliases take
their relation from that same owner. Owner identity is an internal proof of the
same retained solver result. Canonical indices are correspondence metadata only.
Legacy pair construction has no such owner and cannot authorize residual reuse.
Charge the owner payload and allocation header before construction; aliases
retain it without copying lower arrays.
The resolver and a later prepared consumer query are separate explicit caller
operations. Each retains its supplied admission throughout; later queries
re-admit the immutable result rather than resetting a live resolver ledger.

Equivalence scratch, witnesses, output buffers and all comparisons are charged
with checked counts under the same invocation ledger. No global cache or shared
mutable state is introduced. Cancellation, resource exhaustion or failure of a
required pair aborts publication. Focused verification compares the complete
49-pair residual and incident oracle, falsifies reuse with changed guard/domain/
layout/coefficient inputs, and checks retained owners, readmission and terminal
cancellation on the selected Native/ASAN/WASM/Embedded paths. It reuses unchanged
lower artifacts and does not authorize a broad rebuild.

`OriginalIssuedGraphRelationOwning` exposes immutable kind/pair requirements while
retaining the concrete family/source/DI value. Upper exact point values keep this
owner after extraction from a result. This additive protocol changes no relation
construction or lower solve; it avoids a point dropping authored source evidence
when its containing publication value leaves scope.

### Issued graph parameter refinement

`OriginalIssuedGraphParameterRefining` consumes a concrete source/DI-bound issued
collection, a checked pair ordinal, and a predicate over that pair's complete
solver layout. `DefaultOriginalIssuedGraphParameterRefiner` admits the retained
source/domain/L5 proof and refines `relation.projection.original` through L4's
`refinePullback`. Parameters and both auxiliary suffixes remain distinct; a
predicate with a different arity is rejected; L4 validates coefficient-field
compatibility. No original
intersection equations are solved again and no parameter inverse is inferred.

The immutable `OriginalIssuedGraphParameterRefinement` retains the entire issued
collection, pair ordinal and pullback. Each included refined cell has L4's raw
lifted-cell ordinal; excluded cells retain -1 and complete exclusion evidence.
Membership accepts full lifted coordinates with an independent caller admission.
An optional `queryField` supplies an exact descendant of the coefficient field;
omitting it preserves coefficient-field queries. L3 validates that the query
field imports the source coefficients and owns every coordinate. Foreign or
incompatible fields fail explicitly; coordinates are never rounded or rebuilt.
All source/proof admission, coordinate-map/output storage, work and terminal
cancellation use that admission. COW copies share the original buffers. There is
no shared mutable state or target-specific isolation/Sendable branch.

The self consumer may attach an internal attained decision depth to this
wrapper, under its [domain-proved residual simplification contract](../OriginalSurfaceEmbedding/DESIGN.md#domain-proved-residual-simplification).
Membership re-admits that history before any return, including empty results;
legacy/general refinements without that history retain their existing behavior.

This port owns parameter refinement only. Boundary consumers must separately
prove face binding and compile exact material/pcurve conditions; self consumers
must compile only checked scoped structural identity exclusions. Arbitrary input
predicates do not certify material membership, structural identity or embedding.
Projected XYZ/image/fiber publication remains the upper consumer's responsibility.

Verification uses the production component in the independent graph proof target:
a guarded offset source supplies a real auxiliary coordinate; conditions preserve
its positive branch, reject a negative witness and produce complete empty
refinements. A continuous CS component is split at an exact nonbinary boundary.
Raw correspondence, source lifetime, invalid arity, independent resource
limits and cancellation at entry and final publication are checked. Existing
lower source/toolchain/product receipts must match before cached reuse. Repair
verification may regenerate independent lower artifacts under the existing explicit
authorization, without building the CAD production targets; independent
component proof does not replace full production integration evidence.

## M6 Retained Parameter Refinement

Boundary and self-contact consumers add predicates to an already complete L5
selection through `NativeExactParameterRefining`. The implementation consumes the
public L4 `refinePullback` contract with the identity coordinate projection. It
retains the raw relation and the complete refined region, including excluded
cells and the exact raw-cell ordinal of every included cell. No raw equality
compiler/resolver is replayed and no sample classifies a whole cell.

```text
retained L5 selection + new consumer predicate
    -> L4 exact whole-cell pullback
    -> retained raw/refined owners and complete exclusion
```

Caller cell/topology limits and one noncopyable admission own all work, storage,
depth and terminal cancellation. Boundary/self components own their added
predicate semantics and retain their complete Native covers beside this receipt.
Focused consumer fixtures verify branch ownership, empty refinement, membership,
independent resource refusal and source lifetime through their public routes.

### Native refinement reuse during M6 intake

The Native L5 refinement uses the same point-location contract as issued-graph
refinement. `contains` accepts an optional descendant `queryField`, re-admits the
retained raw component and refined region depths, and delegates coefficient and
coordinate ownership checks to L3. Omission preserves coefficient-field queries.
An incompatible field is a typed failure, never exclusion. L4 scalar admission failures
propagate as Native scalar failures, including resource shortage and cancellation. The immutable raw and
pullback owners survive source release; query scratch uses the current admission.
No shared state, unsafe storage, or target-dependent isolation is introduced.

The independent Native consumer intake fixture compiles the actual Native refiner
and result against current L0-L5 contracts. It checks algebraic membership and
exclusion, foreign fields, exact work/storage boundaries, raw/refined ordinals,
entry/terminal cancellation and retained-depth refusal. This evidence owns the
shared adapter only; actual face/self and Topology integration remain separate.


The retained polynomial lift/plane resolver consumes the source-owned checked
polynomial witness reduction described in
[source issuance](../OriginalSourceIssuance/DESIGN.md#polynomial-lift-witness-reduction-for-a-retained-public-query).
Each raw pair retains the original cover, reduced graph preparation and forward
original-coordinate map. Reducing uniquely determined UV is exact transport,
not removal of original UV or a second solve of the same intersection problem.


### Exact affine plane-incidence restriction

A polynomial lift/plane query may restrict local T before L5 only from the exact
necessary plane equation `N dot (Hxyz - origin * Hw) = 0`. A zero equation keeps
the whole requested graph. A nonzero constant proves exclusion. A nonconstant
linear equation has exactly one candidate, derived by field division and retained
with its coefficients. This restriction currently applies only when the retained
original T transport is exactly identity; other transports keep the original
query. For an identity T transport and a higher-degree equation, one exact
division by the full nonconstant homogeneous weight may expose a constant or
linear necessary equation. The existing L5 map retains `Hw != 0`; therefore
`P = Hw * Q` has exactly the same plane preimage on that guarded map. Only an
exactly zero division remainder and a quotient of degree at most one permit this
preselection. A nonzero remainder or higher-degree quotient keeps the original
complete L5 query. Division/resource/cancellation failures propagate.

The sealed restriction receipt retains the original binding, selected binding,
raw equation, original plane owner and attained depths. The quotient is only a
candidate restriction law: the original homogeneous weight, conditions and
binding remain unchanged. Original request/support
intersection and every source guard remain authoritative; a candidate is not a
contact proof. L5 still proves contact, absence or positive-dimensional fibers.
No failed calculation becomes exclusion. Excluded chart queries retain these
complete exclusion receipts even when they generate no raw relation pair.

The existing graph compiler may use an exact selected singleton as its root
domain only after proving identity transport and inclusion in the original local
support with the original endpoint policy. It retains all request and guard
predicates. The whole plane UV support is unchanged. The public-cell verification
must keep the same work/storage/depth/cancel ceilings; this is the causal response
to CS-POLY-01 exhausting work in template 1 after polynomial witness reduction.

After exact domain restriction, the compiler substitutes any closed singleton
parameter into every imported position and predicate law. The substitution is
valid only on that retained domain; it does not assert global source equality.
All predicate instructions, original parameter slots, auxiliary slots, binding
owners and endpoint policies remain present. A guard that becomes false still
proves exclusion through the existing predicate. This avoids projecting a varying
polynomial over a parameter already proved fixed, without a second solve or a
larger admission. The existing identity-domain restriction is reused rather than
duplicated, and non-singleton queries do not allocate a substitution array.

## Symbolic Native Parameter Family

The concrete acceptance input and stop are owned by
[CS-NATIVE-PERIODIC-PARAM-01](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md#cs-native-periodic-param-01-unbounded-independent-native-cycles).
This additive public entry preserves the finite collection API. The new protocol
`NativeExactSymbolicRelationFamilyResolving` accepts the same source-bound Native
covers, caller admission and map/pair/cell/topology limits. The default intersector
composition roots expose `exactParameterRelationFamily` for CS and SSI. The
family owns parameter correspondence and complete symbolic coverage; it does not
assert geometric image/fiber dimensions or ordinary numerical dispatch readiness.

```text
Whole Native covers / retained original periods and selected requests
  -> each fundamental original law once, using the existing chart/map preparation
  -> every fundamental CS/SSI pair resolved once by existing L5
  -> immutable template family + original whole covers and integer index domains
  -> member(original cycles): selected-image conjunction and retained local L5
  -> exact original-tuple membership, with an independent query admission
```

Only the resolver constructs family/template/member receipts. Each template
retains its original first/second source chart indices and the complete
fundamental relation. The family retains the original source/frame, authored
support, request/effective set and period proofs; integer indices have the
existing arbitrary-size OriginalParameterCycle representation. Each member's
selection is exactly the conjunction of its retained L5 fundamental relation
and both selected-image predicates. Exposing a fundamental relation alone does
not assert that every one of its cells survives a partial member request.

Preparation issues full-support covers from the retained domain spaces without
source rebinding or domain decomposition. It prepares exactly the zero-cycle
fundamental template of each source, retaining all closed chart sides. A source
with empty effective selection may publish a family with no templates only
because the retained effective domain proves complete exclusion. Every other
pair must resolve successfully; a resource, coverage or cancel failure is atomic.

At member creation, DI `member` supplies exact original integer lifts and
`selectedImage = lifted chart intersect effective request`. Its full inverse is
retained for coordinate transport. Membership first validates original arities,
field ownership, retained source/transport/value/coefficient depths and owner
limits even for empty selections, then tests both selected images and the
already-resolved fundamental L5 predicate. No inverse is inferred from XYZ;
only the existing proven affine Native DI inverse is consumed. Every query has
entry and terminal checkpoints, including exclusion. Original periods/scopes are
never widened, and no structural identity removes distinct tuples.

Published owners are immutable Sendable with identical target declarations.
Invocation-local arrays and exclusive admissions are the only mutable state.
Checked counts/bytes precede allocations; maps/pairs and source/transport/value/
coefficient depths remain independent. New buffers and member transports are
charged; retained relation arrays are shared. NativeExactRelationFailure preserves
original causes. Foreign fields/templates/cycle layouts fail explicitly. Four
fixed target changed-path checks and finite-family regression own this delta;
unchanged lower/DTO evidence is reused under admitted receipts, not rebuilt.


## Pair-Bound Revolution Axis Intake

The finite `CS-REVOLUTION-AXIS-FIBER-01` observation stops in the ordinary
adaptive path with `invalidVectorLength(0.0)` before publishing its nonempty
original angular fiber. Its source-owned Rodrigues law and complete revolution
cover already exist. A normal-only repair cannot publish this relation.

`OriginalRevolutionAxisRelations` owns one checked axis query, rather than a
complete surface graph family. It retains the actual line graph family, full
`OriginalRevolutionDomainCover`, source-issued axis-section receipt, compiled
local sections and every ordered solved pair. The source contract is owned by
[OriginalSourceIssuance](../OriginalSourceIssuance/DESIGN.md). Its checked theorem
proves that every nonzero-radial original point is outside the exact line axis;
radial-zero points use the same original position with every authored U retained.

```mermaid
flowchart LR
 C[Full original revolution cover] --> A[Checked pair-bound axis intake]
 S[Source axis section and complement exclusion] --> A
 L[Exact original axis-line graph] --> A
 A --> G[Existing local graph compiler]
 G --> P[Existing L5 pair decomposition]
 P --> O[Immutable pair-bound owner]
 O --> U[Shared L6 geometric publication]
```

The intake verifies exact source ownership and scalar compatibility between the
full cover, every section and the actual line. Sections are in family-law order,
with no omitted chart. They keep authored U/V, generator correspondence,
radial-zero and nonzero-denominator guards. The existing DI binder intersects
requests and the existing graph compiler preserves all guards and parameter slots.
The restricted sections are never passed as a complete `OriginalIssuedGraphFamily`
for the original surface. Whole-query completeness comes from the retained full
cover plus the checked axis complement exclusion. No source equation, trigonometric
coefficient or original intersection is regenerated in the consumer.

One caller admission accounts for source preparation, bindings, graphs, pairs,
L5/L6 and publication, with inherited proof and decision depths readmitted.
Every source, cover and intermediate owner remains immutable and retained by the
result. Typed failures propagate; cancellation is checked on entry, during work,
and at final publication, including empty results. No approximate axis test or
fallback is permitted after this producer accepts the exact-axis query.

Verification belongs to the public acceptance cell and checks the whole original
T/U/V set, exact XYZ image and coordinate fiber, all seam/generator incidents,
clipped and empty requests, false/foreign axis inputs, independent resource
limits, cancellation and detached lifetime. Fixed lower receipts are reused;
only changed upper bodies are compiled. Full revolution and M4-M8 coverage remain
outside this finite cell.

## Source-Proved Finite Physical-Phase Plane Relations

For the frozen [angular public cell](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md#cs-angular-physical-arc-plane-01-exact-physical-phase-candidate),
a pair-specific Q(pi) compiler consumes the existing full analytic cover and
checked original plane cover. It internally obtains the sealed
[finite cosine-zero source theorem](../OriginalSourceIssuance/DESIGN.md#finite-physical-cosine-zero-authority)
from that exact cover.law. It proves the complete polynomial identity
normal dot (law.position-origin) = A*C with A nonzero in the original law ring.
Thus the original pair's full intersection is exactly the source theorem's
zeros. No source position law is regenerated by this compiler.

```text
full source cover + whole-phase-zero theorem + full plane cover
  -> whole plane-incidence polynomial identity and unique original UV
  -> exact request membership + all original incidents + transverse proof
  -> restricted singletonT / singletonUV graphs using source/basis values
  -> existing generic Q(pi) L5 compile/resolve -> generic L6
```

For each proved root, the actual plane basis.parameters inverse must succeed
and basis.position must equal the source value exactly. The checked orthonormal
basis establishes that there is no other original plane UV. Effective curve
and plane requests select every tuple; excluded roots retain their exact
selection decision. The dot product of original normal and source derivative
must be nonzero for transverse classification. Each selected graph is a closed
singleton restriction only; it is not a cover of the original circle or plane.
L5/L6 attest these restricted TUV and image/fiber relations, while pair
completeness additionally depends on the retained full covers, whole polynomial
identity, zero theorem and unique-UV proof.

The immutable pair owner retains those authorities and both restricted graphs,
L5/L6 results, all incidents/ordinals, exact points and attained decision depth.
Construction and readmission use the same caller ledger, including all scratch
and output buffers, source/transport/field depths and terminal cancellation.
Readmission checks the retained cover template/family counts and admits every
retained curve and plane incident through its existing parameter transporter;
scalar proof depth alone does not admit transport depth. A depth2 retained
incident must reject maximumTransportDepth1 and accept its exact depth2 bound
without reconstructing charts or repeating the source zero decomposition.
OriginalPiScalarDomain is used directly; existing fixed-field issued graph APIs
and lower L0-L6 implementations are unchanged. Source/field/owner/role/coverage,
resource and cancel failures propagate through the existing typed failure ports.
No partial or empty success substitutes for a failed completeness proof. The
[public consumer](../NativeExactGeometricRelations/DESIGN.md#finite-physical-arc-plane-publication)
owns ordinary entries and numerical representatives. The public-cell fixture
owns exact two-root/empty/request/incident/dimension behavior and changed-path
failure/resources/cancel/lifetime evidence across the four fixed target lanes.

## Certified Apex Empty Pair Binding

For CS-CERT-SPHERECONE-APEX-EMPTY-01, OriginalCertifiedApexPlaneExclusion
retains the [sealed source separation theorem](../OriginalSourceIssuance/DESIGN.md#certified-apex-whole-support-plane-separation)
and exact original domain selection. It owns no position/configuration formula
and calls no L5 solver for an already proved empty pair.

```text
sealed source/plane separation receipt
  -> existing generic T frame -> request intersection authored support
  -> existing plane domain issuer -> actual UV support/request/effective
  -> immutable complete-empty pair owner
```

The checked internal factory accepts the source receipt and public requests.
It obtains source, field and closed support from the receipt, binds the actual
source through DefaultOriginalParameterTransporter.frame and existing
selection/intersection, and issues the plane cover only from receipt.plane.
Callers cannot substitute a different plane, source law or unchecked predicate.
The owner retains authored T support, requested/effective T, full/requested/
effective original plane UV cover and the proof owner. Empty or singleton
requests preserve their exact selection meaning. Whole-source separation implies
empty tuples, incidents, image and fiber for every effective request. This does
not assert a nonempty source graph, identity, host UV relation or global equality.

Source/plane receipt readmission and each retained selection depth/finite
endpoint use the same ledger and exact field. Existing plane basis/cover
source/transport/chart/family limits remain enforced. No fake identity transport
is introduced to admit a selection, and no source/domain decomposition is
repeated. Immutable owners and new output/scratch payloads are charged before
creation; depth/storage/work/cancel/overflow failures propagate.

The [public producer](../NativeExactGeometricRelations/DESIGN.md#certified-apex-empty-publication)
consumes this complete-empty owner. Verification binds the fixed ordinary input,
exact source/plane/request ownership, closed support intersection and every
retained bound, including foreign binding, empty/singleton/support-external
requests, attained depths and exact/one-less resources. Detached sources and
independent admission readers must retain the same proof without reconstruction.

## Complete original curve graph families

A sealed `OriginalCompleteCurveGraphs` value owns complete original authored T
coverage and every guarded auxiliary position graph. The additive complete-curve
family bridge retains that entire value together with the same-owner DI request.
It reads the source proof, checks authored scalar arity and owner correspondence,
binds each actual graph with `DefaultOriginalParametricGraphDomainBinder`, and
uses the existing issued graph compiler. It never fabricates a rational-chart
cover, promotes auxiliary coordinates to authored parameters, or reissues source
equations. The result retains both complete family and request even when empty.

```text
sealed complete original curve graphs + same-owner authored T request
    -> checked retained cover -> existing graph binding/compiler
    -> issued graph family -> existing L5 CS relation
```

CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01 retains its original five-variable
`[T,firstU,firstV,secondU,secondV]` graph and consumes the source-issued checked
one-T reduction. The source reduction substitutes every original equation,
denominator and guard and retains a bijective forward map to all four original
host coordinates. Its complete-family coverage is the sealed reduction receipt,
including the unreduced graph and proof history. The consumer never regenerates
or eliminates source equations.

The initial seven-variable materialized CS attempt exhausted the unchanged work
allowance in L3 decomposition. Materializing that layout was an implementation
choice, not the all-original-UV requirement. The selected solver now combines
reduced T with Native U/V using existing L5's three-variable graph route. The
complete original host fiber is represented by the retained exact source
bijection, not fabricated seven-variable CAD cells. L5/L6 preserve all selected
TUV cells and original image/fiber semantics; auxiliary dimension never becomes
authored dimension. Geometric publication restores exact `(T,hostUV4)` through
the existing forward-coordinate publication hook. One admission owns all proof
readmission, binding, compilation, solving and publication work/storage/depth/
cancellation. Unsupported coverage fails explicitly. Later proof reads receive
their own explicit admission and readmit retained history.

For CS-IMPLICIT-SPLIT-DYADIC-PARABOLA-PLANE-01, the source-owned finite
coverage contains reductions in actual stored-cell order. Each evidence retains
its original cell ordinal, closed global T support and checked local-parameter
polynomial. The source owner proves the complete closed cover and exact shared
host correspondence at the seam. The family bridge compiles every graph in that
same order without filtering empty requested bindings. It preserves authored T
as the sole parameter and does not regenerate local/global parameter laws. Raw
pairs therefore retain the actual first-graph index and both seam incidents;
collection proof history and every original five-coordinate graph remain retained.

The source-owned complete-family theorem and its unique position/host lift
authority are assumptions from [Source Issuance](../OriginalSourceIssuance/DESIGN.md).
The finite family consumer also accepts the source owner's checked single-cell
reversed triangular capability. Authored T remains the graph parameter; the
source reduction owns the decreasing host-coordinate law and total T derivative.
The consumer uses the same binding and coordinate-restoration contracts for
forward and reversed traversal. Reversed multiple-cell, closed and other implicit
capabilities remain outside this limited admission.
[Geometric publication](../NativeExactGeometricRelations/DESIGN.md#implicit-curve-publication)
owns the ordinary selector and certified numerical compatibility. Verification
must inspect complete reduced raw/lifted cells, retained full source graphs,
checked forward bijections and complete empty exclusion, not only witness samples, and must exercise owner/depth/resource/cancel/lifetime boundaries.

## Implicit host-plane empty pair binding

`OriginalImplicitHostPlaneExclusion` owns complete empty CS authority from the
[sealed whole-host separation receipt](../OriginalSourceIssuance/DESIGN.md)
and the exact original requests. Its field is `OriginalExactScalarDomain` and
its source is the actual `OriginalImplicitCurveSnapshot`; it requires no positive
implicit parameterization, graph reduction or L5 decomposition.

```text
actual implicit source + sealed whole Native-host/plane separation
    -> authored T frame -> requested/effective T
    -> existing plane domain issuer -> requested/effective original UV
    -> immutable complete-empty pair owner
```

The internal checked factory retains the receipt's exact source, field, closed
support and plane basis. It uses the existing parameter transporter and plane
domain issuer, including their owner/arity/semantics checks. A missing public T
range selects the authored full support; explicit outside, empty or singleton
requests retain their actual requested and effective domains. Whole-host
separation excludes every original common-root position, hence all requested
tuples, incidents, images and fibers. This is no assertion of a positive host UV
parameterization or nonempty implicit graph.

The same caller admission reads the source theorem and every retained selection.
`maximumCharts` must cover the actual stored cell count both at issuance and
readmission; source, transport, plane chart and integer-family limits remain
active. The owner retains the entire attained proof depth, including discarded
selection arithmetic, and later reads admit that history before any empty return.
Scratch/output/owner storage, work, exact arithmetic, overflow and cancellation
remain charged and failures propagate. All retained state is immutable Sendable;
mutable counters and depth maxima are invocation-local on all targets.

[Geometric publication](../NativeExactGeometricRelations/DESIGN.md#implicit-host-plane-empty-publication)
consumes this authority. Verification must use the actual closed implicit source,
whole/requested domains, source/host/plane ownership, complete exclusion theorem,
cell/depth/resource boundaries, cancellation and detached independent readmission.

## Rolling graph intake for finite plane SSI

The rolling family preparer consumes the existing complete rolling DI cover.
Each retained original chart is reduced by the source-owned checked auxiliary
reducer, bound to the same effective request, and compiled with the existing
issued graph compiler and caller ledger. Coverage retains all original charts
and the reduction evidence retains every auxiliary lift; no chart or source
position is reconstructed by this consumer. The checked section owner in NativeExactGeometricRelations consumes this
family and retains its complete coverage receipts.

Charts with an exactly false constant substituted original guard are excluded
before L5, with their full reduced/original receipts retained in family coverage.
Surviving graph ordinals map explicitly to original template ordinals. This
avoids decomposing already-proved empty charts; it never treats a failed guard
evaluation or unresolved reduction as exclusion.
## Symbolic surface predicates

`NativeExactSymbolicSurfacePredicateCompiling` exposes the existing checked L5
compiler's complete surface-pair formula without requesting cell decomposition
or connected components. Its immutable family retains both authored covers,
every fundamental chart pair and the complete unbounded integer index domains.
`NativeExactSymbolicSurfacePredicateFamily.member` retains exact lift inverses;
membership evaluates the original three cross-multiplied equalities and both
nonzero homogeneous weights after exact selected-domain admission. Compilation
and evaluation use the same caller admission. A predicate family proves a set
description, not emptiness, connectedness, dimensions or embedding validity.

The consumer in [OriginalSurfaceEmbedding](../OriginalSurfaceEmbedding/DESIGN.md)
uses this representation when only a symbolic residual and membership are
required. Existing decomposed Native relation APIs are unchanged. Verification
owner: `ImagePeriodicSelfAcceptance.swift`, including all 81 actual pair laws,
unbounded cycle controls, resource boundaries and detached result lifetime.

## Certified coaxial cone-cylinder selections

The three coaxial cone-cylinder cells consume the source-owned selected root
and intrinsic cylinder traversal from [SourceIssuance](../OriginalSourceIssuance/DESIGN.md#certified-coaxial-cone-cylinder-root-and-traversal).
`OriginalCertifiedCoaxialCurveSurfaceRelation` retains that binding, the original
T support/request/effective selection, the target binding and both UV selections.
For the declared X-directed planeY0, the source theorem supplies the complete
quarter and three-quarter roots. The DI consumer only restricts those tuples.
For the retained cylinder, it retains T and an arbitrary integer cycle with
U=B*(T+n), V=height. Independent integer indices retain every cone and cylinder
parent UV; they are never inferred from XYZ.

```text
Selected original root/traversal -> exact DI request intersection
    -> plane finite tuples OR cylinder integer-indexed interval relation
    -> immutable public reader -> ordinary/prepared CS result
```

Cylinder emptiness is decided by exact integer existence in
[U.lower/B-T.upper,U.upper/B-T.lower], with incident endpoint inclusion.
Positive dimension requires positive-length T and U intervals and strict overlap;
singletons are retained as zero-dimensional solutions. The relation predicate
retains holes and open/disconnected requests without enclosing-box substitution.
All publication and subsequent queries use the caller admission, source depth,
transport depth, chart/family limits and terminal cancellation checkpoint.
Owners and field values are immutable and retained after input release.
Verification belongs to `CertifiedCoaxialPublicAcceptance.swift`; it checks both
selected roots, empty/singleton/open restrictions, enormous positive/negative
cycles, all parent UV, foreign fields, exact resource boundaries and lifetime.
This closes only the named coaxial cells, not the other certified variants.

## Certified sphere-cone mixed exact coordinates

The checked source snapshot retains original physical theta=B*T, the full
cosine-zero theorem and both selected radicals. The consumer retains a Pi-field
curve support/request/effective frame and a separate algebraic physical-angle
plane frame for each root. These fields are not coerced to one rounded field.
It restricts complete source tuples against target UV, retaining every root
ordinal and source owner. Whole unbounded target axes require ownership admission,
not an unnecessary sign query on an already certified real coordinate. Finite
endpoints use exact algebraic comparisons; unresolved comparisons remain failures.
All cone/sphere integer labels and the canonical symbolic latitude accompany
the isolated result. This owner solves no original problem again.

### Cone-cone cardinal contact selection

Consume the sealed original two-angle full-branch source theorem without
re-solving the original pair. Existing Pi-valued DI frame owns T[0,1], exact
request/effective, open/singleton/disconnected selections and all root ordinals.
Retain the actual planeX0/origin0/uZ authority and binary64 target box separately.
Each constant coordinate's certified enclosure proves inclusion/exclusion; an
undecidable finite-boundary guard fails unresolved, never empties the result.
No synthetic common field is assigned to the two source-angle owners.
Immutable coordinate descriptors retain complete parent slants, integer lifts,
source/branch/ordinal/owner and proof depth. Readmission checks all retained
scopes and limits; source preparation is not repeated by retained queries.

For both sphere-cone and cone-cone selected-ordinal owners, admit each actual
output payload before append. Do not reserve unadmitted slots for empty/partial
selection; complete empty retains no speculative ordinal buffer. Full and empty
N/N-1 work/storage fixtures verify this shared output-ownership invariant.

### Certified role lift and existing affine transport

Consume one retained coaxial relation through the checked source-owned affine
child-window chart and local-r frame. Existing DI affine/inverse/selection
operations retain exact support/request/effective and all preimages. Child
contacts are filtered only by that window and local request, then ordered by
local parameter, including reversed closed endpoints. The raw child relation
and parent/local correspondence remain owned by the result. No original problem
is re-solved by retained membership/UV queries. Both parent UV are forwarded
from the same child receipt; a selected lift UV is a view of that output, not a
new projected/merged tuple. All wrapper/child owners, transport and request
proof depths are readmitted before every query. Full/empty storage and final
cancel are part of publication; no speculative output reservation is allowed.

The lift retains transportDepth2: direct affine correspondence depth1 and its
checked inverse/pullback depth2. Readmission rejects depth1 even when only the
forward map is queried. Fixture expectations admit the actual depth2; caller
source/value/coefficient/transport ceilings are unchanged.
