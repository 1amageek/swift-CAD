# Portable Geometry Verification

## Purpose and Scope

Child of [the package](../../DESIGN.md), without children. Owns G1/G2 executable
geometry, knot-reduction and source-signature checks on matching normal WASM and native targets.

## Responsibilities and Boundaries

Exercises actual cyclic geometry, refinement, restriction, projection and source
transport. It does not establish whole-kernel, Embedded, exchange or application
coverage; those remain in the final integration item. Each new geometry requirement
must add its own behavioral evidence before this executable can cover it.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Verification ownership | Platform-specific geometric runtime evidence | Full integration remains required |
| [Periodic B-spline](../CADGeometry/PeriodicBSpline/DESIGN.md) | depends on | Periodic evaluation, exact editing and budgets | Exercises rational cycles across their seam | No sampled curve fitting |
| [KnotRemoval](../CADGeometry/KnotRemoval/DESIGN.md) | depends on | Full-domain deviation bounds | Exercises cyclic curves, pcurves and both tensor axes | Resource refusal must remain explicit |
| [CADIR](../CADIR/DESIGN.md) | depends on | SubshapeGeometrySignature transport | Retains the exact periodic value in a finite edge span | A signature is not a evaluated body |

## Architecture

```text
Native/WASI host -> periodic rational value -> evaluation/refinement/restriction
                -> prepared projection/bounds -> geometry signature transport
                -> malformed input and resource-budget refusal
```

## Contracts and Invariants

A success marker requires each operation to execute and satisfy its behavioral
checks. Failed comparisons throw classificationFailure; expected resource and
input failures must retain their own typed codes. All values are task-local and
no target changes the storage, isolation or error contract.

## Verification and Change Impact

Build with Swift 6.4.0 and the matching normal WASM SDK. Execute the exact emitted
artifact with Scripts/run_wasi_smoke.mjs, bounded by the repository guard. Native
SubshapeGeometrySignatureTests owns source transport and corruption rejection.
Tensor checks execute independent periodic axes, mixed derivatives, origin-aware
projection, seam restrictions/refinement, interval derivative containment, face
signature transport and resource/input refusals, including a folded periodic
Bezier span with two regular roots that must not yield a unique answer when
its subdivision budget is exhausted. Knot reduction executes the public protocol
for rational pcurves, periodic curves and both periodic tensor axes, checks
source/origin and bound retention, and checks typed work-budget refusal. Periodic geometry or transport
changes invalidate this runtime evidence. The matching
Embedded SDK currently lacks Foundation used by existing CADCore/CADGeometry;
normal WASM runtime success does not establish Embedded support.
