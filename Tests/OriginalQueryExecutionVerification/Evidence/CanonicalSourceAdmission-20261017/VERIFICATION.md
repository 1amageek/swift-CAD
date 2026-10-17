# Canonical source admission — 2026-10-17

This evidence accepts the generic caller-admission encoding unit, not the full
Section caller. One `PortableSourceEncodable` generic requirement carries the
same `NumericWorkAdmission` through the Core encoder, all 481 IR writers,
SHA/source fingerprint and memo mouths, and the sole in-repository Kernel codec
conformer. Ordinary APIs choose their existing authoring policy once and delegate
to that direct body. The actual source contracts remain in
[Core encoding](../../../../Sources/CADCore/PortableSourceEncoding/DESIGN.md),
[IR](../../../../Sources/CADIR/DESIGN.md), and
[cache content](../../../../Sources/CADKernel/CacheContentIdentity/DESIGN.md).

```text
Core R3: sole generic requirement + original canonical encoder/writers
  -> fresh Geometry2171 / Topology142 / IR818 using that Core
       -> IR R2: actual source writers / SHA / retained memo admission
            -> strict per-target prefix reuse
                 -> actual BRepCacheContentSource.swift only, as CADKernel
                      -> same four codec behavioral groups
```

| Actual shared groups | Native | ASAN | Normal WASM | Embedded WASM |
|---|---:|---:|---:|---:|
| Core golden bytes, bounds and cancellation | 3 PASS | 3 PASS | 3 PASS | 3 PASS |
| IR fingerprint, cumulative limits, memo and cancellation | 4 PASS | 4 PASS | 4 PASS | 4 PASS |
| Kernel original content, limits, typed failures and lifetime | 4 PASS | 4 PASS | 4 PASS | 4 PASS |
| Total | 11 | 11 | 11 | 11 |

The 44 executed groups use the same shared source per unit on all four targets.
Native uses real Swift Testing wrappers. Portable entry points call the identical
shared functions, including the same Mutex/Sendable observation owners. The
Kernel checks use an actual nonempty authored cube and real BRep validation;
`VOLUME_MOMENT_PORTABLE` excludes only that unchanged helper's unrelated wrappers.
The minimal CADKernel module contains the byte-identical production codec file,
not an equation slice or alternate conformer.

The Core tests retain fixed independent byte vectors, original local counters,
canonical order/collision/depth failures, exact cumulative N/N−1 and cancellation.
IR exercises actual SHA/fingerprint output, work/storage and prefix boundaries,
warm raw/validated memo readmission, cancellation and retained immutable sources.
Codec checks preserve original content across regenerated topology IDs, exact
cumulative work/storage boundaries, nested typed failures, cancellation and COW
source lifetime. Typed byte N is measured on each target; neither stride nor
local byte counts are assumed identical across targets. Original reviewed source
inverse and oracle records are archived without rewriting their contents.

## Provenance and limits

`manifest.json` is the sole package index. It maps each archive member to its
original absolute path, original SHA-256 and size. `proof-records.tar.gz` holds
byte-exact accepted indexes, raw receipts, source freezes, review/inverse records,
original command plans, source response lists and Native XML. It includes the
fresh Native module receipts needed to bind client results to their real compiler
origins. Receipts retain complete argv, tools/SDK fingerprints, fixture/source
inventories, product hashes, prefix origins and measured phases.
`runtime-logs.tar.gz` contains all twelve exact successful runtime logs and the
unaccepted first Embedded codec compile log. Every packaged member was read back
and hash-checked. No module, object, executable, framework or SDK binary is
committed here, and no original JSON is also emitted in a second representation.

The fixed toolchain is Swift 6.4.0 release. Native/ASAN use macOS 27; normal and
Embedded WASM use the matching SDK and `wasm32-unknown-wasip1`, preserving the
accepted WMO/resource/link flags. Existing Collections products are pinned to
their actual matching-target origins. The IR gate freshly generated the dependent
Geometry2171/Topology142/IR818 modules because the Core requirement changed; it
did not reuse modules compiled against the old protocol. The codec gate then
strictly reused those new four-module prefixes and generated only its sole-file
CADKernel module and real clients. No Modeling or full CADKernel was generated.

Each lane retained a 1200-second compiler deadline, 10-GiB process-tree RSS bound,
one compiler job and 120-second runtime bound. Native cases retain their existing
one-minute limits. All accepted stages stayed inside these bounds. All final
postflight lists are empty; the codec's final combined check matched 3336 unique
source/tool/product/log pins. Packaging itself performed no build, runtime,
regeneration or review.

## Preserved failure and correction

The first codec Embedded compile stopped before client/runtime because the actual
codec file used `TreeDictionary` without directly importing `HashTreeCollections`.
Its original failed receipt and diagnostic are retained under archive `history/`.
The prior Native/ASAN/WASM successes remain historical evidence for that older
source, not substitutes for the final four-target result.

Root corrected only `import HashTreeCollections`. Removing that line recovers the
previous reviewed production bytes exactly. Codec R2 source
`6592d37c348c4972f39a19a866dbaa676c6096a78294185876ebeb649c94ff1e`
then passed all four current targets with unchanged fixtures. Its freeze retains
the failure and correction; the final codec index binds the fresh successor
products and all four runtime outcomes. Other earlier setup failures named in
original indexes remain unaccepted history, not successful executions.

## Delivery boundary

This package does **not** establish complete Section cache validation, ordinary
DocumentEvaluator/box execution, Section P+1 failure-before-stale ordering and
empty sink, positive nonempty SVG, UI, full Kernel, or all seven U1 requirements.
Those caller gates are separate from this source-witness unit.

Root fast-forwarded Main from `d6cca5ea` to implementation `1fa00aa3`.
[Integration](integration.json) matches all 3199 production generation inputs,
526 owned source/fixture/design/evidence files and three protected files against
the accepted snapshot. This is source and dependency parity of the already
executed 44 groups, with no new production build or unchanged runtime replay.
The accompanying delivery record updates task progress; whole Section/U1 remains
open. If cache products, tools, SDKs or required snapshots are
retired later, the records retain historical proof only; they do not promise that
the old commands are runnable or that a missing prefix can be silently replaced.
A future run requires a newly verified matching dependency closure.
