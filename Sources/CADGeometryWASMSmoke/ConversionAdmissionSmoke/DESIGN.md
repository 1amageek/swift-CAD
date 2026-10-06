# Conversion Admission Smoke

## Purpose and Scope

Child of [CADGeometryWASMSmoke](../DESIGN.md), with no children. Owns portable
behavioral witnesses for unchanged-default common curved conversion and final
callback cancellation. Executable registration and invocation remain parent-owned.

## Responsibilities and Boundaries

Invokes public `GeometryConverting` and original source protocols. It owns four
curved success checks and six cancellation checks; it does not own converter
implementation, source preparation, target selection, platform runtime or limits.
No target condition changes source, callback or cancellation semantics.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Smoke](../DESIGN.md) | parent | executable registration and target provenance | Parent calls the synchronous and async witnesses | These files do not register themselves |
| [Conversion](../../CADGeometry/GeometryConversion/DESIGN.md) | depends on | continuous same-chart geometric guarantees and cancellation | Executes actual converter and immutable original sources | Whole intervals and caller allowances remain unchanged |

## Architecture

```text
parent Native / normal WASM / Embedded runner
  -> public common converter -> four original curved conversions
                            -> six final-callback cancellation attempts
  -> output degree/count and three-field checks / explicit cancellation
```

## Contracts and Invariants

`runCurvedConversions()` uses the same literal analytic circle/cylinder,
varying-weight quarter-circle and polynomial ruled inputs and allowances as the
native default admission owner tests. Default scalar/work and candidate limits
remain unchanged. Actual output degrees/control counts and reported continuous
position/tangent/principal-curvature bounds must satisfy the request. Independent
sample witnesses compare the output to the original value without authorizing
continuous acceptance themselves. Failure throws a typed classification error.

`runPublicationCancellation()` creates an isolated child task per public
curve/surface approximation, interpolation and certification entry. The source
returns complete valid line/plane enclosure evidence and cancels that same task
in its final anchor callback. Each attempt must throw `CancellationError`.
Publishing any successful value is a smoke failure; another error propagates.
All mutable candidate/task state belongs to one invocation. Sources are immutable
Sendable values; no shared state, I/O callbacks or target-specific storage exists.

## Runtime Flows

The parent runs four synchronous conversions, then awaits all six independent
cancellation attempts. A child is awaited before the next child is created;
cancellation cannot leak into the parent or authorize omission of an attempt.

## Failure, Concurrency, and Constraints

Caller source and converter resource failures remain explicit. The executable
owner fixes build/runtime timeout, Swift 6.4.0 SDK, target and runtime identity.
This child provisions no new stack or budget, and performs no retries.

## Verification and Change Impact

Each selected target must compile, link and execute the registered child on its
exact production source graph. A generated file or successful compile does not
establish portable evidence. The native source tests remain their own proof;
root-owned portable registration and actual target receipts are pending. Source,
converter, SDK or runtime changes invalidate the affected witness evidence.
