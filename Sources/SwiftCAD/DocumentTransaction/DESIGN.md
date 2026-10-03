# Document Transaction

## Purpose and Scope

Child of [SwiftCAD](../DESIGN.md), with no children. Owns PARA.A2: atomic
publication of multiple CAD commands, explicit rollback, bounded undo/redo and
complete restoration of source dependencies, attributes, references and evaluated
identities. It does not persist history, generate geometry, change command
legality or manage derived artifacts.

## Responsibilities and Boundaries

`DocumentTransacting` declares every session operation as a protocol requirement.
`DocumentTransactionSession` is its actor implementation. `DocumentEditing` owns
each command's legal source transition. `ExactDocumentEvaluating` owns actual
geometry evaluation. The session publishes only complete evaluated snapshots,
using each evaluation's `document` as source authority. Draft preview is source
data and never claims successful geometry evaluation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SwiftCAD](../DESIGN.md) | parent | DocumentEditing public facade | Hosts the transaction session | Existing Editor and Pipeline retain their owners |
| [CADIR](../../CADIR/DESIGN.md) | depends on | CADCommand, CADDocument validation and value ownership | Owns command legality and source graph | Commands must remain legal in their supplied order |
| [DocumentFoundation](../../CADIR/DocumentFoundation/DESIGN.md) | depends on | Attribute ownership and persistent references | Full source snapshots preserve records and IDs | External symbolic references are preserved, not implicitly resolved |
| [CADKernel](../../CADKernel/DESIGN.md) | depends on | ExactDocumentEvaluating and EvaluatedDocument | Supplies exact evaluated geometry | Deferred output must not be passed to materialized-artifact validation |

## Architecture

```mermaid
flowchart LR
    Caller[DocumentTransacting caller] --> Actor[DocumentTransactionSession actor]
    Actor --> Draft[One owned source draft + opaque token]
    Draft --> Editor[Injected DocumentEditing]
    Editor --> Validate[Complete source validation]
    Validate --> Exact[Injected ExactDocumentEvaluating]
    Exact --> Publish[Atomic committed evaluated snapshot]
    Publish --> History[Bounded before/after evaluated records]
    History --> Restore[Undo / redo without reevaluation]
```

## Contracts and Invariants

- Initial source validation and exact evaluation must succeed before a session
  exists. Native exact evaluation rejects an empty geometry result according to
  its existing contract; the session does not invent an initial success value.
- `begin(expectedEpoch:)` admits one active draft. Its opaque UUID token belongs
  to this session, this draft and its committed base epoch. Foreign, rolled-back
  or committed tokens fail. A stale epoch cannot reopen an older state.
- `stage(_:in:)` applies a nonempty ordered command batch to a local source
  copy. Every editor result is source-validated and keeps the document ID. The
  batch replaces the draft only after every command and cancellation check
  succeeds. Failure preserves both the previous draft and committed history.
- `preview` returns only the owned source draft, base epoch and command count.
  `snapshot` returns the committed EvaluatedDocument and status. Draft changes
  never appear in a committed snapshot.
- `commit` requires staged commands, history capacity and an available next
  epoch. It validates the complete draft, evaluates exact geometry, verifies
  that the returned source equals the draft and that configuration tolerance
  equals the evaluator's captured tolerance, then checks cancellation. Only
  then does one actor turn clear redo, append history, replace committed state,
  advance epoch and close the draft.
- Editor, source-validation, evaluator and cancellation failures propagate
  unchanged. Failed commit preserves the active draft for correction or explicit
  rollback, and changes neither committed state nor history.
- Each history record owns complete before/after EvaluatedDocument values.
  Undo/redo restores those values without rebuilding geometry or generating new
  identities. Source metadata, dependency edges, revisions, attributes,
  references, resolved parameters, B-rep, subshapes, lineage and evaluator state
  are restored together.
- Undo/redo rejects an active draft and requires the current epoch. Successful
  commit, undo and redo advance the session epoch monotonically; undo cannot
  cause ABA. Begin, stage, preview and rollback do not change committed epoch.
- A successful new commit after undo intentionally discards the redo branch.
  Failure preserves it. No history record is silently pruned to create capacity.

## Runtime Flows

```text
initial source -> validate -> exact evaluate -> source/tolerance check -> session
begin(epoch) -> stage ordered batch -> preview source -> commit -> evaluated publish
stage or commit failure -> unchanged committed/history + retained prior draft
rollback(token) -> discard draft
undo(epoch) / redo(epoch) -> restore complete retained snapshot -> advance epoch
```

## State, Ownership, and Lifecycle

The actor owns committed state, an optional draft, session UUID, monotonically
increasing epoch and two history stacks. Inputs and snapshots are Sendable owned
values with native copy-on-write backing. The actor retains injected Sendable
editor and evaluator values. Their methods are synchronous; a transaction
operation contains no suspension point during validation, evaluation or
publication, so actor reentrancy cannot interleave a draft mutation with commit.
There are no tasks, streams, pointers, external storage or shutdown resources.

| State | Native / WASM / Embedded storage | Isolation | Read / mutation | Release |
|---|---|---|---|---|
| committed, draft, epoch, history | Identical actor-owned values | Actor | Protocol requirements on the same actor | Actor lifetime |
| injected services and limits | Immutable Sendable values | Actor-owned references | Synchronous service requirements | Actor lifetime |

## Failure, Concurrency, and Constraints

`DocumentTransactionError` owns transaction misuse, invalid limits, exhausted
capacity, incompatible editor/evaluator outputs and unavailable undo/redo.
Underlying command or geometry errors remain their original errors.
Cancellation is checked before each mutation, between staged commands and
before/after exact evaluation, before publication. A queued concurrent begin
observes the first active draft and fails rather than overwriting it.

Callers explicitly provide positive `maximumHistoryEntries` and
`maximumCommandsPerTransaction`; there are no guessed defaults. Undo and redo
combined retain at most the history limit. Capacity is checked before geometry
evaluation. Command-count arithmetic and epoch increment are checked before
state mutation. Source size, geometry allocation and evaluation work retain
their existing source/evaluator contracts. Caller-retained snapshots have
caller-owned lifetimes outside the session's history limit.

## Verification and Change Impact

[DocumentTransactionTests](../../../Tests/SwiftCADTests/DocumentTransactionTests.swift)
owns atomic ordered batch failure, rollback, actual primitive geometry rejection,
complete undo/redo snapshot and metadata/reference/dependency restoration,
generated identity preservation, redo-branch replacement, stale ABA/foreign
tokens, concurrent begin, explicit limits and cancellation after evaluation.
The root task owns native and WASM/Embedded compile/link/runtime and integration
evidence. Parent facade and capability publication must reflect the tested
transaction scope. Changes to command validation or exact-evaluation lifetime
require rechecking these admission and snapshot guarantees.
