# CS-POLY-CORRECTION-01 Verification

The fixed ordinary corrected-polyline-lift/plane cell passes all ten groups on
Native, ASan, ordinary WASM and Embedded WASM. One comprehensive
[review](REVIEW.md) approves the cell with no finding. Implementation commit `b4bfb2bef42a1254e39d5ae8ae800cbf1063e70a` is main-integrated
through a normal fast-forward after independent latest-main comparison. Terminal acceptance and historical
failed attempts are preserved separately.

| Accepted lane | Terminal receipt | Runtime groups | Exact storage success / one byte less |
|---|---|---:|---|
| Native | [v3 receipt](accepted/cs-poly-correction-native-20261011-v3/receipt.json) | 10 | 6,693,548 succeeds; 6,693,547 refuses |
| ASan | [v3 receipt](accepted/cs-poly-correction-asan-20261011-v3/receipt.json) | 10 | 6,693,548 succeeds; 6,693,547 refuses |
| Ordinary WASM | [v3 receipt](accepted/cs-poly-correction-wasm-20261011-v3/receipt.json) | 10 | 4,065,192 succeeds; 4,065,191 refuses |
| Embedded WASM | [v6 receipt](accepted/cs-poly-correction-embedded-20261011-v6/receipt.json) | 10 | 4,065,192 succeeds; 4,065,191 refuses |

Each accepted receipt records `changed-public-path-verified`, its exact lane,
parent receipt, production hashes and admitted checks. Each lane's `runs.json`
records successful focused proof compile/link and all ten runtime groups:
ordinary, coons-regression, selections, query-work, query-storage, depth,
cancel-entry, cancel-callbacks, cancel-final and lifetime. Commands, timeout/CPU
limits, generated Proof.swift, driver.py and unmodified logs are alongside it.
These receipts establish only their listed cell, lane and groups, not whole-family completion.

| Lane | Focused compile/link elapsed | Sum of ten runtime-group elapsed values | Peak owned-process RSS sum |
|---|---:|---:|---|
| Native v3 | 28.085 s | 110.614 s | Not recorded by the original driver |
| ASan v3 | 86.193 s | 160.259 s | Not recorded by the original driver |
| Ordinary WASM v3 | 44.879 s | 204.376 s | Not recorded by the original driver |
| Embedded v5 successful port | 422.070 s | Reused port only | 2,410,992 KiB |
| Embedded v6 proof | 364.578 s | 18.511 s | 2,570,496 KiB during compile; 217,376 KiB maximum during runtime groups |
| Embedded v4 diagnostic | 300.427 s; port compile timeout | No fixture compile or runtime | 2,572,960 KiB |

The runtime sums aggregate recorded per-group elapsed values and are not an
end-to-end wall-time measurement. Embedded's `peakOwnedProcessResidentSumKiB`
was sampled about once per second and sums owned processes' RSS; shared pages
can be counted more than once, so this is not unique physical RAM. The
v4 `cleanup.json` records no live owned compiler descendants and no port receipt.
The final worker reports no live owned compiler/runtime descendants. Embedded v6
ordinary and Coons-control groups took 4.244 and 5.995 seconds; each other group
took less than two seconds.

Embedded's [operational policy](reused-port/cs-poly-correction-embedded-20261011-v5/operational-policy.json)
separates the revised compiler wall monitor of 600 seconds from the unchanged
300-second per-process CPU limit and two compiler threads. Runtime limits remain
120 seconds wall and per-process CPU. These compiler monitoring bounds do not
change CAD caller limits or assertions. Sampled owned-process CPU sums were
255.35 seconds for the v5 port and 268.79 seconds for the v6 proof; they are
observations, distinct from the per-process CPU limit.

| Input / independent oracle | Exact scope |
|---|---|
| Original constructor | `PolylineAtlasLiftProof.shape(multi: false).1`, retained as `originalBoundaryCorrected`, with `SurfaceLiftCurve3D` and existing `PolylineLiftProof.points()` |
| Target and request | Whole stored-N plane through `(1/2,0,0)`, normal `unitX`; full authored curve support `[0,1]` |
| Host law | `X=u`, `Y=v`, `Z=u(1-u)(1-H(v))/2`, `H(v)=10v^3-15v^4+6v^5`; original source coefficients and arc-length stations are reused |
| Complete roots | Positive root of `t^2+2t-1=0`, namely `sqrt(2)-1`, and `t=1`, kept distinct |
| Incidents | Three original incidents grouped 2/1 at the two roots, with every closed incident owner retained |
| XYZ and UV | Both roots have XYZ `(1/2,1/2,1/16)`, host UV `(1/2,1/2)`, plane UV `(1/16,-1/2)` |
| Dimensions | Two isolated original points, image dimension 0 and parameter-fiber dimension 0 |

The `ordinary` group exercises all four ordinary APIs on the actual corrected
host: standard `intersections`, standard `intersectionResult`, callback-admitted
`intersections`, and callback-admitted `intersectionResult`. Rich publication
checks exact root equations, source correspondence, plane UV and the 2/1 incident
mapping; numerical representatives do not merge equal-XYZ/distinct-T roots.
The same APIs run the unchanged planar Coons control with all twelve incidents
in 8/4 groups. Selection controls prove singleton, root-free, outside-support and
plane-UV-excluded requests using complete empty results where applicable.

