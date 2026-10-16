import CADCore

/// An exact affine parameterization recognized from one bilinear B-spline
/// patch. The structural proof is independent of modeling tolerance.
struct ExactAffineBSplineSurfacePatch: Sendable {
    let surface: BSplineSurface3D
    let origin: Point3D
    let uDirection: Vector3D
    let vDirection: Vector3D

    init?(_ surface: BSplineSurface3D) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(surface, using: &execution)
    }

    init?<A: ExactScalarAdmission & ~Copyable>(_ surface: BSplineSurface3D,
        using execution: inout A) throws {
        try execution.consumeWork(1)
        guard surface.uDegree == 1,
              surface.vDegree == 1,
              surface.uControlPointCount == 2,
              surface.vControlPointCount == 2,
              Self.isSingleBezierKnotVector(surface.uKnots),
              Self.isSingleBezierKnotVector(surface.vKnots) else {
            return nil
        }
        let weights = try OriginalCoefficientAllocation.flatten(rows: surface.weights, using: &execution)
        guard let weight = weights.first,
              weight.isFinite,
              weight > 0.0,
              try weights.allSatisfy({ try execution.consumeWork(1); return $0 == weight }) else {
            return nil
        }
        let p00 = surface.controlPoints[0][0]
        let p10 = surface.controlPoints[0][1]
        let p01 = surface.controlPoints[1][0]
        let p11 = surface.controlPoints[1][1]
        let exactU = try Self.exactDifference(p10, p00, using: &execution)
        let exactV = try Self.exactDifference(p01, p00, using: &execution)
        let parallelogramResidual = try Self.exactSubtract(
            try Self.exactDifference(p11, p10, using: &execution),
            exactV, using: &execution
        )
        guard try parallelogramResidual.allSatisfy({
            try execution.consumeWork(1)
            return try FloatingPointExpansion.sign($0, using: &execution) == .zero
        }) else {
            return nil
        }
        let gramUU = try Self.exactDot(exactU, exactU, using: &execution)
        let gramUV = try Self.exactDot(exactU, exactV, using: &execution)
        let gramVV = try Self.exactDot(exactV, exactV, using: &execution)
        let determinant = try FloatingPointExpansion.subtract(
            try FloatingPointExpansion.product(gramUU, gramVV, using: &execution),
            try FloatingPointExpansion.product(gramUV, gramUV, using: &execution), using: &execution
        )
        guard try FloatingPointExpansion.sign(determinant, using: &execution) == .positive else {
            return nil
        }
        self.surface = surface
        origin = p00
        uDirection = p10 - p00
        vDirection = p01 - p00
    }

    func parameterProjectionResult(of point: Point3D, tolerance: ModelingTolerance) throws -> SurfaceParameterProjectionResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterProjectionResult(of: point, tolerance: tolerance, using: &execution)
    }

    func parameterProjectionResult<A: ExactScalarAdmission & ~Copyable>(
        of point: Point3D, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> SurfaceParameterProjectionResult {
        try execution.consumeWork(1)
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
        try OriginalCoefficientAllocation.reserve(count: 5, of: (u: Double, v: Double).self, using: &execution)
        var candidates: [(u: Double, v: Double)] = []; candidates.reserveCapacity(5)
        if freeU >= 0.0, freeU <= 1.0,
           freeV >= 0.0, freeV <= 1.0 {
            candidates.append((freeU, freeV))
        }
        for index in 0..<2 {
            try execution.consumeWork(1)
            let u = Double(index)
            candidates.append((
                u,
                min(max((offsetV - u * uv) / vv, 0.0), 1.0)
            ))
        }
        for index in 0..<2 {
            try execution.consumeWork(1)
            let v = Double(index)
            candidates.append((
                min(max((offsetU - v * uv) / uu, 0.0), 1.0),
                v
            ))
        }
        let resolved = try OriginalCoefficientAllocation.map(elements: candidates, using: &execution) { candidate, execution in
            let u = uLower + (uUpper - uLower) * candidate.u
            let v = vLower + (vUpper - vLower) * candidate.v
            let projected = try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
            return (
                u: u,
                v: v,
                point: projected,
                residual: (projected - point).length.nextUp
            )
        }.min { first, second in
            try execution.consumeWork(1)
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

    func unboundedParameterProjectionResult(of point: Point3D, tolerance: ModelingTolerance) throws -> SurfaceParameterProjectionResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try unboundedParameterProjectionResult(of: point, tolerance: tolerance, using: &execution)
    }

    func unboundedParameterProjectionResult<A: ExactScalarAdmission & ~Copyable>(
        of point: Point3D, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> SurfaceParameterProjectionResult {
        try execution.consumeWork(1)
        let solution = try normalizedParameters(
            of: point,
            tolerance: tolerance, using: &execution
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

    private func normalizedParameters<A: ExactScalarAdmission & ~Copyable>(
        of point: Point3D, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> (u: Double, v: Double) {
        try execution.consumeWork(1)
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

    private static func exactDifference<A: ExactScalarAdmission & ~Copyable>(
        _ lhs: Point3D, _ rhs: Point3D, using execution: inout A
    ) throws -> [[Double]] {
        try OriginalCoefficientAllocation.reserve(count: 3, of: [Double].self, using: &execution)
        return [
            try FloatingPointExpansion.difference(lhs.x, rhs.x, using: &execution),
            try FloatingPointExpansion.difference(lhs.y, rhs.y, using: &execution),
            try FloatingPointExpansion.difference(lhs.z, rhs.z, using: &execution),
        ]
    }

    private static func exactSubtract<A: ExactScalarAdmission & ~Copyable>(
        _ lhs: [[Double]], _ rhs: [[Double]], using execution: inout A
    ) throws -> [[Double]] {
        try OriginalCoefficientAllocation.map(first: lhs, second: rhs, using: &execution) { values, execution in
            try FloatingPointExpansion.subtract(values.0, values.1, using: &execution)
        }
    }

    private static func exactDot<A: ExactScalarAdmission & ~Copyable>(
        _ lhs: [[Double]], _ rhs: [[Double]], using execution: inout A
    ) throws -> [Double] {
        try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
        var result = [0.0]
        for values in zip(lhs, rhs) {
            try execution.consumeWork(1)
            let product = try FloatingPointExpansion.product(values.0, values.1, using: &execution)
            result = try FloatingPointExpansion.sum(result, product, using: &execution)
        }
        return result
    }
}
