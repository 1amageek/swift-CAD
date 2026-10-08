# Native Common-Issuer Consumer Handoff

## Scope

Current production Native preparation, retained source-law handoff and all nine
consumer protocol/facade/result sources compile against the validated cached
lower contract. Actual preparation executes; this does not run a CS/SSI solve or
claim all-family/public-query completion. No production target is rebuilt.

| Lane | Compile/link | Runtime | Executed invariants |
|---|---|---|---|
| Native Swift 6.4.0 | Passed | Passed | Weighted curve/surface complete coefficient identities, COW retention, finite closed clipping, singleton and outside selections, explicit unsupported/invalid inputs, exact and insufficient work/storage, entry/final cancel |
| Native ASAN | Passed | Passed | Same preparation fixtures, no reported sanitizer defect |
| Normal WASM 6.4.0 | Passed | Passed on Node WASI | Same preparation and failure fixtures |
| Embedded WASM 6.4.0 | Passed | Passed on Node WASI | Same preparation and failure fixtures |

[Proof](../Sources/NativeConsumerProof/NativeConsumerProof.swift) and
[script](../Scripts/VerifyNativeConsumer.py) own this boundary. Import overlays
are generated from the unchanged production file bodies and checked byte-for-byte.
They preserve one cached lower module identity; no copied algorithm or fallback
is used. The current resolver is compiled but its solve methods are not executed.
The proof calls the production preparation methods, not a separately reimplemented
law. Lower L0/L1/L3/L5 source premises and cached runtime artifact are hash-gated.

## Lower Interval Premise

Five current L2 files differ from the cached module because DI0 introduced the
shared interval facade. The receipt records both hashes. The used public finite,
closed, empty and singleton interval contract is unchanged; latest DI0 has its
own committed Native/ASAN/WASM/Embedded behavior evidence. This preparation proof
uses the earlier verified implementation of that contract. It does not establish
latest whole-module interval ABI integration or public-query runtime. Those
remain owned by final integration, not this source-only build.

## Ownership and Failures

The query retains the source-law receipt through compilation/resolution and the
final checkpoint. Existing publication transfers the original immutable Native
snapshot and exact polynomial/domain owners to the existing result; no public
stored field, result layout or Codable change is introduced. The common issuer
uses the same caller admission; nested source/polynomial scalar failure causes are
preserved. Existing root/cell/relation failure wrappers remain intact.

| Logical state | All four lanes | Mutation / release |
|---|---|---|
| Prepared source law | Immutable Sendable receipt | No mutation; query releases after publication |
| Source and polynomial owners | Immutable retained COW values | Public result retains existing owners |
| Caller admission | Exclusive noncopyable value | Same inout ledger, no stored pointer or shared state |

## Review

One scoped review checked source/consumer trace, exact coefficient law, current
single-span applicability, all admitted temporary/output buffers, lifetime,
target parity and typed failure propagation. Finding confirmation fixes borrowed
Array iteration and failure fixture classification. Four stable lane runs pass.
The checksum receipt binds actual files, compiler commands, logs, artifacts and
all reused object inventories. No root-solving, coverage, performance speedup or
whole-seven acceptance is inferred.
