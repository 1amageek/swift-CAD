# OpenBoundaryLoop

## Purpose and Scope

This component discovers exact open-boundary edge loops in a B-rep body. Its
parent is [CADTopology](../DESIGN.md). It has no child components.

## Responsibilities and Boundaries

It owns face-use incidence, boundary-edge connectivity, ordered traversal, and
the predicate distinguishing a fillable opening from a lone face's outer
perimeter. It does not own
geometry conversion, spline grouping, surface evaluation, stable generated
identity, or viewport presentation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADTopology](../DESIGN.md) | parent | body-owned topology | Defines exact topology authority. | Invalid components are omitted, not repaired. |
| [CADModeling SurfaceFill](../../CADModeling/SurfaceFill/DESIGN.md) | used by | ordered loop containing an edge seed | Converts each exact edge to a spline and builds a sheet. | Three-edge loops are split at certified arc-length positions; four or more edges retain existing vertices as corners. |
| [RupaCore](../../../../RupaKit/Sources/RupaCore/DESIGN.md) | used by | all eligible loops for one body | Publishes loop membership to the viewport snapshot. | Mesh silhouette is not used for membership. |

## Architecture

```text
body shells -> face coedges -> one-face edges -> vertex components -> ordered cycles
```

## Contracts and Invariants

- Count edge uses within the requested body's shells; an edge shared by faces
  is not an open boundary.
- Each returned component is a single cycle with degree two at every vertex.
- A cycle may contain one closed edge or two edges. Geometric surface builders,
  not boundary discovery, own minimum-side or supported-curve restrictions.
- A closed loop is fillable when its body contains multiple faces, or when a
  one-face sheet's entire loop matches an `.inner` trimming loop. A lone
  one-face outer perimeter is not a hole and must not produce a duplicate
  coincident fill.
- Ordered edges are topological references and retain stored-direction
  orientation; no coordinate welding or tolerance-based endpoint matching is
  performed.
- Multiple disjoint loops remain distinct. Invalid connected components do
  not suppress unrelated valid loops.

## Verification and Change Impact

The corresponding `CADTopologyTests` prove one loop, disjoint loops,
seed-relative direction, exclusion of branching/open components, and the
single-face inner-versus-outer fillability rule. Consumers to recheck are
CADModeling SurfaceFill and RupaCore body-display topology.
