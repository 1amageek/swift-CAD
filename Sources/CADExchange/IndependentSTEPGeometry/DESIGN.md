# Independent STEP Geometry

## Purpose and Scope

Child of [CADExchange](../DESIGN.md), with no children. Implements standalone
curve and surface exchange through `IndependentSTEPGeometryExchanging`.
Named geometry values are returned directly; no body, shell or project source
is manufactured. Native document storage, assemblies, mapped instances,
arbitrary angular contexts and the full X7 requirement remain separate.

## Responsibilities and Boundaries

Owns immutable named curve/surface transfer values and the independent public
STEP route. Existing exact primitive readers/writers own coordinate and rational
coefficient transfer. Existing STEP syntax and resource owners admit the input
before independent geometry is published. Applications own project insertion.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADExchange](../DESIGN.md) | parent | bounded STEP primitive transfer | Reuses real exact readers and writers | Existing B-rep entry remains unchanged |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | Curve3D/Surface3D validation | Retains actual source geometry | An unsupported native family throws |

## Architecture

```text
named source values -> exact primitive writer -> geometric sets -> STEP bytes
STEP bytes -> bounded syntax/unit admission -> representation sets
           -> exact primitive reader -> complete named source values
```

## Contracts and Invariants

Named rational B-spline curves and surfaces retain knots, weights and original
control coordinates. Analytic transfer uses existing exact entity support.
Surface admission is original analytic or rational B-spline geometry;
procedural charts are explicitly refused until full X7 has bounded original-law
transfer. Unbounded analytic supports use generic SHAPE_REPRESENTATION rather
than falsely asserting the bounded-surface subtype's constraints.
Curve trims retain their ordered start/end and may reverse traversal. Line
trims are converted between native length parameters and file length units;
foreign lines must use a unit-magnitude STEP VECTOR. Other line parameter laws
are explicitly refused rather than silently normalized. Names
use printable ASCII STEP strings with doubled apostrophes; other encodings
throw explicitly. Coordinates are internal meters; the declared length unit
controls file conversion. Plane angles are radians; other contexts are refused.
All representation items must be admitted. Product metadata is refused because
these geometry-only values cannot retain it. Mixed B-rep/mesh/instance inputs,
unknown items and missing references fail instead of returning partial success.
Empty models are invalid. No fake topology or sampled geometry supplies success.

## Runtime Flows

The facade validates source values and limits, builds a complete entity table,
admits final bytes and only then writes the sink. Import validates the envelope,
entity table, representation ownership, context and units before building values.
One throwing invocation returns the complete result or publishes no result.

## State, Ownership, and Lifecycle

All new model values are immutable Sendable values. Parsing caches are local to
one synchronous builder and never shared. Byte borrowing stays inside the source
closure; the imported values own their geometry. No tasks, streams or callbacks
outlive an operation. No conditional synchronization declarations are introduced.

## Failure, Concurrency, and Constraints

Malformed data uses ImportError; unsupported semantics use the existing typed
exchange KernelError. Byte/entity/nesting/iteration/deadline limits are shared
with the existing STEP facade. Cancellation propagates. Source validation and
all resource admission precede the single final sink write; sink failure itself
remains the sink owner's failure contract.

## Verification and Change Impact

[IndependentSTEPGeometryTests](../../../Tests/CADExchangeTests/IndependentSTEPGeometryTests.swift)
owns real protocol-level curve/surface round trips, exact coefficients, directed
trims, names, unit conversion, malformed/mixed inputs, budgets and cancellation.
The existing ExactSTEPExchangeTests remain the upper B-rep regression owner.
Native proof does not establish WASM/Embedded execution or full X7 completion.
Entity choices follow the [STEP wireframe schema](https://www.steptools.com/stds/stp_aim/html/t_geometrically_bounded_wireframe_shape_representation.html)
and [STEP surface schema](https://www.steptools.com/stds/stp_aim/html/t_geometrically_bounded_surface_shape_representation.html).

The parity-branch integration reuses the parent EntityTable byte/string ledgers
instead of introducing a second byte counter. Its optional processing budget
checks the same synchronous add boundary without altering existing default
callers. Explicit unfiltered Builder admission preserves the separate B-rep
representation selection. Native verification executes the fourteen independent
capability tests and four unchanged original ExactSTEPExchangeTests together.
This proof covers the committed integration snapshot, not the parent's broader
ongoing uncommitted source batch.
