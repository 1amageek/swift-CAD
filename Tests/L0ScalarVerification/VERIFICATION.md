# L0 Isolated Verification

> Historical evidence for the pre-repair snapshot, retained in commit 9c4a203e.
> Source inventories and hashes below describe that snapshot only. The current
> SOURCE-SHA256.txt has been regenerated for the repaired snapshot; current
> execution results are in [Resource Repair Verification](../L1PolynomialVerification/RESOURCE-REPAIR-VERIFICATION.md).

## Scope and Snapshot

Verified on 2026-10-07 in `codex/exact-scalar-contract-design`, based on
`cd041f9bcdb6432947a6248a3676e4e13f955cb2`, in the independent worktree
`/private/tmp/cad-exact-scalar-contract-design-20261007`.

The L0 target compiles the 48 production Swift files in
[ExactScalar](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/DESIGN.md),
through the checked-in relative symlink `Sources/ExactScalar`. Compiler-generated
`L0.SwiftFileList` inventories for all four builds exactly matched those 48 files.
The graph contains only L0, L0Fixtures, L0Proof and L0ScalarTests. It has no package
dependencies. CADGeometry, CADCore, intersection consumers and applications were
not built. The production package graph is unchanged.

[SOURCE-SHA256.txt](SOURCE-SHA256.txt) records the verified production sources,
fixtures, Native tests, manifest and WASI runner. Design-only edits after those
runs do not change this executable snapshot.

## Environment

| Item | Verified selection |
|---|---|
| Compiler | `/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift` |
| Version output | `Apple Swift version 6.4 (swift-6.4-RELEASE)` |
| Host | `arm64-apple-macosx27.0.0`; deployment macOS 14 |
| Normal WASM SDK identifier | `swift-6.4.0-RELEASE_wasm` |
| Embedded WASM SDK identifier | `swift-6.4.0-RELEASE_wasm-embedded` |
| WASM target | `wasm32-unknown-wasip1`, confirmed in compiler command manifests |
| Embedded mode | `-enable-experimental-feature Embedded`, confirmed in compiler command manifest |
| Runtime | Node.js 24.19.0, WASI Preview 1; `/usr/local/bin/node` |
| Concurrency | 2 compiler jobs per isolated build, separate build paths |
| Timeouts | Native test/runtime 60 seconds; sanitizer/cross-target build 120 seconds |

Both SDK identifiers are listed by the pinned compiler. Their selected WASI SDK
root comes from the matching `swift-6.4.0-RELEASE_wasm.artifactbundle`; the Embedded
identifier adds Embedded compilation rather than selecting a different version.

## Observed Results

| Configuration | Build/link and execution |
|---|---|
| Native debug | 6 Swift Testing tests passed; actual Task cancellation included |
| Native Address Sanitizer | The same 6 tests passed; no sanitizer errors |
| Normal WASM debug | Linked L0Proof; all portable fixture groups and final PASS executed; exit 0 |
| Embedded WASM debug | Linked L0Proof; all portable fixture groups and final PASS executed; exit 0 |

Portable runtime output on each WASM target:

```text
PASS: rational source bits and field operations
PASS: retained algebraic source, order and lifetime
PASS: independent limits, explicit failures and cancellation
PASS: L0 exact values, decisions, arithmetic, lifetime, resources and cancellation
```

The runner supplies `args: [path]` and explicitly calls `wasi.start(instance)`.
Successful module instantiation alone is not execution evidence. Raw WASM files
remain in the dedicated build directories. No wasm-opt transformation was used.
The cross-target linker emits an unused `-rdynamic` argument warning; runtime
fixtures passed with that warning present. Node emits its WASI experimental warning.

## Behavioral Coverage

