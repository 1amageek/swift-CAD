# L2 Real-Root Verification

## Scope and Snapshot

Verified 2026-10-07 in `codex/exact-real-root-l2`, worktree
`/private/tmp/cad-exact-polynomial-l1-20261007`. Implementation units:
`733c0246` (complete root issuance/queries) and `ac9f6ed6` (runtime extensions).
The final verification commit includes the portability and sorting corrections.
[SOURCE-SHA256.txt](SOURCE-SHA256.txt) identifies the 30 production L2 files,
5 portable fixture files, proof entry, Native test file and verification manifest.

The isolated package compiles actual production files through relative symlinks.
Compiler inventories exactly matched 49 L0, 29 L1 and 30 L2 source files in
Native, ASAN, ordinary WASM and Embedded WASM. Existing L0/L1 recorded SHA-256
manifests match unchanged production files. Their prior lower-contract evidence
is reused; their test packages were not independently rebuilt. No production
package graph, dependency or higher CAD source was changed or built.

## Executed Configurations

| Configuration | Actual executed result |
|---|---|
| Native debug | 12 Swift Testing tests passed, including four concurrent immutable-root readers |
| Native Address Sanitizer | Same 12 tests passed; no sanitizer error |
| Ordinary WASM debug | All 11 synchronous fixture routines executed on Node WASI; exit 0 |
| Embedded WASM debug | Same 11 routines executed on Node WASI; exit 0 |

Compiler: Apple Swift 6.4 (`swift-6.4-RELEASE`), pinned
`/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`.
Host compiler target arm64-apple-macosx27.0.0, package deployment target macOS 14.
Execution was on the host, not a macOS 14 device.
SDKs: `swift-6.4.0-RELEASE_wasm` and
`swift-6.4.0-RELEASE_wasm-embedded`, target wasm32-unknown-wasip1.
Runtime: `/usr/local/bin/node` 24.19.0, WASI Preview 1.
Embedded uses SDK-required WMO, debug `-Onone`, and the matching SDK's
libswiftUnicodeDataTables.a. There is no optimization-dependent metadata workaround.
Raw WASM artifacts remain in their dedicated build directories.

Two compiler jobs; Native/runtime guards 60 seconds and ASAN/cross-build guards
120 seconds. Final Native tests took about 0.95 seconds; ASAN about 1.93 seconds.
These are verification run times, not an algorithmic performance guarantee.
WASM link emitted only the existing unused `-rdynamic` clang warning; Node
reported its standard experimental WASI warning. No function-signature mismatch
warning or runtime trap was observed.

## Behavioral Evidence and Actual Paths

| Invariant | Public execution and refutable assertions |
|---|---|
| Complete original roots | `isolate` checks square-free counts, complete exclusions and multiplicity sum; x(x-1)^2 returns exactly two roots with multiplicities 1/2 and original ordinals 0/1 |
| Domain semantics | Every inclusion combination on [0,1]; selected singleton; zero law whole-domain classification; empty selection; nonzero constant and x^2+1 certified empty; unbounded line/ray counting |
| Exact identity/order | Negative/positive roots of x^2-2 are distinct; positive root equals the corresponding root of x(x^2-2); nearby roots 0 and 1/1,000,000 remain separate |
| Root signs/refinement | Exact source-zero and positive/negative polynomial signs; requested positive width verified by exact field comparison; refined root retains exact identity |
| Runtime extension | Same static scalar/domain type for alpha^2=2, beta^2=alpha and a third extension; embedded ancestor equals beta squared; inverse multiplied by beta equals one |
| Reducible defining law | Select sqrt(2) from (x^2-2)(x^2-3); alpha squared minus two is zero and cannot divide; alpha squared minus three is nonzero and its inverse is negative |
| Existing algebraic base | OriginalExactScalarDomain supplies exact alpha and retained coefficient depth; L2 singleton/root and further extension preserve alpha exactly |
| Retained ownership | Drop creating domains/inputs, reconstruct identical root/scalar domains from issued evidence, then sign/query/import; original variable-1 map in a two-variable basis remains readable |
| Atomic failure | Result ceiling refuses before enumeration publication; wrong issuer/field/sibling fails; independent work/storage/value/coefficient depths fail; zero width/invalid variable/reversed domain/negative limit fail |
| Storage and final cancel | Measured successful query storage minus one fails, exact allowance succeeds; refusal counters remain readable; cancellation at the successful run's final checkpoint prevents result publication |
| Immutable concurrency | Native/ASAN TaskGroup shares root/source/domain across four readers with separate caller admissions; all exact source-zero queries succeed |

