import CADCore

/// An exact affine parameterization recognized from one bilinear B-spline
/// patch. The structural proof is independent of modeling tolerance.
struct ExactAffineBSplineSurfacePatch: Sendable {
    let surface: BSplineSurface3D
    let origin: Point3D
    let uDirection: Vector3D
    let vDirection: Vector3D

    init?(_ surface: BSplineSurface3D) {
        guard surface.uDegree == 1,
              surface.vDegree == 1,
              surface.uControlPointCount == 2,
              surface.vControlPointCount == 2,
              Self.isSingleBezierKnotVector(surface.uKnots),
              Self.isSingleBezierKnotVector(surface.vKnots) else {
            return nil
        }
        let weights = surface.weights.flatMap { $0 }
        guard let weight = weights.first,
              weight.isFinite,
              weight > 0.0,
              weights.allSatisfy({ $0 == weight }) else {
            return nil
        }
        let p00 = surface.controlPoints[0][0]
        let p10 = surface.controlPoints[0][1]
        let p01 = surface.controlPoints[1][0]
        let p11 = surface.controlPoints[1][1]
        let exactU = Self.exactDifference(p10, p00)
        let exactV = Self.exactDifference(p01, p00)
        let parallelogramResidual = Self.exactSubtract(
            Self.exactDifference(p11, p10),
            exactV
        )
        guard parallelogramResidual.allSatisfy({
            FloatingPointExpansion.sign($0) == .zero
        }) else {
            return nil
        }
        let gramUU = Self.exactDot(exactU, exactU)
        let gramUV = Self.exactDot(exactU, exactV)
        let gramVV = Self.exactDot(exactV, exactV)
        let determinant = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(gramUU, gramVV),
            FloatingPointExpansion.product(gramUV, gramUV)
        )
        guard FloatingPointExpansion.sign(determinant) == .positive else {
            return nil
        }
        self.surface = surface
        origin = p00
        uDirection = p10 - p00
        vDirection = p01 - p00
    }

    func parameterProjectionResult(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        let offset = point - origin
        let uu = uDirection.dot(uDirection)
        let uv = uDirection.dot(vDirection)
        let vv = vDirection.dot(vDirection)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite,
              determinant > Double.leastNonzeroMagnitude,
              case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An exact affine B-spline patch lost its parameter inverse."
            )
        }
        let offsetU = offset.dot(uDirection)
        let offsetV = offset.dot(vDirection)
        let freeU = (offsetU * vv - offsetV * uv) / determinant
        let freeV = (offsetV * uu - offsetU * uv) / determinant
        var candidates: [(u: Double, v: Double)] = []
        if freeU >= 0.0, freeU <= 1.0,
           freeV >= 0.0, freeV <= 1.0 {
            candidates.append((freeU, freeV))
        }
        for u in [0.0, 1.0] {
            candidates.append((
                u,
                min(max((offsetV - u * uv) / vv, 0.0), 1.0)
            ))
        }
        for v in [0.0, 1.0] {
            candidates.append((
                min(max((offsetU - v * uv) / uu, 0.0), 1.0),
                v
            ))
        }
        let resolved = try candidates.map { candidate in
            let u = uLower + (uUpper - uLower) * candidate.u
            let v = vLower + (vUpper - vLower) * candidate.v
            let projected = try surface.point(u: u, v: v, tolerance: tolerance)
            return (
                u: u,
                v: v,
                point: projected,
                residual: (projected - point).length.nextUp
            )
        }.min { first, second in
            if first.residual != second.residual {
                return first.residual < second.residual
            }
            if first.u != second.u { return first.u < second.u }
            return first.v < second.v
        }
        guard let resolved else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An exact affine B-spline patch produced no projection candidate."
            )
        }
        guard resolved.residual <= tolerance.distance else {
            return .outsideTolerance(residual: resolved.residual)
        }
        return .projected(try SurfaceParameterProjection(
            u: resolved.u,
            v: resolved.v,
            point: resolved.point,
            residual: resolved.residual,
            iterations: 0
        ))
    }

    func unboundedParameterProjectionResult(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        let solution = try normalizedParameters(
            of: point,
            tolerance: tolerance
        )
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An exact affine B-spline patch lost its finite parameter domain."
            )
        }
        let projectedPoint = origin
            + uDirection * solution.u
            + vDirection * solution.v
        let residual = (projectedPoint - point).length.nextUp
        guard residual <= tolerance.distance else {
            return .outsideTolerance(residual: residual)
        }
        return .projected(try SurfaceParameterProjection(
            u: uLower + (uUpper - uLower) * solution.u,
            v: vLower + (vUpper - vLower) * solution.v,
            point: projectedPoint,
            residual: residual,
            iterations: 0
        ))
    }

    private func normalizedParameters(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        let offset = point - origin
        let uu = uDirection.dot(uDirection)
        let uv = uDirection.dot(vDirection)
        let vv = vDirection.dot(vDirection)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite,
              determinant > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An exact affine B-spline patch lost its parameter inverse."
            )
        }
        let offsetU = offset.dot(uDirection)
        let offsetV = offset.dot(vDirection)
        return (
            (offsetU * vv - offsetV * uv) / determinant,
            (offsetV * uu - offsetU * uv) / determinant
        )
    }

    private static func isSingleBezierKnotVector(_ knots: [Double]) -> Bool {
        guard knots.count == 4,
              let lower = knots.first,
              let upper = knots.last,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            return false
        }
        return knots[0] == lower
            && knots[1] == lower
            && knots[2] == upper
            && knots[3] == upper
    }

    private static func exactDifference(
        _ lhs: Point3D,
        _ rhs: Point3D
    ) -> [[Double]] {
        [
            FloatingPointExpansion.difference(lhs.x, rhs.x),
            FloatingPointExpansion.difference(lhs.y, rhs.y),
            FloatingPointExpansion.difference(lhs.z, rhs.z),
        ]
    }

    private static func exactSubtract(
        _ lhs: [[Double]],
        _ rhs: [[Double]]
    ) -> [[Double]] {
        zip(lhs, rhs).map { values in
            FloatingPointExpansion.subtract(values.0, values.1)
        }
    }

    private static func exactDot(
        _ lhs: [[Double]],
        _ rhs: [[Double]]
    ) -> [Double] {
        zip(lhs, rhs).reduce([0.0]) { result, values in
            FloatingPointExpansion.sum(
                result,
                FloatingPointExpansion.product(values.0, values.1)
            )
        }
    }
}
