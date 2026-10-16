# CADTopology Test Bindings

## Purpose and Scope
The SwiftPM `CADTopologyTests` target verifies the topology components indexed by
[the module design](../../Sources/CADTopology/DESIGN.md). This binding migration
covers the five original callback/effect suites and the nine additional real
SwiftPM inputs identified by the full-target compiler diagnostics. The binding
inventory records each affected API and file.

## Responsibilities and Boundaries
The tests retain their authored geometry, independent integral formulas, topology
ordering, source identity, foreign-receipt rejection, and resource/cancellation assertions.
Test instrumentation observes admission callbacks; it does not authorize production work.

## Related Designs
| Design | Relationship | Contract Used | Caution |
|---|---|---|---|
| [Topology](../../Sources/CADTopology/DESIGN.md) | verifies | Canonical direct caller bindings | Module compilation alone is not runtime evidence. |
| [Execution](../../Sources/CADGeometry/OriginalQueryExecution/DESIGN.md) | depends on | Same execution, independent ceilings, retained failure cause | Inspect the original cause through admission wrappers. |
| [Area](../../Sources/CADGeometry/SurfaceAreaIntegration/DESIGN.md) | verifies | Source chart and integral authority | Preserve geometry and numerical oracles. |
| [Open boundary](../../Sources/CADTopology/OpenBoundaryLoop/DESIGN.md) | verifies | Throwing single-core traversal | Preserve order and fillability predicates. |

## Architecture
```text
Authored fixture -> one test execution -> chart / preparation / evaluation
                               |               |
                               +-> budget <----+
Independent formulas / topology predicates -> existing assertions
```

## Contracts and Invariants
All operations within a counted phase use the same live `OriginalQueryExecution`.
Nine former callback-step equality/reuse/`+2` assertions are replaced by measured
cumulative admission boundaries. Each fixture independently measures preparation
work `P` and final work `N`, then replays preparation and the selected operation
on one execution at ceiling `N` and `N-1`. The former succeeds with exactly `N`
admitted work; the latter retains a work-axis resource refusal with the exact
ceiling and rejected debit. No child budget resets preparation work.

The adaptive integrator's actual cell counter remains a distinct mathematical
ceiling: six admitted cells must refuse the seventh with residual seven. The
polynomial flux tests likewise retain their actual coefficient-operation counter,
including the 370-operation refusal and exact cumulative coefficient allowance;
that counter is not total arithmetic work.

The old callback total did not observe root-solver events, and that metric is
removed rather than presented as proof of reuse. Read-only verification of the
selected retained-owner path shows that `centeredFanBounds(using:proof)` passes
`proof.range` and `proof.midpoint` to `pairedFanFields` without a chart localizer
call. Child restriction passes `parent.range` and `parent.root` to the existing
midpoint restriction operation; the unchanged-parent branch returns the retained
parent. This evidence owns the solver-reuse claim, while runtime numerical,
foreign-owner, and exact cumulative-admission tests own the observable results.
The production implementation remains fixed; this is a test metric migration.
A callback failure remains a failure with its original typed cause inside the admission
wrapper. No assertion is weakened to accept an arbitrary error.

The three former missing-callback checks now have two explicit proof obligations:
missing the mandatory `using` argument is rejected by the compiler in
[the negative fixture](../OriginalQueryExecutionVerification/CompileFailures/MissingAreaExecution.swift);
an actual runtime owner with zero work refuses single-cell preparation, multi-cell
preparation, and prepared-chart evaluation with a typed resource failure. Foreign
source rejection and exhaustion of the preparation owner's remaining work stay runtime checks.

## Verification and Change Impact
The shared verification owner compiles all 33 SwiftPM inputs against a fixed candidate
module snapshot, then executes the affected runtime tests with an explicit filter for the heavy
area suite. The first binding snapshot passed all 33 inputs; later metric edits
require their own stable verification and do not inherit that typecheck result. The negative fixture is
outside every SwiftPM target and must produce three missing-`using` diagnostics against
the same accepted modules. Neither a successful source scan nor fixture creation proves
these obligations; pending compiler/runtime results are reported separately.
