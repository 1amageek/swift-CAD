# Unreferenced Private Helper Removal

Base: `167322aeb3fa9d3a5405a06a291b5a3f43aad7c7`.
Scope: thirteen private helpers, seven files, 492 deleted source lines including attached comments/attributes.

Each removed method has no remaining name reference in its containing file. Private access, absence of dynamic/Objective-C dispatch and inspection of the actual production callers establish that these methods are unselected. Every byte outside the recorded deletion ranges is unchanged. Active unsupported branches and their incomplete-implementation markers remain; removing obsolete markers does not complete those capabilities.

One complete review confirms that only the selected declarations and attached comments/attributes are removed. Shared storage, synchronization, conditional compilation, public APIs and all retained success/failure paths are unchanged.

Fixed compiler: `Apple Swift version 6.4 (swift-6.4-RELEASE)`, target `arm64-apple-macosx27.0.0`.
`swiftc -frontend -parse -module-name PrivateHelperRemoval -package-name SwiftCAD <seven files>` passes (0.214s, 60s timeout).
The same command with `-enable-experimental-feature Embedded -whole-module-optimization` passes (0.196s, 60s timeout).
`git diff --check` passes.
These are syntax and source-preservation checks, not type-check, link, runtime, sanitizer or WASM execution evidence. No existing cached executable was used as evidence for the changed snapshot.

| File | Removed methods | Accepted source SHA-256 |
|---|---|---|
| `Sources/CADKernel/MeshTessellator.swift` | `legacyBoundaryUsageEstimate`, `circularStepCount`, `boundsPerCurvedDirection`, `linearStepCount`, `appendTrimmedParametricFace`, `hasSingularBoundary` | `9e2efd5c30168ef56ecf82b5b85acaa00a6c1037e89119be18929079eea6055c` |
| `Sources/CADModeling/Loft/LoftFeatureEvaluator.swift` | `trimmedToGuides`, `resolvedProfiles` | `f5e31b28912d5cae7e242cb181ad660e6ff1707d903d61ca3318a2b818211af1` |
| `Sources/CADGeometry/DefaultCurveDifferentialEncloser.swift` | `bSplineJet` | `08189005c2938492616c2921d64673fc97088b298a023d305b00a6039a773997` |
| `Sources/CADGeometry/ImplicitCurveIntervalJetEncloser.swift` | `isSinglePositiveWeightSpan` | `05723e089843fa10428a768cf07a333238b19633c0222ebb52395bee73f82517` |
| `Sources/CADKernel/SelectionMeasurementEvaluator.swift` | `projectedCurveDistance` | `16eebfa77223cb227185c4b842aaaaf65efaebc2a73a38b0cbb120ba09446a1e` |
| `Sources/CADKernel/BooleanOpenFaceArrangementBuilder.swift` | `selectedAction` | `ca7eb49ce93649db68be0c71b7c46bfcac092a0ecfeed560f5bb4c19b62d7450` |
| `Sources/CADKernel/SurfaceQueryEvaluator.swift` | `finiteInterval` | `86e67fa271e5898f651016b61a2fe5c936cdeb22a17f80094de70753788368bc` |

Compiler SHA-256: `79ae5c26645489fb783ae980f0f1bdae810f90fb180c9ac39808807b65e9fd69`.

Delivery: `dc36b2ad` fast-forwarded into `codex/m4-m8-completion`. An independent reverse-patch copy exactly reproduces every pre-integration owned path, including the other work in Boolean error handling and PROGRESS. No foreign work was staged, stashed or committed. Post-integration Native-mode syntax parsing and the committed removal diff check pass. `main` is unchanged. The delivery-record commit only closes this progress/evidence entry.


## Latest-main integration

The isolated integration combines removal commits `dc36b2ad` / `2178ba92`
with main `c6468c45`. All seven main source inputs exactly match the original
verified base `167322ae`; all seven resulting files exactly match the accepted
SHA-256 values above. The existing declaration review and Native/Embedded
syntax evidence therefore remain applicable without rebuilding unrelated modules.
The complete source diff removes exactly thirteen private declarations and492
source lines, adds no source, and leaves no references to the removed names in
their owning files. No removed declaration has Objective-C/dynamic dispatch,
and no shared-state, synchronization or target-conditional storage is changed.
All five current execution-policy designs from `c6468c45` remain byte-identical.
The original cleanup worktree's U1 migration is not staged, stashed or committed
by this delivery. The historical branch-delivery paragraph above predates this
main integration. No new runtime, feature-completion or broad build claim is made.

Main delivery: integration commit `830d3dbb` was fast-forwarded into clean
`main` and normally pushed to its configured `origin/main`. A live remote-tip
check confirmed equality. Both original cleanup commits are ancestors of that
tip; all seven source hashes still match the accepted table. The ongoing U1
worktree remains on `2178ba92` with its migration changes outside this delivery.
