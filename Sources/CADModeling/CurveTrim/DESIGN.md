# Curve Trim

## Purpose and Scope

Own finite original curve restriction and feature publication. Parent:
[CADModeling](../DESIGN.md). This component has no children.

## Responsibilities and Boundaries

Resolve one explicit curve output, admit its authored finite interval, retain
the same original law and publish bounded display samples with native
parameters. Geometry owns image mapping and original curve evaluation;
restriction does not fit a curve or prove whole-curve topology.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | feature evaluation and curve output | Publishes retained trim values. | No body construction authority. |
| [SectionResolution](../SectionResolution/DESIGN.md) | used by | original finite restriction | Restricts before directed section reversal. | Reference bounds use the selected source chart. |
| [ParameterImage](../../CADGeometry/ParameterImage/DESIGN.md) | depends on | original signed scalar images | Preserves wrapped original curve parameters. | Image endpoints are retained in their authored chart. |
| [OriginalCoons](../../CADGeometry/OriginalCoons/DESIGN.md) | depends on | retained guide traversals and endpoint correction laws | Restricts those original normalized source charts. | Spline display kind does not replace the guide source. |

## Architecture

```text
curve output reference -> original curve + source parameter domain
    -> finite span admission -> same original law + explicit finite trim
        -> native display samples -> generated curve publication
```

## Contracts and Invariants

The result retains the original exactCurve value and the authored finite
parameter domain, including signed parameter images. Display kind follows the
underlying law using mapped original endpoint parameters; this metadata cannot
authorize geometry or boundary incidence. The complete original curve remains
the authority for every sample and downstream jet. Plane metadata is retained.
Periodic restrictions cannot exceed one original image turn. Trim and mapping
failures propagate rather than returning the untrimmed source.
The caller-admitted trim route validates the original evaluated-curve receipt
without display-cache replay, prepares original closed jets once and admits all
33 display parameter/point slots before allocation. Each displayed point is a
candidate inside a complete original singleton position enclosure, with its
radius bounded by distance/64. The source curve and authored interval remain
unchanged. Exact bounded edge classification determines closure; a nearly full
period or nearly matching endpoint cannot manufacture a closed trim. Kind is
display metadata and never requires an opaque original parameter projection.
Section resolution borrows the composing admission for this same route;
legacy standalone callers retain their existing convenience policy.

## Failure, Concurrency, and Constraints

An invocation publishes at most 33 original-law display samples. Missing source,
invalid interval, nonfinite image arithmetic and invalid original geometry
remain typed failures. All values are local and preserve common Sendable
contracts across targets; the evaluator has no mutable shared state.

## Verification and Change Impact

[CurveTrimFeatureEvaluatorTests](../../../Tests/CADModelingTests/CurveTrimFeatureEvaluatorTests.swift)
owns retained laws, finite bounds, periodic excess and missing geometry.
[CurveTrimCommandParityTests](../../../Tests/SwiftCADTests/CurveTrimCommandParityTests.swift)
owns public command publication. Deferred checks must include negative signed
images, nested images and their original endpoint and derivative correspondence.
Changes require rechecking SectionResolution and its construction consumers.
Source edits alone do not establish these behavioral results.

The original-polyline family retains its authored Euclidean-length clock through
trim selection. Display metadata remains spline-shaped; it does not replace the
raw adjacent-point source or redefine native stations by vertex index.
