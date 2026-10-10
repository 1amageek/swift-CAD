# GenericShape

## Purpose and Scope

This component is a child of [CADTopology](../DESIGN.md). It owns the T1 common
input abstraction for standalone vertices, edges, open or closed wires, faces,
shells, solids and heterogeneous compounds. Its public operations extract the
selected ownership closure, validate it, traverse its subshapes and apply exact
rigid transformations. Boolean and feature-specific dimension combinations
belong to B3/B4 and consume this abstraction through its public contract.

## Responsibilities and Boundaries

`ShapeRepresenting.shapeSnapshot()` acquires one immutable `Shape` containing
its root selection and `BRepModel` together. `Shape` is the concrete value and
returns itself. `ShapeOperating` defines common
operations and `DefaultShapeOperator` supplies their implementation.
`ShapeReference` preserves dimensional root identity; a wire owns an ordered
list of `ShapeEdgeUse` values, independently of face-local `Loop.role` and
pcurve ownership.

The component does not weaken `BRepModel.validate`: that existing contract
requires body-owned shells and all referenced descendants. Standalone topology
uses its own selected closure. Face and shell validation temporarily adapts that
closure to the existing sheet-body validation path; synthesized adapter owners
are never returned or persisted. Solid validation uses the original body's
material-component and cavity contract. Compound means aggregate selection;
Face-connected solid collections retain explicit interface metadata owned by
[SolidComplex](../SolidComplex/DESIGN.md). Common operations preserve that root
and its cell-local identities instead of silently flattening it into a compound.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADTopology](../DESIGN.md) | parent | B-rep incidence and validation | Stores topology referenced by the shape. | Body ownership remains strict. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | Curve/surface validation, parameter-preserving rigid images | Supplies exact geometric representations. | Chart transport must preserve pcurve lifts. |
| [CADModeling](../../CADModeling/DESIGN.md) | used by | Common Shape input and selected topology closure | Subsequent dimension-specific operations use the same input abstraction. | T1 does not establish Boolean domain coverage. |

[SolidComplex](../SolidComplex/DESIGN.md) owns the face-connected root contract;
this component consumes its public validation contract and retains all interface
IDs through extraction and rigid images.

## Architecture

```mermaid
flowchart LR
    Root["ShapeReference: vertex / edge / wire / face / shell / solid / compound / solidComplex"] --> Provider["ShapeRepresenting"]
    Provider -->|"One atomic shapeSnapshot acquisition"| Shape["Immutable Shape: root + model"]
    Shape --> Operation["ShapeOperating"]
    Operation --> Closure["Selected descendant closure"]
    Closure --> Validation["Wire/edge invariants or existing B-rep validators"]
    Closure --> Traversal["Deterministic subshape traversal"]
    Closure --> Transform["Rigid image + pcurve chart transport"]
```

## Contracts and Invariants

- Every common operation acquires exactly one immutable snapshot of a valid
  provider. Extraction, validation, transformation and returned root use only
  that captured value. A provider may change its selection between operations;
  its snapshot method must atomically capture the root and model together.
- Extraction copies exactly the selected descendants and their geometry. It
  preserves IDs, edge direction, trims, face/shell orientation, body material,
  component ownership and void-shell relationships. It never mutates input.
- Root references and every selected descendant must exist with a matching
  table ID; unrelated malformed or unselected topology is outside the closure.
- Vertices have finite coordinates. Edges carry valid geometry with endpoints
  matching their curve and trim under the existing modeling tolerance contract.
- Wires contain a nonempty ordered edge-use chain. Consecutive oriented endpoint
  IDs agree; an open final endpoint is valid. A closed wire returns to its first
  endpoint. Closure never implies a face or a solid.
- Edge geometry admission retains the existing B-rep edge/trim domain: one
  vertex closing a full-period edge and degenerate zero-length edges are
  explicitly refused. Their seam/pole representations require T5's topology
  changes; the generic abstraction does not claim those domains are complete.
- Standalone faces and shells use the existing exact B-rep validation path,
  including pcurve correspondence and sheet manifold/orientation checks.
- Solids retain the existing exact body validation, outer-shell/void ownership,
  closure and positive-material component constraints.
- Compounds preserve their ordered heterogeneous roots and may be empty.
  Shared selected descendants are copied once by identity; compound membership
  does not create or transfer material ownership.
- Common operations use protocol requirements, including through existentials;
  no extension-only dispatch is required by Embedded Swift.
- Rigid transforms preserve IDs and parameterized curves. Each face-local
  pcurve is transported through its source and target surface charts, and the
  output passes the same validation contract before it is returned.
- Invalid selections and malformed topology fail explicitly with typed topology
  or kernel errors. Numerical and geometry limitations propagate unchanged.

## Runtime Flows

