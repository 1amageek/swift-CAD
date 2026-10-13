# Original Surface Embedding

## Purpose and Scope
Parent: [CADGeometry](../DESIGN.md). Own the symmetric original surface self-contact atlas, local projection contraction and immutable prepared embedding session. No children.

## Responsibilities and Boundaries
Retain one original surface preparation and its finite authored UV domain. Geometry owns original continuity, differential and surface-pair contact witnesses. Consumers own material trim membership and publication. This component has no dependency on Topology, Modeling or Kernel.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original surface values | Neutral original geometry producer | No topology authority is introduced. |
| [Surface Surface Query Admission](../SurfaceSurfaceQueryAdmission/DESIGN.md) | depends on | prepared original self pair | One preparation and caller accounting | Critical and coincident completeness remains with the producer. |
| [Geometry Conversion](../GeometryConversion/DESIGN.md) | depends on | immutable admission | Construction callers borrow the same work and byte owner | No fresh allowance is created. |
| [Original Offset Feasibility](../../CADKernel/OriginalOffsetFeasibility/DESIGN.md) | used by | contact visitor with finite trim proof | Material self-contact composition | Consumers may exclude only whole outside trim boxes. |

## Architecture
```text
original surface + authored UV box + caller admission
    -> one original self-pair preparation + continuity receipt
    -> symmetric complete product atlas
    -> original differential contraction / original cross contacts
    -> full-domain embedding or consumer material-trim admission
```

## Contracts and Invariants
The session derives both self-query operands from one immutable preparation. Source recursion, geometric subdivision and exact algebra caps remain independent. Every atlas visit and lower query uses the supplied live callbacks; an absent byte callback remains absent. A conversion admission overload borrows its exact identity and counters rather than copying an allowance.

On a convex original chart box, a separately issued continuous piecewise-Lipschitz map receipt and outward infinity-norm contraction of `I - C J` strictly below one prove injectivity. A numerical inverse is only a preconditioner. Derivative hulls alone never issue continuity. A proved injective hull excludes the whole parameter pair, including its diagonal.

The atlas covers the complete symmetric product by two closed diagonal children and their one unordered cross pair. No small cell or coincident numerical endpoints prove injectivity. All cross contacts reach the original contact visitor. A full-domain certificate accepts an original implicit contact cell only when an injective hull proves that all its contacts belong to the same UV parameter, or throws self-intersection for a nonempty cell whose two parameter boxes are strictly separated and strictly inside the authored domain. A domain-boundary contact can represent an original periodic seam or declared boundary incidence; numerical parameter separation cannot label it an interior self-intersection. Critical, point, coincident and unresolved overlapping-UV or domain-boundary contacts require their original producer proofs before certification; they fail explicitly in the current partial branch. No absent numerical witness proves contact absence.

## State, Ownership, and Lifecycle

The drafted-sheet projection consumer retains the original wall and its separately
issued coordinate-projection source/DI/full self-product. It excludes only the
checked authored diagonal in unchanged original UV. A completely empty residual
proves original nonstructural contact exclusion by the source-owned projection
inclusion theorem. A nonempty residual is unresolved for original XYZ and must
not reject original contact or certify embedding. Source guard/regularity checks
and final cancellation remain mandatory. This exact path serves both the actual
single-wall package session and Kernel's complete-global-exclusion material case.

The actual feature's unchanged8MiB storage ceiling rejects full decomposition
of its one projected pair (37,312,875bytes in the independent source oracle).
Retain the existing L5 compiled complete symbolic equality predicate instead.
Verify every graph's parameter-to-authored UV map is identity and auxiliary-free.
For each ordered pair, exact division proves the compiled X and projected-Z
equations are nonzero scalar multiples of the corresponding UV differences.
The L5 compiler's retained nonzero-W division theorem preserves those equations
under every source guard. Every selected raw tuple therefore belongs to the
checked M5 authored diagonal. Retain every pair predicate, source/cover owner,
diagonal receipt and inherited depth. Failure to prove this implication is
unsupported, never absence or contact. No cell decomposition or new solver is
added; no scope or allowance is changed.
The session retains immutable original pair, UV domain, policy and callbacks once. No shared mutable counters are introduced; the composing invocation remains their owner on all targets. The atlas reserves its typed DFS payload before allocation. Intersection temporary accounting remains the lower producer's contract.

