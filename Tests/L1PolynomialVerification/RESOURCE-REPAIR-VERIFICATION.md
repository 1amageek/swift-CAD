# L0/L1 Resource Repair Verification

## Scope and Snapshot

Verified on 2026-10-07 in `codex/exact-polynomial-l1`, in
`/private/tmp/cad-exact-polynomial-l1-20261007`, following redesign commit
`a6880e6d`. This record owns the current R1/R2 repair evidence for both levels.
The earlier VERIFICATION.md files remain historical evidence in `9c4a203e`.
Current [L0 hashes](../L0ScalarVerification/SOURCE-SHA256.txt) and
[L1 hashes](SOURCE-SHA256.txt) identify the executed source snapshot.

The production package graph is unchanged. No external dependency or production
target was added. Only the isolated verification packages were built. Compiler
L0.SwiftFileList inventories exactly matched 49 actual production sources in
standalone Native/ASAN and combined Native/ASAN/WASM/Embedded builds. Combined
L1.SwiftFileList inventories exactly matched 29 actual production sources in
all four configurations. Relative symlinks compile these production files;
there is no alternative arithmetic implementation. The combined proof imports
the same L0 fixtures through a relative symlink, avoiding duplicate cross-builds.
L1 production depends only on L0 and the Swift standard library.

## Repairs and Behavioral Evidence

| Finding | Actual repaired path | Refutable evidence |
|---|---|---|
| R1: one UInt32 word admitted for a larger monomial | Public quotientAndRemainder and internal univariateDivision now admit the typed tuple before term construction | The Native red test failed in quotient, remainder and internal division branches with one word spent. Green rejects the insufficient limit with zero words spent. Public cubic-root sign also succeeds and fails explicitly with insufficient cumulative storage. |
| Shared native sizing | L0 typed storage and L1 allocation helpers use exactScalarPayloadBytes | Negative counts and multiplication overflow fail explicitly; selected-target MemoryLayout supplies the payload stride. Existing L1 construction, arithmetic and independent storage-failure fixtures execute through the helper. L1 retains its original countOverflow mapping. |
| R2: multiplying N terms by zero traversed N outer iterations with work 3 | Public input owner/depth admission precedes the certified zero branch; wrap retains attained depth and final checkpoints | Both operand orders succeed with work 3/storage 0. Foreign zero is rejected; value/coefficient depths survive the result; entry, final-work and terminal cancellation fail. Native scaling confirms traversal removal. |

The cubic fixture selects the positive root of alpha cubed minus two in [1, 2],
then certifies the negative sign of alpha squared minus three through the public
OriginalExactScalarDomain path. A fresh query with one byte less than the measured
successful storage fails; spent work/storage remain recorded and the operand is
usable afterward. Quotient and remainder branches also verify their exact values.
The internal division rejection is a Native @testable assertion; portable public
division and cubic-sign assertions execute on both WASM configurations.

Storage denotes cumulative admitted payload, not peak RSS or physical allocator
overhead. Existing mathematical scope, tolerances, independent caps and ledger
semantics are unchanged. Removing the unused originalTerm in the quotient branch
avoids a second temporary; each executed branch creates one admitted monomial.

## Executed Configurations

| Configuration | Actual result |
|---|---|
| Native L0 debug | 8 tests passed |
| Native L1 debug | 8 tests passed |
| Native L0 Address Sanitizer | Same 8 tests passed; no sanitizer errors |
| Native L1 Address Sanitizer | Same 8 tests passed; no sanitizer errors |
| Normal WASM debug | Combined L0/L1 proof linked and executed, exit 0 |
| Embedded WASM debug | Same combined proof linked and executed, exit 0 |

Compiler: Apple Swift 6.4 (`swift-6.4-RELEASE`), pinned
`/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`.
Host: arm64-apple-macosx27.0.0. SDKs: `swift-6.4.0-RELEASE_wasm` and
`swift-6.4.0-RELEASE_wasm-embedded`, target wasm32-unknown-wasip1.
Runtime: `/usr/local/bin/node` 24.19.0, WASI Preview 1.
Two compiler jobs; 60-second Native/runtime/benchmark guards and 120-second
ASAN/cross-build guards. Incremental build paths reused existing caches.
Embedded uses required WMO and the matching SDK's libswiftUnicodeDataTables.a
for fixture String comparisons. The standard-library archive is not a new package.

Both WASM executions printed all seven lines:

```text
PASS: rational source bits and field operations
PASS: retained algebraic source, order and lifetime
PASS: independent limits, explicit failures and cancellation
PASS: typed payload admission and cubic-root sign resource boundaries
PASS: L1 zero-product owner, depth, resources and cancellation
PASS: L1 division, multivariate GCD, square-free decomposition and resultant
PASS: L1 primitives, retained coefficients, lifetime and resource failures
```

