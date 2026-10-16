# Curve Differential Bounds

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns curve differential interval bounds, position enclosures, spatial derivative ranges and third-order parameter differentiation. It does not issue source identity, intersection coverage or replacement geometry.

## Responsibilities and Boundaries

The differential dispatcher preserves each existing original family formula and selected native/procedural branch. Native B-spline evaluation and original source owners supply their actual mathematics; surface-lift and implicit owners supply their original composition and localization contracts. Position bounds and derivative-range adapters compose those public contracts. All actual calls borrow the same direct execution.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Direct numerical helper ownership | Composes these public lower ports | Numerical representatives do not issue source equality |
| [Original Geometry Source Validation](../OriginalGeometrySourceValidation/DESIGN.md) | depends on | Prepared original curve/native coefficient authority | Supplies closed original owning jets | Union bounds do not establish smooth joins |
| [Original Higher Curve Jets](../OriginalHigherCurveJets/DESIGN.md) | coordinates with | Direct original Taylor and cached coefficient proof | Preserves independent scalar axes and source policy | Retained cached words re-admit their actual proof depth |
| [Geometry Conversion](../GeometryConversion/DESIGN.md) | used by | Differential/position enclosures | Certifies candidates against the original law | Fitting residuals are not whole-domain bounds |
| [Curve Arc Length](../CurveArcLength/DESIGN.md) | used by | Original derivatives and owning-chart bounds | Bounds speed and integration remainder | Original smoothness remains separately proved |

## Architecture

```text
original curve + selected interval + direct execution
    -> existing native / analytic / implicit / lifted formula
        -> original third-order interval jet / spatial derivative range
            -> differential enclosure -> position enclosure
```

## Contracts and Invariants

Public and actual helper entries take `using execution: inout OriginalQueryExecution`. Ordinary conveniences create one root execution and delegate to the identical formula body. The source curve, native interval, ordering of arithmetic, original branch selection and explicit source/spatial/scalar policy remain authoritative. No callback reconstructs an admission, no private child budget is created, and no ordinary convenience is invoked from an admitted operation.

Every source-sized loop and concrete typed allocation is charged by its actual owner before the operation. Pure fixed-field interval arithmetic does not receive fictional heap fees. Direct callbacks that describe mathematical composition pass the original execution explicitly and do not retain it. Original affine-word cached coefficients first re-admit their source proof.

The rational Bezier derivative certificate retains the existing immutable polynomial roots and existing concrete Mutex/stateless restriction cache backends. A closed enum dispatches generic direct arithmetic to the concrete backend; no generic requirement is invoked through an existential in Embedded. The OS availability selection, cache key equality, quotient-rule correlation, dyadic restriction and nil capability result are unchanged. Query failures throw independently of nil. Polynomial interval coefficients are binary outward scalar fields; cache reuse retains those fields and performs no algebraic-root proof inference. Work/storage admission and polynomial arithmetic occur outside Mutex critical sections; the lock only accesses cache state.

## Runtime Flows

The differential route validates the selected source/domain, retains its original direct jet when available, and otherwise composes the existing procedural magnitude/localization formula. A surface lift retains its unchanged UV law and surface derivatives. Third-order point differentiation composes the existing lower derivatives and original third derivative formula. Position bounds consume the same differential or exact lift branch.

### Primitive Stack Boundary

`DefaultCurveDifferentialEncloser.directJet` charges its existing dispatch work
once, then selects either the line/circle primitive helper or the original
family helper. Both helpers are `@inline(never)` boundaries: a primitive query
must not reserve the stack temporaries of native, original Taylor, or lifted
families before its branch is selected. Primitive formulas exist once; the
family helper retains the original remaining cases, argument order, nil
capability results, and the same exclusive execution. This separation changes
neither source validation nor work/storage/depth admission.