Closure extraction uses an explicit work stack, checking cancellation at each
selected entity. Descendant table membership prevents duplicate graph visits;
extraction work is linear in selected root occurrences plus selected topology
and geometry. Traversal orders entity IDs with sorting and preserves explicit
wire selection order. Validation is scoped to each distinct dimensional root, so overlapping
aggregate selections do not invent a second topology owner.

Transformation first validates and extracts the selected shape, transports each
selected geometry and vertex once, then transports each face's pcurves and
orientation. It validates the result before publication.

## State, Ownership, and Lifecycle

Shapes own value snapshots backed by existing copy-on-write persistent maps.
The captured value retains its root and model for the whole operation even if
the provider subsequently changes. A live provider owns synchronization of its
source state and returns an independent value snapshot through the protocol
requirement. Operators are stateless `Sendable` values. There is no shared
mutable operator state, cached validation certificate or asynchronous resource
lifetime.

## Failure, Concurrency, and Constraints

Missing references, mismatched IDs, disconnected wire ordering, invalid trim
endpoints, sheet roots passed as solids and inconsistent face pcurves fail
before an operation produces a result. Cancellation propagates as
`CancellationError`. There is no global allocation or geometry fallback.
Runtime is proportional to selected input size and inherited geometric proof
cost; no tessellation is used as geometry or topology authority.

## Verification and Change Impact

[GenericShapeTests](../../../Tests/CADTopologyTests/GenericShapeTests.swift)
owns behavior: every dimensional root succeeds through the same public
operator, open and closed wires preserve orientation, heterogeneous nested
compounds preserve membership while deduplicating descendants, extraction
excludes unrelated topology, rigid images preserve exact edge and surface lifts,
and malformed selections, wire gaps and wrong-dimensional solid inputs fail.
An acquisition-counting, mutex-protected live provider changes roots between
snapshots and proves each operation acquires once and returns a root present in
its selected closure.
Existing `BRepModel` validation tests retain the strict body ownership contract.
The root task owns native and WASM/Embedded compile/link/runtime verification;
source inspection alone is not completion evidence.

### Ordered Original Affine Model Images

The flat `OriginalAffineOperationWord` overload retains one exact forward/inverse
word on each original curve and support, regardless of factor count. It transports
face-local traversals through `OriginalAffineWordSurfaceParameterCurve`, retaining
their native UV coordinates and directed fractions. Vertices use the prepared exact
action once, and its exact orientation sign reverses faces for reflections. Its
`ShapeAffineWordAdmission` forwards each original algebra visit as work at
structural depth zero. Algebraic extension depth uses the immutable word
constructor's retained authority; it is independent of source traversal and curve
subdivision. The adapter converts retained UInt32-word counts to checked byte counts before
the optional caller storage callback. No private allowance is created. Source
nesting uses the caller source cap; word length does not consume that cap. Output
validation remains the caller's responsibility under the original tolerance.

| Operation | Source authority | Admission owner |
|---|---|---|
| Flat image | Original ordered forward/inverse factors | Caller work and byte ledger |
| Vertex publication | Prepared exact final action | Same caller ledger |
| UV traversal | Original source lift and exact target support binding | Same caller ledger |
| Output certificate | BRep validation at requested level | Caller bounded validator |

The existing array-of-forward-affines overload now delegates to the same flat
original-word producer. It constructs `.forward` factors from the original array
under the existing caller work ledger; rational factors require no ordered-field
root extension. Empty arrays preserve the original model. Hosted implicit/image
pcurves travel through the same original word carrier as every other boundary,
rather than leaving a source-support binding on a transformed target. Original
array order, IDs, native UV, exact determinant parity and output-validation
responsibility remain unchanged. No rounded intermediate matrix or vertex chain
becomes the final original source authority.

The protocol's bounded affine operation consumes an immutable `ValidatedBRepModel`
and the authored ordered affine words. It returns a model image, not a new validation
certificate. Every word is retained in nested original curve and surface image laws;
no rounded matrix product replaces the source. UV charts, coedges, trims, entity IDs,
body material, shell roles and void ownership remain unchanged. Each exact negative
spatial determinant reverses face orientation. Singular affine words fail before
publication. Every source entity, word, original determinant and recursive geometry
admission uses the caller work callback and caller source/subdivision caps. The caller
owns cumulative storage and output validation: arbitrary scale can amplify an existing
allowed source vertex/correspondence discrepancy, so the result cannot inherit the old
validation tolerance or volume certificate without that check. The existing rigid Shape
operation retains its behavior and validation path.

```text
Immutable validated model + ordered affine words + caller ledger
    -> original nested curve/surface laws + transformed vertices
    -> exact determinant face parity + preserved native UV topology
    -> model image -> caller bounded validation/publication
```

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.
