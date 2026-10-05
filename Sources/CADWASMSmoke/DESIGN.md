# Portable Kernel Verification

## Purpose and Scope

This executable module is a child of the [package](../../DESIGN.md). It owns the actual entry point for whole-production-graph Native, normal WebAssembly and Embedded WebAssembly verification. Its child is [RectangularBSplineMeshSmoke](RectangularBSplineMeshSmoke/DESIGN.md).

## Responsibilities and Boundaries

The entry point constructs and evaluates an exact box, checks topology, volume and public failure/capability contracts, then awaits its child fixtures before publishing its final completion marker. Production geometry and mesh contracts remain with their library owners. A source subset or successful compile alone cannot establish runtime success.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Production target graph and fixed toolchain | Registers the executable product | Keep all production dependencies |
| [Rectangular mesh fixture](RectangularBSplineMeshSmoke/DESIGN.md) | child | `run() async throws` | Exercises public original mesh paths | All child checks precede final success |
| [CADKernel](../CADKernel/DESIGN.md) | depends on | DocumentEvaluator and MeshTessellator | Owns actual evaluation and mesh behavior | Preserve allowances and typed failures |

## Architecture

```text
actual executable entry
    -> exact document evaluation and public contract checks
    -> await rectangular mesh fixture
    -> final completion marker
```

## Contracts and Invariants

`main() async throws` awaits all fixtures in the same invocation. A thrown error or cancellation prevents final success. Every target retains the same source, ownership and cancellation contracts; no target branch removes checks or synchronization. Each runtime receipt identifies its actual toolchain, SDK, source, linked artifact and runtime.

## Runtime Flows

The entry point completes synchronous exact evaluation, awaits its child and prints `CADWASMSmoke passed` only after every check succeeds.

## State, Ownership, and Lifecycle

Each invocation owns its document, evaluation and child tasks. The entry point has no retained mutable state or persistent resources. Each child owns and completes its own tasks and streams before returning.

## Failure, Concurrency, and Constraints

Build and execution use external command timeouts, the fixed Swift 6.4.0 toolchain and matching SDK. Production dependency failures remain explicit unverified target closure. Native execution does not establish WebAssembly or Embedded semantics.

## Verification and Change Impact

Build, link and execute this actual product on each required target. Check the child's completion marker and the final entry-point marker. Entry composition changes invalidate executable integration evidence; unchanged child source and prerequisites retain their existing local evidence. Broader M1 completion belongs to its requirement owner.
