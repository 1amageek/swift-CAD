# Structural surface metering portable evidence

This evidence owns only the original structural surface work contract after the
Native surface dispatcher frame separation. Native focused checks passed under
Root's gate; the two portable lanes below executed all four checks successfully.
Embedded is intentionally **not run yet**: Root paused that generation until the
next concrete silhouette worker-frame change can be batched. This is neither a
whole Drawing result nor whole G01/U1/U4 completion.

## Source and behavior

The actual Native source authority is
`/Users/1amageek/.codex/verification-artifacts/swift-CAD/g01-direct-20261016/native-structural-surface-r1/receipt.json`,
SHA-256 `53a65398fd6a177d3a9e604c743ed8391a0d16ab0c919132b91225e211f5958c`.
It pins 65 Core and 2,170 Geometry sources, including structural meter
`e0978f2bb75c79ef1b3181fb24e626a68b36221dbf5cbd3a60260d98fa2241d4`.

```text
surface: original cancellation + debit 1
  -> Native B-spline: unchanged private payload traversal
  -> other family: unchanged enum case body in separate frame
```

Removing only the thin branch, private dispatcher boundary and three non-inlining
attributes reconstructs the entire old source file byte-for-byte, SHA-256
`a55bc576924ec5af013c350c6f4809d7c16bcc8bc835ec275475c96f772cfeec`.
This preserves every old Native/non-Native case body, recursion order and resource
call. [source-freeze-r1.json](source-freeze-r1.json) records that premise. The owning
contract is [StructuralGeometryWork/DESIGN.md](../../../../../Sources/CADGeometry/StructuralGeometryWork/DESIGN.md).

The focused fixture exercises actual OriginalQueryExecution/OriginalQueryBudget
paths: exact Native surface and curve fee sequences, primitive/all five analytic
surface families and a recursive offset; Native work N=73 and N−1=72, cumulative
shared-owner work 146, no source mutation or storage fee; checked actual cumulative
Int.max overflow for Native and plane; entry and terminal cancellation. The same
Mutex-protected observers and cancellation state are used for every target.
Production traversal introduces no shared mutable state.

The new fixture initially omitted the child Surface discriminator in the expected
offset fee sequence. Before any portable client compile, only that expected literal
was corrected to the original `[1,1,1,1,4,1]`; no production fee or cap changed.
[fixture-freeze-r2.json](fixture-freeze-r2.json) retains the exact before/after hashes.
Final portable fixture SHA-256 is
`fe043859ebb6d290c4cc0c85a2d584d4a5c01bca3f139d48bd19df34c7c97bc8`;
Native fixture SHA-256 is
`71e88abba3ccc955d3690fc634dbbc0349f7d1eaee8cec94e8cf4871ab2b26fe`.

## Actual portable execution

| Lane | Fresh Geometry (s) | Link (s) | Runtime (s) | Result |
|---|---:|---:|---:|---|
| ASAN / macOS 27.0 | 120.164 | 2.278 | 1.166 | four exact PASS lines |
| normal WASM | 110.793 | 1.601 | 0.228 | four exact PASS lines |
| Embedded WASM | not started | not started | not started | pending next source boundary |

Both completed lanes use pinned Swift 6.4.0 release and the existing verifier and
process-tree monitor, one compiler, 1,200-second compile/link ceiling, 120-second
runtime ceiling and 10-GiB RSS ceiling. Matching retained Lineage Core/Collections
products were strictly receipt-gated; Core and lower/common proofs were not
regenerated. Each lane generated fresh Geometry once. Endpoint, boundary and G01
runtime groups were not replayed.

Both terminal receipts report passed with no source, snapshot or product drift.
One final integrity gate checked 2,246 unique inputs, 4,492 pinned snapshot files,
18 products and six phase logs with no mismatch. Each terminal receipt and phase
log was copied immediately after success.

[summary.json](summary.json) indexes actual phase measurements and remaining scope.
[provenance.json](provenance.json) records actual input/product/log hashes. The
`structural-surface-asan/` and `structural-surface-wasm/` folders retain the exact
receipts, focused summaries and phase logs. Binaries and full source snapshots
remain under the absolute durable artifact root named in those receipts.

Native Drawing passed the measured meter stop and then reached a different
silhouette entry stack stop. Root owns that subsequent minimal source change and
the final caller integration result. These retained ASAN/WASM results remain
scoped to their frozen source authority; they are not relabeled as evidence for
later source snapshots. Root may compose their unchanged metering premise with
subsequent separately verified deltas.
