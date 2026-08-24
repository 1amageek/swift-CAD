import CADCore

extension Surface3D {
    /// Reports whether the surface owns an exact affine map from its
    /// parameter plane to 3D space.
    package var hasExactAffineParameterization: Bool {
        switch self {
        case .plane, .analytic(.plane):
            return true
        case let .bSpline(surface):
            return ExactAffineBSplineSurfacePatch(surface) != nil
        case .cylinder, .analytic:
            return false
        case let .procedural(.offset(surface)):
            return surface.source.hasExactAffineParameterization
        case .procedural(.ruled):
            return false
        }
    }

    /// Projects through the unbounded affine support, allowing control
    /// geometry outside a bounded surface domain to retain its exact map.
    package func exactAffineParameterProjectionResult(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult? {
        try validate(tolerance: tolerance)
        try point.validate()
        switch self {
        case .plane, .analytic(.plane):
            return try parameterProjectionResult(
                of: point,
                tolerance: tolerance
            )
        case let .bSpline(surface):
            return try ExactAffineBSplineSurfacePatch(surface)?
                .unboundedParameterProjectionResult(
                    of: point,
                    tolerance: tolerance
                )
        case .cylinder, .analytic:
            return nil
        case let .procedural(.offset(surface)):
            guard surface.source.hasExactAffineParameterization else {
                return nil
            }
            return try parameterProjectionResult(
                of: point,
                tolerance: tolerance
            )
        case .procedural(.ruled):
            return nil
        }
    }
}
