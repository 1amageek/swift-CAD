# Original Spatial Point

## Purpose and Scope
Retain one authored binary XYZ point and its complete original spatial operation word. Parent: [Geometry](../DESIGN.md). No children.

## Responsibilities and Boundaries
The point and word factors are original position authority. A Vertex numerical point is a localization candidate when this source exists. This component owns D0 evaluation and composition, while topology owns Vertex identity/incidence and Exchange owns foreign unit/frame interpretation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | Original point composition | Neutral source carrier | No topology dependency |
| [Original affine word](../OriginalAffineOperationWord/DESIGN.md) | depends on | Prepared exact position enclosure and appending | Exact rational/field action before outward conversion | Caller algebra remains independent |

## Architecture
```text
raw authored point + original flat word
    -> same caller exact word preparation
        -> exact singleton source position action
            -> outward XYZ box -> admitted numeric localization
```

## Contracts and Invariants
The bounded constructor and later queries use explicit source, subdivision and independent algebra policies with the same ExactScalarAdmission work/storage admission. Exact XYZ singleton intervals enter the existing prepared word position action; no rounded matrix-point product becomes source. Later lower algebra admission reconstructs the same raw word law under the selected cap. Cache, tolerance and caps are excluded from source equality and portable identity. Appending preserves the point and delegates ordered factor composition to the word owner.

## State, Ownership, and Lifecycle
The immutable source retains the authored point and paid exact word preparation. All field buffers belong to the existing word owner and are charged before allocation. No new mutable budget or independent allowance is created.

## Failure, Concurrency, and Constraints
Nonfinite source coordinates, invalid caller capabilities, singular words and exhausted algebra/work/storage fail explicitly. Numeric localization succeeds only when the original XYZ error box proves the requested physical distance. Source and geometric caps are validated independently, without using either as an algebra ceiling.

## Verification and Change Impact
Behavioral verification must cover exact unit scaling, cancellation before outward conversion, normalized-frame words, append order, stricter later algebra caps, invalid/singular inputs and same-ledger exhaustion. Vertex source validation, foreign point ingress/egress, BRep incidence and mesh/measurement consumers are affected. Source-authored types alone are not completion evidence.

## Direct Original Query Calling

The [module direct execution contract](../DESIGN.md#u1-direct-execution-ownership)
governs caller composition. Scalar source construction consumes the original
`inout A: ExactScalarAdmission & ~Copyable`, with explicit work units, checked
allocation bytes, independent value/coefficient scope observations and unchanged
source laws. Geometry query composition uses the same original execution;
ordinary conveniences create one cumulative owner only at their real entry.
Callback-to-admission reconstruction, copied budget writeback and cancellation-
only legacy allowances are removed. Actual structural and parameter guards,
original source ownership and scoped identities remain required.

### Direct Source Execution

Pure original word/coefficient operations receive the original generic
`inout A: ExactScalarAdmission & ~Copyable`. General geometry construction,
validation and retained queries receive the original `inout OriginalQueryExecution`.
Actual lower calculations keep that same object; no legacy, validation or borrowed
admission is reconstructed from resource callbacks. Configured capabilities
remain independent of attained proof metadata. Actual payload bytes are checked
and admitted before materialization; failures and cancellation publish no partial
source or complete query. Ordinary numerical entry points may create one explicit
independent execution and delegate to the direct operation. Source-only generic
branches consume their genuine Native/word law without acquiring a general
geometry capability.

```text
Original caller execution -> source validation/query -> original lower operation
generic caller A -> pure Native/word coefficient law -> retained source proof
```

Owning behavioral success, guard rejection, independent budgets/depth, terminal
cancellation and retained lifetime must execute through the actual direct path.
Syntax or signature checks alone are not completion evidence.
