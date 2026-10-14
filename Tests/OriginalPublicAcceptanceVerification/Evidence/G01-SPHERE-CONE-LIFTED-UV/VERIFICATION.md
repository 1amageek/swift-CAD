# Independent finite sphere-cone UV lifts

This partial G01 unit extends the accepted strict finite-arc source receipt to independent arbitrary signed integer cone/sphere cycles. It does not complete a whole G01 cell, G01, M4-M8 or a seven-requirement gate.

The public red on main `cc861b8a` is retained in `../G01-SPHERE-CONE-FINITE-UV/next-cycle-red`: an exact source witness belongs to cone U `[B+1,B+2]`, V `[3,4]`, sphere UV `[-2,-1] x [-1,0]`, while both ordinary public orders reject with `unsupportedCapability`. B is the source's binary64 intrinsic label period, not mathematical physical radians.

## Changed authority

Each independent primitive period receipt is checked for owner, axis, intrinsic label meaning and exact B equality before reducing bounds. Existing exact Q floor and arbitrary-word import retain cycles and principal rational endpoints. No normalized endpoint is rounded into a binary64 surface box. The source retains raw cone U separately from principal phase, and sphere inverse U retains its independent exact azimuth offset. DI consumes the sealed source cycle acceptance; wrong cycles produce `outsideSupport`.

The remaining strict chart, one-branch whole-interval and sphere-guard conditions are unchanged. Seam crossing, active boundary cuts and critical endpoint clipping remain incomplete; a failed proof is never empty or partial success.

## Accepted behavior

| Target | Compiler inputs | Runtime groups | Command/runtime total seconds | Peak GiB |
|---|---:|---:|---:|---:|
| Native | 2186 | 31 | 394.75 | 3.88 |
| ASAN | 2186 | 31 | 861.23 | 4.44 |
| Ordinary WASM | 2186 | 31 | 626.66 | 4.85 |
| Embedded WASM | 2186 | 31 | 575.60 | 4.94 |

The 2186 inputs are 2177 Geometry source files and nine fixtures. Unchanged Core/dependency generation is reused only after matching all 168 input premises and products. No Core, Kernel or independent L2-L6 artifact is regenerated. Geometry compilation includes unchanged lower source files. Every lane has a 20-minute/10-GiB wall/RSS stop; every runtime group has a 180-second stop. Fixed Swift 6.4.0 release and matching WASM/Embedded SDKs are identified in compiler command receipts.

The existing 26 groups pass unchanged. Five new groups cover `(coneCycle,sphereCycle)=(1,0),(-2,3)` in both orders; exact raw endpoints/interior and original XYZ/UV descriptors; positive/negative huge-U singleton results; independent wrong-cycle refusal; query work/storage N/N-1; cancellation and retained member admission. The singleton raw labels are `+2^72` and `-2^90`, with nonempty principal remainders in `(1.1,1.9)`. Their cycles and remainders use independent Python Fraction divmod/UInt32 word expectations, without using the source floor implementation as the oracle.

| Raw U | Exact cycle | Exact principal remainder |
|---|---|---|
| +2^72 | 751587968840192343281 | 202428320808333/140737488355328 |
| -2^90 | -197024276503643381637114474 | 128103711844799/70368744177664 |

`prepared/` additionally accepts two independent-cycle inputs in both orders on Native/ASAN/ordinary WASM: prepare -> nonempty query -> release session/input -> raw endpoint membership under independent admissions. Maximum cumulative caller work is 8,332,174/8,388,608; storage is 6,915,776/268,435,456 bytes. Source preparation and query reuse the same caller allowance; later readers do not mutate that counter. This supplement recompiles only fixtures against receipt-matched products. It does not add Embedded nonempty prepared evidence. Embedded source-composed WMO covers the 31 public groups; the previously documented external module-reader compiler gap remains an M8 gap.

## Review, ownership and receipts

One cycle-scoped source/DI/public/fixture/prepared review found no required repair after Native acceptance. The root checked all portability runtime receipts and logs. All changed stored source/proof data remain immutable Sendable values/owners; mutable subdivision/refinement state is query-local on all targets. No conditional synchronization, shared mutable cache or unsafe ownership change is introduced.

Per-lane manifests bind original inputs, compiler commands, generated fixtures, immutable retained products and runtime log hashes. Products are copied to `.build/g01-lifted-finite-20261014/accepted/<lane>` before later builds can overwrite mutable build paths. Prepared receipts additionally bind probe/runner/transformed fixtures. `SUMMARY.json` is the accepted lane inventory; it is not a count of completed requirement cells. The protected twelve foreign draft/artifact hashes remain unchanged.

Source commit `3c4ee80d` is integrated into main. Independent latest-main delivery matches 2354 input premises, 345 task files and eight copied Native products, then fresh relink and eleven public/prepared groups pass; `delivery-native/receipt.json` binds the comparison and new products. No performance speedup is claimed by the target timings; they measure this verification run only.
