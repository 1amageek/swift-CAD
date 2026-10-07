# Native Exact Relation Integration

## Scope
The production CADGeometry module includes L0-L5 and the verified L1-L4
optimization (source 6c677725). Existing default CS/SSI intersectors implement the
new NativeExactCurveSurfaceResolving / NativeExactSurfaceSurfaceResolving protocol
requirements. `exactParameterRelation` constructs source-bound complete TUV/UVUV
relations directly from authored B-splines and uses one caller L0 admission.

The supported geometry is finite, nonperiodic, positive-weight and source-valid,
with exactly one positive native knot span per axis. The retained result includes
original source snapshots, original requested selections and complete L5 receipts.
Parameter dimension is not geometric image/fiber dimension. Existing
`intersectionResult` numerical publication is preserved; no whole CS/SSI or
seven-requirement acceptance is claimed by this bounded integration.

## Execution Evidence
`Evidence/run.json` inventories every production Core/Geometry source and the
actual compiler input lists in Native, ASAN, normal WASM and Embedded WASM lanes.
The verification package uses complete relative production source symlinks and
no isolated layer defines. Swift 6.4.0 release, its matching WASM SDKs and Node
24.19.0 WASI Preview 1 execute the shared fixtures. Raw artifacts remain under
`.build/native-exact-{wasm,embedded}/out/Products/Debug-webassembly-wasm32/`.

| Lane | Stable snapshot result |
|---|---|
| Native | Four public fixture tests pass in 15.970 seconds; unchanged legacy public smoke passes |
| Address Sanitizer | CS, SSI, failure and provenance groups each pass within their 120-second guard |
| Normal WASM | New public relation proof and unchanged legacy public smoke both pass on WASI |
| Embedded WASM | New public relation proof and unchanged legacy public smoke both pass on WASI |

All four actual compiler input inventories contain the same complete 64 CADCore
and 1,292 CADGeometry source files (1,356 total). Embedded's completed Geometry
build took 109.94 seconds after retaining its earlier compiler cache. The normal
and Embedded WASM folded fixtures return the same cells, incidence and membership.

| Public execution | Assertions |
|---|---|
| CS weighted, repeated contact, endpoint | Exact tuple membership and complete isolated component |
| Continuous CS | Positive-dimensional parameter relation retained |
| Singleton and clipped-out requests | Closed selection and full exclusion, with original requests retained |
| Folded CS | Both UV tuples at the same XYZ remain selected |
| SSI line, identical plane, absent | Complete curve/region parameter dimensions or empty selection |
| Folded SSI | 45 selected cells, 108 incidence attachments, one component, opposite UV membership |
| Failure | Independent work/storage/cell/component/degree/depth, malformed weights, periodic/multispan refusal and cancel |
| Terminal callback | Last result allocation cancellation rejects both point and empty publication |
| Lifetime | Mutating/releasing original input does not alter retained source/tuple authority |
| Scalar provenance | Explicit projection root/fiber root/fiber fields, staged sink rejection propagated |
| Existing public smoke | Legacy rings, ordered roots, rich/discrete Native/ruled/affine paths, codec, limits and final cancel |

CS uses 8,388,608 work; SSI uses 80,000,000 work and 1 GiB storage. No numerical
accuracy, source degree or proof ceilings were relaxed. Native folded SSI uses
9,520,618 work / 371,107,969 admitted bytes. The normal WASM counterpart uses
9,397,330 / 186,495,821 bytes. These are admission counters, not resident-memory
measurements or whole-family performance guarantees.

## Closed Integration Findings
- Rename the parent Geometry-only count/failure helper to avoid a module filename
  collision with L0's actual RationalAlgebraAdmitting protocol file.
- Add an explicitly typed ExactAlgebraicPairAuthority provenance record; preserve
  old geometric records and outer geometric source metadata. CADExchange's sink
  transports records without interpreting the algebraic record type.
- Normalize independent scalar failures at existing Geometry publication entry
  boundaries. Preserve non-scalar errors, admissionRejected causes and cancellation.
  The actual unchanged legacy proof reproduced the depth failure before repair
  and succeeds after repair. No retry or success substitution was introduced.

## Ownership and Synchronization Review
| State | Native | normal WASM | Embedded WASM | Lifetime / release |
|---|---|---|---|---|
| Native adapter buffers | Invocation-local Array | Same | Same | Owned value payload / ARC |
| L0 admission | Exclusive inout A | Same | Same | Caller owns query, no reset or escape |
| Existing numeric bridge | Scoped borrowed pointers | Same | Same | Does not escape withAdmission |
| Published sources and L5 owners | Immutable Sendable values/classes | Same | Same | Retained to result lifetime |
| Provenance context table | Non-Sendable invocation-local emitter | Same | Same | Ends with visit |
| Silhouette accounting | Mutex<State>, locked entries | Same | Same | Shared immutable accounting owner |
| Fixture sink | Mutex<[Event]>, short memory operation | Same | Same | Same isolation and Sendable |

No Embedded-only raw mutable state, weakened Sendable contract, unchecked
concurrency or new escaping pointer is introduced. These are synchronous query
and ownership proofs, not claims about deployment-specific multithreading.

## Resource Discipline
Runtime tests retain the 120-second maximum outer guard. The initial ASAN cold
build reached that bound before completing; its finished compiler cache was
reused. One all-group ASAN process also exceeded 120 seconds, so the same CS,
SSI, failure and provenance assertions execute as four bounded groups. Historical
timeout logs are retained separately and do not count as pass evidence.

The indivisible full Embedded Geometry WMO compile exceeded the initial 120-second
estimate; its earlier production precedent was about 203 seconds. The dedicated
build-only script bounds this compile at 300 seconds while preserving -Onone,
WMO, the matching SDK and all source/solver limits. Proof execution remains under
120 seconds. This change is an operational compiler watchdog, not a query budget.

## Review
One integrated source review covers Native extraction, exact coefficient/domain
transport, admission/lifetime, complete public relation, original provenance and
legacy error compatibility. The concrete integration findings above were fixed
before the stable four-lane verification. Unchanged lower proofs are reused.
