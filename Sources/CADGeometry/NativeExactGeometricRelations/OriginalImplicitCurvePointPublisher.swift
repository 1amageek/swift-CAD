import CADCore

/// Adapts source-proved implicit forward laws to shared certified scalar publication.
struct OriginalImplicitCurvePointPublisher<T: Sendable,F: Sendable,D: Sendable> {
    typealias Cover = OriginalCompleteCurveGraphDomainCover<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,OriginalImplicitCurveGraphReduction>
    typealias Geometry = OriginalIssuedGeometricRelations<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,Cover,T,F,D>

    func publish<A: ExactScalarAdmission & ~Copyable>(_ geometry: Geometry,
        field: OriginalExactScalarDomain, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits, maximumDepth: Int,
        using admission: inout A
    ) throws -> (points: [CurveSurfaceIntersection], receipt: OriginalIssuedNumericalCurveSurfacePoints) {
        try OriginalRationalGraphPointPublisher<OriginalImplicitCurveSnapshot,OriginalImplicitCurveGraphEvidence,Cover,T,F,D>()
            .publish(geometry, field: field, options: options, tolerance: tolerance, limits: limits,
                maximumDepth: maximumDepth, curveEvaluator: OriginalImplicitCurvePointEvaluator(reduction: geometry.original.first.coverage.family.coverage),
                using: &admission)
    }
}
