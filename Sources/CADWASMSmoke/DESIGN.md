# CADWASMSmoke

## Purpose and Scope

This executable is a child of the [Swift-CAD package](../../DESIGN.md). It verifies actual bounded kernel execution on Native and the matching normal WebAssembly SDK. Its child [MainMeshCompactionSmoke](MainMeshCompactionSmoke/DESIGN.md) owns the compaction publication witness.

## Responsibilities and Boundaries

The composition root constructs the original meter-valued box, evaluates its exact B-rep, checks topology and literal volume, invokes its child witnesses and publishes completion only after they succeed. Production evaluation and tessellation remain kernel responsibilities. This executable does not establish Embedded support or complete M1 coverage.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Swift-CAD](../../DESIGN.md) | parent | native package composition | Owns package scope. | A smoke result is bounded to its actual input and target. |
| [CADKernel](../CADKernel/DESIGN.md) | depends on | evaluation and tessellation | Executes the complete production graph. | Typed failure and caller limits remain required. |
| [MainMeshCompactionSmoke](MainMeshCompactionSmoke/DESIGN.md) | child | mesh publication witness | Verifies indices, attributes and FaceRuns through public tessellation. | Reuses the original evaluated box. |

## Architecture

```text
Original source document -> DocumentEvaluator -> exact B-rep
    -> topology and volume checks -> MainMeshCompactionSmoke -> completion
```

## Contracts and Invariants

The original source, meter units, topology counts and volume tolerance are retained. Child verification consumes the actual evaluated B-rep; it does not substitute generated mesh data. Failed verification throws before completion is printed.

## Failure, Concurrency, and Constraints

The executable is synchronous and invocation-local. It propagates producer and witness errors without a fallback. The external runner fixes the toolchain, SDK and runtime and imposes a process deadline; successful compilation alone is insufficient.

## Verification and Change Impact

Run the same production witness on Native and matching normal WebAssembly, retaining source and artifact hashes and terminal markers. A witness change requires its owning contract verification. A production path change invalidates only the evidence that depends on that path. Embedded and other geometry families remain separate obligations.
