# Original Native Curve Chart Cover

## Purpose and Scope

Direct child of [CADGeometry](../DESIGN.md), without children. Owns complete finite selected original B-spline curve chart covers for intersection consumers. Each owner retains the existing original rational homogeneous law and its exact source translation.

## Responsibilities and Boundaries

The issuer owns finite closed source coverage, one-sided native owner identity, source/tolerance binding and independent cycle metadata. It does not solve roots, deduplicate tuples, choose final seam publication owners or authorize smoothness through joins. The existing prepared curve conservative jet issuer retains its separate bounds contract.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original curve source | Composes the finite chart issuer | Parent owns public consumer integration |
| [Periodic B-splines](../PeriodicBSpline/DESIGN.md) | depends on | Original cyclic storage and wrapping period | Retains authored knots and repeated homogeneous controls | Approximate translated-knot validation cannot authorize exact seams |
| [Rational Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | OriginalRationalCurvePolynomial and selected interval jet | Reuses the existing exact source laws | Same caller work and UInt32 storage ledger |
| [Native Surface Chart Cover](../OriginalNativeSurfaceChartCover/DESIGN.md) | coordinates with | Exact source difference arithmetic | Uses the unchanged preparation adapter arithmetic | Curve and tensor tuple identity remain independent |
| [Native CS](../CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | used by | Complete finite chart cover | Curve charts compose with surface charts | Public publication remains the consumer's responsibility |

## Architecture

```text
Original stored curve + finite selected interval + caller admission
    -> source validation -> exact stored period and knot-translation proof
    -> outward finite cycle range -> checked exact endpoint transport
    -> every intersecting positive native span -> existing original rational law
    -> immutable complete cover and source-bound closed owners
```

## Contracts and Invariants

Every intersecting closed native chart is returned. Singleton knots and seams retain both incident one-sided owners; equivalent XYZ does not identify their parameters or cycles. Each chart retains its complete native domain, selected intersection, native index, cycle, exact represented translation, original law and tolerance. Zero-width knot intervals are not charts. Open selected intervals lie inside the original native domain. Periodic selection accepts arbitrary finite widths within caller admission, independently of origin metadata.

The period is the original wrapping subtraction of stored endpoints and must have zero exact-difference tail. Every stored knot a cycle apart must differ by exactly that period. Each integer-cycle product and translated native endpoint must be exactly represented. Approximate translated knots remain unsupported even when source validation accepts them. Neither modeling tolerance, rounded knots, restricted controls nor normalized representative endpoints change source authority. The existing OriginalRationalCurvePolynomial validates every translated law using originalDouble authority and the unchanged source wrapping period.

## Runtime Flows

The issuer validates the source and finite ordered interval, proves the periodic source, computes outward cycle bounds and enumerates all intersecting source spans. Every source visit, cycle, candidate span, original polynomial operation and retained chart is debited to the caller's RationalAlgebraAdmitting owner. Checked capacity growth charges full retained chart storage before allocation. No private span, work, storage or solver allowance is created. Chart evaluation uses the same original rational selected-interval derivative law at exact originalDouble parameters; it does not subtract a rounded base station.

## State, Ownership, and Lifecycle

The complete cover and nested owners are immutable Sendable values. They retain original source and law values after the caller releases or modifies its source copy. Invocation-local arrays and counters have no shared mutable storage or target-specific synchronization. Owner evaluation explicitly validates source, tolerance and selected closed support before using its retained law.

## Failure, Concurrency, and Constraints

Malformed source, invalid finite bounds, foreign source/tolerance, support violations and nonpositive caller span limits fail explicitly. Approximate period/knot transport fails unsupportedCapability. Unrepresentable cycle range, translation, endpoint or allocation arithmetic and caller span exhaustion fail resourceLimitExceeded. Work and storage failures propagate unchanged. Cancellation checks cover source scans, every cycle/chart and the final return after caller callbacks. Failure returns no partial cover. Infinite requests, nonrepresentable transports and other curve families remain separate source domains; this contract does not complete the entire original-domain task.

## Verification and Change Impact

[OriginalNativeCurveChartCoverTests](../../../Tests/CADGeometryTests/OriginalNativeCurveChartCoverTests.swift) verifies literal polynomial and varying-weight rational point/derivative laws, negative/multi-period/reversed/shifted ranges, closed knot/seam owners, retained tuple/cycle metadata, open-domain behavior, malformed/approximate/unrepresentable refusal, foreign authority and independent span/work/storage/cancellation failures. The unchanged prepared closed-native suite owns legacy conservative bounds behavior. Native evidence is limited to this issuer; normal/Embedded WASM and public CS/SSI composition require their own actual runtime evidence.