The Native optimized object prologue and the actual primitive-to-sewing runtime
own the stack regression evidence. Source separation and typechecking alone do
not establish that the optimized primitive stack frame is bounded. The focused
primitive direct-jet fixture preserves original position/derivative laws and
same-query cumulative work, exact work refusal, storage and cancellation.

## State, Ownership, and Lifecycle

Dispatchers and returned bounds are immutable Sendable values. Temporary basis, homogeneous derivative and result buffers belong to one exclusive query. Query cumulative work/storage state belongs solely to the common budget Mutex; the separately owned restriction memo is described below; this component retains no work/storage callbacks, mutable query scope or target-dependent synchronization state.

| Logical state | Native | WASM / Embedded | Read / mutation | Release |
|---|---|---|---|---|
| Immutable derivative roots | Same immutable dictionary owner | Same owner | Constructor / read only | Cache owner release |
| Memoized restrictions, supported Mutex backend | `Mutex<State>` | Same `Mutex<State>` | `withLock` lookup / insertion; numerical work and admission outside lock | Cache owner release |
| Existing older-OS stateless backend | Immutable roots | Same immutable roots when selected by OS availability | Read-only numeric restriction | Cache owner release |

Target compile/link/runtime synchronization evidence remains pending; syntax parsing does not establish backend semantics. The C math import is the only Embedded feature branch in these files.

## Failure, Concurrency, and Constraints

Existing invalid-domain, singular-system, nonfinite arithmetic and unsupported original-family failures remain explicit. Missing exact coverage or required lower authority never becomes a successful empty or synthesized bound. Work/storage/source/scalar/spatial exhaustion and cancellation propagate through the caller execution, including a final publication checkpoint.

## Verification and Change Impact

[CurveDifferentialEncloserTests](../../../Tests/CADGeometryTests/CurveDifferentialEncloserTests.swift), original closed-native-jet tests, [SurfaceLiftThirdOrderDerivativesTests](../../../Tests/CADGeometryTests/SurfaceLiftThirdOrderDerivativesTests.swift), and [SurfaceParameterThirdOrderDerivativesTests](../../../Tests/CADGeometryTests/SurfaceParameterThirdOrderDerivativesTests.swift) own formula and owning-side behavior. Recheck analytical/native/procedural branches, prepared/one-shot consistency, observed N/N-1 work/storage, independent scalar/source/spatial caps and terminal cancellation. GeometryConversion, ArcLength, Modeling surface-lift and Kernel bounds callers must pass the same execution. Focused syntax parsing is preparatory only; semantic and runtime evidence remains pending until the direct shared API graph compiles.

## Curve Tessellation Execution Closure

The module adapter `Curve3D+TessellationBounds.swift` composes this component's
original derivative bounds. Its direct curve and validated-curve entries borrow
one `OriginalQueryExecution` through source validation, periodic derivative
certification, midpoint derivatives, native patch restriction and retained
closed-native jets. A one-shot curve entry creates one independent root. A
validated ordinary entry obtains the existing retained preparation execution;
its direct entry uses the same receipt/contribution readmission scope as other
validated reads, including a foreign query execution. No derivative subquery
creates a new allowance or treats a cancellation callback as admission.

The original chord error, arc-length, tangent-angle and stationary endpoint
formulas and all native sliver/whole-span branches remain unchanged. Traversal
of source images admits actual source depth. Weight, patch and native-owner
visits consume work; coordinate rows admit their typed storage before mapping.
Pure fixed-field bound assembly consumes scalar work without fictional heap
allocation. Cancellation is checked before work and final publication.

`CurveTessellationDirectExecutionTests` owns direct/retained/foreign execution
behavior, formula preservation and caller work/storage refusal. Existing
`BSplineCurveParameterDerivativesTests` retains stationary-endpoint convergence
coverage. Native rectangle fixtures pass one actual execution through prepared
spans, point jets, selected normals and panel traversal, preserving their
original ownership/domain/collapse/cancellation oracles. Semantic and runtime
verification remain pending the common direct graph compilation.
