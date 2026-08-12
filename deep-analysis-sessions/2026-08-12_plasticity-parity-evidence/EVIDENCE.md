# Plasticity-parity evidence manifest — 2026-08-12

## Build identity
- Commit: 4e628cb (main; suite matrix re-verified on this build)
- Toolchain: Apple Swift 6.4-dev (LLVM 264fd65923c28d9, Swift ef761e567dc94ee), swiftly 1.1.0
- Target: arm64-apple-macosx27.0.0
- Lane: `swift build -c release --build-tests --scratch-path .build-release -Xswiftc -enable-testing`
  followed by `swift test -c release --scratch-path .build-release --skip-build --no-parallel --filter <suite>`

## Suite results (release lane, sequential)
| Suite | Passed | Failed |
|---|---|---|
| CADCoreTests | 23 | 0 |
| CADGeometryTests | 404 | 0 |
| CADIRTests | 216 | 0 |
| CADKernelTests | 501 | 0 |
| CADTopologyTests | 82 | 0 |
| CADModelingTests | 71 | 0 |
| CADExchangeTests | 197 | 0 |
| SwiftCADTests (facade, minus boolean integration) | 90 | 1* |
| PrimitiveSphereBooleanIntegrationTests | 3 | 0 |
| PrimitivePlaneTorusBooleanIntegrationTests | 3 | 0 |
| PrimitiveGeneralSphereTorusBooleanIntegrationTests | 3 | 0 |
| PrimitiveGeneralTorusTorusBooleanIntegrationTests | 3 | 0 |
| PrimitiveGeneralConeTorusBooleanIntegrationTests | 3 | 0 |
| PrimitiveFaceContainmentTests | 2 | 0 |
| OffsetSphereOctantContainmentTests | 1 | 0 |
| TiltedConeApexContainmentTests | 1 | 0 |

*The single failure is `facadeBuildsCurveEditSweepThroughSharedOperations`:
path-normal sweep along a general curved path requires an exact
moving-frame surface construction that does not exist yet. The failure is
a typed unsupported case (`sweepPathNormalUnavailable`), not a defect.

## Timing notes
- Cone-torus Booleans: 38 s / 117 s / 117 s (first passes ever; five-minute limit restored).
- Sphere-torus intersection: 236 s (known performance debt versus the 137 s
  pre-snap baseline).
- Determinism: KernelQueryPipelineTests passed 4/4 on five consecutive runs
  after authoring-order extraction (previously flaked at two failures in
  three runs).

## RupaKit (Rupa repository, commit 52591c8)
- Full suite: 2218 passed, 0 failed (debug lane, single run with
  `BUILT_PRODUCTS_DIR=<repo>/.build/debug`; the CLI process tests locate
  the `rupa` executable through that variable because `swift test` runs
  in-process and Bundle.main points into the toolchain).
- The one parity leftover (trim-loop edge persistent names) is delivered:
  authored trim edges carry kernel edge-ordinal names and the CLI test now
  locks that behavior in.

## Known open items (verified against doc.plasticity.xyz)
1. Path-normal sweep on general curved paths (task #21).
2. Mirror / symmetric duplicate (task #22) — absent from FeatureOperation.
3. Project curve onto surface or body (task #23) — no user-facing feature
   op; kernel projection machinery exists.
4. Join/unjoin as a user-facing operation — in scope (listed in
   Plasticity's tool manual); sewing machinery exists internally.
5. Isoparm extraction — deferred: a modeling aid rather than a
   geometry-producing operation, and no evaluator or test depends on it.
6. Deform/slide and xNURBS-class surfacing (Square, Refit Face, explicit
   Rebuild) — out of scope: Studio-tier tools built on a proprietary
   third-party solver; the Indie-tier tool set is the parity baseline.
7. Twelve typed-unsupported envelope boundaries in modeling/kernel remain
   by design (explicit contracts, not silent gaps).
