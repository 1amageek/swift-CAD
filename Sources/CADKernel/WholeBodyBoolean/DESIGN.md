# Whole Body Boolean

## Purpose and Scope
Own whole-operand selection and original face-patch extraction when the complete Boolean intersection producer admits a non-crossing relation. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
The original intersection producer owns complete boundary event coverage. Original solid classification owns material membership. This consumer selects whole bodies, preserves original shell ownership and carries source ancestry. It does not infer complete absence of intersections from vertex samples.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | general Boolean materialization | Produces one sewing request | Request validation does not prove material relation |
| [Coincident Face Patch Merge](../CoincidentFacePatchMerge/DESIGN.md) | depends on | complete original face and trim bijection | Proves duplicate boundary regions and merges ancestry | Different source face partitions need shared arrangement |
| [Source Face Patch](../../CADModeling/SourceFacePatch/DESIGN.md) | depends on | original source copying | Retains original curves, trims and coedge laws | No geometry fitting |

## Architecture
```text
complete non-crossing graph -> original material classification
    -> whole body keep/reverse/discard
    -> coincident complete face/trim correspondence -> one representative
    -> original shells + merged source ancestry -> sewing request
```

## Contracts and Invariants
Both original boundaries classified as boundary are only a coincidence candidate. Whole coincidence requires a complete bijection of authored face regions, including every hole and whole directed edge law on certified common supports. The same face count and complete merged-region coverage establish this existing unsplit route; a different source face partition requires the general shared arrangement producer, rather than a vertex-only shortcut.

For coincident volumes, union and intersection retain one tool representative. If another target already contains that representative, union retains the containing target instead. Difference removes coincident targets and reverses the tool only when another retained target contains it. Slice retains its original target partition contract. A retained coincident tool representative merges face, edge, vertex and body parents from every coincident target. Its original shell grouping and orientations are unchanged.

## State, Ownership, and Lifecycle
All source values are immutable; relation lists, copied patches and merged correspondence belong to one invocation. Common Sendable value and synchronization contracts are unchanged on all targets. Existing source-copy, correspondence and sewing policies retain their individual allowances; this consumer declares no new whole-Boolean ledger.

## Failure, Concurrency, and Constraints
A missing source, unresolved original correspondence, unsupported repartition, inconsistent relation or empty material result is a typed failure. A union of proven identical volumes is not an empty result. Vertex agreement and support coincidence alone cannot authorize publication.

## Verification and Change Impact
Deferred behavioral verification covers identical solids under union/intersection/difference, coincident operands among nested or disjoint targets, split-versus-unsplit face domains, cavities, source ancestry and cancellation. Existing WholeBodyBooleanFacePatchMaterializerTests own contained and disjoint regressions. No behavioral evidence is claimed during the source phase.
