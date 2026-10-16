import CADCore

extension Surface3D {
    /// Reports whether the surface owns an exact affine map from its
    /// parameter plane to 3D space.
    package var hasExactAffineParameterization: Bool {
        get throws {
            var execution = try OriginalQueryExecution.independentGeometry()
            return try hasExactAffineParameterization(using: &execution)
        }
    }

    package func hasExactAffineParameterization<A: ExactScalarAdmission & ~Copyable>(
        using execution: inout A) throws -> Bool {
        try execution.consumeWork(1)
        switch self {
        case .plane, .analytic(.plane):
            return true
        case let .bSpline(surface):
            return try ExactAffineBSplineSurfacePatch(surface, using: &execution) != nil
        case .cylinder, .analytic:
            return false
        case let .procedural(.originalImage(image)):
            return try image.source.hasExactAffineParameterization(using: &execution)
        case let .procedural(.offset(surface)):
            return try surface.source.hasExactAffineParameterization(using: &execution)
        case .procedural(.originalAffineWord), .procedural(.originalAngularTransport), .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return false
        }
    }

    /// Projects through the unbounded affine support, allowing control
    /// geometry outside a bounded surface domain to retain its exact map.
    package func exactAffineParameterProjectionResult(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try exactAffineParameterProjectionResult(of: point, tolerance: tolerance, using: &execution)
    }

    package func exactAffineParameterProjectionResult(of point: Point3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SurfaceParameterProjectionResult? {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        try point.validate()
        switch self {
        case let .procedural(.originalImage(image)):
            guard try image.source.hasExactAffineParameterization(using: &execution) else { return nil }
            let base = try image.parameterDerivatives(u: 0, v: 0, tolerance: tolerance, using: &execution)
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
                tolerance: tolerance, using: &execution
            )
        case let .bSpline(surface):
            return try ExactAffineBSplineSurfacePatch(surface, using: &execution)?
                .unboundedParameterProjectionResult(
                    of: point,
                    tolerance: tolerance, using: &execution
                )
        case .cylinder, .analytic:
            return nil
        case let .procedural(.offset(surface)):
            guard try surface.source.hasExactAffineParameterization(using: &execution) else {
                return nil
            }
            return try parameterProjectionResult(
                of: point,
                tolerance: tolerance, using: &execution
            )
        case .procedural(.originalAffineWord), .procedural(.originalAngularTransport), .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return nil
        }
    }
}
