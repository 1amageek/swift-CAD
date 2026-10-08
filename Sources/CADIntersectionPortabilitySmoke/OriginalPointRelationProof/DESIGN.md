# Original Point Relation Proof

## Purpose and Scope

This component owns bounded public behavioral verification of isolated-point
intersection and complete empty coverage. Parent: [Intersection Portability
Smoke](../DESIGN.md). It has no children.

## Responsibilities and Boundaries

Literal original B-spline and original Native curve/ruled fixtures exercise normal and caller-admitted rich and
discrete curve/surface and surface/surface requirements through existentials.
The public native receipt must retain exact tuple ownership; arrays alone are
insufficient. Geometry algorithms remain production-owned.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Intersection Portability Smoke](../DESIGN.md) | parent | Fixed-target entry and bounded recipe | Joins cancellation proof | A failed target is not completion |
| [Native CS Points](../../CADGeometry/CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | depends on | Original tuple publication | Supplies curve/surface receipts | Positive dimension cannot publish an isolated subset |
| [Original Affine CS Points](../../CADGeometry/OriginalAffineCurveSurfacePoints/DESIGN.md) | depends on | Exact affine source word and complete original UV tuples | Checks common public witness and retained source | Native detailed cases remain their own proof |
| [Original Polynomial CS Points](../../CADGeometry/OriginalPolynomialCurveSurfacePoints/DESIGN.md) | depends on | Complete isolated original tuple receipts and atomic non-discrete refusal | Supplies unchanged ruled source authority | Native-only detailed cases are reused; this executable checks target public capabilities |
| [Native SSI Points](../../CADGeometry/NativeSurfaceSurfacePointRelations/DESIGN.md) | depends on | Original tuple publication | Supplies surface/surface receipts | Empty success requires full coverage |
| [Native Exact Geometric Relations](../../CADGeometry/NativeExactGeometricRelations/DESIGN.md) | depends on | Single-span L6 source/parameter owner and complete exclusion | Supplies migrated Native CS/SSI receipts | Legacy Native optional receipts are nil on this family; parameter equality and owner identity still require actual queries |
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
Migrated Native points retain L6 evidence: their handle must resolve to the retained
selected cell, reject an independently solved owner's handle and expose the exact
literal parameters. Empty L6 selections retain the complete closed unit domains.
The verification uses an explicit bounded ledger for these retained-owner queries;
it does not re-solve the original intersection or accept receipt presence alone.
The weighted nonunit-domain Native curve/ruled fixture must pass all four rich/discrete
ordinary/admitted protocol requirements. Its exact tuple owner survives input mutation
and release; two UV preimages at one XYZ remain distinct. A finite no-root domain
retains complete empty coverage, and positive dimension fails atomically. Independent
work, storage, source-depth, algebra-depth and candidate limits fail explicitly.
The actual last storage callback of point and domain-excluded empty publication
cancels a joined Task and must reject success for admitted rich and discrete paths.
The affine fixture preserves weighted Native UV under a rational forward/inverse
shear and reflection, checks independent literal world coordinates through all four
public requirements, and retains its exact source word after authored inputs are
mutated and released. Exact point queries use the same checked work/word-storage
ledger. Complete empty coverage, positive-dimensional atomic refusal, independent
work/storage/source/algebra/candidate limits and final point/empty storage-callback
cancellation are exercised on each executable target. Native detailed cases are reused.
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
invokes no external callback while locked. Exact algebra work counts are debited
without reduction; cell visits and public depth callbacks charge one work unit. Storage callback ordinals are checked
for overflow and counted under that same Mutex; exact tuple query UInt32-word
admission is converted to physical bytes by checked multiplication before debit; task cancellation occurs after
leaving the lock. The async entry owns and joins the
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
