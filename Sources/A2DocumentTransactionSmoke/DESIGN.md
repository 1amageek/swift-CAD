# A2 Document Transaction Smoke

## Purpose and Scope

An executable verification module under the package [design](../../DESIGN.md).
Its only child is [DocumentTransactionProof](DocumentTransactionProof/DESIGN.md).
It executes the public A2 transaction path on Native, normal WASM and Embedded.

## Responsibilities and Boundaries

The entry point awaits the child proof and prints its final marker only after
success. It owns no transaction implementation, alternative source envelope,
geometry evaluator, persistence codec or target-specific fallback.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Executable target registration | Provides the production dependency graph | Matching toolchain/SDK and runner are required |
| [DocumentTransactionProof](DocumentTransactionProof/DESIGN.md) | child | Throwing asynchronous public proof | Owns actual success and refusal assertions | A marker is not emitted after any failure |

## Architecture

```text
async executable entry -> DocumentTransactionProof.run -> final success marker
```

## Contracts and Invariants

All targets compile the same source. Uncaught proof or production failures fail
the executable. Foundation-free output uses Swift `print`; it does not replace
the complete production source graph with a private value-only adapter.

## Verification and Change Impact

The root verification lane builds and links this target with fixed Swift 6.4.0
and matching SDKs, then runs its actual executable on Native and Node WASI.
Source, Package graph, artifact and logs must be bound in the verification
receipt. A backend without actual runtime evidence remains unverified.
