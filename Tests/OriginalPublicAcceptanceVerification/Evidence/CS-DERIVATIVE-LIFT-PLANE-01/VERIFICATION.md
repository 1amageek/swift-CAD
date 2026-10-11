# CS-DERIVATIVE-LIFT-PLANE-01 Verification

The fixed derivative-host/Native-pcurve ordinary public cell passes twelve groups
on Native, ASan, ordinary WASM and Embedded WASM. These are terminal behavioral
results for this cell; broader host/pcurve combinations retain their explicit
incomplete-implementation markers. Main integration and the single comprehensive
review are separate delivery responsibilities.

| Lane | Terminal receipt | Compile wall seconds | Twelve runtime groups, summed seconds | Exact storage success / one byte less |
|---|---|---:|---:|---|
| Native | [v10](accepted/cs-derivative-lift-plane-native-20261011-v10/receipt.json) | v5 port 8.729; v10 fixture 1.906 | 12.082 | 8,115,568 succeeds / 8,115,567 refuses |
| ASan | [v1](accepted/cs-derivative-lift-plane-asan-20261011-v1/receipt.json) | port 13.981; fixture 3.780 | 15.603 | 8,115,568 succeeds / 8,115,567 refuses |
| Ordinary WASM | [v1](accepted/cs-derivative-lift-plane-wasm-20261011-v1/receipt.json) | port 8.655; fixture 1.753 | 18.655 | 4,121,220 succeeds / 4,121,219 refuses |
| Embedded WASM | [v1](accepted/cs-derivative-lift-plane-embedded-20261011-v1/receipt.json) | port 50.756; fixture 40.514 | 11.486 | 4,121,220 succeeds / 4,121,219 refuses |

Every final lane compiles exactly the same fixture bytes, SHA256
`0609ef09434364ebbfd3bff699b65b9498567d7ef9dbf84062be5675fc5ee66c`,
with driver SHA256
`53ffaa816236eb1f0ecaeedee99704435c624879c3d452b7b091aae31974f30d`.
Native v10 freshly compiles this final fixture against the matching current
[v5 consumer port](reused-current-port/cs-derivative-lift-plane-native-20261011-v5/port-receipt.json).
Its earlier, smaller fixture is preserved as historical port provenance, not the
final twelve-group cell proof. Other final lanes compile their own current port
and fixture. Each port receipt is persisted immediately after successful compile,
source/product/log admission and before compiling its fixture.

```text
admitted RetainedHostAdapters source/DI + admitted PublicLiftPlane L2-L6
    -> 61 current selected consumer bodies (DerivativeLiftPlanePort)
        -> actual ordinary standard/callback bare/rich APIs
            -> original equations + weights/guards -> L5 -> L6 -> retained points
```

The driver uses the fixed Swift 6.4.0 release compiler and matching SDK flags
recorded verbatim in each compile command; WASM executes on Node.js 24.19.0 WASI
Preview 1. It compiles no lower source/DI or L2-L6 bodies and performs no broad
CADCore/CADGeometry/Kernel build. `RetainedHostAdapters` owns the derivative
source, chart/DI contracts and nominal issued fields. The selected polynomial
reducer, graph compiler, resolver and publisher consume those same contracts.
Explicit qualified imports resolve the existing verification namespaces; no
unchecked nominal conversion, source reconstruction or replacement field is used.
Polyline regressions use the existing constructor bodies and minimal existing
consumer-side provider sources against the same retained contracts.

| Independent oracle | Checked result |
|---|---|
| Source | Existing `DerivativeHostShape.shape(weighted:true,projected:true)` and mode0 Native diagonal degree-one B-spline pcurve; whole T=[0,1] |
| Target | Whole plane x=1/2, original normal unitX |
| Root and position | Sole T=1/2, XYZ=(1/2,1/2,5/32) |
| Correspondence | Host UV=(1/2,1/2), plane UV=(5/32,-1/2), every original T/UV witness retained |
| Incidents | All eight closed source incidents, mapped to one numerical representative; no incident loss |
| Dimensions | Parameter, image and fiber dimensions zero for every returned stratum |

The canonical endpoint first-derivative basis is
`-4v^3+7v^4-3v^5`, owned by `OriginalPlaneHermiteDerivativeBasis` and consumed
by both the original rational atlas and interval-jet evaluator. At v=1/2,
h10=5/32, h11=-5/32, h21=1/64 and the weighted construction scalar is 1/2;
the projected scalar is 5/8 and multiplication by u(1-u)=1/4 gives Z=5/32.
The prior derived value 65/512 was an arithmetic error, not a source contract or
user requirement. The original [prechange observation](STOP.md), its nineteen-file
manifest and all raw fixture/log bytes remain unchanged. In particular, the v4
failed numeric assertion is preserved under diagnostics and is not positional
acceptance evidence.

