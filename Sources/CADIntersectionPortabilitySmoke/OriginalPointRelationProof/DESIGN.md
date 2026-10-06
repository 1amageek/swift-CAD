# Original Point Relation Proof

## Purpose and Scope

This component owns bounded public behavioral verification of isolated-point
intersection and complete empty coverage. Parent: [Intersection Portability
Smoke](../DESIGN.md). It has no children.

## Responsibilities and Boundaries

Literal original B-spline fixtures exercise normal and caller-admitted rich and
discrete curve/surface and surface/surface requirements through existentials.
The public native receipt must retain exact tuple ownership; arrays alone are
insufficient. Geometry algorithms remain production-owned.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Intersection Portability Smoke](../DESIGN.md) | parent | Fixed-target entry and bounded recipe | Joins cancellation proof | A failed target is not completion |
| [Native CS Points](../../CADGeometry/CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | depends on | Original tuple publication | Supplies curve/surface receipts | Positive dimension cannot publish an isolated subset |
| [Native SSI Points](../../CADGeometry/NativeSurfaceSurfacePointRelations/DESIGN.md) | depends on | Original tuple publication | Supplies surface/surface receipts | Empty success requires full coverage |
| [Original Plane Derivatives](../../CADGeometry/OriginalCoons/PlaneDerivatives/DESIGN.md) | depends on | Immutable generated source and native decoding allowance | Exercises common indirect storage | Copying must preserve source semantics and lifetime |

## Architecture

```text
literal sources -> public existential query -> retained receipt + materialization
local Mutex ledger -> public admission -> same query or explicit typed failure
joined cancelled Task -> actual query -> CancellationError
```

## Contracts and Invariants

Success compares independent literal coordinates and exact rational source
parameters. Normal/admitted/discrete results must agree. Empty native receipts
must be present and cover the finite original domains. Positive-dimensional
fixtures must fail atomically through the discrete publication requirement.
Rich relation publication owns its separate contract and may support such
coverage without changing the discrete requirement. Independent zero work and zero storage allowances
must fail before publication. Cancellation inside admitted work must propagate.
An original plane-derivative value must survive release of its original local
value, retain equality and hash identity, and evaluate its literal center.
Its retained RootSpan must also share directed source identity through double
reversal and return the literal reversed position/derivative on the same bounded
query allowance after the original local source has been released.
Native codec reconstruction must retain that same source and query result;
one-word-short cumulative decoder storage must fail explicitly.

## State, Ownership, and Lifecycle

Fixtures and results are local immutable values. A Sendable ledger owns the
same Mutex state on all targets, debits checked cumulative allowances, and
invokes no external callback while locked. The async entry owns and joins the
cancelled task. No target-specific raw state, unchecked Sendable or detached
resource is used.

| Target | Storage and isolation | Read | Mutation | Release |
|---|---|---|---|---|
| Native | `Mutex<State>` | `counts` with the same lock | checked `debit` with the same lock | last Sendable ledger owner |
| Normal WASM | `Mutex<State>` | same entry | same entry | same owner lifetime |
| Embedded WASM | `Mutex<State>` | same entry | same entry | same owner lifetime |

The source declaration and Sendable conformance are unconditional. WASI Preview
1 execution does not establish real multithreaded contention semantics; Native
and target runtime evidence are reported separately.

## Failure, Concurrency, and Constraints

A failed assertion throws a distinct proof error. Production domain failures
must match their typed categories; unexpected failures abort. Build and runtime
have process-group deadlines, and unfinished child processes are terminated.
Fixture operations use finite source, subdivision and algebra limits.

## Verification and Change Impact

The same public smoke runs on fixed Native and matching normal/Embedded WASM.
Compile/link evidence includes every CADCore/CADGeometry source file, not just
the fixture dependency slice. Native codec behavior is checked only where the
codec capability exists. These checks establish geometry behavior only on the
executed target/backend.
