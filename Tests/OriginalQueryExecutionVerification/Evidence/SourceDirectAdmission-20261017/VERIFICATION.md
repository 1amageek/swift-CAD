# SOURCE Direct Admission Verification — 2026-10-17

This package records the finite four-file SOURCE correction. It does not establish completion of U1, G01, all source families, or all project requirements. The JSON index contains exact source, receipt, toolchain, product and log hashes; this document adds no execution evidence.

## Implementation and ownership

| Source owner | Change | Contract/test owner |
|---|---|---|
| `NativeSurfaceEmbedding/BSplineSurfaceEmbeddingValidator.swift` | Resolve stationary native support through the existing direct planar resolver on the caller execution; remove the fixed replacement fee. | [Native embedding design](../../../../Sources/CADGeometry/NativeSurfaceEmbedding/DESIGN.md), shared stationary/source-depth and caller-resource checks |
| `ExactIsoparametricPlanarIntersectionGraph.swift` | Pass the same execution to the two selected middle-curve jet readers. | [Geometry graph contract](../../../../Sources/CADGeometry/DESIGN.md), shared graph checks and separate public four-cell regression |
| `ParameterImage/OriginalParameterGain.swift` | Charge actual typed factor capacity before retention; preserve flattened factor order and original multiplication. | [Parameter image design](../../../../Sources/CADGeometry/ParameterImage/DESIGN.md), typed-storage, exact-limit, COW and nested-factor checks |
| `ParameterImage/ParameterImageCurve3D.swift` | Ordinary validation uses its one existing execution; preserve the original ordinary nil-phase arithmetic. | Same parameter-image contract, independent authored image-law checks |

[Shared checks](../../../CADGeometryTests/SourceDirectAdmissionChecks.swift) are used by both [Native source wrappers](../../../CADGeometryTests/SourceDirectAdmissionGapTests.swift), [Native graph wrappers](../../../CADGeometryTests/SourceIsoparametricAdmissionGapTests.swift), and the [portable entry](../../SourceDirectAdmissionPortable.swift). The Native wrappers have eight declarations with thirteen expanded SOURCE inputs. They verify original laws, actual caller admission, independent resource axes, exact N/N−1 work/storage limits, entry/terminal cancellation, retained factors and COW. The public four-cell sphere graph test is separate from the internal fee probes.

## Accepted behavior and its premises

| Execution | Actual accepted result | Scope |
|---|---|---|
| Native original r3 | 19/20 expanded inputs passed; the one failure was the invalid interval bit-parity premise. Twelve of thirteen SOURCE inputs passed, together with separate metadata/public graph/native-corner controls. | Retained old Core binding; not a single all-green Native run |
| Native corrected r4 | The corrected factor/image-law function passed (one test). | Current Core/Geometry; composes with the unchanged twelve SOURCE successes |
| ASAN r3 | 13/13 SOURCE inputs passed | Retained old Core contract, no module regeneration |
| Normal WASM r3 | 13/13 SOURCE inputs passed | Retained old Core contract, no module regeneration |
| Embedded WASM r3 | 13/13 SOURCE inputs passed | Retained old Core contract, no module regeneration |
| Current Native/ASAN/WASM/Embedded Core/Geometry | Compilation passed | Separate compile evidence; not current-Core SOURCE13 runtime evidence |

The frozen compiler is Swift 6.4.0 with the matching normal/Embedded WASM SDK; Native uses macOS 27. Exact commands and SDK/tool hashes are in the referenced receipts. Limits remain 1200 seconds and 10 GiB per compile/link phase, 120 seconds per runtime, and one compiler job. Native source/test/product checks and final portable postflight checks recorded no drift.

The runtime Core binding is explicit: the sole old-to-current Core difference accepted by Root is an additive `Expression` API change, with unchanged ABI and zero references from the 2171 Geometry sources. Current four-target Core/Geometry compilation passed separately. We do not relabel the three retained-Core SOURCE13 executions as current-Core runs.

## Resolved fixture finding and preserved diagnostics

The newly added `ordinary == admitted` interval-width assertion failed on both the changed implementation and the historical 3927-source library. The historical one-function baseline is pinned in the index (`cadd4417…32777`). The original contract requires enclosing the authored map, not bit-identical outward widths between the ordinary binary-interval and admitted rational-endpoint algorithms.

Only that fixture premise was corrected. For the authored map `q(t) = 1 − 2t` on `[0, 1]`, monotonicity and the endpoint values prove the complete image `[-1, 1]`. Both enclosures must contain −1, 0 and +1. The independent point `q(1/4) = 1/2`, rational zero-depth, COW, nested-factor, resource and cancellation checks remain. Production formulas, fees, caps and the ordinary nil-phase were unchanged. The private finding freeze preserves exact before/after bytes and inverse recovery of the old fixture.

The initial historical four-input admission RED, generic ASAN failure, diagnostic ASAN failure, Native r3 failure and historical invalid-premise baseline remain explicitly failed diagnostics at their hashed durable origins. They are not counted as successes. The independent review found no SOURCE blocker; its mixed scope also included the separate `OriginalQueryFailure` diagnostic-prefix file, which is excluded from this four-file SOURCE commit.

## Preservation

[index.json](index.json) is the compact provenance index. `receipts/` contains exact gzip copies of the three accepted portable client receipts and the two Native composition receipts. `logs/` retains exact small runtime logs and Native XML. Full source maps, compiler products and immutable snapshots remain at the absolute durable paths recorded in the index; no binary or large source tree is duplicated here. No build or test was repeated to create this package.
