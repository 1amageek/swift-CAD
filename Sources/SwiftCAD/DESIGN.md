# SwiftCAD

## Purpose and Scope

SwiftPM facade module in [swift-CAD](../../DESIGN.md). It composes source authoring,
validated document edits, kernel evaluation, queries and exchange for callers.
The [Document Transaction](DocumentTransaction/DESIGN.md) component owns mutable
transaction sessions. Existing facade entry points retain their source owners;
this task does not relocate them.

## Responsibilities and Boundaries

`DocumentBuilder` constructs source through `DocumentEditing`. `DocumentEditor`
validates and returns owned edited source values. `CADPipeline` composes the
kernel's evaluation/query and exchange contracts. Transactions own publication
and history, while exact geometry remains owned by the kernel and topology.
Application project publication and UI history are application responsibilities.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [swift-CAD](../../DESIGN.md) | parent | Kernel/application boundary | Public facade composition | No application project publication |
| [Document Transaction](DocumentTransaction/DESIGN.md) | child | DocumentTransacting | Atomic document publication and history | Exact evaluation must succeed before commit |
| [CADIR](../CADIR/DESIGN.md) | depends on | CADDocument and CADCommand | Source ownership and validation | Complete source values remain authoritative |
| [CADKernel](../CADKernel/DESIGN.md) | depends on | ExactDocumentEvaluating and kernel queries | Exact evaluated snapshots | Deferred evaluation is distinct from materialized artifacts |
| [CADCapabilities](../CADCapabilities/DESIGN.md) | depends on | Executable command admission | Shared public capability catalog | Admission does not prove geometry |
| [CADExchange](../CADExchange/DESIGN.md) | depends on | NativePackageStore and OfficialFormatExchange | Source and exchange publication | Exchange owns format and resource refusal |

## Architecture

```mermaid
flowchart LR
  Builder[DocumentBuilder] --> Editor[DocumentEditing]
  Transaction[DocumentTransacting] --> Editor
  Editor --> Source[CADIR validated source]
  Source --> Kernel[ExactDocumentEvaluating]
  Kernel --> Snapshot[Owned evaluated snapshot]
  Snapshot --> Transaction
  Pipeline[CADPipeline] --> Kernel
  Pipeline --> Exchange[CADExchange]
```

## Contracts and Invariants

- Editing returns a complete validated source copy; failure leaves caller-owned
  input unchanged. Command legality belongs to the existing editor contract.
- Exact evaluation and derived-artifact generation use kernel-owned contracts.
  The facade never substitutes sampled geometry for exact evaluation.
- Transaction publication, isolation, failure atomicity, history capacity and
  snapshot restoration are owned exclusively by the child design.
- Exported geometry, topology, IR, modeling, kernel and exchange types retain
  their defining modules' contracts.

## Verification and Change Impact

`Tests/SwiftCADTests/CADCommandPipelineTests.swift` owns the command/evaluation
composition path. `Tests/SwiftCADTests/DocumentTransactionTests.swift` owns the
transaction path, including actual geometry failure and complete undo/redo
restoration. Changes to source validation, editor behavior or exact evaluation
require rerunning the affected composition fixtures and transaction guarantees.
