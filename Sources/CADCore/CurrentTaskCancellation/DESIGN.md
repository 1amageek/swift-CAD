# Current Task Cancellation

## Purpose and Scope

This component provides the Foundation-free, target-independent cancellation
check used by Core code that must observe the current Swift task. It is a child
of [CADCore](../DESIGN.md). It owns only the checker contract and immutable
implementation; consumer routing, domain failure mapping, and transaction
publication remain outside this component.

## Responsibilities and Boundaries

The component exposes a `Sendable` protocol and an immutable concrete checker.
The checker reads `Task<Never, Never>.isCancelled` at the call site and throws
`CancellationError` when the current task is cancelled. It does not store task
handles, cancel tasks, sleep, yield, publish state, or translate cancellation
into a domain error.

The implementation contains no Foundation import and no target-specific branch.
Native, normal WASM, and Embedded WASM use the same source and the same
failure contract. Consumers decide where a check belongs in their own bounded
operation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Core public module boundary | Exposes the component to Core consumers | Do not add consumer policy here |

## Architecture

```text
Current task
    -> Task<Never, Never>.isCancelled
        -> CurrentTaskCancellationChecker
            -> success, or typed CancellationError
```

## Contracts and Invariants

- `CurrentTaskCancellationChecking` is `Sendable` and exposes only
  `checkCancellation() throws(CancellationError)`.
- `CurrentTaskCancellationChecker` is immutable and stateless.
- A cancelled current task always throws `CancellationError` at the check;
  an uncancelled current task returns normally.
- The checker never returns success after observing cancellation and never
  replaces cancellation with a default value or domain success.
- The check observes the task at invocation time. It does not promise automatic
  checks at suspension points or cancellation of another task.
- All supported targets compile the same implementation without conditional
  synchronization, storage, or error behavior.

## Runtime Flows

```text
consumer enters bounded operation
    -> checker.checkCancellation()
    -> continue only on normal return
    -> propagate CancellationError on cancellation
```

## State, Ownership, and Lifecycle

The checker owns no mutable state and has no external resource or lifecycle.
Any consumer-created `Task` owns cancellation propagation; the checker only
observes that task while its synchronous check executes.

## Failure, Concurrency, and Constraints

The checker is safe to share because it is immutable and `Sendable`. It does
not use a lock, actor, `nonisolated(unsafe)`, or unchecked sendability. The
only failure is the standard `CancellationError` produced for a cancelled
current task.

## Verification and Change Impact

Dedicated Core tests verify uncancelled success and `Task.cancel()` followed by
typed cancellation propagation. Existing component probes verify the same
source and markers on Native, normal WASM under Node WASI Preview 1, and
Embedded WASM under the matching SDK. Full CADCore Embedded portability remains
separate from this component if another Core source imports unavailable modules.
