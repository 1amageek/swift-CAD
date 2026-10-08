import CADCore

extension DefaultCurveSurfaceIntersector: NativeExactCurveSurfaceIntersecting {
    /// Publishes one original L5/L6 relation with explicit caller-owned exact limits.
    public func intersectionResult<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws -> CurveSurfaceIntersectionResult {
        do {
            return try NativeExactCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
                options: options, tolerance: tolerance, maximumExtensionLevel: maximumExtensionLevel,
                limits: limits, using: &admission)
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }

    /// A positive source relation is never reduced to its isolated numerical representatives.
    public func intersections<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws -> [CurveSurfaceIntersection] {
        let result = try intersectionResult(curve: curve, surface: surface, options: options,
            tolerance: tolerance, maximumExtensionLevel: maximumExtensionLevel,
            limits: limits, using: &admission)
        guard !result.hasPositiveDimensionalSolutions else {
            throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                message: "The complete exact curve-surface relation is not discrete.")
        }
        do { try admission.checkpoint() }
        catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
        return result.points
    }
}
