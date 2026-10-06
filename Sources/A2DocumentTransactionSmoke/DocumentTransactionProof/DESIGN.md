# Document Transaction Proof

## Purpose and Scope

Child of the [A2 smoke module](../DESIGN.md), with no children. Owns an executable
behavioral proof of the public transaction contract, not an implementation of it.

## Responsibilities and Boundaries

The proof constructs actual source geometry, invokes the production editor and
exact evaluator, and calls every operation through `any DocumentTransacting`.
Decorators change source metadata or cancel only after invoking the actual
production service. They never fabricate geometry or substitute evaluated data.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [A2 smoke](../DESIGN.md) | parent | Async entry and failure exit | Runs the proof on each target | No target-specific assertions or success fallback |
| [DocumentTransaction](../../SwiftCAD/DocumentTransaction/DESIGN.md) | depends on | Actor publication and complete history snapshots | Supplies the public operations being proved | Preview source is not evaluated geometry |
| [CADKernel](../../CADKernel/DESIGN.md) | depends on | Actual exact DocumentEvaluator | Produces real B-rep and stable retained evaluation identities | Deferred snapshots deliberately omit materialized caches and meshes |
| [IndependentShapeSource](../../CADIR/IndependentShapeSource/DESIGN.md) | depends on | Original geometry store, item/selection identity and source validation | Supplies a nonempty independent line source in the complete document fixture | Source preservation does not claim independent-shape modeling or exchange completion |

## Architecture

```text
original sketch/parameter/extrude and reference
  -> public session -> ordered commands -> actual exact evaluation
  -> committed snapshot -> undo/redo -> complete stored-value equality
failure/cancel -> original committed evaluation and prior draft preserved
```

## Contracts and Invariants

- Whole CADDocument equality covers schema, units, source graph, parameters,
  attributes, references, metadata, assemblies, product records and any nullable
  independent-shape source. Assertions also prove that parameters, dependency
  edges, references, metadata and actual geometry changed before restoration.
- The fixture validates a nonempty independent original line and its trimmed
  item/root with the production source validator. Staging and publication retain
  that complete source; undo/redo equality includes its original laws and IDs.
- B-rep, subshape IDs, lineage, resolved parameters, curves, configuration,
  assembly artifacts and metrics must equal their retained before/after values.
  Exact-evaluation meshes and both cache collections must remain empty.
- Ordered partial failure must preserve the prior draft and command count.
  Rollback must consume the token without changing committed state or history.
- Source-valid geometry below modeling tolerance must fail actual exact commit
  with the existing typed invalid-input reason and residual.
- Epochs remain monotonic across undo. Foreign and consumed tokens, stale epochs,
  concurrent begin, explicit command/history limits and redo branches have typed
  assertions. No unexpected error is accepted as an intended refusal.
- Cancellation before every mutating operation and after actual evaluation must
  retain complete committed state and active draft. Current-task checks execute
  in the same task and actor path on all targets.

## Runtime Flows

```text
history restoration -> ordered rollback -> exact refusal/correction
  -> stale/foreign/concurrent admission -> capacity/redo branch
  -> pre-cancelled operations and post-evaluation cancellation -> final marker
```

## State, Ownership, and Lifecycle

Each run owns local fixtures, sessions and snapshots. Tasks are awaited and
task groups join before return. There are no streams, global mutable state,
file resources, pointers or shutdown obligations. Decorators are immutable
Sendable values; all transaction state belongs to the production actor.

## Failure, Concurrency, and Constraints

Proof failures use a typed error with a static reason. Production errors retain
their original type. Cancellation uses actual Task cancellation. Concurrent
admission returns owned Sendable outcomes and checks exactly one acceptance.
Caller history/command limits are explicit. The external runner supplies a
bounded timeout; source/evaluation resource limits remain their production values.

## Verification and Change Impact

The same executable must compile, link and run against the complete production
graph on each required target. Native transaction tests independently verify
the owner contract. Full Embedded source-envelope availability and new source
fields are lower prerequisites, not inferred from a standalone checker probe.
Changes to source fields or exact evaluator output require preserving the whole
equality assertions and adding an actual nonempty field fixture when its source
producer is available.
