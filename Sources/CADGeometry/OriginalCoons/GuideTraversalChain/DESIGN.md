# Original Guide Traversal Chain

## Purpose and Scope

This child of [Original Coons](../DESIGN.md) owns an immutable aggregate chart
for directed original guide traversals. It has no children. Each traversal
retains its own original native parameter correspondence and endpoint witness.
The aggregate chart is a declared construction law, not the parameterization of
an existing Euclidean-length polyline or a converted spline.

## Responsibilities and Boundaries

The issuer owns exact rational aggregate stations, original traversal identity,
source ordinal provenance, exact endpoint incidence and requested differential
continuity. Loft owns event selection, the chosen partition, candidate
construction, final correspondence and topology. Shared Geometry owns Curve3D
routing. No construction control net becomes the original guide law.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Original Coons](../DESIGN.md) | parent | Original curve boundary law | Aggregate guide boundary | Same original capacities |
| [Original Root Span](../../OriginalRootSpan/DESIGN.md) | depends on | Retained endpoint and directed jets | Every guide piece | Exact roots remain immutable |
| [Loft](../../../CADModeling/Loft/DESIGN.md) | used by | Source connector | Final guide side | Fresh candidate certification |

## Architecture

```text
original directed RootSpans + exact rational aggregate stations + ordinals
    -> source C0 and exact endpoint incidence
    -> original quotient derivative joins, independently per requested order
    -> piecewise source queries under one allowance
    -> final original guide curve -> final candidate certificate -> Loft
```

## Contracts and Invariants

Stations strictly increase from exact zero to exact one. On station interval
[a,b], the source is traversal((t-a)/(b-a)). Native correspondence remains owned
by that RootSpan. Source segment ordinals retain original guide order and allow
multiple owning pieces of one original segment. Exact C0 incidence is required.
Higher continuity is proved from original quotient derivatives with the exact
inverse station widths. A union of derivatives cannot prove a smooth join.
Requested whole higher jets require their actual join proof. First-order
piecewise bounds require only the admitted C0 law.

All arithmetic, temporary arrays, retained coefficients, source descent and
queries use one caller work/cell/UInt32-word ledger. Query byte callbacks are
converted by the caller's explicit slot stride. Scalar algebra, source descent
and geometric subdivision retain independent original caps. Numeric positions
are candidates with an explicit position enclosure guard.

## State, Ownership, and Lifecycle

Raw fields and derived join admission are immutable Sendable values. Equality
and codecs retain traversals, stations and original source ordinals; derived
continuity/preparation state is excluded. No private mutable budget exists.
Native encoding has three required fields. Decoding charges unkeyed buffer
growth before allocation and reconstructs the issuer under the decoder's same
original allowance and independent source-depth policy. Certification tolerance
is derived from the first traversal and checked against every traversal.

## Failure, Concurrency, and Constraints

Unequal exact endpoints, unavailable original continuity, nonpositive station
widths, source-depth exhaustion, cancellation and caller resource exhaustion
fail explicitly. Missing nonrational higher join authority remains a precise
capability failure; cached interval equality never substitutes for it.

## Verification and Change Impact

After implementation, verify native and nonnative original guide pieces,
algebraic endpoints, direction changes, multiple pieces of one segment,
nonrepresentable aggregate stations, C0/C1/C2/C3 distinctions, exact event
publication, final Loft correspondence, cancellation and caller exhaustion.
Source authoring alone provides no behavioral completion evidence.

Later selected algebra capabilities are additive on first-order, Taylor,
derivative and owning-piece queries. Every selected retained RootSpan is
re-admitted under the intersection of current and retained algebra caps before
its endpoint localization is consumed. Source depth and geometric subdivision
remain separate. The original owning partition and caller counters are retained.
