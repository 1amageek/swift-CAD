# L1 Isolated Verification

## Scope and Snapshot

Verified on 2026-10-07 in `codex/exact-polynomial-l1`, in the independent worktree
`/private/tmp/cad-exact-polynomial-l1-20261007`, based on L0 commit `42869524`.
Implementation commits are `4358e99c` and `66e6c8fd`.

The verification graph contains L0, L1, L1Fixtures, L1Proof and L1PolynomialTests.
L1 depends only on L0 and the Swift standard library. Relative symlinks compile
the actual production sources. Compiler-generated L0.SwiftFileList and
L1.SwiftFileList in all four build directories exactly matched the 48 L0 and 29
L1 production Swift sources. No CADCore, CADGeometry, intersection or application
target was built. L0 production sources and the production Package.swift have no
diff from the base commit. No external package or production target was added.

[SOURCE-SHA256.txt](SOURCE-SHA256.txt) identifies the tested production sources,
fixtures, Native tests, verification manifest and WASI runner. The component
contract is [ExactPolynomial/DESIGN.md](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactPolynomial/DESIGN.md).
Unchanged [L0 evidence](../L0ScalarVerification/VERIFICATION.md) is reused.

## Environment and Execution

| Configuration | Selection and observed result |
|---|---|
| Compiler | Apple Swift version 6.4 (swift-6.4-RELEASE), pinned release toolchain |
| Native debug | arm64-apple-macosx27.0.0; 7 tests passed, 0.075 seconds of test execution |
| Native Address Sanitizer | Same 7 tests passed, 0.159 seconds; no sanitizer errors |
| Normal WASM debug | swift-6.4.0-RELEASE_wasm; L1Proof linked and executed, exit 0 |
| Embedded WASM debug | swift-6.4.0-RELEASE_wasm-embedded; L1Proof linked and executed, exit 0 |
| WASM target/runtime | wasm32-unknown-wasip1; Node.js 24.19.0, WASI Preview 1 |
| Process limits | Two compiler jobs; Native/runtime timeout 60 seconds, ASAN/cross-build timeout 120 seconds |

Compiler command manifests record the matching release SDK artifact bundle and
target. Embedded compilation additionally records `-enable-experimental-feature
Embedded` and WMO. The fixture error-tag String comparisons require the matching
SDK's `libswiftUnicodeDataTables.a`; Embedded links that standard-library archive
explicitly. Key-path map expressions in fixtures were replaced by ordinary
closures shared by every target. Production algorithms and state are identical.

Both WASM executables produced:

```text
PASS: L1 division, multivariate GCD, square-free decomposition and resultant
PASS: L1 primitives, retained coefficients, lifetime and resource failures
```

The WASI runner invokes `wasi.start(instance)` with `args: [path]`; module
instantiation alone is not counted. Raw artifacts are retained without wasm-opt.
The unused `-rdynamic` linker warning and Node WASI experimental warning were
present with successful runtime results.

## Behavioral Evidence and Review

| Contract | Executed checks |
|---|---|
| Canonical values and decisions | Duplicate addition/cancellation; independent sparse coefficient expectations; zero and zero-variable constants; exact domain identity and explicit import |
| Arithmetic and calculus | Known multiplication coefficients; derivatives; simultaneous substitution; evaluation; exact degrees; checked invalid arity/index/exponent and exponent overflow |
| Division | Exact quotient, nonzero remainder and p=q*d+r; zero divisor and notDivisible failures |
| Multivariate GCD | Four variables, common multivariate content, nonzero primitive PRS remainder, operand reversal, zero inputs, coprime inputs and sparse degree 1000 |
| Square-free decomposition | Exact expected factors and multiplicities 2 and 3; unit restoration, reconstruction, derivative square-freeness and pairwise coprimality; constant and undefined zero cases |
| Resultant | Known linear result and reversal sign; common-factor zero; constant conventions; quadratic result; cubic case requiring later pivot row exchange; dimension/count overflow |
| Exact algebraic coefficients | Retained selected square-root coefficient used in arithmetic, GCD, square-free decomposition and resultant |
| Ownership and depth | Returned polynomial survives source/domain scope; retained domain evaluates it; both value and coefficient depth axes survive cancellation to zero; subsequent shallow admission rejects |
| Resources and cancellation | Work/storage fail independently; cumulative counters remain spent; entry, final work/storage callback and terminal cancellation; actual Native Task cancellation; all advanced operations reject and operands remain usable |

One stable implementation review traced the actual domain, admission, arithmetic,
iterative GCD, factor and resultant paths against the fixed component contract.
The portability repair received a targeted check: only fixture expression syntax
and the Embedded link command changed. Final runs cover the repaired snapshot.

Contexts and values retain immutable Sendable owners. Scratch arrays and the
noncopyable admission observer are query-local. The scoped pointer only borrows
the initialized caller ledger within its enclosing operation; it does not escape,
rebind, allocate or transfer across tasks. Native ASAN executed this path. Import
conditionals do not change storage, synchronization or Sendable. No incomplete
success branch, shared mutable cache or alternate-solver fallback was found.

## Reproducible Commands

Run from the worktree root:

```bash
L1_SWIFT=/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift
L1_UNICODE=/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a
bash scripts/swift-test-timeout.sh 60 -- "$L1_SWIFT" test \
  --package-path Tests/L1PolynomialVerification --build-path .build/l1-native \
  -j 2 --filter L1PolynomialTests
bash scripts/swift-test-timeout.sh 120 -- "$L1_SWIFT" test \
  --package-path Tests/L1PolynomialVerification --build-path .build/l1-asan \
  -j 2 --sanitize address --filter L1PolynomialTests
bash scripts/swift-test-timeout.sh 120 -- "$L1_SWIFT" build \
  --package-path Tests/L1PolynomialVerification --build-path .build/l1-wasm \
  --swift-sdk swift-6.4.0-RELEASE_wasm -j 2 --product L1Proof
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node \
  Tests/L1PolynomialVerification/Scripts/RunWASI.mjs \
  .build/l1-wasm/out/Products/Debug-webassembly-wasm32/L1Proof.wasm
bash scripts/swift-test-timeout.sh 120 -- "$L1_SWIFT" build \
  --package-path Tests/L1PolynomialVerification --build-path .build/l1-embedded \
  --swift-sdk swift-6.4.0-RELEASE_wasm-embedded -j 2 --product L1Proof \
  -Xlinker "$L1_UNICODE"
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node \
  Tests/L1PolynomialVerification/Scripts/RunWASI.mjs \
  .build/l1-embedded/out/Products/Debug-webassembly-wasm32/L1Proof.wasm
shasum -a 256 -c Tests/L1PolynomialVerification/SOURCE-SHA256.txt
```

Local logs are `.build/l1-evidence/native-final.log`, `asan.log`, `wasm-build.log`,
`wasm-runtime.log`, `embedded-build.log` and `embedded-runtime.log`.

## Evidence Limits

This proves the isolated finite polynomial contract on the recorded targets.
It does not prove real-root decomposition, geometric intersection, threaded WASM,
upper-layer integration or main integration. Production remains in the existing
component hierarchy; no CADExactAlgebra target was introduced.
