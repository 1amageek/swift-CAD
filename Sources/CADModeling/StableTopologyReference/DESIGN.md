# Stable Topology Reference

## Purpose and Scope
Child of [CADModeling](../DESIGN.md), with no children. Owns provenance-first
resolution of persisted subshape identities against a supplied current B-rep,
live index and complete lineage. Geometry signatures remain the explicit last
resort within the original feature provenance. No external snapshot is inferred.

## Responsibilities and Boundaries
The resolver owns deterministic candidate selection and ambiguity/cycle failure.
The feature producer owns split/merge/preserved lineage; CADIR owns persistence;
CADKernel owns source-snapshot publication and selection admission. Geometry
signature generation/comparison is composed through SubshapeGeometrySignatureBuilder. The bounded variant retains the legacy stored-field equality semantics.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | validated feature provenance | Hosts resolution | Producers must retain complete lineage |
| [CADIR](../../CADIR/DESIGN.md) | depends on | StableSubshapeReference/SubshapeIndex | Owns persisted identity | Geometry never changes feature provenance |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | current evaluated topology lookup | Publishes resolution | Snapshot admission precedes lookup |

## Architecture
```text
Persisted identity -> direct live compatible topology
                  -> iterative lineage closure -> unique compatible live output
                  -> exact same-feature geometry witness -> unique output
                  -> missing / ambiguous / invalid / reachable-cycle failure
```

## Contracts and Invariants
Every returned topology identity must exist in the supplied B-rep. A direct
identity remains authoritative over geometry; a split may not choose a branch
implicitly; equal topology reached through several merge parents is deduplicated.
Reachable cycles fail. The lineage traversal uses an explicit enter/exit stack
and completed-node set, so long valid histories do not consume the call stack.
It preserves all live descendant candidates and never replaces traversal with
nearest geometry or a bounded prefix. Cancellation is checked in graph creation,
traversal and final geometry matching. Geometry fallback remains within the
original feature and uses the existing complete signature comparator.

## State, Ownership, and Lifecycle
All source values are immutable caller snapshots. Dictionaries, sets and the
iterative traversal stack are invocation-local; no shared cache is introduced.

## Failure, Concurrency, and Constraints
Invalid lineage, nonexistent live topology and incompatible direct topology
fail explicitly. Missing outputs and multiple live candidates retain the
existing typed KernelError contract. Work and storage are bounded by the supplied
finite lineage/index graph; no truncation or guessed history-depth limit applies.

## Verification and Change Impact
Existing StableSelectionResolverTests own direct/unique/split/geometry/cycle
behavior. After source implementation, the task must execute long-chain, diamond
merge, deletion and reload paths plus current-snapshot admission. Source shape
alone is not completion evidence. Producer lineage or persistence changes require
rechecking those public paths.

Bounded query composition passes the same work-depth and byte callbacks through every lineage visit and signature construction. Fixed-schema signature loops pre-admit typed arrays before reservation. Original curves/surfaces/pcurves are validated at the existing signature structural tolerance, with caller source/subdivision/algebra capabilities. Before stored-field equality, GeometryStructuralComparisonWork pays the complete original payload traversal, including certificate fields; vertex matching retains the original distance tolerance. No source encoder or different canonical equality substitutes for this contract.
