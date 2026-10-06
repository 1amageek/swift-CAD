# CADWASMSmoke

## Purpose and Scope

This executable module is a child of the [Swift-CAD package](../../DESIGN.md).
It owns the actual entry point for bounded whole-production-graph verification
on Native and the matching normal WebAssembly SDK, with Embedded WebAssembly
remaining a separate required target closure. Its children are
[MainMeshCompactionSmoke](MainMeshCompactionSmoke/DESIGN.md),
[OriginalNativeRectangleSmoke](OriginalNativeRectangleSmoke/DESIGN.md) and
[RectangularBSplineMeshSmoke](RectangularBSplineMeshSmoke/DESIGN.md).
An executable declaration does not establish Embedded support or complete M1.

## Responsibilities and Boundaries

The composition root constructs the original meter-valued box, evaluates its
exact B-rep, checks topology and literal volume, checks public failure and
capability contracts, invokes its synchronous children and awaits its
asynchronous child before publishing final completion. Production evaluation,
geometry and tessellation remain their library owners' responsibilities. A
source subset, generated mesh substitute or successful compile alone cannot
establish runtime success.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Swift-CAD](../../DESIGN.md) | parent | Production target graph and fixed toolchain | Owns package scope and registers the executable product. | Keep production dependencies; each receipt is scoped to its actual input and target. |
| [CADKernel](../CADKernel/DESIGN.md) | depends on | DocumentEvaluator and MeshTessellator | Executes actual evaluation and tessellation. | Preserve caller allowances and typed failures. |
| [MainMeshCompactionSmoke](MainMeshCompactionSmoke/DESIGN.md) | child | mesh publication witness | Verifies indices, attributes and FaceRuns through public tessellation. | Reuses the original evaluated box. |
| [OriginalNativeRectangleSmoke](OriginalNativeRectangleSmoke/DESIGN.md) | child | original nonclamped mesh witness | Verifies literal original positions, normals and typed resource/singularity refusals. | Nonperiodic Native and normal WASM only. |
| [RectangularBSplineMeshSmoke](RectangularBSplineMeshSmoke/DESIGN.md) | child | `run() async throws` | Exercises public original mesh paths. | All child checks precede final success; evidence remains scoped to the actual target. |

## Architecture

```text
Original meter-valued source document
    -> DocumentEvaluator -> exact B-rep
    -> topology and literal volume checks
    -> MainMeshCompactionSmoke + OriginalNativeRectangleSmoke
    -> public failure and capability checks
    -> await RectangularBSplineMeshSmoke
    -> final completion marker
```

## Contracts and Invariants

The original source, meter units, topology counts and volume tolerance are
retained. Child verification consumes actual production geometry; the
compaction witness consumes the evaluated B-rep rather than substituting mesh
inputs. `main() async throws` completes all fixtures in the same invocation.
A thrown error or cancellation prevents final success. No target branch
removes checks or synchronization. Each runtime receipt identifies its actual
toolchain, SDK, source, linked artifact and runtime.

## Runtime Flows

The entry point completes synchronous exact evaluation and witnesses, awaits
its asynchronous child and prints `CADWASMSmoke passed` only after every check
succeeds.

## State, Ownership, and Lifecycle

Each invocation owns its document, evaluation and child tasks. The entry point
has no retained mutable state or persistent resources. Each child owns and
completes its own tasks and streams before returning.

## Failure, Concurrency, and Constraints

Producer and witness errors propagate without a fallback. Build and execution
use external command timeouts, the fixed Swift 6.4.0 toolchain and matching SDK.
The external runner fixes the runtime and process deadline. Production
dependency failures remain explicit unverified target closure. Native execution
does not establish WebAssembly or Embedded semantics; an intended target is
not an execution receipt.

## Verification and Change Impact

Build, link and execute this actual product on each required target, retaining
source and artifact hashes and child and final completion markers. Run the same
bounded production witness on Native and matching normal WebAssembly; Embedded
and other geometry families retain their separate obligations. A witness change
requires its owning contract verification. Entry composition changes invalidate
executable integration evidence; unchanged child source and prerequisites
retain their existing local evidence. A production path change invalidates
only evidence that depends on that path. Broader M1 completion belongs to its
requirement owner, and no prior receipt certifies this merged snapshot.
