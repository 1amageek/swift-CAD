# Kernel Failure Contract

## Purpose and Scope

Child of [CADCore](../DESIGN.md), with no children. Owns immutable kernel
failure values, cause classification, domain-error normalization and diagnostic
presentation. Requirement C4 in [the task register](../../../OCCT_REQUIREMENTS.md)
is the functional requirement owner.

## Responsibilities and Boundaries

Normalization preserves the original kernel phase, code, subshape, residual,
message and existing context. Supplied feature and tolerance context fill only
missing fields. Evaluators own geometric decisions, success and admissible input
ranges; this component classifies their reported failures.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Typed error values | Publishes the failure contract | Domain errors remain owned by their defining types |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | KernelError.wrapping | Normalizes evaluation boundaries | Classification never fabricates successful geometry |
| [CADCapabilities](../../CADCapabilities/DESIGN.md) | used by | KernelErrorCode categories | Publishes documented failure causes | Catalog declarations do not prove geometric coverage |

## Architecture

```text
Domain failure -> KernelError.wrapping -> immutable code and diagnostic context
                                      -> KernelFailureCategory -> caller policy
```

## Contracts and Invariants

- Resource exhaustion is classified as resourceLimitExceeded, not invalidInput.
- Explicit unsupported-domain failures retain unsupportedCapability.
- Cancellation, missing references, invalid topology, I/O, unavailable dependencies,
  security refusal and unclassified failures have distinct codes.
- An unknown error is unclassifiedFailure; it is never blamed on input validity.
- Existing KernelError context is preserved exactly except for missing context fill.
- Every KernelErrorCode has one explicit cause category. Non-discrete results
  remain distinct from numerical indeterminacy and unsupported domains.
- Classification operates on typed causes. Diagnostic wording is not a predicate.
- User-facing descriptions return the diagnostic message; debug descriptions
  retain phase, code and context. Callers inspect codes rather than parsing text.

## State, Ownership, and Lifecycle

Values are immutable and Sendable. No shared mutable state, ownership transfer,
locks, allocation pools or platform-specific isolation branches are introduced.

## Failure, Concurrency, and Constraints

Normalization does not retry, convert failure to success or select a backend.
Cancellation reported as a domain error retains a cancellation code even across
an evaluation boundary that returns KernelError. Existing cancellation checks
that throw CancellationError remain unchanged.

## Verification and Change Impact

[KernelFailureContractTests](../../../Tests/CADCoreTests/KernelFailureContractTests.swift)
checks actual public normalization for unsupported input, resources, cancellation,
unknown errors and context preservation, and exercises every declared code's
category. [KernelFailurePipelineTests](../../../Tests/SwiftCADTests/KernelFailurePipelineTests.swift)
checks real document evaluation, tessellation resource exhaustion, invalid
geometry and task cancellation through CADPipeline. CADWASMSmoke exercises
resource and unsupported contracts on normal WASM with the matching release
toolchain/SDK. Embedded runtime verification remains required by the task-wide
integration contract: its current build stops at an existing Foundation import
because the matching Embedded SDK does not provide Foundation. No Embedded
success is inferred from native or normal WASM results. Changes to codes
require exhaustive category handling and downstream capability review.
