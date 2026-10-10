# Original Plane Pair Classification Repair

## Contract and Change

The actual public `DefaultSurfaceSurfaceIntersector` and
`PlanePlaneSurfaceIntersector` are recompiled together. They reuse the existing
original supporting-plane equation issuer and exact rational arithmetic. Two
direct-authored planes are parallel only when their exact equation normals have
zero cross product, and coincident only when their equation constants are
proportional too. Numerical tolerance cannot establish either equality.

The dispatcher forwards its selected options to the existing SSI scalar
allowance. Near-angle transverse pairs continue to numerical line publication;
unrepresentable line coefficients and unsupported procedural equation transport
fail explicitly. The legacy non-unit-normal refusal remains.

## Behavioral Evidence

`Evidence/red` retains the pre-fix failure through the actual public dispatcher:
planes separated by5e-7 under distance1e-6 incorrectly return coincidence.
`Evidence/native` and `Evidence/asan` retain the accepted final fixture, compiler
commands, original source and product hashes, and build/runtime logs.

The22 cases cover:

- Positive/negative sub-tolerance separation, the least positive subnormal,
  larger separation, both argument orders and opposite normals.
- Exact identical planes with tangent origin displacement and opposite normals.
- Perpendicular and below-tolerance transverse angles in both orders.
- Near-parallel planes with separated origins and a distant intersection line.
- Existing transverse offset-plane publication.
- Unsupported procedural equation transport and underflowed line coefficients.
- Exhausted option-derived scalar work, legacy scaled-normal refusal and task cancellation.

Both final runs compile/link and execute successfully with Swift6.4.0 release.
The one stable source review has no remaining scoped findings. The remaining
numerical transverse line/UV publication is marked incomplete in production.

## Dependencies, Ownership and Limits

The immutable copied CADCore/CADGeometry objects match the original M2 generation
products. Before and after runtime, the runner checks those objects/modules and
127 unchanged current source premises: all64 CADCore files, all56 ExactScalar
files and the7 direct equation/admission/classification/publication dependencies.
The three recompiled inputs are the actual dispatcher, plane-pair producer and
behavioral fixture. There are no replacement geometry implementations.

| State | Ownership | Isolation and lifetime |
|---|---|---|
| Scalar allowance | Value local to one invocation | Same existing storage/work admission; no new shared state |
| Exact equations | Invocation-local immutable values | Scoped owners survive all predicates; no escaping borrow |
| Published result | Existing value result types | No new references, callbacks or platform-specific ownership |

ASAN instruments only the recompiled sources; cached dependencies are not
reinstrumented. No full CADCore/CADGeometry/Kernel or L2-L6 production target was
rebuilt. This repair does not establish fresh WASM/Embedded publication acceptance,
general procedural plane coverage, exact transverse UV/image publication, M8,
whole-seven or full87 completion.

## Reproduction

```sh
python3 Tests/OriginalPlanePlaneIntersectionVerification/Verify.py
python3 Tests/OriginalPlanePlaneIntersectionVerification/Verify.py --asan
```

Each invocation admits its recorded dependency/source premises before execution,
uses a fresh scratch output, and limits compile/link to90s and runtime to30s.
Changed premises cause explicit refusal. Existing foreign worktrees are read only.
