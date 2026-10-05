# Original STEP Group Owner

## Purpose and Scope
Child of [Independent Shape Source](../DESIGN.md), with no children. Owns a real STEP GROUP declaration independently of zero or more APPLIED_GROUP_ASSIGNMENT records.

## Responsibilities and Boundaries
The owner retains its distinct tagged identity, original UTF8 name and required nullable description. IndependentShapeGroup owns each assignment identity and membership; its originalSTEPGroupID binds this owner. Exchange owns legal GROUP/assignment authoring and metadata loss policy. No empty assignment or geometry is manufactured for an unassigned declaration.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Independent Shape Source](../DESIGN.md) | parent | Metadata declarations and assignment binding | Explicit originalSTEPGroups collection | Owner declarations are metadata anchors, not groupable members |
| [Independent Shape Exchange](../../../CADExchange/IndependentShapeExchange/DESIGN.md) | used by | Original declaration transport | Emits every real GROUP once | GROUP itself is excluded from groupable_item |

## Architecture
```text
original GROUP -> immutable owner record -> zero or more assignment references
               -> source metadata anchor -> one real emitted GROUP
```

## Contracts and Invariants
Native fields are id/name/description, all required including nullable description. Name and description compare by exact UTF8 bytes. Collection identity order is canonical and unique. Assignment metadata must agree exactly with the referenced owner. A metadata-only source may have no geometric roots; that represents real declarations, not an empty successful geometry result. Unassigned owners remain retained and emitted.

## State, Ownership, and Lifecycle
Values and strings are immutable Sendable/COW. Native codecs are unavailable under Embedded without changing common semantic values. Parent validation pays record/text/work admission before indexing and comparison.

## Failure, Concurrency, and Constraints
Missing owners, contradictory metadata, duplicate identity, missing nullable fields, caller work/text/record exhaustion and cancellation fail before publication. IGES has no separate owner declaration; discarding it requires an explicit independentShapes loss.

## Verification and Change Impact
After SOURCE87, exercise bare declarations, several equal/overlapping assignments, shared identity, distinct equal-valued owners, nil/empty descriptions, malformed references and resource/cancellation behavior through public Native/STEP/partial/IGES policy paths. Source authoring alone is not behavior evidence.