## Native Scaling Measurement

Both measurements use Native debug, the same public multiplication path, 200
repetitions per sample and five samples. Inputs are prepared outside timing;
the table reports median seconds. Each sample admits work 600/storage 0.
The pre-repair run used a scratch verification executable compiling the original
production sources; its timing body is retained in Sources/Benchmark/Benchmark.swift.
The post-repair run uses the tracked L1ZeroProductBenchmark executable. These
measurements establish removal of input-sized traversal, not a portable wall-time
guarantee or a cross-target performance claim.

| Input terms | Before | After |
|---|---:|---:|
| 1,000 | 0.029101875 | 0.000115709 |
| 50,000 | 1.454271041 | 0.000110584 |

## Review and Boundaries

One stable implementation review traced both scalar division branches, typed
sizing and checked word conversion, public L1 query owner/depth admission, wrap
and final checkpoints. No remaining finding in this scope was identified.
Conditional-source inspection found only L1_ISOLATED_VERIFICATION imports:
no target-dependent storage, Sendable, isolation or failure implementation.
The sizing function is stateless. Mutable admissions are caller-owned query-local
inout state; input/context owners remain immutable and use native retention.
No new shared mutable state, unsafe allocation or pointer boundary was introduced.

Higher CADGeometry/CADCore/intersection/application compilation and main integration
are not covered. This worktree has no configured upstream; no push was performed.

## Reproduction

From the worktree root, use the pinned compiler above as SWIFT:

```sh
SWIFT=/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift
bash scripts/swift-test-timeout.sh 60 -- "$SWIFT" test --package-path Tests/L0ScalarVerification --build-path .build/l0-native -j 2
bash scripts/swift-test-timeout.sh 60 -- "$SWIFT" test --package-path Tests/L1PolynomialVerification --build-path .build/l1-native -j 2
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" test --package-path Tests/L0ScalarVerification --build-path .build/l0-asan -j 2 --sanitize address
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" test --package-path Tests/L1PolynomialVerification --build-path .build/l1-asan -j 2 --sanitize address
bash scripts/swift-test-timeout.sh 60 -- "$SWIFT" run --package-path Tests/L1PolynomialVerification --build-path .build/l1-native -j 2 L1ZeroProductBenchmark
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" build --package-path Tests/L1PolynomialVerification --build-path .build/l1-wasm --swift-sdk swift-6.4.0-RELEASE_wasm -j 2 --product L1Proof
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/l1-wasm/out/Products/Debug-webassembly-wasm32/L1Proof.wasm
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" build --package-path Tests/L1PolynomialVerification --build-path .build/l1-embedded --swift-sdk swift-6.4.0-RELEASE_wasm-embedded -j 2 --product L1Proof -Xlinker /Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/l1-embedded/out/Products/Debug-webassembly-wasm32/L1Proof.wasm
```

Raw logs remain in .build/l1-evidence. Their hashes identify the local evidence:

```text
5eeca68a2488d1c5e768fd2b948c1f5859c34bae98a0011a2d337e4720e409d3  l0-storage-red.log
b4f23f7346fba1a879ec3adc52593ba0a80a9a1c9773ed483f9e7e6fe9b0b78a  l0-native-fixed.log
8296cb42f64c65d76c67ed0468e2fbc77e4538b1f555f313785f0cbe28ab50c9  l1-native-fixed.log
5c47b882d7ba2efc5e27d88338b29993e88c0bfc5011578b84e9afe4ceb23a34  l0-asan-fixed.log
b3a724a9e263ef29680a548bee1cb8753de0696c53503730d0a45edc0598a1e8  l1-asan-fixed.log
7be3b3ba92b1a6f04403a1d9e532e7fd92685fe0c4652bceb365e4ce5f5638b9  wasm-fixed-build.log
43c50e39a71b673e28002318eee6107b1db7c05fdf592236fc118282d11d0414  wasm-fixed-runtime.log
d2a6e7d42118b618a8b5131ffeac007af449653856a673d1dbe0ce72b078edb7  embedded-fixed-build.log
aeea1920bbc54b9b866c9216e05b43517876493b0b75b155302f7d3d8367250d  embedded-fixed-runtime.log
b8fc89d39298d92a2d190e6fb49acdab99839f2fa12901c6ee313e34a4714f87  redesign-before.log
5e28f9079d2f74efe707080f5f7815734254ed95335f28b78933caebc652b94a  redesign-after.log
```