| Contract | Executed refutation checks |
|---|---|
| Exact values | Exact 0.1 and smallest-subnormal source bits; both signed zeros; Int64.min and UInt64.max; independent Python Fraction-generated multiword arithmetic goldens |
| Exact decisions | Rational and selected-root signs/orders; positive and negative square-root branches; differences below Double resolution remain distinct; unrelated nonconstant owners reject both operand orders |
| Arithmetic/failures | Four rational operations and field identities; selected algebraic root identities and exact reciprocal; rational and algebraic zero division; nonfinite/noncanonical sources and unsupported generator reject |
| Ownership | A returned algebraic value outlives creating source and domain variables; reconstructed retained owner still evaluates and compares it; same-owner import reuses backing; supported rational constant transfer preserves value |
| Resource axes | Work and storage fail independently; both root depth axes remain independent, including zero constants; inherited depth cannot exceed explicit owner cap; no counter reset or refund on failure |
| Checked accounting | Word-to-byte overflow rejects before storage admission; cumulative work/storage counter overflow leaves spent counts intact |
| Cancellation | Entry cancellation, initial-depth callback cancellation, final work/storage callback and terminal-checkpoint cancellation; rational fast paths and algebraic publication; Native actual Task cancellation |
| Error ownership | Unmapped implementation/admission error retains its cause and already spent work |

The stable implementation was reviewed once against these five contracts and
actual domain/bridge/numeric call paths. Concrete boundary/depth/cancellation gaps
were closed before the final runs. Source inspection found no target-conditioned
state, unchecked Sendable, unsafe isolation, deferred shutdown, or placeholder
success path in L0. The only mutable stored state is the noncopyable query-local
ledger; immutable domains and evidence do not acquire a shared mutable cache.
The scoped pointer bridge borrows initialized ledger/depth values and does not
escape, rebind, manually allocate, deallocate or transfer them between tasks.
The deinit shutdown guard also passed for L0 and this verification package.

## Reproducible Commands

Run from the independent repository root. All commands select this verification
package explicitly. `scripts/swift-test-timeout.sh` only guards processes.

```bash
L0_SWIFT=/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift
bash scripts/swift-test-timeout.sh 60 -- "$L0_SWIFT" test \
  --package-path Tests/L0ScalarVerification --build-path .build/l0-native \
  -j 2 --filter L0ScalarTests
bash scripts/swift-test-timeout.sh 120 -- "$L0_SWIFT" test \
  --package-path Tests/L0ScalarVerification --build-path .build/l0-asan \
  -j 2 --sanitize address --filter L0ScalarTests
bash scripts/swift-test-timeout.sh 120 -- "$L0_SWIFT" build \
  --package-path Tests/L0ScalarVerification --build-path .build/l0-wasm \
  --swift-sdk swift-6.4.0-RELEASE_wasm -j 2 --product L0Proof
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node \
  Tests/L0ScalarVerification/Scripts/RunWASI.mjs \
  .build/l0-wasm/out/Products/Debug-webassembly-wasm32/L0Proof.wasm
bash scripts/swift-test-timeout.sh 120 -- "$L0_SWIFT" build \
  --package-path Tests/L0ScalarVerification --build-path .build/l0-embedded \
  --swift-sdk swift-6.4.0-RELEASE_wasm-embedded -j 2 --product L0Proof
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node \
  Tests/L0ScalarVerification/Scripts/RunWASI.mjs \
  .build/l0-embedded/out/Products/Debug-webassembly-wasm32/L0Proof.wasm
shasum -a 256 -c Tests/L0ScalarVerification/SOURCE-SHA256.txt
```

Detailed local logs are retained in `.build/exact-scalar-design/` as
`native-test.log`, `asan-test.log`, `wasm-build.log`, `wasm-runtime.log`,
`embedded-build.log` and `embedded-runtime.log`.

## Evidence Limits

This completes the isolated five-contract L0 implementation. It is not evidence
for higher geometry/intersection contracts, all-seven completion, their ABI/error
mapping, browser deployment, threaded WASM, or main integration. Minimal parent
wrappers retain their original geometry boundary and delegate numeric authority;
their build and behavior were explicitly outside the user-authorized build scope.
No external Numerics dependency or production CADExactAlgebra target was added.
