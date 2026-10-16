# Retained moment-loop algebra admission

The actual public exact-receipt moment entry now forwards its already-selected
algebra ceiling 32 into trim-loop unwrapping. The source, independent incoming
value/coefficient ceilings, subdivision policy, equations and 262144-work
request ceiling are unchanged. The owning contract is
[Volume Moments](../../../../Sources/CADTopology/VolumeMoments/DESIGN.md).

## Counterexample and expected result

The authored unit cube has six outward-oriented planes, eight vertices,
twelve shared edges and twenty-four directed two-point polyline pcurves.
The genuine public `ValidatedBRepModel` constructor first validates that source.
An existential `BRepVolumeMomentMeasuring` then consumes its retained exact
receipt through the direct caller execution.

| Observation | Actual result |
|---|---|
| Before correction | Receipt succeeds; the moment query refuses at the original polyline producer's missing caller algebra-admission guard |
| Independent integrals | V = 1; X/Y/Z = 1/2; XX/YY/ZZ = 1/3; XY/XZ/YZ = 1/4 |
| Exact-third oracle | Every square-moment interval contains both adjacent binary64 dyadics bracketing the exact rational 1/3 |
| Required accuracy | Every full outward interval width meets the unchanged absolute request 1e-5 |

Receipt preparation is a separate observed operation, as the retained-receipt
entry requires. Native preparation consumes 87146 work and 931152 bytes.
It is neither hidden inside a retry nor charged again as integration. The
raw-model moment entry's shared validation/integration policy is unchanged.

## Accepted execution

All lanes use fixed Swift 6.4.0 and matching SDKs. Native uses macOS 27.
Compilation/linking is bounded to 1200 seconds and 10 GiB per lane; execution
is bounded to 120 seconds. Jobs remain one, with at most two compilers.

| Lane | Checks passed | Runtime seconds | Query work | Query bytes |
|---|---:|---:|---:|---:|
| Native candidate | 5 | 1.426 | 73665 | 421904 |
| ASAN | 5 | 28.386 | 73665 | 429408 |
| Ordinary WASM | 5 | 3.209 | 73665 | 342096 |
| Embedded WASM | 5 | 0.932 | 73665 | 342136 |

Each lane measures its own storage and checkpoint trace; target differences
are retained. Work/storage exact-N success and separate N-1 refusals use one
retained source receipt, including thirteen prior caller work units. Native's
cumulative work boundary is 73678. Entry, in-progress and the last observed
checkpoint cancellation all refuse output. Independent ambient algebra axes
(0,32), (32,0) and (0,0) remain effective; this rational cube needs no algebraic
extension. Source authoring mutation, COW and result use after the receipt and
query scope end preserve all ten original intervals.

Core 67 and Geometry 2171 source/product premises are unchanged and reused.
Only Topology 142 is regenerated. Its current total source authority has 2380
inputs. ASAN and Embedded retain their successful compiler phases from runs
whose later client compilation failed; those failed runs are never relabeled
as runtime successes. No upper module or independent L2-L6 artifact is rebuilt.

## Fixture and diagnostic scope

Native and portable clients use the same check body. Native candidate, ASAN
and ordinary WASM accepted shared-source hash `cb42683853869d2dbd2e854830f3384459feb705c892be955a2bfcbfdad20012`.
Embedded accepted final hash `88e32377739550032c63d740f799579542d1828ac45a185bfc10188b7e81d022`.
Removing its sole direct `import HashTreeCollections` line reproduces the
earlier source byte-for-byte. No calculation, oracle, state or lifetime body
changes. Main integration freshly compiles the final Native client rather than
resuming the earlier test build; its receipt belongs to `integration.json`.

The retained diagnostics distinguish the missing-policy RED from two fixture
API failures (`TreeDictionary.removeAll(where:)`) and the Embedded direct-import
requirement. None of those client compilation failures ran a test. The initial
minimal positive used a rounded-third comparison; final acceptance uses the
stronger exact-third bracket and does not count that initial run as the final
five-check proof.

[index.json](index.json) binds source, compiler/SDK, products, commands, logs,
test inputs and immutable compressed raw receipts.
[REVIEW.md](REVIEW.md) records the scoped review and finding confirmation.

This delivery closes the retained cube moment admission counterexample. Raw
Mass validation and its historical work-exhaustion counterexample require
their own current caller proof. Curved moment domains, general repair,
U1-U4 and the seven whole requirements remain separate incomplete gates.
