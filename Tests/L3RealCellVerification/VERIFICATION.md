# L3 Real-Cell Verification

## Scope and Snapshot

Verified 2026-10-07 in `codex/exact-real-cell-l3`, worktree
`/private/tmp/cad-exact-polynomial-l1-20261007`.
Implementation commits: `3eb70937` (source/projection), `b8c0e554` (lifting),
`cc4e8ae6` (query/selection). The final evidence commit includes the issued-prefix
query repair and final C1/C2/C4/C6 behavioral assertions.

The isolated SwiftPM package compiles actual production files through symlinks.
[SOURCE-INVENTORIES.txt](SOURCE-INVENTORIES.txt) records exact compiler inventories:
49 L0, 29 L1, 30 L2 and 34 L3 files in every configuration. All existing recorded
L0/L1/L2 production hashes match; their independently verified contracts/evidence
are reused. No lower production file, production package graph, new dependency,
higher CAD target or main integration is included.
[SOURCE-SHA256.txt](SOURCE-SHA256.txt) identifies the final L3 implementation,
fixtures, tests and manifests. [DESIGN.md](DESIGN.md) owns the verification graph.

## Executed Configurations

| Configuration | Actual result on final source |
|---|---|
| Native debug | 18 Swift Testing tests passed; four concurrent immutable readers |
| Native Address Sanitizer | Same 18 tests passed; no sanitizer error |
| Ordinary WASM debug | All 13 synchronous fixture routines executed; exit 0 |
| Embedded WASM debug | Same 13 routines executed; exit 0 |

Pinned compiler: Apple Swift 6.4 (`swift-6.4-RELEASE`), executable
`/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`.
Host target: arm64-apple-macosx27.0.0, package deployment target macOS 14;
execution is on the host, not a macOS 14 device. SDK identifiers:
`swift-6.4.0-RELEASE_wasm` and `swift-6.4.0-RELEASE_wasm-embedded`;
WASM target: wasm32-unknown-wasip1. Runtime: Node 24.19.0, WASI Preview 1.
Embedded uses SDK-required WMO, debug `-Onone`, and the matching SDK's
`libswiftUnicodeDataTables.a`. Raw artifacts remain in their dedicated directories.

Every command has a 120-second process-group guard and each build uses two jobs.
R1 Native execution took 7.169 seconds; ASAN took 16.428 seconds while independent
builds ran concurrently. These are test run times, not a general performance guarantee. Cross-builds emitted the existing
unused `-rdynamic` warning; Node emitted its experimental WASI warning. No signature
mismatch or runtime trap was observed.

## Behavioral Evidence

| Contract | Actual paths and assertions |
|---|---|
| C1 source/Boolean binding | `sourceFailures`, `domains`, `selectionAndLocation`: foreign owners, invalid postfix/index/box count, retained initialization, source-specific predicate identity, zero-variable true/false selection and exact point/condition queries, field-family validation with no coordinates |
| C2 full projection | Native `projectionAndSource`: PSC j=0 equals L1 resultant; higher minors equal known zero/one determinants; shared-factor zero PSC matches independently computed GCD degree; derivative/coefficient/PSC provenance retained |
| C3 nullification/degree drop | `nullification`, `nullifiedQuery`: xy=0 has all three exact zero cells; xz+y=0 has an entire z-fiber at x=y=0; non-sample z=7 and z=-9 satisfy the same retained condition |
| C4 box coverage | `domains`, `retainedAndOutside`: all four endpoint combinations, closed/open singleton, explicit empty box, unbounded/rootless domains, zero/nonzero constants, zero variables and six variables; outside queries prove exclusion without root enumeration |
| C5 singular/mixed sets | `singularities`: isolated x²+y², cusp y²-x³, repeated (x-y)² and a line plus an isolated point; `nullification` also checks crossing branches |
| C6 exact identity/conditions | All samples locate in their issued cells; non-sample points in same-sign disjoint sectors remain separate; foreign IDs fail; generic parent handles yield valid prefix samples/conditions rather than invalidCell |
| C7 algebraic coefficients | `transportedCoordinates`, `algebraicQueries`, `OriginalCoefficientFixtures`: exact earlier-coordinate embedding, linear-section reuse, ancestor bounds, sibling rejection, compatible descendant queries and retained preexisting algebraic coefficient depth |
| C8 consumer relations | `applicationRelations`: 3-variable isolated CS, overlap and two distinct folded UV points; 4-variable SSI line and coincidence region; exact selected dimensions and location, no geometry producer integration claim |
| C9 atomic resources | `resources`, `OriginalCoefficientFixtures`, `checkedProjectionSizes`: independent work/storage/value/coefficient limits, source domain traversal at the exact work boundary, cell/root/extension ceilings, checked matrix/count overflow, cancellation at final producing/querying/selection checkpoint, exact admitted storage/work versus one-less failure; no partial publication/fallback |
| C10 ownership/portability | `escapedOwnership`: drop creating inputs/domain/partition and recover through retained condition; `concurrentImmutableReaders`: four independent admissions share receipts; same public protocol requirement paths execute on both WASM SDKs |

