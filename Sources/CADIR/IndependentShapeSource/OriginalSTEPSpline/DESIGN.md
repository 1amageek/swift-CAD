# Original STEP Spline

## Purpose and Scope
Child of [Independent Shape Source](../DESIGN.md), retaining original STEP spline control-point records and explicit descriptive attributes. No children.

## Responsibilities and Boundaries
Own shared control-point identities/names, curve/surface form, LOGICAL assertions, knot specification and rational-family presence. Geometry owns original control coordinates, weights and knots. Exchange owns standard parsing and publication. Records cannot replace or independently mutate the spline law.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Independent Shape Source](../DESIGN.md) | parent | complete source validation | Binds metadata to actual original spline | All shared point identities use the same original element registry |
| [Original STEP Placement](../OriginalSTEPPlacement/DESIGN.md) | depends on | OriginalSTEPPlacementElement | Reuses original point identity/name/coordinate record | POINT and DIRECTION identities cannot alias |
| [Independent Shape Exchange](../../../CADExchange/IndependentShapeExchange/DESIGN.md) | used by | spline transport | Retains and reemits explicit standard attributes | Context gain is an exact law, not a numeric unit guess |

## Architecture
```text
Original shared points + form/logical/knot assertions
  -> immutable metadata -> complete source binding
Raw BSpline geometry + original spatial word
  -> same source binding -> Native / STEP publication
```

## Contracts and Invariants
Curve controls are ordered in native parameter order. Surface controls use the native [v][u] order; Exchange transposes the standard [u][v] boundary exactly once. Each original point's coordinates match the corresponding raw BSpline control point exactly. LOGICAL unknown remains distinct from false and true; closed assertions do not invent a periodic knot extension. Rational presence remains distinct when all original weights happen to equal one. Curve/surface form and knot specification retain their original standard enumeration values. Metadata is optional per original geometry law; absence remains distinct from authored unspecified attributes. Native requires both source maps and exact record fields.

## Failure, Concurrency, and Constraints
Immutable Sendable values. Native decoding admits array counts and physical retained storage before reserve/append under the existing shared allowance. Wrong geometry family, mismatched controls, inconsistent shared identity, unknown enum and invalid array bounds fail explicitly. No guessed labels, closedness, periodic extension or rational-family presence.

## Verification and Change Impact
Source authoring precedes behavioral verification. Required evidence covers shared point records across spline/frame/LINE sources, distinct logical states and forms, simple/complex/rational STEP, surface transposition, exact normative unit conversion, Native strict decoding, translation and two output generations. Parent source validation and Exchange publication must be rechecked when this child changes.

Normative definitions: [curve](https://www.steptools.com/stds/stp_aim/html/t_b_spline_curve.html), [surface](https://www.steptools.com/stds/stp_aim/html/t_b_spline_surface.html), [curve form](https://www.steptools.com/stds/stp_aim/html/t_b_spline_curve_form.html), [surface form](https://www.steptools.com/stds/stp_aim/html/t_b_spline_surface_form.html), [knot type](https://www.steptools.com/stds/stp_aim/html/t_knot_type.html).
