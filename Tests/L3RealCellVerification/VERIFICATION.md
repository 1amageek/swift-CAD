# L0-L3 Optimization Verification

## Scope and Snapshot

Verified 2026-10-07 in `codex/exact-layer-optimization`, worktree
`/private/tmp/cad-exact-layer-opt-20261007`, based on `f0d6ae9e`.
This report supersedes the original L3 final-source report for this branch.
The original report remains available at the base commit. The task changes four
internal operations and their authoritative component designs. Public protocols,
source equality, exact ordering, ownership, depths, cancellation, caller limits,
production package graph and higher CAD code are unchanged.

## Implementation and Review

| Layer | Change | Correctness evidence |
|---|---|---|
| L0 | Opposite-sign/zero and equal-denominator comparison without subtraction/reduction | Pairwise differential comparison against exact subtraction over signs, fractions and multi-limb inputs; work failure and terminal cancellation |
| L1 | Ordered addition/subtraction merge; negate only right-only subtraction terms | Public canonical construction reference, matching/cancelling terms, empty operands, foreign ownership, storage refusal and terminal cancellation; existing rational/algebraic division, GCD, resultant and square-free fixtures |
| L2 | Prove disjoint isolation order before GCD/Sturm construction | Both orders, touching half-open intervals, same-root and different-law equality, foreign root issuer, final cancellation; existing multiplicity/refinement/tower/denominator fixtures |
| L3 | Count/group terms by exponent rather than scan all terms at every degree; retain degree-zero law | Independent filtered-coefficient reference for both axes and missing degrees; existing projection/PSC, nullification, geometry-shaped relations, location, source binding and resource fixtures |

One stable source review checked each changed path and its lower/upper assumptions.
Canonical polynomial operands justify ordered merge; matching coefficients are
still proven zero/nonzero by the field. Disjoint intervals justify strict root
order; overlapping intervals retain the original common-root proof. Public L1
construction remains the authority for grouped coefficients. No scoped finding
remains. The two-level L3 workload previously exhausting 200M work is outside this
fixed-input optimization measurement and has not been rerun; no claim that this
optimization closes that case or the seven higher requirements is made.

## Native Performance Measurement

[OptimizationBenchmark](Sources/OptimizationBenchmark/OptimizationBenchmark.swift)
uses prepared identical inputs outside timing, five fresh-process samples and
Native debug with the pinned compiler. Results below are median seconds for the
entire repetition batch, not per-call latency. [baseline.log](Evidence/baseline.log)
and [after.log](Evidence/after.log) retain raw samples. Work/storage values are
cumulative admitted logical payloads, not peak RSS or measured allocator counts.

| Path and repetitions | Before seconds | After seconds | Speed ratio | Work before/after | Storage bytes before/after |
|---|---:|---:|---:|---:|---:|
| L0 equal-denominator 1000 comparisons | 0.003668083 | 0.000382167 | 9.60 | 48000 / 7000 | 52000 / 0 |
| L1 100 additions of interleaved 64-term operands | 0.016405416 | 0.003284958 | 4.99 | 153300 / 38500 | 1638400 / 409600 |
| L2 100 comparisons of disjoint roots | 0.094604750 | 0.000698000 | 135.54 | 291800 / 200 | 3957600 / 19200 |
| L3 100 sparse degree-48 coefficient extractions | 0.014593750 | 0.007801334 | 1.87 | 29200 / 15300 | 2499200 / 580800 |

These measurements establish improvements only for the four specified inputs.
They are not general CAD timings, release optimization measurements or portable
wall-time guarantees. The limits are unchanged. Fewer operations and allocations
reduce admitted consumption rather than bypassing admission checks.

## Executed Configurations

| Configuration | Result |
|---|---|
| Native debug | 49 tests passed: L0 9, L1 8, L2 12, L3 20 |
| Native Address Sanitizer | Same 49 tests passed; no sanitizer errors |
| Ordinary WASM debug | Combined L0/L1/L2/L3 synchronous fixtures and optimization regression completed; exit 0 |
| Embedded WASM debug | Same combined proof completed; exit 0 |

The combined test package links existing lower fixtures/tests and compiles each
production module once. Exact compiler inventories match actual production
sources in all four builds: L0 49, L1 29, L2 30, L3 34; see
[SOURCE-INVENTORIES.txt](SOURCE-INVENTORIES.txt). Current sources are bound by
[SOURCE-SHA256.txt](SOURCE-SHA256.txt). Lower evidence is re-executed because its
production sources changed. Existing unchanged contracts remain authoritative.

