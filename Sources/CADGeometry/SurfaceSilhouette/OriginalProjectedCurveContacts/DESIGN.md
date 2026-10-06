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
