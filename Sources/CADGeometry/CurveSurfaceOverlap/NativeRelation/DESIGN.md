# Native Curve Surface Relation

## Purpose and Scope
Child of [Curve Surface Overlap](../DESIGN.md). Publishes the complete original
finite nonperiodic single-chart native CS relation, including mixed-dimensional
components. Multi-span isolated publication remains owned by
[Native Point Relations](../NativePointRelations/DESIGN.md).

## Responsibilities and Boundaries
Retain original operands, domains, cells, closure incidence and connected components.
Numerical overlap correspondence does not represent this multivalued relation.
Positive-dimensional multi-chart composition requires an original ownership proof;
the current producer fails explicitly rather than joining numerical boundaries.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Overlap](../DESIGN.md) | parent | rich publication | Whole relations accompany legacy fields | Empty overlap arrays do not certify discreteness |
| [Intersection Algebra](../../IntersectionAlgebra/DESIGN.md) | depends on | decomposition, incidence, ordered relation | Complete original cells and exact fibers | Resource/cancellation failures propagate |
| [Native Points](../NativePointRelations/DESIGN.md) | coordinates with | isolated localization and admission | Preserve isolated fast path | No boundary cells published as isolated components |

## Architecture
```text
original native product -> isolated fast path or full decomposition
  -> retained cells + closure attachments + connected components
  -> exact maximal t-prefix projections + image/fiber dimensions
  -> immutable public owner
exact t station -> original equations/guards -> ordered UV relation -> all fibers
```

## Contracts and Invariants
Every selected original cell is retained. Handles are scoped to one immutable owner.
Connected components use proved closure incidence, never XYZ equality or tolerance.
Projection merges consecutive selected t-prefix cells in the original cylindrical
order, preserving open/closed endpoints. Cell image dimension is zero for a fixed
t-prefix or an identically constant original curve law, otherwise one. Parameter
fiber dimension is cell dimension minus its t-prefix dimension; geometric image
fiber dimension is cell dimension minus image dimension. Samples are exact points,
not whole-cell ranges. Rich legacy points contain isolated components only.
Discrete queries fail atomically on every positive-dimensional selected cell.

## Runtime Flows
The public fiber query substitutes an exact retained scalar into every original
equation and denominator guard, preserves its causal source depths and requested
t membership, and uses the existing ordered real relation engine for all UV cells.

## State, Ownership, and Lifecycle
The receipt retains immutable original chart laws, complete decomposition and
source operands. Samples retain their exact field owners. CellIdentifier is an
immutable identity-only token scoped to one receipt; it requires that receipt for
membership and does not independently retain original geometry or chart laws.
No mutable cache, shared state or numerical inverse owns membership or identity.

## Failure, Concurrency, and Constraints
Publication uses the original invocation ledger and candidate ceiling. The
candidate ceiling independently bounds all selected cell records and connected
component records, including boundary cells, rather than their geometric XYZ
images. Publication preserves source and
algebra depth, storage admission and cancellation. The preferIsolatedCells lower port prepares original cells once for its initial
classification. The isolated rank path is selected only when every actual selected
real cell has zero dimension, including real-only isolated loci of a positive-
dimensional complex ideal. Any positive-dimensional real cell selects full
original rank partition and incidence. The positive preferred path retains an
unpruned full partition to satisfy the existing finite-branch closure theorem;
initial isolated pruning remains unchanged. There is no failed-solver retry. Fiber queries use caller-provided
OriginalRelationUsage and independent parameter/coefficient depth. No private quota. Multi-chart rich queries keep the isolated-only original proof
path and translate its positive-dimensional result to unsupportedCapability; they
do not spend full closure work on a relation the current owner cannot compose.

## Verification and Change Impact
NativeCurveSurfaceRelationTests exercises full overlap, multiple UV, collapsed
images/fibers, mixed components, exact membership/projection, foreign handles and
independent admitted failure. Changes to decomposition or incidence require this
owner's full relation evidence; isolated fast-path evidence remains separate.
