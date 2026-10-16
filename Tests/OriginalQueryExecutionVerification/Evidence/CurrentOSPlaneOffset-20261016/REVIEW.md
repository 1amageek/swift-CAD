# Review

## Fixed Boundary

One comprehensive source review covers the current-OS fallback removals,
original plane displacement predicate, actual offset caller, memo isolation and
Core-only product reuse. Subsequent checks are limited to the concrete target
findings exposed by actual full-module compilation and runtime. They do not
repeat the comprehensive review or expand acceptance to unrelated families.

| Examined finding | Resolution and check |
|---|---|
| Earlier OS fallbacks | Current successful expressions remain unchanged; actual target capability branches remain. |
| Rounded materialized plane | Source-owned exact displacement/orientation predicate is shared by publication and consumption; unequal candidates preserve the original definition. |
| Memo fallback and shared state | Same Mutex-protected completed-only publication, fallible compute outside lock, retained owner and no Embedded raw-state branch. |
| WASI clock / Embedded C math | Preserve timestamp epoch, nanoseconds and typed failure; continuity expression body stays unchanged. |
| Oversized IR values | Only bridgeSurface is indirect; immutable payload, case fields, explicit codec and source fingerprint expressions remain unchanged. |
| Target dependency visibility | Sixteen direct HashTreeCollections imports and three CADTopology imports use the already-pinned products; the IR target declares its actual direct product. |
| Cancellation | Twelve replacements use the existing Core current-task checker at the same lexical sites and retain CancellationError semantics. |
| Stable chain ordering | Exhaustive ten-case formatting preserves measured Native strings and lexicographic sort keys; real chain behavior is exercised. |
| Embedded key paths | Twenty-four same-field closures preserve eager/lazy map, flatten order, finite short circuit, collection ownership and accounting. |
| Fixture async iteration | The same ThrowingTaskGroup uses next(), retaining eight results, error propagation, concurrency and cancellation assertions. |
| Product reuse | No unchecked product selection, omitted production sources, source surrogate or accepted prior failure. |

The source reviews find no remaining concrete blocker in this fixed boundary.
Actual target outcomes and exact runtime acceptance are recorded separately in
[VERIFICATION.md](VERIFICATION.md) and [index.json](index.json); source review
alone is not runtime evidence.

## Explicit Limits

The historical aggregate SIGSEGV is unclassified. The independent existing
prepared/one-shot endpoint regression remains open and its strict oracle is
unchanged. Those observations are neither erased nor presented as passing tests.
Full source-family coverage, U1–U4 and the whole intersection requirements remain
outside this finite delivery. Final Native/ASAN/normal-WASM/Embedded runtime acceptance is now complete for
this boundary. The main-integration gate passes exact source/product reuse and a fresh
three-function actual public caller replay; raw evidence is in
[integration.json](integration.json).
