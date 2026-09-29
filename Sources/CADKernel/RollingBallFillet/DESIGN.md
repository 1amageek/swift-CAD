# Rolling Ball Fillet Composition

## Purpose and Scope

Child of [CADKernel](../DESIGN.md), with no children. Constructs a complete
solid sewing request from an existing selected edge, without regenerating its
source feature. Current construction domain is an open tangent chain between
one plane cap and finite Bezier lateral charts, with distinct terminal neighbors.

## Responsibilities and Boundaries

Owns treatment ordering, source-face partition composition, terminal closure,
and retention of unaffected shell faces. Geometry owns contact/intersection
certificates; CADModeling owns directed sewing patches. This builder does not
publish a feature, replace a body, or mutate the input model. Existing feature
evaluation must own closed-solid/global validity and replacement admission.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | source extraction, face arrangement, sewer | Existing topology composition owner. | Do not use Boolean recovery tolerance for machining. |
| [Modeling RollingBall](../../CADModeling/RollingBall/DESIGN.md) | depends on | chain resolver, blend and cap patches | Reuses boundary construction. | A patch is not a valid solid. |
| [Geometry RollingBall](../../CADGeometry/RollingBall/DESIGN.md) | depends on | offset contacts and native implicit trims | Retains curved supports and certified correspondence. | Multiple or inconclusive intersections fail. |

## Architecture

```text
Exact input body + selected edge + radius
    -> cap incidence -> ordered tangent chain
    -> original lateral arrangements + blends
    -> temporary support continuation -> terminal neighbor arrangements
    -> trimmed cap + retained source faces + blends + unaffected faces
    -> solid sewing request -> existing sewer -> feature admission (not yet wired)
```

## Contracts and Invariants

- Input must have an exact certificate at the operation tolerance. Modeling-only
  certificates, invalid radii, foreign edges and ambiguous incidence fail.
- Each source face is retained or replaced exactly once. Unaffected geometry,
  face orientation, shell orientation, and original subshape ancestry survive.
- Tangent selection is ordered by the cap's coedges, never dictionary order.
  The initial supported domain requires at least two chain spans and two distinct
  terminal neighbors. Closed chains and a face visited twice fail explicitly.
- Temporary Bezier continuation retains chart coordinates. Its rounding
  allowance is one percent of the modeling distance; retained source faces
  never use the extended support. The initial search window extends the varying
  coordinate of the selected lateral coedge (V for constant-U, U for constant-V)
  and neighbor U/V by one quarter of their finite domain, with no retry or silent
  enlargement. Failure to close inside that window is explicit, not a success.
  The selected coedge must lie on a complete isoparametric chart boundary.
  Terminal retained-side selection belongs to the blend patch builder and is
  independent of intersection traversal direction.
- Terminal partitions must produce exactly two regions and exactly one region
  excluding the removed original corner. Original supports and native spatial
  intersection curves remain authoritative; transferred UV curves are bounded
  correspondence representations, not exact intersection certificates.
- The output contains every retained face of the original shell and declares
  solid topology. No intermediate sheet is returned as a feature result.

## Runtime Flows

Construction is synchronous and fallible. It prepares contacts once per span,
replaces the two endpoint blends with continued/trimmed blends, updates cap
rails, then emits the request. A failure discards all request-local preparation.

## State, Ownership, and Lifecycle

The builder retains immutable source values and ancestry for one request. All
arrays, incidence indices and replacements are local to the invocation. There
is no shared mutable state, global cache, actor, callback or alternate Embedded
storage. Native and Embedded compile the same declarations.

## Failure, Concurrency, and Constraints

Geometry calls use existing bounded intersection/correspondence options. Work
visits each cap edge and source face once outside geometry admission; storage
is proportional to source incidence and emitted patches. Existing source-patch
extraction additionally scans source ancestry for each emitted boundary use;
this component does not claim linear total runtime. Cancellation is checked
between chain/terminal/retained-face operations. Unsupported construction,
missing references and failed certificates throw KernelError; cancellation
propagates. No retry, tolerance widening or planar/mesh fallback is permitted.

## Verification and Change Impact

[InvoluteGearProfileTests](../../../Tests/CADKernelTests/InvoluteGearProfileTests.swift)
owns the native gear composition check. Completion requires a live-source
whole-body request sewn as a closed solid, preserved source surfaces/ancestry,
and typed refusal for invalid selection/radius. Existing isolated contact and
terminal fixtures establish only their respective lower-level contracts.
[RollingBallFilletRequestBuilderTests](../../../Tests/CADKernelTests/RollingBallFilletRequestBuilderTests.swift)
exercises the complete builder on a smaller curved extruded solid, including
untreated face retention, closed sewing, volume reduction and invalid requests.
Its focused continuation check compares swapped UV charts and reversed boundary
directions, including refusal of partial or interior chart boundaries.
Feature publication remains incomplete until solid/global validity, stable
selection, reevaluation and the existing application transaction path pass.
