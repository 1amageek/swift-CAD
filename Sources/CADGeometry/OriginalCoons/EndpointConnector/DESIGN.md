# Original Endpoint Connector

## Purpose and Scope

This child of [Original Coons](../DESIGN.md) retains generated connector geometry
whose endpoints are original directed curve expressions. Its child is
[Guide Correction](GuideCorrection/DESIGN.md).
A construction B-spline is a candidate and the original generated interior law;
its endpoint labels do not replace the original section endpoint expressions.

## Responsibilities and Boundaries

The connector owns the source law C(t)+(A-C(0))*h0(t)+(B-C(1))*h1(t). A and B
retain their original traversal and endpoint side. Linear, cubic Hermite and
quintic Hermite correction bases respectively preserve value, first derivative,
and first plus second derivative constraints of the generated construction.
Source endpoint/chart production belongs to Original Root Span. Construction
fidelity and topology publication belong to Loft and its consumers.

The [Guide Correction](GuideCorrection/DESIGN.md) child applies the same endpoint
polynomial to an original guide traversal instead of a native construction net.
Its independent source-versus-source fidelity certificate retains the original
guide's unchanged positional, tangent and curvature requirements.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Original Coons](../DESIGN.md) | parent | Four original boundaries and corner incidence | Adjacent charts share this connector | A candidate endpoint cannot establish original incidence |
| [Original Root Span](../../OriginalRootSpan/DESIGN.md) | depends on | Retained exact endpoint expression, bounded jets | Original endpoint and construction evaluation | Original caps and source side are retained |
| [Loft](../../../CADModeling/Loft/DESIGN.md) | used by | Final chart and generated connector publication | Supplies actual original section endpoints | Nonrepresentable interior endpoints require an exact chart carrier |

## Architecture

```text
construction source + two original endpoint expressions + correction basis
    -> caller-paid endpoint preparation
    -> immutable connector source
        -> whole original Taylor product law
        -> structural endpoint expression at t=0/1
    -> curve dispatch -> original Coons and topology publication
```

## Contracts and Invariants

The original parameter domain is [0,1]. The construction has that exact finite
domain and one immutable tolerance. The polynomial basis is formed from exact
binary integer coefficients. At endpoints the position enclosure is the
retained endpoint expression directly; interval cancellation is not endpoint
incidence evidence. The piecewise first-order path consumes the retained construction D0/D1 hull
and the polynomial correction directly, preserving C0-only construction joins
without demanding higher continuity. Closed owning jets apply the correction independently to every retained
construction owner, preserving its native index/domain and selected parameter
range. They never replace one-sided ownership with a hull continuity claim.
Positional continuity requires the
original construction traversal's own C0 admission.
Interior derivatives consume the whole corrected source
law, with no fitted or rounded coefficient substitution. Numeric representatives
are candidates and must meet the unchanged position error admission.

All scalar work, retained endpoint bounds, native preparation and Taylor
allocation bytes charge the same caller. Byte-to-storage conversion explicitly
uses the composing owner's stride; canonical exact callers use UInt32 words.
Source recursion and geometric subdivision remain separate. No private budget,
refund, source-depth reset or midpoint endpoint authority is introduced.

## State, Ownership, and Lifecycle

Original source fields and prepared endpoint/construction values are immutable.
Equality and hashing use the source fields, excluding derived caches.
Native serialization requires exactly the six source fields and uses the
existing decoder-owned allowance for constructor preparation; it serializes
neither endpoint interval caches nor a fresh private budget. The
source retains every endpoint expression throughout the connector's lifetime.
There is no mutable target-specific state.

## Failure, Concurrency, and Constraints

Mismatched tolerances, invalid construction domains, unavailable original
endpoint queries, insufficient remaining caps, nonfinite coefficients,
cancellation and exhausted cumulative reservations throw typed errors.

## Verification and Change Impact

Deferred behavior must cover native/angular/algebraic original endpoints,
nonrepresentable endpoint positions, all three correction bases, interior and
endpoint derivative bounds, shared seam incidence, serialization source
preservation, cancellation and exhaustion. Parent curve dispatch and actual
Loft edge/side publication must consume this law. Source authoring alone is
not completed behavioral evidence.
