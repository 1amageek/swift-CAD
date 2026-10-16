# Curve Arc Length

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns original-curve length enclosures, retained length partitions and inverse arc stations. It does not author replacement geometry or establish source equality.

## Responsibilities and Boundaries

The resolver owns adaptive interval integration, heap ordering, cumulative length bounds and inverse localization. Prepared original geometry owns coefficient and owning-chart authority. Consumers select accuracy and explicit source, spatial and scalar ceilings; the same direct execution accounts for all actual work and allocations.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original direct query execution | Hosts original curve operations | Length accuracy is independent of source identity |
| [Original Geometry Source Validation](../OriginalGeometrySourceValidation/DESIGN.md) | depends on | Prepared original coefficients and immutable depth receipt | Retains original curve preparation | Later readers re-admit actual attained depth |
| [Original Higher Curve Jets](../OriginalHigherCurveJets/DESIGN.md) | depends on | Original one-sided derivatives | Bounds speed and integration remainder | A hull does not prove join smoothness |
| [Pipe](../../CADModeling/Pipe/DESIGN.md) | used by | Retained differential and inverse arc queries | Consumes original sweep station law | A station representative does not establish exact correspondence |

## Architecture

```text
curve + interval + explicit accuracy/caps + caller execution
    -> original prepared curve -> outward adaptive partition
        -> immutable partition + source + policy + cumulative budget
            -> exclusive reader execution -> length / smoothness / inverse stations
```

## Contracts and Invariants

All admitted resolver and retained-query requirements accept `using execution: inout OriginalQueryExecution`. Ordinary entries create one root execution and invoke the same direct original path. Original coefficients and complete requested domains remain authoritative. Every integration cell preserves its original interval and actual subdivision depth. Every heap and inverse buffer is admitted before allocation or COW materialization. Remaining source depth, scalar depth, subdivision depth and interval count retain independent meanings.

Retained queries share immutable source, partition, accuracy policy and cumulative budget. They do not retain work/storage callbacks or query-local scopes. An explicitly independent reader re-admits the preparation's actual operation-local depth receipt without recomputing the partition or replaying historical work.

The canonical path prepares the original curve and consumes either its existing uniform-speed primitive theorem or its original outward derivative bounds. The uniform theorem retains the existing analytical line/circle length and exact scalar fraction formulas in the same direct path. The former ordinary-only candidate/decomposition branch does not remain as a second unmetered execution path. Chords and numerical sampling do not grant original authority.

## Runtime Flows

Preparation validates the original requested domain, constructs original derivative authority, and refines the largest unresolved integration gap until the complete sum meets the selected accuracy. Inverse queries refine retained original cells and require complete cumulative target coverage. All actual calls borrow the same execution, including source jets, smoothness checks, heap comparisons and array materialization.

## State, Ownership, and Lifecycle

Prepared owners retain immutable COW source and cell arrays plus their common budget and policy. Each caller exclusively owns its noncopyable execution. Shared cumulative accounting remains in the common budget's identical Mutex owner on Native, WASM and Embedded; this component introduces no target-conditional mutable state or unchecked concurrency.

## Failure, Concurrency, and Constraints

Invalid domains/fractions, nonfinite bounds, unresolved target coverage, exhausted work/storage/source/scalar/spatial/count ceilings and cancellation propagate. Resource failure never becomes a partial complete length or inverse result. Cleanup unwinds local scopes while preserving the original failure. Final publication observes cancellation.

## Verification and Change Impact

Existing [CurveArcLengthResolverTests](../../../Tests/CADGeometryTests/CurveArcLengthResolverTests.swift) own independent length and inverse-station oracles, including exact line stations and narrow analytical circle length bounds. [BSplineCurveCommonBasisResolverTests](../../../Tests/CADGeometryTests/BSplineCurveCommonBasisResolverTests.swift) owns common-basis image behavior. Direct migration requires observed N/N-1 cumulative work/storage, source/spatial/count refusal, terminal cancellation, prepared reuse and independent reader tests. Modeling Pipe and original sweep station callers must pass the same execution. Focused parsing is preparatory evidence; runtime and portable verification remain pending until the shared direct API graph compiles.

Source ownership review (portable compile/runtime evidence is pending):

| State | Native / WASM / Embedded storage | Isolation | Read / mutation entry | Release |
|---|---|---|---|---|
| Original curve, partition and policy | Immutable retained COW values | Immutable Sendable owner | Direct retained query / constructor only | Prepared owner release |
| Cumulative charges | Same `OriginalQueryBudget` reference | Common Mutex owner | Execution operations | Budget owner release |
| Heap and inverse refinement | Query-local arrays and counters | Exclusive query execution | Private direct helpers | Query end |
| Proof scopes | Noncopyable execution fields | Caller-exclusive | Same inout execution | Scope close/query end |

Conditional math-module imports and existing Codable availability do not branch storage, Sendable or isolation. This component adds no external callbacks or I/O.
