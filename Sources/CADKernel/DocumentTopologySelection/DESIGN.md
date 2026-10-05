# Document Topology Selection

## Purpose and Scope
Child of [CADKernel](../DESIGN.md), with no children. Owns A7 admission of
rendered triangle provenance against the exact current evaluated source.
Rupa owns placement, filtering, highlight and native frame hit acquisition.

## Responsibilities and Boundaries
An immutable selection snapshot binds complete CAD source, evaluated B-rep,
configuration, subshape index and the actual body's Mesh. It resolves the
producer-recorded FaceRun only after current snapshot equality and body
ownership checks. Geometry proximity and display-mesh identity never invent
a B-rep face identity.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | complete EvaluatedDocument | Supplies current source and topology | Revisions alone do not establish equality |
| [CADIR](../../CADIR/DESIGN.md) | depends on | Mesh.FaceRun / source equality | Supplies producer provenance | Every triangle must have exactly one face owner |
| [StableTopologyReference](../../CADModeling/StableTopologyReference/DESIGN.md) | depends on | current live subshape identity | Names face for persistent selection | Multiple live names remain ambiguous |

## Architecture
```text
Mounted body Mesh + complete evaluated source -> immutable selection snapshot
Native hit triangle + supplied current evaluation -> full snapshot admission
 -> original FaceRun -> current body-owned face -> persistent subshape identity
```

## Contracts and Invariants
A stale source, altered B-rep, changed configuration, different body mesh or
changed subshape index fails. Constructor admits complete nonempty FaceRun
coverage and actual face ownership in the selected body. Selection checks
triangle bounds and checked prefix arithmetic. Missing or duplicate provenance
is a typed failure; no adjacent face, nearest point or old snapshot is selected.

## State, Ownership, and Lifecycle
The snapshot owns immutable Sendable values with native copy-on-write backing.
It introduces no shared mutable state, pointer or asynchronous lifecycle.
Consumers associate the snapshot with their occurrence and mounted-frame
identity; two placed parts may share geometry while retaining distinct app
selection targets.

## Failure, Concurrency, and Constraints
Invalid mesh/provenance, stale snapshot, missing topology and ambiguous live
subshape names fail before publication. Cancellation is checked during traversal.
Memory remains bounded by the already admitted source and Mesh values.

## Verification and Change Impact
After all source implementation, test current/stale/ABA source, changed mesh
at the same revision, foreign body run, out-of-range hit and placed occurrence
selection through the actual Rupa native input path. Kernel behavior alone
does not complete application-frame admission.

Persisted document subshape attributes publish an explicit resolution entry on
EvaluatedDocument. Complete witness arrays resolve all-or-nothing through the
existing lineage/signature owner. No partial result or implicit new selection
is returned when a referenced output was deleted or split. Native reload and
transaction restoration preserve the symbolic source records before resolution.

Consumers can validate a retained snapshot without a hit using validateCurrent.
This compares the same complete source, B-rep, configuration, mesh and subshape
values as triangle lookup. It enables mounted-frame admission before resolving
vertex, edge, face or rectangle queries.