## Failure, Concurrency, and Constraints
Original source validation, cancellation, resource exhaustion and unresolved contact authority propagate. Historical surface-intersection per-proof limits remain intact and are tightened by an explicit smaller caller spatial cap. No private aggregate ceiling or tolerance widening is added.

## Verification and Change Impact
Deferred behavioral verification must cover regular sheets, discontinuous joins, separated-parameter self-intersections, shared UV interfaces, finite trimmed holes, exhausted work/bytes/depth and concurrent independent invocations. Offset and drafted-sheet consumers must recheck their original authority and publication whenever lower continuity or contact contracts change. Source-only publication of this component does not claim whole-domain implementation completion or runtime verification.

## Exact Native Self-Contact Port

`OriginalExactNativeSelfContactQuerying` adds a public retained-L5 route beside the interval atlas. It consumes a complete `NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>` issued from one shared immutable source binding. It always issues the selected authored-coordinate diagonal, and accepts additional nonforgeable DI identity receipts for chart boundaries, periodic orbits, collapsed subsets and declared incidences. Equal XYZ alone never creates an exclusion.

```text
complete retained Native UVUV family + scoped DI identity receipts
    -> checked original-coordinate affine views for each chart/lift pair
    -> scope membership AND proved affine equality / complete-product identity
    -> NOT(identity union) in the retained L5 polynomial ring
    -> L4 whole-cell pullback refinement, preserving raw cell ordinals
    -> immutable residual contacts + original covers, laws, identities and lifts
```

The consumer retains every raw pair ordinal, including empty refinements. It does not claim an embedding certificate when residual contacts remain; completeness describes exact subtraction of the supplied proved identities from the complete original relation. A missing additional identity leaves its contact selected. A foreign owner, incompatible coordinate semantics, exhausted work/storage/depth, cancellation or incomplete lower refinement throws a typed `NativeExactRelationFailure`; no such path publishes absence or a partial result.

The checked DI views are the authority for affine words and identity constraints. Each receipt's selected left/right scopes are compiled with exact open/closed endpoints and disconnected interval unions in original coordinates. The original-to-local inverse maps are retained for queries; neither raw equality solving nor source law issuing is repeated. Caller L3/L4 limits and the same noncopyable admission apply throughout.

| Invariant | Behavioral evidence |
|---|---|
| Only selected proved identities are excluded | diagonal, seam, collapsed pole and scoped boundary fixtures |
| Nonstructural same-XYZ UV remains | folded surface opposite-UV fixture |
| All chart/lift and raw/refined owners survive | raw pair count and `sourceCellOrdinals` membership checks |
| Failure cannot become absence | foreign proof, cancellation and work/storage/depth refusal fixtures |
| Result owns its source lifetime | query after source value mutation |

The additive exact port depends on [Native Exact Relations](../NativeExactRelations/DESIGN.md), [Original Parameter Identity](../OriginalDomainIdentity/OriginalParameterIdentity/DESIGN.md) and [Original Parameter Transport](../OriginalDomainIdentity/OriginalParameterTransport/DESIGN.md). Existing interval atlas callbacks remain unchanged. Changes to DI views or L4 pullback guarantees require rechecking this exact consumer and its Native behavioral fixtures.

### Latest-main Native intake verification

