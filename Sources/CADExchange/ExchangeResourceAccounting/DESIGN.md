# Exchange Resource Accounting

## Purpose and Scope
Owns shared cumulative counters and the original deadline for conversion and drawing invocations. Parent: [CADExchange](../DESIGN.md). No children.

## Responsibilities and Boundaries
The existing value accountant defines ceilings and errors. This component owns one synchronized instance and immutable references to it. It does not own fitting, geometry, glyph preparation or publication.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADExchange](../DESIGN.md) | parent | ExchangeResourceLimits and processing deadline | Caller admission authority | No counter reset during an invocation |
| [Geometry Conversion Exchange](../GeometryConversionExchange/DESIGN.md) | used by | one retained admission | Preparation and certification share ownership | Callbacks retain the counter owner, not the admission container |
| [B-rep Drawing Exchange](../BRepDrawingExchange/DESIGN.md) | used by | cumulative drawing usage | Escaping preparation callbacks share counters | Snapshot values do not replace live counters |

## Architecture
```text
Invocation -> immutable shared owner -> Mutex<ValueAccountant>
           -> callbacks -------------> same owner
```

## Contracts and Invariants
Copies retain the same counters, ceilings and original deadline on all targets. Each counter update is serialized; overflow and exhausted ceilings fail without accepting the update. Snapshots atomically borrow current values for remaining-allowance computation, never restore counters. External callbacks, fitting, I/O and source algorithms run outside the lock. A conversion ledger issues one canonical execution and passes it through preparation and certification on the original shared budget.

## State, Ownership, and Lifecycle
The owner retains one Mutex<ExchangeResourceAccountant>. Drawing usage and callbacks retain that owner. The conversion ledger retains both the owner and its admission; admission callbacks retain only the owner, preventing a retain cycle. The owner is released after all users and callbacks release it.

## Failure, Concurrency, and Constraints
Short in-memory accounting mutations use Synchronization.Mutex on Native, WASM and Embedded. Each operation checks cancellation and its deadline before locking; the existing value accountant may repeat those bounded nonblocking checks during its short mutation. No external callback runs under the lock. Negative counts, overflow, deadline and caller-ceiling failures propagate unchanged.

## Verification and Change Impact
After the source phase, verify shared usage copies and concurrent callbacks consume one cumulative allowance, exhausted updates remain failures, admission copies preserve invocation identity, cancellation/deadline propagate, and callbacks release their owner without a cycle. Recheck conversion and drawing publication at these boundaries. Source authoring is not runtime evidence.


## Canonical Admission Integration

The exchange invocation owns one `OriginalQueryBudget`. Source conversion, exact scalar operations and retained drawing/silhouette readers borrow `OriginalQueryExecution` on that owner. Format counters and deadlines retain their existing independent limits; a callback wrapper or a copied mutable allowance cannot implement canonical proof/depth admission. Native serialization that borrows this execution retains actual active contributions and its independent wire-byte contribution. This is the caller closure of [Geometry execution](../../CADGeometry/OriginalQueryExecution/DESIGN.md), not a change to payload semantics.

Verification must compile the extracted package and check original format behavior plus same-owner/cap refusal on the affected entries. Existing larger-worktree receipts do not prove this extracted delivery snapshot.
