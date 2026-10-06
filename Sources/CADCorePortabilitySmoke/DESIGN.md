# Core Portability Smoke

## Purpose and Scope

This executable owns the entry point for the actual complete CADCore Native,
normal WASM and Embedded WASM proof. Parent: [Swift-CAD](../../DESIGN.md).
Child: [Core Portability Proof](CorePortabilityProof/DESIGN.md). This is an A2
prerequisite, not a substitute for full Embedded document transactions.

## Responsibilities and Boundaries

The entry delegates all fixture assertions to its child. It reports common,
available-codec and completion markers only after those proofs return. Root
owns Package product registration and bounded build lanes.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Swift-CAD](../../DESIGN.md) | parent | Product and fixed-target verification | Registers the executable depending on CADCore | Complete production closure is required |
| [Core Portability Proof](CorePortabilityProof/DESIGN.md) | child | Literal public value/codec assertions | Owns the finite actual behavior proof | SDK/backend failures cannot produce success |

## Architecture

```text
ProbeEntry -> CorePortabilityProof -> actual complete CADCore
```

## Contracts and Invariants

The same entry invokes the same common producer path on all three targets.
Only the genuinely absent Embedded codec branch differs. The unavailable
marker records absence, not encoded output. Every thrown error propagates.

## Runtime Flows

Common assertions run, the entry awaits the joined cancellation proof, then
runs the available codec proof and prints the terminal completion marker.

## State, Ownership, and Lifecycle

The entry has no stored state, streams, callbacks or unmanaged resources.
Its child owns and joins its task before returning.

## Failure, Concurrency, and Constraints

Runtime uses an outer 120-second deadline; root assigns a bounded build lane.
No failure is caught by the entry or replaced with a success marker.

## Verification and Change Impact

Build/link this registered product with fixed Swift 6.4.0 and both matching
WASM SDKs; execute each target. The child owns behavioral assertions and proof
receipts bind the complete source, dependency, PIF, product and runtime.
