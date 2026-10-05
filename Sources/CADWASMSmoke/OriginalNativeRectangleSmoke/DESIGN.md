# OriginalNativeRectangleSmoke

## Purpose and Scope

This child of [CADWASMSmoke](../DESIGN.md) verifies the public original
nonperiodic nonclamped rectangular B-spline mesh route on Native and matching
normal WebAssembly. It has no children.

## Responsibilities and Boundaries

The witness constructs an actual original B-rep owner graph using public value
APIs and surface-lift coedges. It executes `MeshTessellator`, compares output
against independent polynomial positions and normals, and verifies explicit
resource and singular-geometry refusal. Geometry and Kernel own production
algorithms. The witness does not establish periodic or Embedded support.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADWASMSmoke](../DESIGN.md) | parent | completion after all witnesses | Runs the same public route on both targets. | Compilation is not behavioral evidence. |
| [RectangularBSplineMesh](../../CADKernel/RectangularBSplineMesh/DESIGN.md) | depends on | original panel mesh, provenance and typed refusal | Executes the complete mesh producer. | Existing clamped routes stay separate. |
| [OriginalRectangleTessellation](../../CADGeometry/OriginalRectangleTessellation/DESIGN.md) | depends on | selected original differential authority | Bounds the stored support. | Sampling is only an independent output check. |

## Architecture

```text
Original coefficient net + exact coedges -> public MeshTessellator
    -> polynomial and normal oracles -> storage/collapse refusal -> completion
```

## Contracts and Invariants

Native parameters `2...3` describe the literal graph `z = 0.2*x*x` or
`z = 0.2*y*y`. Tightening the position or angular allowance increases the
triangle count. Every emitted vertex and normal matches the literal graph;
all triangle edges and their midpoint deviations meet the requested bounds.
The original B-rep remains unchanged and FaceRuns retain its generating face.
Resource and singular requests must throw their producer's typed failure.

## State, Ownership, and Lifecycle

All source and output values are local to the synchronous invocation. No shared
mutable storage or target-specific isolation is introduced.

## Failure, Concurrency, and Constraints

Any failed oracle throws before a completion marker. Original caller limits,
stack configuration and producer proof ceilings remain unchanged. The external
runner imposes a process deadline and records source and artifact hashes.

## Verification and Change Impact

Run the permanent executable with the fixed Swift 6.4 release toolchain and
matching normal WASM SDK, executing the latter on real WASI. Require success,
resource-refusal and collapsed-panel-refusal markers as well as the existing
box markers. Producer or input changes invalidate this witness's evidence.
