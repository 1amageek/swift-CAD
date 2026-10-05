# Rectangular B-spline Mesh Portable Verification

## Purpose and Scope

This child of [CADWASMSmoke](../DESIGN.md) owns the shared Native, normal-WASM and Embedded public Mesh runtime fixture. It has no children. It consumes the complete production CADKernel target graph; a source-excluded Geometry or Kernel subset cannot establish this contract.

## Responsibilities and Boundaries

The fixture constructs original support/curve/topology inputs and calls the public MeshTessellator. Independent literal Cartesian laws check emitted triangle interiors, source normals, diagonals, refinement, source retention and failure. It does not provide production geometry authority, change tolerances, or declare an unexecuted target successful. The parent owns executable entry, stack provision, product graph and target selection.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADWASMSmoke](../DESIGN.md) | parent | actual executable entry and complete target graph | Invokes the same run API on each target | Compile/link alone is not runtime evidence |
| [RectangularBSplineMesh](../../CADKernel/RectangularBSplineMesh/DESIGN.md) | depends on | original selected native rectangular admission | Exercises nonclamped and mixed periodic/open inputs | No private bounds or reconstructed support oracle |
| [CADIR](../../CADIR/DESIGN.md) | depends on | original TessellationOptions/Limits and Mesh | Supplies immutable allowances and actual mesh storage | Budget refusal must retain its typed cause |

## Architecture

```text
Original literal surface + exact directed coedges/vertex identities
    -> public MeshTessellator
    -> independent literal position/normal/all-edge checks
    -> refinement + FaceRun/extraction checks
    -> original storage/singularity/cancellation refusal
```

## Contracts and Invariants

`RectangularBSplineMeshSmoke.run() async throws` performs the same public calls and checks on all targets. Quadratic nonclamped native2...3 supports follow S=(t,v,A*t*t). Unequal positive weights retain a flat original support. Mixed periodic degree1 diamond and nonclamped degree1 radius/height supports follow S=(R(z)C(u),z), R=1+0.25*min(z,1-z). Full periods retain two seam uses and split rims; partial charts retain raw3.5...4.5 coordinates. Literal per-triangle one-sided normals remain independent of source evaluators. Original source, caller allowances, FaceRun and extraction identity must survive; resource or singular/cancel failure publishes no success. The singular fixture keeps four nonzero boundary edges: its literal nonclamped degree1 U controls [0,0,1] collapse only the original native0...0.5 panel, so source-normal admission must refuse before mesh publication.

## Runtime Flows

The parent awaits the shared run API. Each fixture constructs fresh task-local inputs, checks coarse/refined public results and source identity, then executes typed failure and cancellation checks. A cancelled task is released through a finished AsyncStream gate; cancellation must escape as CancellationError. A failed check throws an explicit validation error and terminates the executable.

## State, Ownership, and Lifecycle

The runner has no stored mutable state, pointers or persistent cache. Inputs/results/gate/task are owned by one invocation. Native, normal WASM and Embedded retain identical source, Sendable, cancellation and ownership contracts; no conditional target branch weakens them.

## Failure, Concurrency, and Constraints

The fixture retains existing proof/grid ceilings and caller options. Its run is bounded externally by120s after a separately bounded600s build with jobs2 on fixed Swift6.4.0 and the matching SDK. Missing full-graph Embedded dependencies are explicit unverified target closure, not a passing subset or a different SDK. Expected resource/singularity/cancellation are checked by typed cause, not messages.

## Verification and Change Impact

Execute the actual linked parent product natively, with swift-6.4.0-RELEASE_wasm, and with swift-6.4.0-RELEASE_wasm-embedded. Keep raw artifact/source/manifest/toolchain/SDK/target/runtime receipts per target. Native CADKernelTests own broader rectangular fixtures; this common executable supplies portable public path evidence. Changes to original native span admission, grid/normal emission, caller budget or cancellation invalidate only the affected runtime premise. Whole M1 completion additionally requires root-owned source-domain consistency and verified main integration.
