# SwiftCAD Drawing Caller Tests

## Purpose and Scope
The SwiftPM `SwiftCADTests` target owns the real document drawing caller regression
in [DocumentDrawingCanonicalAdmissionTests](DocumentDrawingCanonicalAdmissionTests.swift).
This clause covers that suite only, with no child test components.

## Responsibilities and Boundaries
The fixture creates the original native sheet through the real document builder
and evaluator. Only source preparation runs on MainActor. Public drawing queries
and retained readers execute on the normal test worker with one caller execution.
The fixture owns no production source law, receipt, or allowance.

## Related Designs
| Design | Relationship | Contract Used | Caution |
|---|---|---|---|
| [Document Drawing](../../Sources/SwiftCAD/DocumentDrawing/DESIGN.md) | verifies | Public silhouette and contact witnesses | Publication success requires actual original-source results. |
| [Original Query Execution](../../Sources/CADGeometry/OriginalQueryExecution/DESIGN.md) | depends on | Same execution, independent resource ceilings and cancellation | Helpers never construct or reset the caller execution. |

## Architecture
```text
Real source preparation (MainActor) -> normal worker
 -> projection / placement -> unplaced silhouette -> placed silhouette
 -> silhouette readers -> contact preparation -> contact readers
```

## Contracts and Invariants
Non-inlined helpers separate public methods and retained readers so unrelated
fixture locals do not share one large synchronous stack frame. Their boundaries
preserve the exact query order, all original assertions, source inputs, explicit
caps, and the same inout execution. The first measured query and exact N / N-1
replays execute the same path. Cancellation checks retain the original cause.

## Verification and Change Impact
The verification owner compiles this real test input against fixed production
products, then runs all three suite cases with the canonical runtime monitor.
Generated entry prologues identify fixture frame changes; they do not establish
behavioral success. Whole-domain plane exclusion, the original quadratic arch
and its endpoint contacts, exact resource boundaries, and cancellation must all
pass on the normal worker before this caller regression is complete.
