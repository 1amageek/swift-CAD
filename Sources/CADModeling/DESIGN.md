# CADModeling

## Purpose and Scope

`CADModeling` owns feature-evaluation requests and exact construction policies
for primitive and derived B-rep geometry. It is a child of the [Swift-CAD
package design](../../DESIGN.md) and has no children for this change.

## Responsibilities and Boundaries

[SpatialPath](SpatialPath/DESIGN.md) evaluates the explicit editable spatial
source into one exact B-spline curve and its sampled presentation.

The module owns primitive B-rep topology construction, including the sphere's
analytic surface patches, periodic seams, pole vertices, edge trims, and
surface parameter curves. It does not own the shared pcurve validation rules,
stable signature serialization, evaluation caching, or Rupa project authority.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Swift-CAD package](../../DESIGN.md) | parent | exact source-to-B-rep flow | Places modeling above geometry and below kernel orchestration. | Keep generated topology complete. |
| [CADGeometry](../CADGeometry/DESIGN.md) | depends on | analytic pcurve validation | Supplies the common structural contract. | Do not add a sphere-specific bypass. |
| [CADKernel](../CADKernel/DESIGN.md) | used by | evaluation and stable topology reads | Consumes the generated B-rep. | Stable reads must see every generated subshape. |

## Architecture

```mermaid
flowchart LR
    Primitive["PrimitiveDefinition"] --> Request["Primitive B-rep request"]
    Request --> Surfaces["Exact analytic surfaces"]
    Request --> Topology["Complete faces/edges/vertices/pcurves"]
    Surfaces --> Topology
    Topology --> Kernel["CADKernel evaluation"]
```

## Contracts and Invariants

All-edge fillets retain the original outer bounds and round every edge of a
validated box or circular cylinder. The two domains are told apart by surface
kind, not by topology counts, which are identical: six planar faces are a box,
four coincident cylindrical faces closed by two planar caps are a cylinder.
A box becomes six inset planar faces, twelve quarter cylinders, and eight
spherical octants. A cylinder becomes two inset planar caps, four cylindrical
band quarters, and eight toroidal fillet quarters, a fourteen-face shell with
twenty-eight edges and sixteen vertices. The cylinder frame is derived from the
two caps, so an extrusion that is symmetric or reversed about its sketch plane
is handled like one that starts at it. Construction owns exact curves, trims and
pcurves, not a rounded display mesh. The nondegenerate domain is tolerance <
radius, and for a box radius < half the shortest side minus tolerance. A box
rounds its corners with spherical octants, but a cylinder rounds its rims with
tori whose center circle must clear its own tube, so a cylinder admits twice the
radius < the cylinder radius minus tolerance with twice the radius < the height
minus tolerance. A cylinder is therefore bounded by half its own radius, and a
capsule is outside the domain. Collapsed faces, unsupported topology, and a
radius the torus cannot carry fail before publication rather than during surface
construction. Existing single-edge behavior remains unchanged. Verification
checks volumetric validity, the per-shape topology, analytic volume, unchanged
bounds, exact-source round-trip, tessellation, and invalid radius/target
rejection.

1. A valid sphere creates one solid body with its complete analytic topology:
   eight faces, twelve edges, and six vertices, with pcurves on every coedge.
2. Seam and pole topology is a real part of the B-rep and remains available to
   stable-reference readers. It is not replaced by Mesh or omitted from a
   signature.
3. Primitive construction delegates parameter validity to `CADGeometry` and
   returns typed failure for invalid dimensions or malformed requests.

## Runtime Flows

Primitive evaluation builds exact topology, validates it at the kernel
boundary, and exposes it through the immutable evaluation snapshot.

## State, Ownership, and Lifecycle

Construction values are request-local. The resulting B-rep is owned by the
evaluation snapshot; derived Mesh remains separate presentation data.

## Failure, Concurrency, and Constraints

Construction is deterministic and side-effect free outside its result. It
fails before returning incomplete topology when a required surface, edge,
vertex, or pcurve cannot be built.

## Verification and Change Impact

Primitive tests assert exact topology counts, analytic volume, pcurve presence,
and stable-reference generation for every sphere subshape. All-edge fillet tests
drive a rectangle extrusion and a circle extrusion through the evaluator and
assert the two results the contract above names, plus the typed rejection of a
body that is neither. Changes require rechecking the shared geometry validation,
the stable signature owners, and the `CADIR` all-edge fillet domain statement.
