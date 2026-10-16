# Existing delivery-helper verification

This package proves the bounded behavior of three existing Geometry helpers at source commit `e842d55a`. It does not complete all of U1.SOURCE, general M4 support equivalence, cyclic degree elevation, G01, Bridge or Rebuild consumers.

| Target | Actual result | Fresh work |
|---|---|---|
| Native, Swift 6.4.0 / macOS 27 | 11 test declarations in 3 suites; 13 expanded input cases; all pass | Build/link test client, then runtime |
| ASAN, Swift 6.4.0 / macOS 27 | 8 exact oracle lines pass | Compile/link client, then runtime |
| Normal WASM, matching Swift 6.4.0 SDK | 8 exact oracle lines pass | Compile/link client, then runtime |
| Embedded WASM, matching Swift 6.4.0 SDK | 8 exact oracle lines pass | Compile/link client from serialized modules, then runtime |

```text
Root Native source receipt: 65 Core + 2170 Geometry sources
    -> exact retained Native / ASAN / WASM / Embedded module products
        -> fresh helper clients -> actual positive/refusal/lifetime/resource oracles
```

No Core or Geometry module was regenerated for these helper runs. Each portable receipt has only `link` and `runtime` phases; the link command also compiles the fixture. Native builds the selected Swift Testing client against accepted modules. Exact source/product hashes and original absolute product, command, toolchain and SDK paths remain in the unmodified receipts. `index.json` connects these records and copied file hashes. No binary or production source snapshot is copied here.

## Contracts exercised

| Helper | Independent positive / ownership controls | Failure and resource controls |
|---|---|---|
| Degree elevation | U/V rational surface, doubled interior knot, raised basis and positive weights; 21×21 source evaluation; generic scalar and query owners agree | Existing 1024-control ceiling, unclamped refusal, exact N / N−1 work and storage, cumulative exhaustion, cancellation |
| Intersection support | Both retained plane/torus hosts; parameter image, rigid image and certified pcurve lift; retained source lifetime | Displaced host within tolerance declines with `nil`; source-depth exhaustion throws; exact N / N−1 work, cumulative exhaustion, cancellation |
| Natural continuation | Independent piecewise-linear end-span law in both axes, common nonunit weights, retained COW source; same/foreign reader budgets | Cold preparation/read N / N−1 work and storage; cumulative ordinary reader; entry/terminal cancellation; mapped source-depth refusal before paid contribution attachment |

The Native count is 11 declarations, not 13 declarations: two declarations each execute U and V arguments, yielding 13 input cases. Portable counts are 8 oracle groups per target, not 24 independent test declarations. Runtime assertions and original tolerances/caps were not changed for these runs.

[Geometry contract](../../../../../Sources/CADGeometry/DESIGN.md) owns these helper semantics. The exact portable fixture and four Native test/helper inputs are preserved under [fixtures](fixtures/). General equivalent-description host membership remains explicitly incomplete; natural continuation is a numerical point reader and does not itself prove whole-domain denominator positivity or publication deviation.

## Evidence and limitations

- [Native receipt](native/receipt.json), [runtime](native/test-runtime.log), [XML](native/results.xml): production source/products unchanged; actual tests pass in 0.264 seconds.
- [ASAN receipt](asan/receipt.json), [runtime](asan/asan-runtime.log): 8 lines pass.
- [WASM receipt](wasm/receipt.json), [runtime](wasm/wasm-runtime.log): 8 lines pass.
- [Embedded receipt](embedded/receipt.json), [runtime](embedded/embedded-runtime.log): 8 lines pass.
- [Source authority](origins/native-source-receipt.json): SHA `ce70b1a795f1b923941eebde77612357eba8e804c12769e9e7c9ec409e07d116`, complete 2235-source map. All three portable drift arrays are empty; Native reports `sourcesAndProductsUnchanged: true`.

Earlier helper logs under the deleted `.build` were not recovered or reconstructed. These fresh executions supply the current helper behavior evidence; earlier silhouette-only runtime groups are not counted as helper execution.

Retained portable module proofs carry `resourceBoundProven: false` and their recorded initial-PGID-sampler limitation. This package preserves that historical compile-monitoring limitation and does not claim a newly proved resource bound for those old module compilations. The new client phases use the current bounded PPID/process-group monitor, with 1200-second / 10 GiB build and 120-second runtime ceilings and one compiler at a time. Exact commands, resource observations and tool/SDK hashes are preserved in each receipt.