A complete partition is justified by the retained full projection conditions and
complete L2 root unions, not by sample residuals. Incoming projection/source/boundary
laws cut stacks; auxiliary derivatives remain in rank/Thom evidence and sample sign
metadata. This corrected unnecessary axis-0 auxiliary roots in the mixed fixture
without increasing its 200M work ceiling. No approximation solver or new root engine
was introduced. The final cumulative review closed ancestor-bound import, zero-variable
behavior, higher-minor evidence and the valid-prefix query defect; its finding fixes
were rechecked. No further review cycle or unrelated hardening remains.

## Ownership and Isolation Matrix

| State/owner | Native / ordinary WASM / Embedded storage | Isolation and release |
|---|---|---|
| Source/context/coefficient field | Identical immutable Sendable ARC owners | Read-only after construction; source retains lower owners |
| Projection/records/stacks | Identical immutable arrays with integer graph offsets | Partition owns graph; no internal ARC cycle |
| Cell/view/condition/selection | Identical retained owner plus offsets/shared arrays | Safe owner-retaining reads; final ARC release |
| Construction and predicate stack | Identical invocation-local arrays | Exclusive synchronous construction, then immutable transfer |
| Admission pointer/depth observer | Identical non-Sendable scoped owner and four callbacks | Exclusive synchronous borrow inside ExactCellAccess.run; never stored in receipts |
| Caller ledger | Identical inout admission | Separate ledger per invocation/task; no shared mutable state |

No target-conditional synchronization, storage or Sendable contract exists. Only
isolated-module imports are conditional. Logical storage admission counts typed
payloads, not exact allocator capacity/RSS. The sole unsafe boundary is the scoped
exclusive admission pointer; ASAN exercised success/failure/cancellation and Native
readers exercise concurrent retained ownership. Synchronous WASI execution does not
establish multithreaded WASM semantics.

## Reproduction and Evidence

From the worktree root, use `bash scripts/swift-test-timeout.sh 120 --` before every
command. Pinned compiler commands:

```sh
swift test --package-path Tests/L3RealCellVerification --build-path .build/l3-native -j 2
swift test --package-path Tests/L3RealCellVerification --build-path .build/l3-asan -j 2 --sanitize address
swift build --package-path Tests/L3RealCellVerification --build-path .build/l3-wasm --swift-sdk swift-6.4.0-RELEASE_wasm -j 2 --product L3Proof
swift build --package-path Tests/L3RealCellVerification --build-path .build/l3-embedded --swift-sdk swift-6.4.0-RELEASE_wasm-embedded -j 2 --product L3Proof -Xlinker <matching-SDK>/libswiftUnicodeDataTables.a
node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/l3-wasm/out/Products/Debug-webassembly-wasm32/L3Proof.wasm
node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs .build/l3-embedded/out/Products/Debug-webassembly-wasm32/L3Proof.wasm
```

Replace `swift` with the pinned absolute compiler above and `node` with
`/usr/local/bin/node`. The matching Embedded archive is located beneath
`/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/`.
Final raw logs remain in `.build/l3-evidence`; [LOG-SHA256.txt](LOG-SHA256.txt) binds them.
The branch has no configured upstream; no push is performed. Closure/incidence,
components, geometry assembly and publication belong to later layers. This evidence
completes independent L3, not the seven higher requirements.

## R1 Source Traversal Admission Repair

The subsequent review found that `bind` accepted 100,000 unbounded domains under
work limit 1, reporting work=1. Each domain now consumes one unit before its
validation, in the same caller admission as the existing invocation and scalar
operations. API, field/owner identity, array retention and existing limits are
unchanged. Source traversal remains invocation-local on every target.

`FailureFixtures.sourceTraversal` covers zero, one and 100,000 domains. Binding
succeeds with exactly n+1 work and fails explicitly at n work; the same domain
remains usable after failure. The new Native test failed before the repair with
invalidCoverage, then passed with the repaired implementation. The cumulative
18-test Native/ASAN suites and 13-routine ordinary/Embedded WASI executables passed.
The repair received a targeted finding recheck against the validated source path.
R1 logs are retained in `.build/l3-evidence/r1-*.log` and included in the log manifest.
Earlier `*-final` logs describe the pre-R1 snapshot.

The review's additional x²-2=0/y²-x=0 probe on [1,2]² exhausted 200M work.
This repair does not change that algorithm or its budget, and does not claim
successful generation/location for that probe. No upper CAD build or integration
was performed.
