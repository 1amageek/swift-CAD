# Original Sweep Invocation

## Purpose and Scope

This child of [CADModeling](../DESIGN.md) carries invocation-local original
section and path authority into composed Sweep evaluation. Persistent CADIR
references and the public evaluator interface remain unchanged.

## Responsibilities and Boundaries

Owns retained directed path spans, original section carriers, closure selection
and their shared source allowance. Candidate staging curves provide sampling
and ordering proposals; they cannot replace retained source laws.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | feature evaluation and publication | Hosts public Sweep composition. | Final semantic topology remains the evaluator's responsibility. |
| [SectionResolution](../SectionResolution/DESIGN.md) | depends on | original directed spans and final candidate receipt | Retains native and nonlinear section/path charts. | A facade or composed candidate is not source authority. |
| [CertifiedCurvedSweep](../CertifiedCurvedSweep/DESIGN.md) | depends on | cumulative original-law allowance | Shares preparation and all correction attempts. | Source and intrinsic algebra depth remain distinct. |
| [Pipe](../Pipe/DESIGN.md) | used by | original composed Sweep call | Forwards Pipe's retained path into generated Sweep operations. | Fraction cuts require their original inverse-length boundary law. |

## Architecture

```text
Pipe original resolution -> immutable invocation carrier
candidate staging -------> sampling proposals
carrier + proposals -----> Sweep original source construction -> publication
```

## Contracts and Invariants

A carrier retains every final candidate's original chart and correspondence.
Its path traversal and closure are selected before candidate staging. Source
budget identity survives each nested Sweep and each hollow-ring operation.
A provided original section supersedes only internal resolution, preserving
its original curve, directed trim and loop identities. Carrier cuts and
extensions must retain their original boundary-law receipts; numerical inverse
midpoints and quadrature alone cannot provide them.

## State, Ownership, and Lifecycle

The carrier is immutable and Sendable. It borrows no mutable staging context.
Its source allowance uses the existing common Mutex owner for all targets.
Referenced original sources and receipts survive the nested operation.

## Failure, Concurrency, and Constraints

Empty or mismatched carriers fail explicitly. Partial distance fraction applied
to a retained carrier requires its own original boundary producer. The same
existing work, physical storage, source-depth and subdivision limits apply.

## Verification and Change Impact

Behavior belongs to `Tests/SwiftCADTests/PipeTests.swift`,
`PipeCustomProfileTests.swift` and `ClosedPathPipeTests.swift`: original analytic
paths survive nested staging, nonlinear chart cuts preserve source authority,
closed twist retains correspondence, and nested rings share exhausted budgets.
Source integration is implemented before behavioral verification.