| Group | Behavior checked |
|---|---|
| ordinary | Actual standard bare/rich and callback bare/rich, exact oracle, all eight incidents and dimensions |
| regressions | Current new port executes unchanged Coons and correction polyline inputs through all four public entries; two distinct T roots with equal XYZ, 8/4 and 2/1 incident groups respectively |
| selections | T singleton, root-free, outside-support and excluded plane UV; successful empty requires retained complete empty geometry/mapping |
| remainder | Same derivative input, unitZ plane at Z=5/32 and T singleton .5, exact XYZ/sourceUV/planeUV=(.5,-.5), all eight incidents |
| query-work | Original finite 8,388,608-work allowance succeeds; fixed callback caps 1 and 100,000 refuse with typed resource error at exactly the cap |
| query-storage | Fresh independent query succeeds at measured exact storage total and refuses one byte below |
| depth | Source depth 3 succeeds, depth 2/1/0 refuse; candidate count 8 succeeds, 7 refuses; polynomial degree 0 refuses; rational-only algebraic depth 0 succeeds |
| cancel-entry | Already canceled Task refuses before work/storage callbacks |
| cancel-callbacks | Entry/mid callback cancellation at ticks 1 and 100,000 propagates cancellation |
| cancel-final | Task cancellation at final nonempty result allocation prevents publication |
| cancel-empty | Outside-support [2,3] complete-empty success calibration, then Task cancellation at its final allocation prevents publication |
| lifetime | Result retains input owners after scope, pcurve/construction point COW, independent concurrent exact readers |

The horizontal-plane singleton control establishes successful retained
high-degree request/publication. Its public DTO does not expose/assert whether
exact division had a nonzero remainder or a higher-degree quotient; it covers the
retained-full-query path without claiming direct nonzero-remainder inspection.
The production branch preserves the original binding/equation/weights/conditions:
only identity T transport plus exact zero remainder of division by the full
nonconstant homogeneous weight and quotient degree at most one permit candidate
restriction. The existing L5 map retains the weight nonzero guard. Nondivisibility
or a higher-degree quotient retains the original L5 request; arithmetic, resource
and cancellation failures propagate.

Full-query work is not claimed deterministic or tested as exact N/N-1. The
unchanged per-unit owners are `NativeExactPublicAdmission.swift`, SHA256
`90a08d932a2e1cac506a74aa35056bf33ffd7a48a62b2ef8d5728efeda817dd4`, and
`NativeCurveSurfacePointAllowance.swift`, SHA256
`cdb345512c2dc14f01a5ec59afb1887efbc71d98328ac8928a7209adeb57e099`.
Their admitted previous resource evidence is reused compositionally:
[Native](../CS-POLY-COINC-01/native/receipt.json),
[ASan](../CS-POLY-COINC-01/asan/receipt.json),
[WASM](../CS-POLY-COINC-01/wasm/receipt.json),
[Embedded](../CS-POLY-COINC-01/embedded/receipt.json).
Those receipt hashes and unchanged body hashes are present in every final lane's
admitted checks. This cell verifies forwarding original callback failures through
the new routing, not new lower admission arithmetic.

| Operational observation | Recorded value |
|---|---|
| Native / ASan / WASM compile bounds | 120 seconds wall and per-process CPU |
| Embedded compile bounds | 600 seconds wall, 300 seconds per-process CPU, two compiler threads |
| Runtime bounds | 120 seconds wall and per-process CPU per group |
| Embedded port sampled CPU / peak owned RSS sum | 69.18 seconds / 7,401,856 KiB |
| Embedded fixture sampled CPU / peak owned RSS sum | 67.21 seconds / 7,642,784 KiB |
| Embedded maximum runtime owned RSS sum | 314,992 KiB |
| Cleanup | Every terminal run reports no remaining owned descendants and no timeout |

RSS is a sampled sum over owned processes, not unique physical RAM; shared pages
may be counted repeatedly. Runtime sums are sums of recorded group elapsed values,
not an end-to-end wall measurement. Compiler monitoring bounds do not change CAD
caller limits. The shared Counter storage/isolation is `Mutex<State>` on every
lane; reads/mutations use `withLock`, and external cancellation occurs after the
lock is released. Embedded conditionals only select group/log APIs, not weaker
state, conformance or ownership contracts. No new unchecked concurrency is added.

The [acceptance manifest](acceptance-manifest.json) records exact hashes and
original scratch paths for immutable raw receipts, commands, logs, generated
sources and current inputs. Binary modules/archives/executables remain in their
admitted scratch paths, with product digests and compiler provenance preserved;
large binaries are not copied into the repository. Every lane admits all reused
premises before execution and rechecks source/product/log hashes afterwards.
Historical changed-root comparisons use matching immutable git blobs or original
compiled snapshots, never an old expected hash falsely matched to new production.

Diagnostics remain separate: v1/v2 selected namespace assembly errors; v3 original
work exhaustion; the explicitly instrumented stage run locating pair4 L5 with
residual/weight degrees10/9; v4 rejected65/512 numeric assertion; and v6/v7 rejected
algebraic-depth0 refusal premise. Failed v3/v4/v6/v7 preserve post-run premise
checks and descendant audits. These failures are not classified as successful
cells or erased by later success. No source/DI re-solve, new shape capability,
new solver or caller-limit increase was introduced.
