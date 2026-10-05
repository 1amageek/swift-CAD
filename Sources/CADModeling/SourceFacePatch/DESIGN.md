# Source Face Patch

## Purpose and Scope
Own immutable original B-rep face extraction into sewing patches. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Copy original supports, native trims, oriented vertex stations, face-local pcurves and source lineage. This component performs no projection, fitting, endpoint evaluation or source validation. An already-admitted original model remains the caller's source authority; extracting a patch does not create a new validation receipt.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | SourceBRepFacePatchBuilder | Original patch extraction for editing and sewing | Legacy callers retain their existing entry |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | immutable original face/loop/coedge/edge data | Retains source identity and oriented trim | Admission belongs to the original validation receipt |
| [Sewing Provenance](../SewingProvenance/DESIGN.md) | depends on | admitted sorted unique ancestry | Pays original ID canonicalization without a sort buffer | Byte callbacks count payload, not allocator metadata |
| [Original Solid Classification](../../CADKernel/OriginalSolidClassification/DESIGN.md) | used by | callback-bounded original patch copy | Finite material intersection proof | Copy work is separate from original trim proof |

## Architecture
```text
original face/loops/coedges + source lineage + caller allowance
    -> paid immutable traversal and oriented native trim copy
        -> sewing patch + deterministic source topology keys
```

## Contracts and Invariants
Stored curve and support values retain their immutable original backing. Reversed uses exchange directed trim endpoints and vertex ancestry while retaining the authored face-local pcurve. Callback entries charge each original loop/coedge/lineage scan and comparison before processing it, and reserve owned loop, edge, lineage, identity-string and stable-key payload bytes before allocation. Checked arithmetic and cancellation precede expansion. The legacy entry uses the identical copy algorithm with absent caller callbacks.

Bounded sewing value constructors use [Sewing Provenance](../SewingProvenance/DESIGN.md) for paid in-place sorted unique ancestry, while legacy constructors preserve their existing API. Output stable-key dictionary payload admission does not establish standard-library bucket metadata accounting. Complete modified patch validation and original correspondence remain separate caller premises. No copied endpoint or pcurve is recomputed or rounded to authorize correspondence.

## State, Ownership, and Lifecycle
All copied arrays and stable-key maps are invocation-local construction state. Published source fields retain immutable value owners; callback values are Sendable and the composing caller owns its ledger on every target. No shared mutable cache or target-specific lock branch exists.

## Failure, Concurrency, and Constraints
Missing source support, loop, edge, vertex, native trim or pcurve fails explicitly. Counter/byte arithmetic overflow and caller resource/cancellation failures propagate. No separate hidden whole-feature ceiling is introduced.

## Verification and Change Impact
After source work, verify reversed and singular/closed uses, holes, original image curves and supports, complete ancestry, deterministic stable keys, cancellation and caller exhaustion. Recheck sewing publication, finite-face classifiers and edits consuming copied source patches. Source-only changes do not establish behavioral completion.
