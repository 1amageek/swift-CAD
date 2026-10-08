import CADCore

extension DefaultSurfaceSurfaceIntersector: NativeExactSurfaceSurfaceIntersecting {
    /// Publishes exact isolated representatives and retains complete original image/fiber strata.
    public func intersectionResult<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox? = nil, secondDomain: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumPolynomialDegree: Int, maximumExtensionLevel: Int,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws -> SurfaceSurfaceIntersectionResult {
        do {
            try options.validate(tolerance: tolerance)
            let geometric = try exactGeometricRelation(first: first, second: second,
                firstDomain: firstDomain, secondDomain: secondDomain, tolerance: tolerance,
                maximumPolynomialDegree: maximumPolynomialDegree, maximumExtensionLevel: maximumExtensionLevel,
                limits: limits, using: &admission)
            return try NativeExactSurfaceSurfacePublisher.publish(geometric,
                options: options, using: &admission)
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }

    public func intersections<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox? = nil, secondDomain: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumPolynomialDegree: Int, maximumExtensionLevel: Int,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws -> [SurfaceSurfaceIntersection] {
        let result = try intersectionResult(first: first, second: second,
            firstDomain: firstDomain, secondDomain: secondDomain, options: options,
            tolerance: tolerance, maximumPolynomialDegree: maximumPolynomialDegree,
            maximumExtensionLevel: maximumExtensionLevel, limits: limits, using: &admission)
        guard result.originalExactGeometricRelation?.hasPositiveDimensionalSolutions == false else {
            throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                message: "The complete exact surface-surface relation is not discrete.")
        }
        do { try admission.checkpoint() }
        catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
        return result.intersections
    }
}
