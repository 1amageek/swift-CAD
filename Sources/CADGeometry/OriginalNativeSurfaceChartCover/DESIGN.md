# Original Native Surface Chart Cover

## Purpose and Scope

Direct child of [CADGeometry](../DESIGN.md), without children. Owns complete finite selected original-native tensor chart covers for intersection consumers. The preparation adapter retains the original homogeneous spans and issues exact cycle transports.

## Responsibilities and Boundaries

The returned immutable token array covers the requested closed box and retains original source, preparation tolerance, native span indices, and independent U/V cycle metadata. It owns finite coverage, not root solving or publication deduplication. The existing mesh issuer retains its one-period and bounded-candidate policy.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original native preparation | Immutable original source spans | Parent owns consumer integration |
| [Original Rectangle Tessellation](../OriginalRectangleTessellation/DESIGN.md) | depends on | Selected span tokens | Retains original homogeneous coefficient authority | Does not widen mesh admission |
| [Periodic B-splines](../PeriodicBSpline/DESIGN.md) | depends on | Original cyclic storage | Original knots and repeated controls | Approximate knot validation does not prove exact transport |
| [Native SSI](../NativeSurfaceSurfacePointRelations/DESIGN.md) | used by | Finite chart coverage | Each tuple keeps its source and cycle | Consumer owns exact right-owner publication |
| [Native CS](../CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | used by | Finite chart coverage | Closed chart owners supply source laws | Same XYZ does not identify parameters |

## Architecture

```text
Original source -> prepared original homogeneous spans
Selected finite box -> outward cycle bounds -> checked exact transports
    -> all intersecting closed native owners -> immutable complete cover
```

## Contracts and Invariants

`originalIntersectionNativeSpans` shares preparation and authority checks with the legacy mesh issuer, admitting any finite selected width within caller work, byte and aggregate span limits. The existing 262,144 span ceiling is shared across all lifted owners. Outward quotient bounds include all incident seam cycles. A period must have zero exact-difference tail; every translated stored knot must have exactly the same period. Each cycle product and each transported closed span endpoint must be exactly represented. No rounded endpoint, canonical origin, or modeling tolerance changes this authority. Source-valid approximate translated knots remain explicitly unsupported. Every closed seam/singleton retains both incident owners per axis; tensor corners retain their product. Cycle metadata distinguishes repeated parameter preimages.

## Runtime Flows

Preparation validates and retains the source once. Selection checks closed finite domains and preparation tolerance, proves each periodic axis, enumerates finite checked cycles, and intersects every original tensor span. Caller work is charged for knot visits, cycles, span scans, and retained owners. Caller bytes admit each axis-lift and span capacity allocation before allocation. Only the complete returned array publishes authority; any failure abandons the value-local partial arrays.

## State, Ownership, and Lifecycle

The token array and tokens are immutable Sendable values. Array storage uses existing value ownership. No shared mutable state, conditional synchronization, or mutable cache is added. Source, tolerance and exact cycle metadata remain retained after caller source release.

## Failure, Concurrency, and Constraints

Invalid domains, tolerance mismatch and invalid ceilings fail explicitly. Approximate source periods fail unsupportedCapability. Unrepresentable cycles, translations, endpoints and exhausted aggregate span limits fail resourceLimitExceeded. Independent caller work and byte failures propagate unchanged. Cancellation checks include the final publication boundary after callbacks. True infinite covers, nonrepresentable transports, analytic poles and broader periodic algebra are outside this finite exact-transport subset.

## Verification and Change Impact

[OriginalNativeSurfaceChartCoverTests](../../../Tests/CADGeometryTests/OriginalNativeSurfaceChartCoverTests.swift) owns multi-period/reversed/shifted selected coverage, literal original point/jet evaluation, singleton seam owners, tuple/cycle metadata, independent work/bytes/span refusals, cancellation and foreign source/tolerance/domain refusal. [OriginalPeriodicC0TessellationTests](../../../Tests/CADGeometryTests/OriginalPeriodicC0TessellationTests.swift) keeps legacy width and exact-source refusal behavior. CS/SSI integration must separately verify original field transport and public complete tuple publication; lower-cover success alone does not complete those consumers or the whole periodic work item.

Native verification on Swift 6.4.0 release compiles and links the complete CADCore/CADGeometry source modules, then executes all three lower-owner suites: 16 test declarations, 66 parameterized cases, 0.296 seconds runtime. The new suite contributes 17 cases; unchanged C0 and mixed owner suites contribute 49. This evidence covers Native lower chart issuance and selected original evaluation only; WASM/Embedded and public CS/SSI composition remain separate verification owners.