All tests use actual production operations. The asynchronous concurrency test is
Native/ASAN evidence only. WASM fixtures establish synchronous ownership and
failure behavior; they do not establish multithreaded WASM execution.

The production algorithms have no fixed polynomial-degree cutoff; the general
construction path is exercised through degree five, including odd multiplicity
five. The runtime tower test exercises three levels and refusal at an independent
configured ceiling. These facts do not establish success at arbitrary resource
limits or unlimited tower depth. Root-count and extension ceilings are explicit
caller policies with no implicit production defaults.

## Repairs and Review

- A generic forwarding class erased through an existential required macOS 15
  noncopyable-generic casting support. A non-generic owner with scoped callbacks
  preserves the deployment target; all requirement calls preserve typed failures.
- Stored throwing callbacks avoid typed-function metadata lookup at the older
  deployment target. The public admission contract remains typed; its callback
  failure is explicitly rethrown. Native/ASAN and both WASM paths execute it.
- The second algebraic-root calculation originally exhausted its 150,000,000-work
  fixture allowance. Selected-root-safe polynomial GCD cancellation and denominator
  normalization close expression growth; exact constant/linear sign reuse and
  lower-degree buffer retention keep the same allowance. The full tower now succeeds.
- Embedded rejected implicit conversion between labeled and unlabeled tuple arrays.
  Stored and input factor tuples now have identical labels on every target.
- Portable fixtures use closures instead of unsupported Embedded key paths.
- Stable cumulative review found an unnecessary sorted-output array. The uniquely
  owned result buffer now sorts in place after admitting sorting workspace.

One scoped review closed the root issuance unit; one scoped extension review and
one cumulative stable review checked actual paths, ownership, failure propagation
and payload admissions. The findings above received affected-target rechecks;
no additional speculative review cycle was performed. No scoped finding remains.

### State and Ownership Matrix

| Logical state | Native / WASM / Embedded storage | Isolation / access | Release |
|---|---|---|---|
| Root domain/source | Same immutable Sendable structs/classes | Read-only public ports | ARC retained by receipts |
| Sturm chain/root brackets | Same immutable arrays/structs/class owners | Queries produce new evidence | ARC retained by roots/counts |
| Coefficient tower/fractions | Same immutable Sendable parent contexts and polynomial owners | Explicit ancestor imports; parent-only references | Acyclic ARC retention |
| Pending cells/result construction | Query-local Array values | Synchronous exclusive invocation | Return transfers immutable result; throw releases temporaries |
| Admission forwarding/depth observer | Same non-Sendable scoped class and fixed borrowed handle | Exclusive synchronous pointer borrow; all protocol calls are requirements | Released inside withUnsafeMutablePointer before its scope ends |
| Caller ledger | Same inout admission contract | Caller owns mutable ledger; never stored in result | Caller-owned |

No target-conditional stored state, Sendable refinement, lock removal or no-op
synchronization exists in L2. Conditional source directives only import the lower
verification modules. The scope introduces no shared mutable state. Resource
storage is cumulative admitted logical payload, not exact allocator capacity/RSS.
The only unsafe boundary is the exclusive scoped admission pointer, exercised
through normal return, failure and final cancellation under ASAN.

## Reproduction and Logs

Run from the worktree root. Each command remains guarded; dedicated paths preserve
build caches. The existing WASI runner is shared with L1 verification.

```sh
SWIFT=/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift
bash scripts/swift-test-timeout.sh 60 -- "$SWIFT" test --package-path Tests/L2RealRootVerification --build-path .build/l2-native -j 2
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" test --package-path Tests/L2RealRootVerification --build-path .build/l2-asan -j 2 --sanitize address
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" build --package-path Tests/L2RealRootVerification --build-path .build/l2-wasm --swift-sdk swift-6.4.0-RELEASE_wasm -j 2 --product L2Proof
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/l2-wasm/out/Products/Debug-webassembly-wasm32/L2Proof.wasm
bash scripts/swift-test-timeout.sh 120 -- "$SWIFT" build --package-path Tests/L2RealRootVerification --build-path .build/l2-embedded --swift-sdk swift-6.4.0-RELEASE_wasm-embedded -j 2 --product L2Proof -Xlinker /Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a
bash scripts/swift-test-timeout.sh 60 -- /usr/local/bin/node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/l2-embedded/out/Products/Debug-webassembly-wasm32/L2Proof.wasm
```

Raw final logs are retained in `.build/l2-evidence`; [LOG-SHA256.txt](LOG-SHA256.txt)
identifies them. [DESIGN.md](DESIGN.md) owns the isolated verification graph.
Higher CADGeometry/CS/SSI/application targets and main integration are outside
this evidence. The task branch has no configured upstream; no push is performed.
