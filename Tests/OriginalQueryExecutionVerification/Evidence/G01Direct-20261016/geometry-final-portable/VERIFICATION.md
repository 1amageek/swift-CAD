# Final Geometry Portable Verification

The final Core65/Geometry2170 snapshot passes the actual structural metering, original Native boundary and current silhouette clients on ASAN Native, ordinary WASM and Embedded WASM. Corrected metering also passes a fresh Native compile/link/runtime. This does not prove projected Drawing contacts, whole G01/U1–U4, Kernel portability or main delivery.

| Lane | Meter | Boundary | Silhouette |
|---|---|---|---|
| ASAN Native | 4 expected lines PASS | 5 PASS | 5 PASS |
| Ordinary WASM | 4 PASS | 5 PASS | 5 PASS |
| Embedded WASM | 4 PASS | 5 PASS | 5 PASS |

Geometry was compiled once per lane; subsequent boundary and silhouette clients reused those exact products. Core, Collections and lower sources were not regenerated. Compiler/client bounds remain 1200 seconds/10 GiB and runtime bounds 120 seconds. [index.json](index.json) binds every actual command, compiler phase, original product, fixture, runtime log and final source hash. Full artifacts remain at the durable root outside `.build`.

The original Embedded metering client failed code generation due to escaping local noncopyable Mutex captures. That failed client remains recorded under `embedded/historical-first-client-capture-error.log`; its successful Geometry compile is accepted separately. The fixture-only correction puts each same `let Mutex` into a private final Sendable owner on every target. Inverse-byte comparison retains every original assertion, debit and callback critical body. No target raw-state branch, no-op lock or changed ceiling was introduced.

The silhouette client exercises all eight Native source selector cases, the original nonconstant quadratic arch and whole UV, retained trim endpoints, actual trim partition witnesses, N/N−1 work/bytes, lifetime/source refusal, and entry/terminal cancellation. Geometry trim events are not projected screen contacts; Root's Drawing verification remains separate. Cooperative WASI execution does not establish multithreaded WASM locking.

Historical G01 public, endpoint and lower/common proofs keep their scopes. Packaging started no compiler/runtime, new review, source edit or commit.
