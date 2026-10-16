# Original Guide Endpoint Correction

## Purpose and Scope

This child of [Original Endpoint Connector](../DESIGN.md) owns an original guide
curve with exact original section endpoint expressions. It has no children.
Tolerance-admissible guide contacts are preserved without strengthening their
admission to exact spatial incidence.

## Responsibilities and Boundaries

The original law is G(t)+(A-G(0))*(1-h(t))+(B-G(1))*h(t), where G is the retained
normalized original RootSpan and A/B are retained section traversal endpoints.
The correction basis belongs to the parent. Endpoint differences are original
source expressions. Interval caches enclose them and never become rounded
coefficients. Loft owns final source-versus-source and candidate fidelity,
support continuity, embedding and topology publication. Shared Geometry owns
dispatch and retained endpoint peeling.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Endpoint Connector](../DESIGN.md) | parent | Authored correction polynomial | Same endpoint basis | Source guide replaces a construction net |
| [Root Span](../../../OriginalRootSpan/DESIGN.md) | depends on | Original directed parameter and endpoints | Three immutable traversals | Preserve source and algebra caps |
| [Guide Chain](../../GuideTraversalChain/DESIGN.md) | depends on | One-sided original guide pieces | C0 guide law | Derivative hulls do not prove joins |
| [Loft](../../../../CADModeling/Loft/DESIGN.md) | used by | Corrected final guide boundary | Exact section corners | Fresh fidelity to the original guide |

## Architecture

```text
original guide G + original section endpoint A/B + correction basis
    -> same-ledger endpoint enclosures
    -> original endpoint-difference polynomial law
    -> exact endpoint reference / original interval D0-D3
    -> full unchanged original-guide fidelity
    -> fresh candidate certificate -> exact corner/continuity/embedding -> Loft
```

## Contracts and Invariants

The corrected chart is normalized [0,1]. Its source RootSpan retains G's
original native parameter map. Position at literal zero/one is the corresponding
original section endpoint expression. The whole interior and derivatives use
the same correction polynomial. A singleton endpoint override never repairs a
different interior law. C0-only joins retain one-sided owning jets separately.
Higher whole jets require the original guide's actual requested continuity.
Smooth native interval admission delegates to that retained original source;
the endpoint correction is a globally smooth polynomial and introduces no join.

Corrected publication requires full position/tangent/curvature correspondence
against G under the existing requirements. Neither a shared candidate nor
triangle estimates from certificates with larger cumulative error replaces
this certificate. Plane derivative refinements additionally preserve that
same guide fidelity.

## State, Ownership, and Lifecycle

Six raw fields are source, startBoundary, startAtEnd, endBoundary, endAtEnd and
correctionBasis. Derived endpoint enclosures and capabilities are immutable
caches excluded from equality, hashing and Native serialization. All query
work/storage bytes and exact words belong to the same caller invocation.

## Failure, Concurrency, and Constraints

Source, scalar algebra and geometric subdivision have independent retained
caps. A later selected algebra cap re-admits all three retained RootSpans before
using endpoint caches; their earlier construction authority never authorizes
a stricter query. Re-admission retains the same counters and existing roots.
Source-depth exhaustion, unavailable C0/owning law, changed tolerance,
cancellation and cumulative resource exhaustion are typed failures. Original
endpoint differences are not replaced by midpoint constants on any failure.

## Verification and Change Impact

Deferred verification covers nonzero tolerance contacts, irrational endpoints,
interior and one-sided derivative bounds, all correction bases, strict final
plane constraints, original-guide fidelity, exact shared corner identity,
serialization, cancellation and cumulative limits. Curve dispatch, source
validation, portable encoding and final Loft consumers must use the raw law.
Source authoring alone establishes no behavioral completion.


## Direct Query Execution Ownership

This component follows the [module direct execution contract](../../../DESIGN.md) through its existing owner hierarchy. High-level retained geometry preparation and queries borrow the same concrete `OriginalQueryExecution`; pure original rational/source arithmetic borrows generic `ExactScalarAdmission & ~Copyable`. Original corner, join, supporting-plane, native adjacent-chart and M6 guard proofs retain their existing mathematics and authority. Work/storage callbacks, private borrowed ledgers and private allowances are removed rather than reconstructed. Explicit source/span/geometric policies remain independent of scalar proof ceilings; optional scalar caps create local proof scopes on the same owner. Actual typed retained buffers and actual loops are charged before their operation, without proxy prepayment. Ordinary roots invoke the same body once; retained readers keep immutable source/policy/common budget and re-admit actual proof evidence for later queries.

Focused syntax parsing only establishes preparatory source validity. Existing behavioral tests and M6/source-proof receipts require the new direct implementation path to compile and execute before this migration is complete.
