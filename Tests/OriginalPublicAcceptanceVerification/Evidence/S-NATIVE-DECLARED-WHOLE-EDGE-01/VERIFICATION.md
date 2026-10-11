# S-NATIVE-DECLARED-WHOLE-EDGE-01 verification

Status: four-lane finite runtime acceptance is frozen. Review, coherent commit and independent delivery are owned by root. `cellComplete:false` remains in the raw receipts and summary; this packet does not claim that delivery has occurred.

## Exact input and independent oracle

The actual original `BSplineSurface3D` constructor in [the fixture](../../NativeDeclaredWholeEdgeAcceptance.swift:57) has degrees `(2,1)`, knots `[-1,-1,-1,1,1,1]` / `[-1,-1,1,1]`, and control rows `[(1,-1,0),(-1,-1,0),(1,-1,0)]` and `[(1,1,0),(-1,1,0),(1,1,0)]`. Its admitted homogeneous original maps are checked exactly against `[u²,v,0,1]` with closed `D=[-1,1]²`. One source is bound once, one full prepared cover is passed on both sides, and the public raw result has one chart pair.

The whole declared boundary is directed `(-1,v)->(1,v)` for closed `v∈[-1,1]`, with permutation `[0,1]`, gains `[1,1]`, offsets `[2,0]`. The actual identity issuer returns `.declaredSharedBoundary`. The public self query receives that proof and automatically excludes the authored diagonal.

```text
original full D × D ── actual exactParameterRelations ── retained raw
                                                           │
whole directed edge receipt + authored diagonal ────────────┤
                                                           ▼
                    actual public contacts → retained checked pullback
                                                           │
                         all terminal iff + ordinal/ID oracle
```

The independently complete raw relation is `u²=p² ∧ v=q` on the whole closed product. After the exact directed exclusion and diagonal exclusion, the complete residual is

`{(u,v,-u,v) | -1<u≤1, u≠0, -1≤v≤1}`.

Its exact oracle image is `(0,1]×[-1,1]×{0}`; parameter and image dimensions are 2 and fiber dimension is 0. These are meanings derived from this exact set, not assertions about unexposed public image/fiber fields.

[The oracle](../../NativeDeclaredWholeEdgeAcceptance.swift:117) uses checked whole-cell sign invariants, with no sample fallback, over every raw and refined terminal. It checks raw inclusion iff `u²-p²=0 ∧ v-q=0`, then refined inclusion iff those equations hold, `u-p≠0`, and `u+1>0`. All raw source cell IDs and order, coordinate map `[0,1,2,3]`, region/include/ordinal lengths, every terminal exactly once, included ordinal range/alignment, and excluded ordinal `-1` are checked. Observed raw selected / refined terminal / included terminal counts are `45 / 693 / 15`; those counts are measurements, not the completeness proof.

The half-scope control declares only closed `v∈[-1,0]` on the same full raw relation. Its complete residual additionally retains the undeclared forward edge at `v>0`; every terminal iff is checked (`45 / 957 / 17`). Closed V corners and the retained reverse edge are also exercised through the public membership query as directed-exclusion controls, subordinate to the complete cell oracle.

## Actual retained correspondence and lifetime

[Public contacts](../../../../Sources/CADGeometry/OriginalSurfaceEmbedding/DefaultOriginalExactNativeSelfContactQuery.swift:65) appends the actual `DefaultNativeExactParameterRefiner` results and retains them in `OriginalExactNativeSelfContacts`. [The Native refiner](../../../../Sources/CADGeometry/NativeExactRelations/DefaultNativeExactParameterRefiner.swift:31) calls the admitted L4 `refinePullback`; the existing checked pullback owns the raw-cell correspondence and the public consumer keeps its `sourceCellOrdinals` without transformation.

The L4/L5 modules, their actual compiler/products and source assumptions are the matched prior accepted receipts carried through each raw receipt's checks and reused Native32/source5 module references. This cell adds no lower build or alternate lower classification. The two equality signs alone do not uniquely distinguish each of the 45 raw cells. Thus the ordinal guarantee here is retention of the existing L4 checked correspondence plus exact source IDs/order and all public ordinal/alignment checks, not a new independent L4 cell-to-cell classification proof.

The complete oracle is executed after local source/frame/construction, preparation ledger and query admission owners exit. The result retains its original raw, identity proofs and pullback owner. This is the exercised retained lifetime; concurrency or arbitrary owner-sharing schedules are not inferred.

## Four-lane scoped acceptance

| Lane | Accepted raw parts | Actual runtime labels | Runtime seconds |
|---|---|---|---:|
| Native | v2 complete; v3 controls; v4 resources | runtime-complete; runtime-controls; runtime-resources | 6.104; 11.674; 13.356 |
| ASAN | v1 complete+controls; v2 resources | runtime-all; runtime-resources | 13.590; 10.864 |
| Ordinary WASM | v1 complete+controls; v2 resources | runtime-all; runtime-resources | 24.915; 19.420 |
| Embedded WASM | v3 complete+controls+resources | runtime-all | 20.371 |

The ASAN/WASM first `all` fixtures predate the resources group and therefore supply only complete+controls. The resources parts supply the missing resources group. Raw receipt fields and historical scope strings remain unchanged. `summary.json` explicitly records named groups, actual run labels, original receipt status, compiler receipt, actual compile/link command, exact products/logs, and immutable fixture/runner snapshots for each part.

