# Original Projected Native Curve Contacts

## Purpose and Scope

Parent: [SurfaceSilhouette](../DESIGN.md). This child owns original rational native
edge versus original rational native silhouette screen coincidence. It has no
children. Runtime owns whole-face visibility and forward LOS depth ordering.

## Responsibilities and Boundaries

The supplied original screen frame, owning native edge span and closed range,
original silhouette branch and its exact trim endpoints are authorities. Screen
coincidence is distinct from physical XYZ incidence. The screen origin cancels
from the two equality laws; the original horizontal/vertical binary coefficients
remain exact. General analytic and normalized-word support is outside this initial
native producer contract and must never use rounded tensor substitutes.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SurfaceSilhouette](../DESIGN.md) | parent | Original zero law, branch/chart and exact trim endpoints | Supplies original silhouette | UV roots must belong to the actual selected branch |
| [RationalBivariateAlgebra](../../RationalBivariateAlgebra/DESIGN.md) | depends on | Q[u,v] exact division, complete plane atlas and retained real field fibers | Eliminates edge parameter and lifts actual real contacts | Resultant zeros alone are never contacts |
| [OrthographicCurveProjection](../../OrthographicCurveProjection/DESIGN.md) | depends on | Original immutable frame coefficients | Supplies screen axes | Same original frame must survive upper publication |

## Architecture

```text
original edge H(s)/W(s) + original surface H(u,v)/W(u,v)
 -> screen X/Y equality in Q[u,v][s]
 -> fraction-free original coefficient-ring elimination of s
 -> complete F(u,v)/elimination incidence
 -> retained actual common real s fiber + both original screen equations
 -> exact native edge cuts / overlap sectors -> Runtime original LOS ordering
```

## Contracts and Invariants

Every coefficient is constructed from original homogeneous coefficients and frame
bits. Sylvester/Bareiss operates in Q[u,v], with exact polynomial division and
pre-admitted typed matrix slots. No coefficient interval is promoted to equality.
For isolated UV incidence, both screen polynomials are specialized in the retained
original UV field, their common real fiber is isolated and original closed edge
range and branch membership are checked exactly. An extraneous resultant root
has no common real fiber and yields no contact. Endpoint exclusions, multiplicity,
source span and achieved depths survive native edge partitioning.

For positive UV loci, ambient Q(u,v) GCD is insufficient: the common fiber lives
modulo the original locus. Its leading-degree/critical partitions and complete real
section lifting must precede publication of continuous projected overlap. Partial
fiber coverage cannot publish a complete event-free sector or empty result.

## State, Ownership, and Lifecycle

All polynomial buffers and retained field owners belong to the invocation. The
same SurfaceSilhouetteUsage controls work, typed retained storage, source traversal,
UV/root subdivision and the independent coefficient algebra cap. No allowance is
created for resultant, lifting or clipping.

## Failure, Concurrency, and Constraints

Budget and cancellation propagate before allocation or cell visits. Unresolved
branch membership or positive-dimensional fiber authority fails explicitly;
projection-only roots and unsupported domains never become physical contacts.
Result construction is atomic: only a complete closed original edge partition
may authorize Runtime visibility classification.

## Verification and Change Impact

Deferred behavior must cover original endpoint/tangent contacts, projection-only
contacts with unequal depth, complex extraneous resultant roots, positive overlaps,
constant projected edges, disconnected source branches and exhausted same-ledger
allowance. Native producer source implementation alone is not full D1 completion.

### Finite incidence publication

The public producer returns a complete partition only after original UV incidence
is finite and every actual real edge fiber and branch inverse is exhausted. Exact
edge cuts are compared in retained ordered fields; equal native values share a cut
while distinct UV/branch incidence remains separate. Open sectors retain exact
endpoint expressions and have no screen coincidence with this supplied branch.
A whole-native-range fiber is an explicit projected overlap, so it never creates
an event-free sector. UV coordinate singleton domains are constrained by their
original rational coordinate equations; adjacent floating bounds are isolation
localization only and never replace the exact authored singleton.

A positive-dimensional UV incidence cannot return this finite partition. Its
source branch remains marked until locus-quotient fiber and real-section cover are
implemented; this limited successful family is not whole D1 completion.

The positive-locus preparation now retains the quotient common fiber and its
projection in (original u, original edge s). Section specialization at a retained
(u,s) root solves the ORIGINAL locus plus both screen equations for actual real
v, using one ordered-field owner. Both source coordinate bounds and edge range
are exact sign constraints. Complex projection fibers cannot become contacts;
a whole transverse fiber is retained explicitly instead of choosing a v value.
Complete section continuation and edge-sector assembly remain mandatory before
this preparation may publish the finite partition contract.

At each isolated edge fiber, original homogeneous edge and surface values are
evaluated in the same retained real tower and divided by their original positive
weights. Their difference dotted with the original frame normal is retained as
an exact depth expression. Its sign is edge-minus-silhouette depth only, not
foreground visibility. A whole edge fiber has no selected edge parameter and
reports that capability explicitly. Contact refinement returns retained new UV
and scalar endpoint depth receipts; increasing precision must retain that value
instead of restarting isolation at the original broad bounds.

