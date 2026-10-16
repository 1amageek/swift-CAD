# Endpoint equality and Native boundary portable verification

This package records real fresh ASAN, normal WebAssembly, and Embedded WebAssembly verification against the recovered Native source authority. It verifies the two focused source contracts below. It does not claim whole G01, U1, or U4 completion.

## Authority and execution

- Native authority: `/Users/1amageek/.codex/verification-artifacts/swift-CAD/g01-direct-20261016/native-production-r1/receipt.json`, SHA-256 `7432d8f66382f64727a09d00855477623f40099f337b0b8992e37995365b4041`.
- Source root: `/Users/1amageek/.codex/worktrees/g01-direct-delivery-20261016/swift-CAD`; exactly 65 Core and 2,170 Geometry sources.
- Toolchain: pinned Swift 6.4.0 release. ASAN targets macOS 27.0. Normal and Embedded WASM use the matching release SDKs and `wasm32-unknown-wasip1`; receipts record exact compiler, linker, SDK metadata, flags, commands, dependency origins, and product hashes.
- Existing `verify_full_geometry.py` orchestrates each run with the existing PPID/process-group bounded monitor. Geometry is generated once per lane. Receipt-gated surviving Lineage Core/Collections products are reused; Core and independent lower/common proofs are not regenerated.
- Per-lane compile/link ceiling is 1,200 seconds, runtime ceiling 120 seconds, process-tree RSS ceiling 10 GiB, compiler concurrency one. No cap or stack setting is raised for these runs.

```text
Recovered immutable Native source authority
  -> exact surviving Core/Collections receipt gates
  -> fresh Geometry per lane
  -> endpoint client: three exact runtime oracle lines
  -> identical Geometry/Core products reused
  -> boundary client: five exact runtime oracle lines
  -> terminal receipts and logs copied immediately
```

## Actual behavior

| Lane | Fresh Geometry (s) | Endpoint link / runtime (s) | Boundary link / runtime (s) | Result |
|---|---:|---:|---:|---|
| asan | 121.478 | 2.303 / 1.159 | 4.013 / 2.038 | 3 + 5 PASS |
| wasm | 172.726 | 4.930 / 0.835 | 1.607 / 0.230 | 3 + 5 PASS |
| embedded | 295.011 | 126.671 / 0.250 | 92.605 / 0.255 | 3 + 5 PASS |

All six terminal receipts report `passed`; final source inputs, pinned snapshots, products, and logs match their recorded hashes. The machine also ran unrelated Swift compilers during this sequence; observed durations are reported rather than substituted with prior timings.

The endpoint fixture is [OriginalNativeEndpointPositionPortable.swift](../../../OriginalNativeEndpointPositionPortable.swift), SHA-256 `426e6319bc2c77057bde29ff878c60172cc9067abe536e55ba0c9636339cbea4`. It executes the actual endpoint relation, verifies exact Native payload positions and retained lifetime, source differences and cumulative work, and cancellation. Its three required lines are retained in every lane's runtime log. The owning contract is [OriginalRootSpan/DESIGN.md](../../../../../Sources/CADGeometry/OriginalRootSpan/DESIGN.md).

The boundary fixture is [NativeBoundaryPortable.swift](../../../NativeBoundaryPortable.swift), SHA-256 `bb7dc36f277993b00b2938a9a943106f4abb60f27618c8a0d131f3fc6fddbc25`. It executes actual `OriginalBoundedCurveSurfaceCorrespondence.deviationBound`: degree-one and degree-two stored Native boundary laws across all four boundaries, stored reversal and directed traversal; valid near/foreign payload and map refusal; exact N/N−1 work/storage, cumulative/COW/lifetime and source-depth controls; entry and terminal cancellation. Its five required lines are retained in every lane's runtime log. The owning contract is [OriginalCurveSurfaceCorrespondence/DESIGN.md](../../../../../Sources/CADGeometry/OriginalCurveSurfaceCorrespondence/DESIGN.md).

The boundary receipts retain exact Geometry reuse provenance. Their `reusedGeometryProof.resourceBoundProven` convenience flag uses a historical RSS-scope string comparison and can read false for the newer monitor wording. The original successful compile phase, actual tracked-process accounting, limit, measured peak, and stop result are preserved; the summary checks those actual phases and the identical product hashes.

## Evidence and scope

[summary.json](summary.json) indexes six successful terminal receipts and actual phase costs. [provenance.json](provenance.json) records source/input/product/log hashes and absolute durable artifact paths. Each `endpoint-<lane>/` and `boundary-<lane>/` directory contains its original receipt, focused summary, and phase logs. Binaries and source snapshots remain in the durable artifact root; this package contains no substitute products or regenerated historical receipts.

The historical [frame-fixed portable proof](../frame-fixed-portable/VERIFICATION.md) preserves the executed public G01 fixture scope before the two subsequent source deltas. These runs do not replay its six G01 groups and do not label that historical source map current. The corresponding [boundary Native evidence](../boundary-proof-native/VERIFICATION.md) and Root-owned endpoint Native evidence establish their separate scoped premises. Composition and overall completion remain Root responsibilities.

The previously observed `.build` receipts `c8d666…` and `c9554…`, logs, and products were deleted before packaging. They are not reconstructed here, and their observed historical success is not presented as durable evidence. This package's six new receipts are the actual retained replacement evidence for the two focused target behaviors.
