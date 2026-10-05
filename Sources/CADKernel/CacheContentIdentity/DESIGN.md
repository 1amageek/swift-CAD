# Cache Content Identity

## Purpose and Scope
Child of [CADKernel](../DESIGN.md), with no children. Encodes ID-independent
original B-rep content for common cached-versus-regenerated geometry admission.

## Responsibilities and Boundaries
This component owns semantic topology traversal and original leaf values.
CADCore PortableSourceEncoder owns cumulative bytes/work/depth, scratch sorting
and cancellation. DocumentCacheValidation owns metadata, exact re-evaluation,
mesh comparison and public failure. Tessellation limits remain independent.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | complete cache admission | Supplies current evaluator and cache | No IDs as geometry authority |
| [PortableSourceEncoding](../../CADCore/PortableSourceEncoding/DESIGN.md) | depends on | original binary values/cumulative encoder | Common deterministic byte stream | No per-leaf ledger reset |
| [IR PortableSourceEncoding](../../CADIR/PortableSourceEncoding/DESIGN.md) | depends on | original geometry field writers | Encodes retained source laws | New persistent geometry must have a writer |

## Architecture
```text
validated original model -> body/component/shell/face multisets
 -> ordered original coedges -> original geometry/trim/endpoints
 -> one bounded canonical encoder -> byte equality -> cache admission
```

## Contracts and Invariants
Generated topology IDs are excluded. Solid component outer/void ownership,
orientations, ordered coedges, endpoint positions, whole original surface/curve
laws, trims, pcurves, material identity and body names are retained. Body,
component, void-shell, sheet-shell, face and loop collections preserve multiplicity
and compare in canonical original-content order. Raw geometry encoding includes
parameter images and original revolutions without a second family dispatcher.
Both cached and expected models share one explicit encoder allowance. The legacy
public overload preserves its no-new-ceiling policy with Int.max counters; the
strict overload forwards caller encoding limits once. Metadata and tessellation
limits keep their own contracts. Failure does not publish an admitted cache.

## State, Ownership, and Lifecycle
Original models and node wrappers are invocation-local immutable COW values;
no mutable model storage is shared or changed. The same encoder owns all scratch
and byte charges. Child arrays are charged before allocation. Retaining the first
byte stream across the second append charges its COW storage before mutation.
Comparison retains ranges over owned arrays without hex/Base64 materialization.

## Failure, Concurrency, and Constraints
Missing source references, invalid source, cancellation, overflow or cumulative
encoding exhaustion propagate. There is no Native/Foundation codec dependency,
Embedded raw state, unchecked Sendable or synchronization exception.

## Verification and Change Impact
After source completion, execute public cache admission on Native, normal WASM
and Embedded: regenerated IDs, full original geometry families, material/component
ownership changes, pcurve/orientation changes, stale meshes, strict budget boundary,
cancellation and corrupt cache refusal. Existing cache success/failure behavior
and source equality must be checked before review/commit. Source is not evidence.
