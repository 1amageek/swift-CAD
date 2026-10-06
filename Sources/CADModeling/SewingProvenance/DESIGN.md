# Sewing Provenance

## Purpose and Scope
Own callback-admitted canonical source ancestry arrays for sewing value construction. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Preserve the existing sorted unique SubshapeID value semantics. Charge original comparisons, copying and deduplication visits to the caller, and admit the retained SubshapeID array payload before its COW mutation. Geometry, topology validation and lineage relation selection remain their existing owners' responsibilities.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | bounded sewing value constructors | Complete canonical ancestry values on every target | Legacy constructors remain available |
| [Source Face Patch](../SourceFacePatch/DESIGN.md) | used by | callback-paid sorted unique parent IDs | Original source-copy publication | This canonicalization does not validate a source face |
| [CADCore](../../CADCore/DESIGN.md) | depends on | SubshapeID ordering and equality | Same deterministic value order as existing constructors | No new source-ID equivalence or tolerance |

## Architecture
```text
source parent IDs + caller work/byte allowance
    -> admit owned array payload -> in-place heap sort
        -> paid exact deduplication -> immutable canonical ancestry
```

## Contracts and Invariants
The result is identical to the legacy sorted Set projection. All comparisons use the original SubshapeID total order and exact equality. In-place heap sorting uses no merge buffer or Set; input immutable role strings remain retained values. A bounded constructor reserves checked count-times-stride bytes before creating the independently mutable output array. Each element visit, sort comparison and swap consumes a callback at depth zero. Callback invocation means one unit of original work; its Int argument is depth, never a work count.

The algorithm owns array payload admission, not standard-library allocator metadata or a complete geometry/feature budget. Scalar arithmetic overflow, cancellation and caller callback failures propagate before publication. Invalid parent identity values preserve legacy construction semantics and are rejected by the existing sewing validation boundary.

The byte callback is optional and its absence propagates directly through copied source patch and edge constructors. No no-op byte sink represents a selected bounded-byte guarantee. Work traversal remains admitted independently; supplied byte callbacks reserve each owned ancestry buffer before allocation.

## State, Ownership, and Lifecycle
The sortable output array is invocation-local. Immutable input arrays and role strings retain their value backing; mutation detaches the output after its byte admission. Published arrays are immutable values. Sendable callback and storage semantics are identical on Native, WASM and Embedded.

## Failure, Concurrency, and Constraints
No new hidden ceiling or shared mutable cache is introduced. Independent callers retain independent allowances; resource exhaustion and cancellation remain typed caller failures. Original sewing source/correspondence validation is a separate prerequisite.

## Verification and Change Impact
After source work, compare against legacy sorted-unique semantics for duplicate/empty/permuted ancestry, checked overflow, cancellation and work/storage exhaustion. Recheck source patch copying and sewing lineage publication. No source-only packet establishes those behavioral results.
