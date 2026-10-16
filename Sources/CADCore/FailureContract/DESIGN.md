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
| [Native Codec Capability](../NativeCodecCapability/DESIGN.md) | coordinates with | Native/normal Codable and unavailable Embedded codec boundary | Preserves common values while isolating codec interfaces | No change to shared state, typed failures or geometric support |

## Architecture

```text
Domain failure -> KernelError.wrapping -> immutable code and diagnostic context
                                      -> KernelFailureCategory -> caller policy
Geometry retained failure -> KernelFailureClassifying -> the same classification
```

## Contracts and Invariants

- Resource exhaustion is classified as resourceLimitExceeded, not invalidInput.
- Explicit unsupported-domain failures retain unsupportedCapability.
- A certified fillet radius exceeding original material thickness reports
  filletThicknessExceeded. Certified blend self-intersection and disappearance
  of a required face report filletSelfIntersection and filletFaceDisappeared.
  These causes require the corresponding original geometry witness; resource
  exhaustion or an inconclusive geometric search cannot be relabeled as them.
- Cancellation, missing references, invalid topology, I/O, unavailable dependencies,
  security refusal and unclassified failures have distinct codes.
- An unknown error is unclassifiedFailure; it is never blamed on input validity.
- Existing KernelError context is preserved exactly except for missing context fill.
- Every KernelErrorCode has one explicit cause category. Non-discrete results
  remain distinct from numerical indeterminacy and unsupported domains.
- Classification operates on typed causes. Diagnostic wording is not a predicate.
- `KernelFailureClassifying` exposes only a `kernelFailure: KernelError`
  requirement. `KernelError` conforms by returning itself; Geometry-owned failures
  retain their original error and immutable query context outside Core.
- The `KernelError.wrapping(any KernelFailureClassifying)` overload reads
  this requirement directly, without a runtime protocol cast. Its `any Error`
  overload recognizes Core-owned `KernelError` and Core domain errors. Owners
  of erased foreign failures expose a concrete classification reader at their
  own module boundary; arbitrary erased protocol conformers cannot be recognized
  by Embedded Swift. This is an explicit migration of the erased-error contract.
  Its returned value is a classification snapshot, not an ownership transfer of
  the original failure. Throwing consumers preserve the original classified error.
- Adding the classification protocol changes neither stored `KernelError` fields
  nor its equality, Native/normal Codable or Embedded codec boundary.
- Portable source encoding exhaustion retains resourceLimitExceeded; malformed
  limits, nonfinite scalars and canonical key collisions retain invalidInput.
  Embedded presents each original encoding cause explicitly without reflection.
- User-facing descriptions return the diagnostic message; debug descriptions
  retain phase, code and context. Callers inspect codes rather than parsing text.

### Target Diagnostic Capability

Native and normal WASM retain the existing `String(describing: error)` source
presentation. Embedded Swift 6.4.0 does not provide that reflective initializer.
For Embedded, the module-internal `KernelDomainErrorPresentation` presents each
Core-owned domain enum using an exhaustive case switch and all actual associated
values. Tagged IDs use their existing canonical description; quantity/resource
kinds use their raw values; schema/vector fields and scalars are explicit. Array
values retain order and duplicates. This is diagnostic text, not a wire codec or
an input admission authority. Diagnostic presentation adds no protocol or state owner.

The earlier `KernelError` branch preserves its message and complete context on
every target. Classification and cancellation are unchanged. An unknown foreign
error remains `unclassifiedFailure`; Embedded uses the explicit message
`Unclassified source error; reflective diagnostic payload is unavailable on Embedded Swift.`
Its missing reflective payload is an intentional target capability difference,
not successful input, an invalid-input reclassification, or a substitute source
record. Native and normal WASM continue to retain their original reflective text.

Verification uses the actual complete CADCore product to test known associated
values (including structured values/IDs/arrays), unknown foreign errors and an
existing fully populated KernelError. Embedded compile/link/runtime remain
required. Adding a Core domain error case requires updating its exhaustive
structural presentation and affected behavioral fixtures. The classification
protocol is source-independent and imports no Geometry or scalar-domain types.


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
integration contract. The [actual Core portability proof](../../CADCorePortabilitySmoke/CorePortabilityProof/DESIGN.md)
owns known associated-value diagnostics, unknown foreign errors and existing
KernelError context on fixed Native/normal/Embedded targets. Complete Embedded
compile/link/runtime is required; Native/normal evidence does not establish it.
Changes to codes
require exhaustive category handling and downstream capability review.


PAR.G6POS1 adds approximationToleranceRejected to KernelErrorCode's numericalIndeterminacy category for an original-source approximation candidate that fails a requested complete-domain position allowance. It does not assert absence of another candidate; geometry consumers own mapping and feature/tolerance context. CADCore does not import CADGeometry.

The erased `any Error` normalization entry and Embedded concrete diagnostic
discovery emit into the caller. Fixed Embedded error-box metadata is owned by
the boxing compilation boundary; a cast inside the separately compiled Core
module can otherwise miss an actual `KernelError`. Concrete associated-value
presentation helpers keep internal serialized visibility, while their typed
arguments avoid erased-error discovery. Runtime verification checks erased
Core errors, known classified witnesses, opaque foreign errors and retained
Geometry errors across the real module boundaries. No synchronization or
classification semantics are conditionalized.