Every lane compiles exactly the same four existing production self-contact bodies into `NativeDeclaredWholeEdgeSelf`, prefixed only by `@testable import NativeDomainAdapters`. The actual per-lane v1 `compile-self4` run and its module receipt bind the exact original/generated source pair and product bytes. Selected-module compiler times are Native 0.830 s, ASAN 1.043 s, WASM 0.570 s, Embedded 0.747 s. Subsequent fixture parts reuse the same admitted module and do not recompile it. Native32, source5, SourceGeometry, DI and L0–L5 are existing matched products; no source/lower build or production change occurs. Swift is fixed to `swift-6.4.0-RELEASE`, with the existing matching WASM SDK/target/Embedded profiles; raw commands preserve the full flags and actual products.

Native v1 and Embedded v1 full receipts remain failed fixture compilation observations before a public runtime query. Their separately persisted successful self4 module compilations are compiler premises only. No failed full receipt is promoted into runtime acceptance.

The Embedded v2 fixture changes only StaticString/integer diagnostic output relative to the accepted v4 resources fixture. [The exact output compatibility diff](fixture-output-compatibility.diff) and before/after immutable refs document that change. Earlier complete/controls fixtures retain their own versions; their whole fixtures are not claimed to differ only in output. Prior successful Native/ASAN/WASM runs were not replayed after that diagnostic repair. The subsequent final Embedded v3 fixture separately fixes F1 at its argument-decode entry, documented by [the exact F1 diff](fixture-entry-F1.diff).

Embedded v2 additionally emits the preserved raw warning:

`warning: data race detected: actor-isolated function at WholeEdge/NativeDeclaredWholeEdgeAcceptance.swift:266 was not called on the same actor`

The reviewer identified F1: the implicit actor-isolated closure passed to `Optional.map` was called from another actor. The v2 raw receipt remains `success:true` with its exact warning/log; geometry groups passed, but v2 is excluded from accepted Embedded entry evidence. No actual shared-memory race or geometric error is inferred from the warning.

The sole F1 correction replaces `getenv(...).map { String(cString:$0) }` with direct `if let` decoding in the Embedded branch, with no callback or synchronization/Sendable weakening. Geometry, query, oracle, resource and other target branches are byte-unchanged. Embedded v3 reuses the same self4 module and compiles/links only the corrected fixture (6.056 s); its single bounded `runtime-all` passes all three groups (20.371 s), and the actor warning is absent in the exact retained log. Native/ASAN/ordinary WASM accepted parts are not replayed. This is focused entry-isolation verification, not a general concurrency claim.

## Applicable controls and operation-local resource boundaries

| Control | Actual evidence |
|---|---|
| Directed whole scope | Complete residual iff, reverse edge and both closed corners retained |
| Scope restriction | Complete half-scope iff retains undeclared positive-V forward edge |
| Invalid identity | V reversal declaration throws `OriginalDomainIdentityFailure.invalidIdentityProof` |
| Position versus germ | Exact `Gu=2u`, giving −2 and +2 at the edges; position proof cannot establish common derivative/normal germ |
| Empty publication | Same-owner out-of-support U=2 cover has no raw pieces; public result has no refinements and one authored diagonal identity |
| Cancellation | Entry cancellation, final retained-pullback publication cancellation, and empty final-publication cancellation return typed cancellation |
| Resource causes | Zero-work and zero-storage prepared query return typed resource failure |
| Retained lifetime | Complete oracle after source/frame/construction/preparation/query admission scope release |

There is no germ query API in this admitted path, so no executed typed germ-rejection API is claimed. The actual negative issuer test is V reversal, and the exact opposite derivatives establish the position-only limit.

The dedicated resources group calibrates a new independent ledger immediately after public `contacts` returns, using retained immutable raw and the same exact identity. Raw preparation and the post-return oracle use different ledgers. The identical raw/proof then succeeds at exact `(workN,storageN)` with exact measured consumption; separate `workN−1` and `storageN−1` queries throw their respective typed resource failures.

| Lane | Independent prepared-query work N | Independent prepared-query storage N |
|---|---:|---:|
| Native | 4,794,448 | 171,176,828 bytes |
| ASAN | 4,794,448 | 171,176,828 bytes |
| Ordinary WASM | 4,763,811 | 86,376,364 bytes |
| Embedded WASM | 4,763,811 | 86,376,364 bytes |

The Native first complete observation measured preparation `8,142,205 work /243,476,900 bytes`, cumulative public return `12,936,653 /414,653,728`, and cumulative post-oracle `12,965,982 /416,182,484`. Those cumulative measurements are not independent prepared-query N. Whole-workflow N/N−1 is unmeasured and is not claimed.

Caller ceilings stay `80,000,000 work /1 GiB storage /depth32`. Each compiler/runtime process is bounded by 120 s wall, 120 s per-process CPU and 120 s sampled owned CPU. Every recorded accepted run has no bounded stop and no remaining owned descendants; actual peak RSS and sampled CPU remain in its run record. No GPU path is involved.

## Exact archival scope

The previous CERT packet's explicit cached `CertifiedSphereConeIntersectionCurve` base (`df15…`) versus current file (`585f…`) compatibility is retained: the original nominal/storage/constructors/spatial/helper bytes are unchanged, with only the admitted additive 40-line snapshot port. The base snapshot and selected-range receipts are referenced separately. No old full-file/current-file equality is asserted.

The text manifest preserves exact raw receipts, compiler/link commands, logs and original/generated/fixture/runner versions. Binary module/archive/executable products remain at their admitted immutable paths and are hash-bound by receipts; they are not copied into text evidence. Manifest unique CAS counts include an inherited prior CAS reference, and own-cell CAS counts are separately reported. Final review and independent delivery must compare current source/compiler/product/log premises and protected drafts; no runtime replay is necessary unless an actual premise changes.
