# Independent DI0 Acceptance

## Scope and baseline

Implemented in `codex/exact-domain-foundation`, independently of concurrent source,
CS and L4 work. DI0 mathematically depends only on L0. Production remains inside
CADGeometry: no production target, package or external dependency was added.
L2 uses lossless facade wrappers around DI0 storage and its sole checked constructor.
Root algorithms, tolerance, ceilings and selected-root/source identity are unchanged.
All seven requirements and the transport/coverage/structural-identity children remain
open beyond this accepted foundation; no shape or L3-L6 target was built.

## Behavioral evidence

| Lane | DI0 | Shared L2 facade |
|---|---|---|
| Native Debug | 5 tests + DomainProof | 24 tests + L2Proof |
| Native ASAN | 5 tests | 24 tests |
| Normal WASM | DomainProof executed | L2Proof executed |
| Embedded WASM, raw Onone/WMO | DomainProof executed | L2Proof executed |

DI0 checks 52 exact interval selections, all 2,704 pairs and all seven endpoint/open
sector positions, including both infinite sectors. Union, intersection, difference,
membership and equality are compared with an independent integer ordering/oracle.
Literal multi-component cuts, excluded touching points, repeated intervals, zero-arity
products, empty axes, field-specific axes, large retained rational endpoints, foreign
owners, unresolved order, invalid bounds/arity, work/storage/depth, overflow and terminal
cancellation exercise actual public entry paths. Native/ASAN additionally exercise
concurrent immutable readers and actual Task cancellation. The portable synchronous
proof does not claim WASM task/thread concurrency coverage. Scoped buffer-address
comparison and zero admitted generated storage confirm the ArraySlice view/retaining
path; this is not a claim of zero allocations in genuine set computation or process
peak-memory measurement.

L2's existing open/closed/singleton/empty/unbounded root count/isolation, coefficient
fields, depth, lifetime, failures and terminal admission regressions consume the
shared constructor. Every direct interval construction in production was searched;
only the checked facade sites remain. Alias-based isolated composition first failed
Embedded specialization due to DI0 members lacking file-local imports. Lossless L2
wrappers solved that module-boundary problem without adding imports to upper sources
or duplicating validation. All final logs correspond to the wrapper implementation.

## Inputs and reproduction

Fixed compiler: `/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`,
Apple Swift 6.4 release. Matching SDK IDs: `swift-6.4.0-RELEASE_wasm` and
`swift-6.4.0-RELEASE_wasm-embedded`; target wasm32-unknown-wasip1; Node 24.19.0 WASI Preview1.
Every build/test/run was externally bounded to 120 seconds (initial dependency run30).
Dedicated `.build/domain-*` and `.build/domain-l2-*` paths preserve caches.

`dependency-inputs.json` records the successful pre-implementation L0+DI0 probe.
`compiler-inputs.json` records actual final SwiftFileLists for all eight lane/graph
combinations, excluding generated runners. `source-hashes.json` binds 173 actual
source/configuration inputs. All six isolated L2 consumer manifests were resolved
without executing their upper targets. `receipt.json` binds tool identifiers,
source manifest and final logs. Verify retained inputs from any checkout with
`python3 Tests/OriginalDomainIdentityVerification/Scripts/VerifyEvidence.py`.

Use Scripts/BoundedRun.py with seconds, log path and the command. Native uses
`swift test --package-path Tests/OriginalDomainIdentityVerification --build-path <path>`;
ASAN adds `--sanitize address`. WASM uses `swift build --swift-sdk <matching-sdk>
--product DomainProof --package-path Tests/OriginalDomainIdentityVerification
--build-path <path>`; Embedded adds `-Xswiftc -Onone` (SDK provides WMO).
Run the raw product with Node and Scripts/RunWASI.mjs. Shared L2 verification changes
the package path to Tests/L2RealRootVerification and the product to L2Proof.
Products live in `out/Products/Debug` or `out/Products/Debug-webassembly-wasm32` beneath
the selected build path. Native tests completed in less than one second each suite;
DI0 builds2-11 seconds, composed L2 builds6-28 seconds; portable runs below2 seconds.