### Original section projection events

A quotient common fiber is square-free in its original separate edge parameter
modulo the retained UV component. Fraction-free quotient division records every
leading denominator exception. Source U stations include the original UV
discriminant/leading/boundary equations, edge fiber discriminant/leading equations,
closed edge endpoint equations and stationary edge-coordinate derivative equations.
Every nonconstant projection is an exact resultant; nullification retains an
explicit unresolved dimension rather than an inferred absence. Complete station
lifting consumes these events before section continuation. These retained cuts
alone do not authorize branch clipping or a complete public partition.

A native transverse boundary or edge endpoint whose original equation vanishes
identically on the retained component is an explicit whole-boundary section. It
is retained separately from isolated critical projections; its vanishing does
not authorize empty coverage or omission of the corresponding closed branch.

Original trim endpoint expressions are transported through the original normalized
free image, cusp polynomial map or retained regular strict-transform chart. The
resulting native free-coordinate values join the same source projection cuts.
A ramified forward endpoint solves only its original unique transverse graph at
the supplied exact free value, verifies original local membership and composes
its original UV maps; it never inverts a rounded native point.

Direct queries and source visitation borrow `OriginalQueryExecution` and retain/attach the issuing persistent contribution handles defined by the [parent execution contract](../DESIGN.md). Original root, source parameter, branch and coverage laws remain unchanged; no callback or copied allowance re-establishes admission.

### Pair Construction and Partition Frame Ownership

The Curve3D partition entry enters the same silhouette query context and first
constructs its original projected polynomial pair on the composing execution.
Only after that complete pair exists does a non-inlined private helper execute
the original post-pair equation, isolation, real-fiber, cut/contact and sector
publication body. The helper retains the same pair, edge, range, span index and
silhouette owners; it introduces no array materialization or additional source
preparation. The BSpline convenience entry keeps its existing nested context and
Curve3D delegation.

```text
same query-context scope -> original pair construction
  -> non-inlined original post-pair partition body -> atomic partition
```

Every original expression, allocation/debit, guard, cancellation point, ordered
field owner, typed failure and publication order remains unchanged. The enclosing
context stays active across both phases. This separates simultaneous stack-frame
scratch lifetime only: pair construction no longer suspends a live post-pair
solver frame. No mutable stored state, target condition, callback, budget or owner
cycle is added. All targets keep the same source and inout execution contract.

The concrete normal-worker stack estimate was 529,888 bytes with the old
169,632-byte Geometry partition closure suspended during pair construction.
Source inverse stitching must reconstruct the complete old producer byte-for-byte.
Root owns fresh Native prologue and the same actual Drawing/resource/cancellation
execution; source equivalence or compile success alone does not prove the caller
fits its worker stack or that all projected families are complete.

### Single Original Pair Ownership at Publication

A published partition retains its complete immutable original polynomial pair as
its sole source authority. `originalEdge`, `originalSpanIndex`, `nativeRange`,
`silhouette` and `frame` are read-only computed views of that pair. They do not
store a second Curve3D, silhouette traversal or frame. The only construction site
builds the pair from the same edge/span arguments; its rational curve law retains
the complete original curve through Native, rigid, affine and original-word
construction, with the original span index unchanged. The pair directly retains
the exact requested edge range, silhouette and projection frame. Every existing
public getter therefore returns the same original value and lifetime as before.

```text
complete original pair
  -> immutable public source views
  -> contacts / cuts / sectors retained in the partition
```

The private post-pair helper keeps its original ordinary immutable pair argument
contract for repeated fiber reads. The partition initializer consumes its
pair/array arguments into the result at publication. No heap wrapper, array
materialization, new source receipt or duplicated stored field is introduced. Contact/root/fiber/cut/sector
algorithms, order, cancellation and typed failures are unchanged. The existing
single `RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedPartition)`
remains at the same publication point and charges its actual new stride. Removed
duplicate source payload bytes are not charged as if still stored; no previously
accepted debit is refunded and no ceiling is raised.

All getters are immutable on Native, WASM and Embedded. Existing value/COW owners
keep the same original source alive through publication and later reads; there is
no shared mutable state, callback cycle or target-specific ownership branch.
This is a public source-value-preserving layout change, not a new identity law.
The component has no public memberwise initializer, Codable representation or
frozen-layout contract. Root rebuilds dependent clients and owns the unchanged
seven-oracle source/read/resource tests and actual Drawing caller gate.

The concrete prior publication chain reserved 546,336 bytes before external
runtime overhead, including the 99,616-byte result initializer beneath the
147,248-byte post-pair helper. Removing redundant result payload and passing
last-use ownership directly addresses those copies without another helper frame.
Actual new Native prologues and caller behavior remain required; source layout
reasoning alone is not a stack-fit success claim.
