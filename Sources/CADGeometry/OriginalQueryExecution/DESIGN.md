# Original Query Execution

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md#u1-direct-execution-ownership), without children.
Owns the direct public execution and cumulative caller accounting for original
queries. Source formulas, parameter coverage and exact arithmetic remain with
their existing owners.

## Responsibilities and Boundaries

`OriginalQueryBudget` owns cumulative work and admitted allocation bytes, plus
optional cumulative cell and source-record ceilings required by independent
source/decoder roots. Its immutable accounting policy preserves each root's
cell work debit and allocation-secondary debit: none, UInt32 words as work and
records, or bytes as work. Explicit source/text storage uses the same byte total
without acquiring numeric allocation-secondary charges.
`OriginalQueryExecution` directly implements scalar admission and owns one
exclusive query's local limits, visited cells and proof scopes. It never embeds
a route allowance or creates a child work/storage budget. Ordinary entries
create their budget once; admitted entries receive the actual execution.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md#u1-direct-execution-ownership) | parent | Direct execution ownership | Defines migration and public lifetime | Compatibility wrappers do not complete migration |
| [ExactScalar](../RationalBivariateAlgebra/ExactScalar/DESIGN.md#direct-local-proof-scopes) | depends on | Direct admission and local proof scopes | Arithmetic receives the original execution | Scope storage never crosses concurrent queries |
| [Numeric Work Admission](../../CADCore/NumericWorkAdmission/DESIGN.md) | depends on | Generic work, typed-storage and cancellation requirements | Existing Core Bezier producers consume this execution directly | No adapter, child budget or additional depth axis |
| [CS](../CurveSurfaceQueryAdmission/DESIGN.md) | used by | Original curve/surface query | Direct public invocation | Geometric depth is not work units |
| [SSI](../SurfaceSurfaceQueryAdmission/DESIGN.md) | used by | Original surface pair query | Prepared and ordinary invocation | Prepared queries preserve the cumulative owner |

## Architecture

```text
Caller / ordinary entry
    -> OriginalQueryBudget (shared cumulative state protected by Mutex)
        -> OriginalQueryExecution (exclusive policy, cell visits, proof scopes)
            -> source / DI / arithmetic / refinement / publication
```

## Contracts and Invariants

Work is an explicit nonnegative unit count. Admitted storage is cumulative bytes
and never refunded. Checked arithmetic and the whole debit precede materialization
or numeric work. Actual allocation bytes debit the byte total exactly once. The UInt32-word
secondary policy independently debits ceil(bytes/4) work and records; it never
rounds the byte total again. Allocation owners that materialize an eight-byte
word capacity for a five-byte payload explicitly request eight bytes. Source
text/authoring retains its distinct exact byte request. Cell visits and source, transport, geometric, value and coefficient depths
retain distinct policy meanings. Forwarding does not repeat an operation's debit.

`OriginalQueryExecution` also conforms to Core's `NumericWorkAdmission` through
its existing `checkpoint`, `consumeWork` and `retainStorage(count:stride:)`
methods. The conformance adds no state or billing layer. Core numerical work
uses the same cumulative budget, active contribution scopes and original failure
causes as its expression or geometry caller. Expression recursion remains the
Modeling owner's value-depth decision; finite numerical iterations do not acquire
source, coefficient or geometric depth.

All concurrent executions may share the budget owner, but each owns independent
local counters and `ExactScalarProofScopes`. Counter mutations and ceiling checks
are atomic under the same Mutex on all targets. External callbacks and numeric
operations run outside the lock. External callback observations remain opaque;
internal counters do not claim to measure an external ledger.

Lexical allocation scopes select secondary billing on the same execution and
same parent budget. Their work, record and byte contribution ceilings observe
actual debits and create no credits or child totals. A scope does not mutate the
shared budget's default policy. Source-owned text bytes remain exempt from
numeric secondary billing. Close restores the preceding policy without
allocation, billing, callbacks or cancellation checks, including throw cleanup.

Conversion scopes retain attribution counters for the requirement's work,
scalar slots and certification boxes. The scope ceiling observes this execution's
operations; it does not supply spendable work or refund the shared budget.
Nested scopes observe each operation once at each owning boundary. Close performs
no callback, allocation, charge or cancellation check.

Preparation observation scopes combine the existing local scalar proof scope
with local source/transport/geometric event maxima. Each begins at zero, observes
only actual operations, and closes without callbacks or allocation. Immutable
preparation receipts consume these observations rather than configured ceilings
or unrelated cumulative maxima. Scope tokens are bound to the exclusive issuer
and stack order. Throw cleanup preserves the original failure.

Ordinary CS policy distinguishes the general chart/span ceiling from the Native
point-product span ceiling; public result count remains a separate limit. The
optional Native span ceiling falls back to the general span ceiling for admitted
callers, preserving the original explicit caller policy.

## Runtime Flows

Every entry checks cancellation. Work/storage debits check cancellation before
and after the callback. Long numeric loops keep their own checkpoints after bulk
admission. Publication checks cancellation after its final callback. Supplied
caller checkpoint policy is observed without introducing a private timeout.

## State, Ownership, and Lifecycle

The immutable budget reference retains its limits and callbacks; only its Mutex
state is mutable. A prepared session retains this owner and immutable source
receipts, then creates an exclusive execution for each query. It does not share a
scope stack. Explicit independent readers create a different budget and readmit
immutable evidence. Query-local preparation identities avoid repeating the same
retained allocation/readmission debit within one execution. The source receipt
owner still validates source, field, branch, guards, scope and tolerance; the
accounting identity is not an evidence issuer. Actual receipt-readmission work
is charged rather than replaying historical decomposition cost. A closed proof scope performs no allocation or callback and
cannot mask the original operation failure.

## Failure, Concurrency, and Constraints

Invalid counts and overflow fail before counter mutation or callback. Budget
exhaustion retains every prior successful debit. External rejection preserves its
original cause. Cancellation remains cancellation at publication. Geometry owns
immutable query failure context; lower scalar types gain no Core dependency.

## Verification and Change Impact

Behavioral tests must cover N/N-1 work/bytes, overflow before debit, independent
depth axes, cell ceilings, nested proof scopes, parallel budget sharing, callback
reentry outside the Mutex, prepared cumulative reuse, independent readers and
entry/middle/final cancellation. CS/SSI and conversion/embedding verification
must run actual direct callers on Native, ASAN, normal WASM and Embedded. Searches
for removed allowances are necessary deletion checks, not runtime proof.

### Independent Geometry Entry

`independentGeometry(context:)` creates one explicitly independent ordinary
geometry execution. It retains cumulative work, allocation bytes, cell and record
observations and cancellation, with no additional caller ceilings. Its local
policy envelope uses `Int.max`; source-family and arithmetic representation
limits remain at their actual algorithm owners. Compositional and admitted
operations receive the existing execution and do not call this factory.

### Allocation Scope Setup

A newly opened allocation scope includes its own stack/issuer setup contribution
in its local ceilings. Checked setup counts are determined before any debit or
allocation and billed under the previously effective allocation policy. The
new frame starts with those admitted work/record/byte counts; it never derives
usage from a shared budget snapshot. Reusing already retained scope capacity
requires no new setup debit. Conversion scope setup likewise contributes its
actual secondary allocation work to its new work ceiling. Closing remains
allocation- and callback-free.

### Certification Box Events

`visitCertificationCell(depth:)` records one actual certification box under all
active conversion scope box ceilings, geometric depth policy and the same shared
cell accounting policy. Its accepted box event is recorded before an external
callback can reject the debit. It does not introduce converter-specific scalar
or work costs. `visitConversionCell(depth:)` adds the existing converter's 512
scalar slots and 4096 work units to that actual box event. The read-only current
conversion scope snapshot reports its own attributed work, scalar slots and
certification boxes; it does not infer counts from shared budget snapshots.

### Low Proof Scope Work Attribution

Every actual work debit checks and records the low proof scope work contributions
through `ExactScalarProofScopes.checkWork` / `recordWork`, including secondary
allocation work. This observes the same debit as conversion and allocation
scopes; it adds no second cumulative charge. A newly opened low proof scope
starts after its own stack storage admission, as specified by the low proof
scope contract. Its setup remains charged to the cumulative owner and any
already active enclosing scopes.

The direct expansion path uses the existing fixed arithmetic primitives and is
checked against the separate pure primitive path in
[direct expansion tests](../../../Tests/CADGeometryTests/FloatingPointExpansionDirectTests.swift).
The common owner behavioral fixture is
[execution acceptance](../../../Tests/OriginalPublicAcceptanceVerification/OriginalQueryExecutionAcceptance.swift).

A low proof scope work rejection exposes its actual used, limit and requested
counts as value metadata. The common execution captures them immediately with
its current immutable query context and the original scalar failure as cause;
it does not reconstruct them after scope unwind or substitute whole-budget
usage. Low generic admissions outside this public boundary retain their existing
scalar failure classification.

`retainStorage(count:stride:)` validates nonnegative dimensions and checked
multiplication before applying the same allocation-byte operation. It carries
no extra work or depth meaning and does not create an intermediate reservation
owner.

A scoped helper unwinds its own frame and any unclosed descendant frames when
its body throws, preserving the original error and the preceding effective
allocation policy. Invalid explicit close tokens still fail. Unwind performs
no debit, allocation, callback or cancellation check.

### Source Operation Debits

`chargeSource(records:work:storageBytes:context:)` admits one source-owned
operation atomically against all three cumulative counters. It bypasses numeric
allocation secondary policy, so explicitly authored source text/storage does not
acquire unrelated scalar records or work. Its execution counterpart also checks
and records the same contributions on exclusive scopes before callbacks. It
preserves all-or-nothing counter rejection for shared format root accounting.

The `uint32WordWork` allocation policy adds `ceil(bytes/4)` to the same work
counter without adding source records. Loft's historical combined quota uses
this policy with its original combined work limit and byte envelope; work and
allocation words are never split into independently spendable totals.

### Geometric Depth Offset

`withGeometricDepthOffset(_:body:)` composes the actual base-depth addition
previously owned by nested geometric callbacks. The exclusive execution stores
one checked cumulative offset. Geometric depth admission maps `offset + local`
before checking the caller ceiling or recording actual preparation depth;
explicit lower remaining-depth ceilings remain unchanged. Nested offsets add in
causal order. `defer` restores the previous value on success, throw or cancellation
without allocation, callbacks or new accounting owners. This mapping does not
apply to scalar, coefficient, source or transport depth.

### Persistent Contribution Authority

`OriginalQueryBudget` also owns persistent lower contribution records in its
sole Mutex. Immutable `OriginalQueryContributionHandle` values retain this
budget identity, a non-reused record ID, allocation accounting policy and an
optional selected execution policy. A prepared source or Encoder may retain the
handle across operations. This records the same actual operation under a lower
ceiling; it creates no second spendable budget, credit, refund or counter owner.

An execution attaches handles lexically. Every debit prechecks the global
counters and every distinct active handle before committing any counter. Repeated
attachment of one handle never duplicates its contribution. Detached parent work
does not affect a lower record. Selection stacks remain exclusive to executions;
only persistent counts share the budget Mutex. Foreign-budget handles fail.
Closing or failure cleanup restores the prior selection without resetting counts.

The base `limits` remain immutable. `effectiveLimits` intersects the base policy
with attached selected policies, and depth admission checks that effective
policy. The accounting policy of the innermost handle applies unless an explicit
allocation scope selects another policy. A raw budget operation may name one
handle without capturing an execution. External callbacks remain outside the
Mutex. Group record buffer growth is checked and charged to the original budget
before allocation, before the newly issued handle exists.

`retainActiveContributionHandles()` explicitly admits and copies only the tiny
ordered policy handle list when a retained owner must capture multiple active selections.
It does not copy source/geometry arrays. A single active handle can be retained
as an immutable value. Reattachment debits the same persistent counts.

Allocation scopes may also select immutable `cellVisitWorkUnits` and
`cellVisitRecords` overrides. An unspecified field inherits the nearest active
specified scope, then the budget's default. Every actual cell event still uses
one cumulative debit and the same persistent contribution records. This retains
the decoder's zero-cost visits while allowing source validation on that same
owner to charge its original one work unit and one record per visit.

An exclusive decoder or later query may initialize execution with one retained
contribution handle. The handle must belong to that same budget. Initial query
selection storage is admitted before activation; proof stacks are always new
and unshared. `availableWork` is an observed bound from the current global and
selected contribution headroom, not a spendable reservation or credit; a later
atomic debit remains authoritative under concurrency.

Root and composed group creation use the same boundary: metadata is charged to
the global budget and already active parent groups; the new child's counts
start at zero. Shared group-buffer capacity is not attributed arbitrarily to a
new child. Composed creation validates exclusive local scopes against the exact
metadata growth computed under the budget Mutex before committing counters.
This internal arithmetic-only preflight performs no external callback or I/O;
accepted local event recording and all caller callbacks run after unlocking.

A captured selection preserves attachment order, including repeated handles, so
reattachment retains the same innermost allocation policy and outer rejection
priority. The cumulative debit still deduplicates IDs. `activeContributionHandle`
is only the innermost handle; it does not capture distinct ancestors. Owners may
use it when `activeContributionCount == 1`; otherwise they retain the full charged
selection. Multiple-handle execution initialization and raw source debits accept
that same immutable selection.

A contribution's `storageByteQuantum` defaults to one. A legacy UInt32-word
quota selects four: each actual allocation or serialization operation attributes
`roundUp(actualBytes, 4)` to that group's byte ceiling while the global byte
counter receives actual bytes exactly once. Two one-byte operations therefore
use eight attributed bytes and two global bytes. Checked rounding and addition
precede every counter mutation. Repeated attachment rounds and attributes once.
This policy changes no numeric work or record debit and issues no extra storage.

Reattaching only already active authorities with the same innermost authority
keeps the selection unchanged and does not allocate another selection frame.
Identity validation and cancellation checkpoints still apply. A changed innermost
authority or any new authority uses the ordinary charged lexical attachment.


### Ambient Billing and Combined Native Quotas

`effectiveAllocationPolicy` exposes the current immutable selection: the nearest
allocation scope, then the innermost contribution, then the root budget default.
A local work/storage ceiling retains that policy explicitly rather than replacing
ambient allocation billing.

An allocation scope may select `maxCombinedUnits`. Its actual contribution is
explicit work plus `ceil(numericAllocationBytes / 4)` per real allocation plus
cell visits. Secondary allocation work and cell-generated work remain actual
global/proof/conversion debits but do not enter this combined quota again.
Source text bytes do not enter the numeric allocation term. Each operation
checks the aggregate contribution and all active selected ceilings before its
single cumulative debit; accepted contributions are recorded before external
callbacks, including when a callback subsequently fails. Compound scalar/work/
storage charging uses the same atomic operation. No second budget, callback
adapter, credit or refund is created.

Opening metadata belongs to existing parent scopes and the cumulative owner.
The new combined counter starts at zero, matching the native quota's historical
constructor boundary. `allocationScopeCombinedUnits` reports the current
selected scope's actual accepted contribution. `allocationScopeSnapshot(token)`
and `closeAllocationScope(token)` return immutable work/byte/record/combined
observations after validating the same issuer and topmost token; both are free
of billing, callbacks and allocation. A source may return that value
with immutable proof metadata before closing, then subtract it from its selected
cap for a later narrow exact phase. Intervening unrelated work stays outside the
quota. Cleanup closes without allocation, callback or counter refund.

Focused verification distinguishes exact N from N−1 for mixed explicit work,
allocations and cell visits, preserves ambient word/byte billing, checks atomic
rejection and post-callback recording, and verifies nested scope attribution.


### Actual Source-Edge Depth Composition

`withSourceDepthOffset(offset, body:)` composes a known retained-child source edge
on the original execution. Checked nonnegative offset addition and free lexical
restoration match geometric depth composition; no caller limit, budget or source
proof is copied. `admitSourceDepth(local)` checks `offset + local` against the
independent effective source ceiling and records the attained mapped event.

Every preparation frame retains its actual starting source offset. Its source
receipt records each mapped event relative to that origin. A child prepared
beneath a parent's source edge therefore keeps child-root-relative depth; later
readmission adds the new caller's actual offset exactly once. The cumulative
execution observation remains root-relative. An event below a live frame's
origin is invalid evidence rather than a negative or clamped receipt. Offset
arithmetic overflow and cancellation/failure preserve prior lexical state.

Verification uses nested parent/child scopes, independent readmission at N and
N−1 source ceilings, checked offset overflow and throw cleanup. Configured
remaining source capacity is never substituted for attained source depth.

### Source Text Byte Category

The original IR source contract limits retained UTF-8 wire text independently
of numeric allocation metadata. `sourceTextByteLimit` on the shared budget and
lexical allocation scopes bounds only explicit `chargeSourceText` events.
Those events atomically admit explicit records/work, actual allocation bytes,
and text-category bytes through the same cumulative owner. Selected persistent
contributions still receive the same actual allocation event once, with their
existing byte quantum. Numeric secondary allocation billing does not apply to
wire text. Numeric allocations and scope metadata never debit the text category.

`localSourceTextBytes` is the exclusive execution's accepted contribution;
shared snapshots retain the cumulative category. Both are updated before any
external callback, so callback failure does not refund admitted text. Negative,
overflow and N−1 rejection leave every counter unchanged. Scope setup is numeric
metadata and contributes zero text bytes. This category adds neither a child
budget nor a separate synchronization owner. Verification checks numeric metadata
under a zero text cap, mixed text/metadata at N and N−1, atomic multi-axis failure,
and accepted debit visibility after callback failure.

Persistent contribution handles carry an optional source-text byte ceiling
independently of their work and numeric allocation policies. Each actual text
debit checks the global byte ceiling, active lexical text ceiling and all distinct
active contribution ceilings atomically. Text counts once per owner and remains
charged after a post-debit callback fails. Numeric metadata allocation consumes
global bytes without consuming the source-text category. Reattaching a retained
handle observes its cumulative count; it cannot reset the source-text ceiling.
