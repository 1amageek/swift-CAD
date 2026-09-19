# Spatial Path Evaluation

## Purpose and Scope

Child of [CADModeling](../DESIGN.md). Evaluates spatial paths without planar
projection. No children.

## Responsibilities and Boundaries

Owns conversion to EvaluatedCurve and sampling through DerivedCurveSampling.
Source editing belongs to CADIR; document publication belongs to the caller.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | validated feature evaluation | Native evaluator dispatch | Errors propagate |
| [SpatialPath source](../../CADIR/SpatialPath/DESIGN.md) | depends on | exactCurve | Source geometry and stable knots | No inferred plane/profile |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | EvaluationResult | Snapshot publication | No B-rep mutation |

## Architecture

```text
Feature -> validated SpatialPathFeature -> exactCurve -> sampler -> EvaluatedCurve
```

## Contracts and Invariants

One path emits one curve with its source feature ID and no claimed plane.
Polyline spans are degree one; Bezier spans are degree three with multiplicity
three internal knots. Closed paths include the closing span. Evaluation preserves
the context B-rep. Invalid source or failed sampling returns failure, not empty data.

## Verification and Change Impact

CADKernelTests spatial-path evaluation verifies exact XYZ, sampled output,
closed endpoints and downstream curve consumption. Source edits are verified in
CADIRTests/SpatialPathTests. Kernel dispatch and persistence must retain the new
operation kind.