The independent consumer assembly recompiles the actual Native consumer and its
source/DI/L5 adapters against current independently verified lower modules. It
reuses receipt-bound unchanged Native DTO/validation products; numerical CS/SSI,
Coons construction and cached old DI/L3 consumers are outside that reuse path.
Verification-only imports select these DTOs explicitly, preventing old cached
relation types from satisfying the new consumer signatures. Native and isolated
builds retain identical consumer bodies, immutable owners and failure semantics.
Actual face issuer/Topology acceptance remains separately bound to its retained
source and compiler receipt. No broad CAD production module is rebuilt.

### Authored-coordinate query field

The exact Native self-contact result accepts an optional query field, defaulting
to the prepared source field. Both two-coordinate tuples are validated in full
before visiting any pair, including a completely empty source product. The same
field supplies DI membership, inverse transport and retained refinement lookup.
The folded u=+/-sqrt(2)/2 fixture refutes treating new algebraic coordinates as
foreign ancestor-field values; unrelated fields and insufficient query depth must
still fail. Retained identity scope and original pair ordinals are unchanged.


## Issued-graph residual self-contact port

`OriginalIssuedGraphSelfContactQuerying` and its default implementation consume
complete `OriginalIssuedGraphRelations<S,E,C,S,F,D>` of one immutable source.
They return `OriginalIssuedGraphSelfContacts`, retaining the raw relation, checked
identity receipts and every `OriginalIssuedGraphParameterRefinement` ordinal.
The finite S-COONS-PLANE-01 acceptance contract is owned by
[Original Domain Coverage](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md#s-coons-plane-01-complete-issued-graph-self-product).
This additive port does not certify embedding or migrate interval callers.

```text
complete issued graph product + scoped original-parameter identity receipts
  -> source/field/role/depth admission
  -> authored-coordinate diagonal on retained original request scopes
  -> exact forward rational UV laws in each actual lifted variable placement
  -> NOT(scope AND proved relation), with nonzero-denominator guards
  -> retained L5 whole-cell refinement for each original pair ordinal
  -> immutable residual parameter result; later lifted-tuple membership queries
```

The selected graph parameter roles must be two original surface coordinates;
auxiliary witnesses keep their actual placement and do not change UV dimension.
Import every retained forward-law term in the ordered local-parameter ring,
using the first parameterCount entries of the compiled graph placement, as
DefaultOriginalIssuedGraphCompiler does. Auxiliary coordinates keep their full
lifted placement and raw guards; they are not extra axes of the authored UV
transport polynomial. Never infer an inverse, recover UV from XYZ, assume four
lifted variables or re-solve source equality. Rational scope inequalities multiply by the denominator with its sign
accounted for; identities require all denominators nonzero. Exact affine identity
constraints use cross multiplication. Complete-product constraints apply only
inside their two proved scopes. Missing structural identity leaves contact selected.

Automatically issue the original-coordinate diagonal using each graph's retained
request frame, through the existing checked M5 issuer. Verify source, coordinate
semantics and exact scalar-field agreement for every graph and supplied identity,
including empty scopes. Graph requests remain scoped; no global identity is inferred
from local chart membership. For an empty complete family, still admit raw proofs
and supplied identities before atomic empty publication. Every nonempty graph pair
uses its own diagonal receipt; differing request frames therefore cannot widen scope.

`OriginalIssuedGraphSelfContactRequestReading` exposes the retained cover request
as a protocol requirement. Rational issued covers and guarded Native-offset covers
return their existing immutable request owner. When a family has no graph, validate
this request against the source anchor and reference frame; when both families are
empty, the first cover supplies that reference. Supplied identities therefore keep
the same field and coordinate-semantics checks even without a graph witness.
Nonempty-family admission remains unchanged. This consumer requirement does not
alter source issuing, graph-family storage or the retained L5 relation contract.

All new arrays, imported terms/powers, predicate instructions and result owners
are caller-accounted; the same noncopyable admission and lower cell/topology caps
remain binding. Compile/query scratch is invocation-local; result backing is
immutable Sendable on Native/WASM/Embedded without platform-conditioned storage.
L4 refinement and membership retain their checked raw-cell pullbacks. A membership
query takes a raw pair ordinal and the full lifted tuple, preserving all witnesses.
It validates ordinal, field, dimensionality and proof depth even for empty results.
Entry, processing, final empty publication and subsequent query cancellation are
observable failures. Foreign source/field, wrong roles, exhausted limits and lower
failures propagate `NativeExactRelationFailure`; no partial result is published.

### Reuse of equal residual refinements

The closed-guide seam's prepared query exhausts8,388,608work during ordinal27.
Its single stage trace attributes7,780,513work to27 completed refinements and
only3,724work to repeated raw proof admission. Duplicate canonical raw pairs
repeat full refinement; empty raw selections also reach the existing L4 target
decomposition. No new empty-pullback certificate or lower solver is introduced.

Invocation-local reuse requires both the same sealed canonical raw relation
and a checked equality witness for the entire compiled residual predicate,
consuming the [predicate equality contract](../NativeExactRelations/DESIGN.md#checked-equality-of-complete-compiled-predicates).
The same raw relation is established by the private immutable solver owner
retained by checked canonical/alias pairs; canonical indices alone grant no
reuse. Legacy pairs without that owner continue through the existing refiner.
Original parameter transports, requests and identity scopes participate in
residual compilation. Compile every
actual pair's diagonal/residual and compare its complete laws, instruction
program and domains before reuse. Changed transport or scope therefore cannot
silently inherit another pair's exclusion.

For a proved match, retain the existing immutable L4 pullback in a new wrapper
with the actual raw pair ordinal and raw owner. Keep every original diagonal,
refinement and raw-cell correspondence in original order. Retain the checked
predicate witness and re-admit its depth during later membership. Nonmatching
predicates use the existing refiner under the same caller ledger and lower caps.
No UV tuple, chart incident or nonstructural contact is removed by sharing work.
Charge all comparisons, scratch, witnesses and result wrappers with checked
counts; terminal cancellation or any required refinement failure aborts the
whole result. Complete independent raw/residual/incident oracles and changed
transport/guard/domain/layout controls falsify unsound reuse.

### Domain-proved residual simplification

The changed-algorithm trace confirms all22 same-owner candidates have equal
complete predicates and reuse their pullback. It still exhausts8,388,608work
inside the21st distinct refinement, actual pair42/canonical(6,0), whose original
selection contains3cells. Before that refinement the query uses7,805,460work
and226,517,908bytes. Reuse is therefore insufficient for this fixed caller.

Compile the complete checked identity formula first. An internal simplifier
may prove a constant or affine sign atom over the retained source Cartesian
domains using exact coefficient signs and finite endpoint arithmetic. Its
closed interval enclosure is conservative for open endpoints. Prove an atom
true or false only when its relation holds or fails over that entire enclosure;
non-affine, unbounded or inconclusive atoms retain their original laws. No
selected-cell sample, XYZ comparison, inverse transport or identity outside its
scope participates in this proof. Denominator guards follow the same rule and
remain unless their truth is proved on the whole retained domain.

Fold Boolean literals in the checked postfix formula and omit only laws no
longer referenced by the equivalent formula. Preserve the domains, parameter
and auxiliary slots, raw partition, selection, all49pair ordinals and checked
identity owners. Raw source guards and original equality remain in the retained
L5 relation. The simplified predicate still enters the existing checked L4
refiner; this does not issue an empty-pullback certificate or skip raw admission.
Charge exact arithmetic, comparisons, traversal, scratch and output storage
through the same live caller admission and propagate every failure/cancel.
Record the maximum attained decision depth through a forwarding admission
borrow covering the complete residual compilation and simplification. Each
refinement wrapper, including a reused pullback, retains its actual decision
depth and re-admits it before later membership or an empty return. A pruned
high-depth law must not weaken later admission. This internal history does not
grant an identity or a public unchecked proof initializer.

Direct controls cover exact constant and affine decisions, ambiguous ranges,
open/singleton domains, unbounded and nonlinear preservation, denominator
guards and Boolean dead-law pruning. The complete independent reverse-seam
oracle must then pass under the unchanged8,388,608work/400,000,000byte query
ceiling before changed-path target verification or review begins.

Verification owns the actual original Coons all16-pair diagonal oracle, complete
empty residual, retained raw/refined ordinals, nonstructural folded and auxiliary
controls, scoped/foreign-owner/field refusal, exact and one-less caller resources,
depth/count boundaries, entry/mid/final/query cancellation and detached/COW reader
lifetime on fixed Native/ASAN/ordinary-WASM/Embedded changed-path assemblies.
Receipt-matched existing source/DI/M5/L5/L4 proofs are reused. Changes to the forward
law, M5 view or refinement contracts require only affected upstream checks. Existing
Native and interval paths remain live; their completion is not inferred here.


## Affine image symbolic Native self-contact port

S-IMAGE-PERIOD-01 reaches actual source/DI and transported periods, but the finite
issued-domain binder rejects its full[-3,6]^2 request with incompleteCoverage.
The decomposed Native family also exhausts the fixed 1GiB storage budget on
its 81 raw chart pairs. The added Native compiler port retains all checked L5
equality predicates without requesting topology. The consumer retains that
complete symbolic predicate family, the sealed affine child-to-parent cover and
checked scoped identities.
It does not enumerate cycles, narrow requests or solve the original equality
again. This is a symbolic residual set, not an embedding or global absence proof.

```text
Actual image source + checked affine DI + Native symbolic predicate family
    -> source/field/roles/coverage + injective spatial-action admission
    -> authored parent diagonal + admitted scoped identity relation views
    -> immutable symbolic residual: raw(parent inverse) AND parent requests
                                    AND NOT(union of proved identities)
    -> selected template/cycle and parent-tuple membership using retained L5
```

The public protocol OriginalAffinePeriodicSelfContactQuerying owns preparation;
its default implementation returns OriginalAffinePeriodicSelfContacts. Source is
an OriginalParameterImageSourceReading with Native surface child. Preparation
requires the exact original spatial affine determinant to be nonzero, so original
parent position equality is equivalent to child equality. Singular spatial
images require parent equality graphs and refuse explicitly. Negative/nonunit
parameter gains and axis permutations come only from the sealed affine DI cover.
Raw Native first/second bindings must be the same child owner, field and authored
roles; their selected domains must cover the entire child preimage of the parent
request. A larger raw request is permitted and the parent predicate restricts it.

The result owns the raw symbolic family, parent cover, inverse correspondence,
exact scoped identity views and full template range. For every raw template and
all integer cycles, its denotation is the complete raw equality restricted to
both parent requests minus the authored diagonal and only the supplied proved
relations. Template ordinals retain their raw meaning; no layer copies raw cell
arrays. Membership checks the original parent tuple/field, maps through the
checked inverse, then queries the retained raw member and exact identity views.
Cycle admissibility remains with the source family. No empty-result or embedding
Boolean is inferred from an unvisited family or absent sample.

All owners are immutable Sendable on Native/WASM/Embedded. Scratch and admission
are invocation-local exclusive inout. Preparation, later queries and final
publication use the same caller work/storage/value/coefficient/source/transport
caps and checkpoints; there is no private allowance, retry or fallback. Storage
for the new views, inverse/result and scratch is charged. Foreign owner/field,
insufficient coverage, singular spatial action, exhausted budgets and cancel
propagate NativeExactRelationFailure preserving the original cause.

Verification is owned by Tests/OriginalPublicAcceptanceVerification/
ImagePeriodicSelfAcceptance.swift and its receipt-bound driver. The complete
symbolic-set oracle verifies all retained fundamental templates and the exact
parent transport/identity predicates, including nonperiodic same-XYZ tuples,
negative/mixed cycles, request endpoints, empty selections, foreign ownership,
N/N-1 resources, depth/cancellation and detached lifetime in four fixed targets.
[Native Exact Relations](../NativeExactRelations/DESIGN.md) owns the complete raw
family; [Parameter Identity](../OriginalDomainIdentity/OriginalParameterIdentity/DESIGN.md)
owns proof issuance/decision; [Domain Coverage](../OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md)
owns the sealed full request/preimage. Changes to those guarantees require
rechecking this consumer. Ordinary SSI/XYZ dispatch and singular image families
remain separate uncompleted responsibilities.


## Retained Native self-contact material refinement

`OriginalExactNativeMaterialSelfContactQuerying` consumes a complete Native self
receipt and two face-issued boundary domains, ordered first/second. Source owners,
requests, pair ordinals and retained L5 contexts must match even for empty inputs.
The existing boundary compiler transports both original UV pairs and retains
all raw-scope proofs. The existing self predicate is consumed unchanged, including
its scoped identity exclusions. Their conjunction is refined once against the
retained raw selection; no original equality problem is resolved again.

The immutable result retains the self receipt, both boundary owners, selection
policy and one refinement per raw pair, including empty refinements. Both sides
retain independent all-incident boundary references aligned with that refinement.
Closed, strictInterior and boundary policies apply to each tuple separately.
Same-XYZ nonstructural tuples survive unless either exact material predicate
excludes them. A complete empty material residual can admit this face self-product;
a nonempty residual rejects embedding. It says nothing about distinct faces.

The same caller work/storage/value/coefficient/source/transport allowance admits
compilation, refinement, retained output and later membership. Foreign owner,
role, raw context or incomplete correspondence, resources and cancellation fail
explicitly. Scratch is invocation-local; all retained owners are immutable Sendable
with the same Native/WASM/Embedded contract. S-TRIMMED-FOLD-01 owns the whole-cell
fold/asymmetric-hole oracle, policy/empty/failure/resource/cancel/lifetime evidence.

## Exact receipt consumption by the embedding caller

The next owned caller migration is S-EMBEDDING-CALLER-01. A shared package
preparer owns source/DI/full Native or issued-Coons products and scoped self
refinement for both Kernel offset admission and the actual original embedding
validator. Every requested closed UV box is restricted in original coordinates;
only the authored diagonal is excluded unless additional checked identities are
explicitly supplied. Nonempty residual contact is topologyFailure. Empty contact
is a necessary global condition, not a local regularity certificate: the existing
source continuity and derivative-based local proof remain separate obligations.

The existing word-based RationalAlgebraAdmitting caller is borrowed through the
existing exact bridge. The bridge's updated usage is returned on normal and
throwing exits; no fresh work/storage allowance or scalar/spatial-depth conversion
is introduced. Both embedding validate overloads check terminal task cancellation
after the final proof callback. The shared preparer owns positional source/DI
preparation; differential enclosure work retains the same authored surface and
owns its separate local theorem. Kernel consumes the same Coons preparation.
Periodic/general-source caller migration remains explicitly incomplete.

The pair quota is the square of the admitted chart ceiling. If this mathematical
ceiling exceeds Int.max on a target, use Int.max, the largest representable array
count. Every representable count is already below that mathematical ceiling;
actual count/allocation overflow still fails. Work/storage and source/chart
ceilings remain binding. A 65,536-cell caller with sixteen actual pairs must
therefore succeed on 32-bit WASM as on Native.

Verification owns actual DefaultOriginalSurfaceEmbeddingValidator calls on the
existing four-chart planar Coons and Native fold, original domain restrictions,
attained independent scalar depths, remaining-source/chart refusals, N/N-1 costs,
entry/mid/final cancellation and immutable retained result lifetime. Complete
production metadata/object generation must match the fixed snapshot; an isolated
renamed port does not discharge the real CADGeometry caller obligation.
The planar source attains depth zero on both scalar axes; no negative depth is
invented to claim a one-below refusal. Unchanged lower receipt limits, guards and
foreign-owner refusals retain their existing verification authority.
