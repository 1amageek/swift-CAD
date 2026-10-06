# Original Evaluation Source Binding

## Purpose and Scope

Child of [CADKernel](../DESIGN.md), with no children. Owns the immutable association
between an evaluated document and the original document validation receipt which
produced it. Public/manual and Native decoded artifacts remain separate from that
producer association.

## Responsibilities and Boundaries

The internal evaluated-value constructor derives `document` from
`validatedSourceReceipt.document`; it accepts no independent document argument.
The receipt is immutable after initialization. Replacing materialized caches
preserves that same source binding and original artifact fields. Original BRep,
curve, lineage, cache freshness and query-specific resource proofs are owned by
their existing producers; this binding does not certify those artifacts.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | evaluation artifact composition | Publishes source-bound original evaluations | Native/manual constructor retains no receipt |
| [CADIR](../../CADIR/DESIGN.md) | depends on | ValidatedCADDocument immutable source | Supplies the original validated source owner | No source substitution or fabricated validation |
| [BRep Drawing](../BRepDrawing/DESIGN.md) | used by | producer source receipt | Reuses document semantic validation | BRep preparation and full drawing limits stay independent |

## Architecture

```text
ValidatedCADDocument
 -> internal constructor (document derived from receipt)
 -> immutable EvaluatedDocument source binding
 -> evaluation / materialized-cache replacement / original drawing query

public initialization or Native decoding
 -> document + artifacts, no producer receipt
 -> explicit bounded validation or admission failure
```

## Contracts and Invariants

- Producer-bound source is the original immutable receipt's document. Callers
  cannot replace the document while retaining that receipt.
- `validatedSourceReceipt` is a `let` field. Engine evaluation initializes the
  binding once; cache materialization creates another immutable bound value.
- Consuming this binding requires no full source equality, fingerprint traversal
  or semantic validation replay. It preserves the original validation authority
  rather than converting uncharged comparison into that authority.
- Public initializer parameters, Native coding keys and wire payloads remain
  unchanged. Those paths have no producer receipt, including after decoding.
- Missing binding does not become successful default validation. A query needing
  shared bounded semantic authority must either invoke a genuine bounded
  validator or report typed failure before publication.
- The receipt and document are immutable Sendable values with the same storage
  and ownership on Native, WASM and Embedded. No mutable registry is introduced.

## State, Ownership, and Lifecycle

The evaluated value retains its immutable receipt and its document's COW storage
for the value's lifetime. Cache replacement retains the same association.
Incremental and validated-BRep state remain with their existing owners; this
component preserves them during cache replacement and does not mutate them.

## Failure, Concurrency, and Constraints

The internal constructor verifies the receipt tolerance equals the artifact configuration
tolerance before publication. It performs no I/O, allocation of copied source payload,
semantic validation, hashing or independent resource reset. Source validation is
completed before the engine calls it. Missing source receipt is an explicit query
admission failure; it is not serialized as a success certificate.

## Verification and Change Impact

After SOURCE87, engine/public/Native-decoded and cache-materialized fixtures must
verify binding presence, preservation and absent-receipt refusal. A changed
source cannot retain the old binding through either constructor. Existing Native
payload round trips remain unchanged. BRep drawing owns successful source-bound
queries and preparation-budget failures; manual bounded semantic admission stays
an explicit remaining lower contract. Source authorship alone does not establish
runtime, complete D1, review or integration evidence.
