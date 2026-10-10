extension DefaultCurveSurfaceIntersector: OriginalIssuedGraphResultResolving {
    public typealias IntersectionResult = CurveSurfaceIntersectionResult
    /// Reuses the solved DI-bound relation and publishes every exact contact and image/fiber stratum.
    /// Read `originalIssuedGeometricRelation` for exact points and local/authored parameter correspondence.
    public func intersectionResult<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable, A: ExactScalarAdmission & ~Copyable>(
        exactRelations: borrowing OriginalIssuedGraphRelations<S,E,C,T,F,D>,
        limits: OriginalDomainIdentityLimits, geometryLimits: ExactGeometricRelationLimits,
        maximumPoints: Int, using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> CurveSurfaceIntersectionResult {
        do {
            try admission.checkpoint()
            guard exactRelations.kind == .curveSurface else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            let receipt = try DefaultOriginalIssuedGeometricRelationResolver().resolve(exactRelations, limits: limits,
                geometryLimits: geometryLimits, maximumPoints: maximumPoints, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: [], overlaps: [], originalIssuedGeometricRelation: receipt)
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