The successful admitted query uses finite work/storage allowances of 8,388,608.
Work controls stop at callback caps 1 and 1,000,000 with typed resource failure.
Embedded v6 recorded 2,339,636 work callbacks on its successful finite query;
this measured count is not an exact full-query threshold.
Full-query work totals vary with retained exact owners; the historical attempts
to treat those totals as a deterministic exact/one-less threshold are rejected.
The unchanged lower admission owner retains its independent resource evidence,
including [the parent Native resource receipt](../CS-POLY-COINC-01/native/runtime-contained-resources.log),
through each lane's admitted parent checks. This is not a new exact threshold
claim for the whole corrected query. Storage controls instead measure the
lane-specific total above, admit a fresh independent query at that exact value,
and reject a fresh query at one byte less.

Depth, candidate-count and polynomial-degree controls preserve typed resource
failure. Cancellation controls cover entry before work/storage, exact callback
ticks and cancellation at final result storage before publication. Lifetime
controls read retained results after input owners leave scope, verify COW source
points, and run concurrent independent exact readers. No unchanged lower
algorithm, admission owner or lifetime contract is replaced by this package.

| Evidence relationship | Preserved boundary |
|---|---|
| Current accepted production | `freshProduction` in each accepted receipt identifies the two replacement producer/publication bodies; generated source bytes and successful compiler commands are under `reused-port/` |
| Reused compiler products | Each v3 `reused-port.json` points to its original v1 `build-receipt.json`. Embedded v6 strictly references the immediate successful v5 `port-receipt.json`, SHA `469dc0f2f60ed1e5b3f39f0ee89e78bfa3440b42e765148a0e52c0175319a7d1`, with 5,224 admitted checks. Successful compiler inputs/logs/metadata are copied without changing paths inside receipts. Earlier failed groups/products are not accepted through reuse |
| Fixture snapshots | The three v3 lanes retain fixture SHA `6ab027c0ad51b3915b77dcbba4c25019a100466616b677443a799a06d32789b7`. Embedded v6 uses fixture SHA `5894c92b68690789f03b0ecfa78c8805f07dc5042a19db4b900dce41f584a7d0` and driver SHA `6db89f41837075c9d4641b2e6ae43dcd46b490f892c5475d8da0fb73e8bed761`. The [logging delta receipt](accepted/cs-poly-correction-embedded-20261011-v6/fixture-logging-delta.json) mechanically reconstructs the exact old source for the selected unchanged non-Embedded bodies. Current whole-file byte identity across four lanes is not claimed |
| Parent evidence | [COINC evidence](../CS-POLY-COINC-01/VERIFICATION.md) and [ordinary evidence](../CS-POLY-01-ordinary/VERIFICATION.md) remain referenced by original paths and immutable hashes rather than duplicated |
| Prechange entry decline | [STOP.md](STOP.md), its raw receipt/logs under `prechange/`, and source bodies from commit `310ed10bae1d842529e14fefe79954e858ee75d5`; the producer hash is `863b7989810a8f6cdccea0bcb9e3f3bd6c85bfb1c05cc00e503572b5cebfd6e5` |
| Historical source paths | `package-manifest.json` maps STOP's old checked root paths to the historical source snapshot. Those checks are historical, not current-root acceptance; the selected-entry decline does not claim ordinary fallback failure |
| Rejected diagnostics | [Historical status](historical/STATUS.md) distinguishes failed work controls, count diagnostics and the stopped Embedded attempt from accepted terminal lanes |

Embedded v1's port compile exited successfully, but its product digests were not
persisted immediately after compilation before the proof was stopped. Its
archive/module therefore do not constitute an admissible historical reuse
receipt. The v3 port timeout and host-contention observation are historical
diagnostics. The separately authorized fresh sequential v4 attempt also timed
out during port compilation at the unchanged 300-second cap. No successful
port receipt, fixture compile or runtime exists for v4; its partial module
products are not admitted. The separately authorized v5 port succeeded and
persisted source, command, toolchain, log and product hashes immediately; its
later proof compile failed solely at two numeric variadic logging calls. That
proof diagnostic remains under `historical/`. Embedded-only logging changes
preserve input/query/assertion code as recorded in the delta receipt. V6 reused
the strict v5 port receipt and completed proof compile/link and all ten groups;
it did not reuse the unadmitted v1 or failed v3/v4 products.

`evidence-manifest.json` hashes packaged immutable files, excluding itself and
mutable verification/integration/review records. `package-manifest.json` retains
original-to-packaged paths and product hashes without binary/archive bytes;
hashes without an admitted historical comparator are explicitly limited to
packaging-time observations. Raw receipts, commands and logs remain unchanged.

Independent delivery matches 2,125 source premises, 204 immutable evidence files,
17,328 prerequisite checks and eight fresh production checks. Six historical
fixture/driver comparisons retain their exact compiled snapshots and reviewed
nonEmbedded reconstruction; they are not current-root byte-equality claims.
[integration.json](integration.json) records those comparators and unchanged
protected source/consumer drafts, index/status and publisher patch. Accepted
runtime evidence was reused without a broad build or repeated execution.
General correction families, other M4-M8 cells, whole-seven and full87 remain open.