Pinned executable:
`/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`.
Actual version: Apple Swift 6.4 (`swift-6.4-RELEASE`), host
arm64-apple-macosx27.0.0; package deployment macOS 14, executed on the host.
SDK IDs: `swift-6.4.0-RELEASE_wasm`,
`swift-6.4.0-RELEASE_wasm-embedded`; wasm32-unknown-wasip1.
Runtime: `/usr/local/bin/node`, 24.19.0, WASI Preview 1. Embedded uses WMO,
debug Onone and the matching SDK Unicode archive. Existing unused `-rdynamic`
and experimental WASI warnings remain; no signature mismatch or trap was found.

## Ownership and Isolation

| Logical state | Native / ordinary WASM / Embedded | Owner and lifetime |
|---|---|---|
| Original values, fields, polynomials and root proof | Identical immutable Sendable owners | Existing receipts retain backing and causal depths |
| Merge output and coefficient counts/buckets | Identical invocation-local Array values | Exclusive construction; admitted before allocation/mutation; output retains required values |
| Admission and cancellation | Same caller inout ledger and scoped forwarding | No reset, copied budget, escaping pointer, new unsafe code or shared mutable cache |
| Partition/cell graph | Identical immutable owners and index arrays | Existing retained graph/view semantics |

Changed files have no target-conditional storage, isolation or Sendable path.
ASAN exercises the existing scoped borrow through new success/failure paths.
Native immutable-reader tests remain successful. Synchronous WASI does not prove
multithreaded WASM behavior; no new shared mutable state requires such a claim.

## Reproduction

Prefix every build/test/run with `bash scripts/swift-test-timeout.sh 120 --`.
Use the pinned absolute compiler above for `swift` below, two jobs, and the same
package `Tests/L3RealCellVerification`:

```sh
swift test --package-path Tests/L3RealCellVerification --build-path .build/opt-native -j 2
swift test --package-path Tests/L3RealCellVerification --build-path .build/opt-asan -j 2 --sanitize address
swift build --package-path Tests/L3RealCellVerification --build-path .build/opt-wasm --swift-sdk swift-6.4.0-RELEASE_wasm -j 2 --product L3Proof
swift build --package-path Tests/L3RealCellVerification --build-path .build/opt-embedded --swift-sdk swift-6.4.0-RELEASE_wasm-embedded -j 2 --product L3Proof -Xlinker <matching-sdk>/libswiftUnicodeDataTables.a
node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/opt-wasm/out/Products/Debug-webassembly-wasm32/L3Proof.wasm
node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/opt-embedded/out/Products/Debug-webassembly-wasm32/L3Proof.wasm
swift run --package-path Tests/L3RealCellVerification --build-path .build/opt-native -j 2 OptimizationBenchmark
```

The Embedded archive is in the matching SDK's
`wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/`
directory. [Evidence](Evidence) retains logs;
[LOG-SHA256.txt](LOG-SHA256.txt) binds their contents. No higher CAD build,
main integration or changes to the original worktree were performed. This branch
has no configured upstream and is not pushed.

## Subsequent L4 Design Boundary

The L4 design commit `b3885553` adds proposed L3 inspection contracts to DESIGN.md.
They are not implemented or certified by either the original `f0d6ae9e` execution
evidence or the L0-L3 optimization evidence above. The original L3 snapshot report
and its hashes remain available at `f0d6ae9e`; the current production/test/package
manifests bind the optimized snapshot. No evidence certifies the proposed ports or L4.

## Working-Branch Integration

Integrated optimization commit `55aa02b5` with L4 design commit `b3885553`
in independent worktree `/private/tmp/cad-exact-layer-opt-integration-20261007`.
Both document conflicts were resolved by preserving all L0-L4 progress and
explicitly separating verified L3 behavior from proposed L4 ports. The parent
and L4 topology designs are byte-identical to `b3885553`; its entire L3 design
is retained with only the optimization section appended.

All 168 optimization source/test/package hashes and eight prior evidence-log
hashes match. The merged Native package compiled in 9.61 seconds and passed
49 tests (20 + 12 + 8 + 9). [integration-native.log](Evidence/integration-native.log)
is bound by the refreshed log manifest; [INTEGRATION-SOURCE-INVENTORY.txt](INTEGRATION-SOURCE-INVENTORY.txt)
confirms all 142 production files came from the integration worktree.
The command used the pinned Swift 6.4.0 compiler, two jobs and the 120-second
process guard; only the optimization task's Native cache was reused.
The unchanged source-bound ASAN and ordinary/Embedded WASM evidence above
remains applicable. No higher CAD build or L4 implementation claim is added.

The integration commit is intended for a clean fast-forward of
`codex/exact-real-cell-l3`; `main` and remote branches remain outside this operation.
