# Geometry Test Binding

## Purpose and Scope
This SwiftPM test target binds the existing geometry assertions to the canonical direct APIs. The parent is the [package design](../../DESIGN.md). This target has no production authority or child components.

## Responsibilities and Boundaries
Tests own instrumentation, expected source laws, resource limits, and failure assertions. Production `OriginalQueryExecution` owns public query admission; pure algebra instrumentation conforms to `ExactScalarAdmission` and owns its real `ExactScalarProofScopes`. No removed production allowance is reproduced.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../../Sources/CADGeometry/DESIGN.md) | depends on | Original-source geometry and direct execution | Exercises retained source and query contracts | Proximity is not source equality |
| [Execution](../../Sources/CADGeometry/OriginalQueryExecution/DESIGN.md) | depends on | Same-owner resource and depth admission | Public tests create a root and pass it through | No fresh root inside a selected query |

## Architecture
```text
Existing semantic assertions
    -> canonical test scalar admission -> real proof-scope mapping
    -> OriginalQueryExecution -> production source / query / reader
```

## Contracts and Invariants
- Preserve authored laws, source domains, ownership, coverage, and rejection assertions.
- Work and storage instrumentation retains its historical units: scalar payload tests count rounded UInt32 words, while canonical admission receives bytes.
- Value and coefficient depth have independent limits. Forbidden root visits still fail, including coefficient visits in rational-only tests.
- An admission rejection retains its original typed test error. Cancellation remains cancellation.
- Shared observable state uses the same Synchronization.Mutex owner on all targets.

## Failure, Concurrency, and Constraints
Canonical witnesses checkpoint before debits and after test-triggered cancellation. Scope work is checked before a debit and recorded only after it succeeds. Scalar tests retain the original local ceilings; public query tests retain explicit source/span/depth policy and cumulative budget.

## Verification and Change Impact
The existing tests are the behavioral oracles. Source migration and parsing alone do not establish success. The task owner runs the frozen affected SwiftPM target after all required API edges are bound, and reports any source-contract conflict separately. Production APIs, the standalone G01 public fixture, and historical evidence are outside this target's edit scope.

The algebra binding owner completes the 23 audit-listed `RationalAlgebraAdmitting` test files from the initial canonical witness edits. The remaining binding owner owns this design and `GeometryTestAdmission.swift`. Shared helper names and canonical proof-scope mechanics remain stable while those files are completed; failures are inspected through `geometryTestOriginalFailure` and `geometryTestIsCancelled`. A value-root visit remapped to the coefficient axis must exercise the coefficient visit policy and independent ceiling.

The supporting-plane and Coons fixtures retain one actual `OriginalQueryExecution` per local noncopyable Budget. Their generic scalar witnesses and concrete source factories borrow that same execution and proof scopes. Immutable observer objects protect work, rounded-word storage, and callback ordinals with `Mutex<State>` on every target; checks and counter mutations occur under the lock, and cancellation occurs after unlocking. Dynamic N/N−1 quotas and Coons cell limits stay on the actual admission path. The silhouette boundary fixture uses `SurfaceSilhouetteContext` with the same retained budget.

| Test state | Storage owner | Isolation | Read / mutation | Release |
|---|---|---|---|---|
| Scalar proof scopes | Local noncopyable admission | Exclusive inout borrow | Canonical admission witnesses | Test/query scope |
| Instrumented source counters | Immutable observer | Synchronization.Mutex on every target | Observer methods / withLock | Retained by actual budget callbacks |
| Public query resources | OriginalQueryBudget | Production Mutex | snapshot / canonical execution debit | Budget and retained source owners |
