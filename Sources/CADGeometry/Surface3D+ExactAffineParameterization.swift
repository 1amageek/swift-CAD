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
        case let .procedural(.originalImage(image)):
            return image.source.hasExactAffineParameterization
        case let .procedural(.offset(surface)):
            return surface.source.hasExactAffineParameterization
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted), .procedural(.originalAngularTransport), .procedural(.originalAffineWord):
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
        case let .procedural(.originalImage(image)):
            guard image.source.hasExactAffineParameterization else { return nil }
            let base = try image.parameterDerivatives(u: 0, v: 0, tolerance: tolerance)
            let offset = point - base.position
            let uu = base.tangentU.dot(base.tangentU), uv = base.tangentU.dot(base.tangentV)
            let vv = base.tangentV.dot(base.tangentV), determinant = uu * vv - uv * uv
            guard determinant.isFinite, determinant > 0 else {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                    message: "Original affine image parameter frame is singular.")
            }
            let u = (offset.dot(base.tangentU) * vv - offset.dot(base.tangentV) * uv) / determinant
            let v = (offset.dot(base.tangentV) * uu - offset.dot(base.tangentU) * uv) / determinant
            let projected = base.position + base.tangentU * u + base.tangentV * v
            let residual = (point - projected).length
            return residual <= tolerance.distance ? .projected(try .init(u: u, v: v,
                point: projected, residual: residual)) : .outsideTolerance(residual: residual)

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
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted), .procedural(.originalAngularTransport), .procedural(.originalAffineWord):
            return nil
        }
    }
}
