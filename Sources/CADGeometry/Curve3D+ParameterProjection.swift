import Foundation
import CADCore

public extension Curve3D {
    func parameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> CurveParameterProjection {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()

        let candidate: (parameter: Double, iterations: Int)
        switch self {
        case let .line(line):
            candidate = (try lineParameter(point, line: line, options: options, tolerance: tolerance), 0)
        case let .circle(circle):
            let basis = try directCircleBasis(circle.normal, tolerance: tolerance)
            candidate = (
                try periodicParameter(
                    point: point,
                    center: circle.center,
                    firstAxis: basis.u,
                    secondAxis: basis.v,
                    firstRadius: circle.radius,
                    secondRadius: circle.radius,
                    domain: parameterDomain,
                    options: options,
                    tolerance: tolerance
                ),
                0
            )
        case .analytic(.planeTorus), .surfaceLift:
            candidate = try iterativeParameter(
                point,
                options: options,
                tolerance: tolerance
            )
        case let .analytic(curve):
            candidate = try analyticParameter(
                point,
                curve: curve,
                options: options,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            return try curve.parameterProjection(
                of: point,
                options: options,
                tolerance: tolerance
            )
        case .implicit:
            candidate = try iterativeParameter(
                point,
                options: options,
                tolerance: tolerance
            )
        }
        let projectedPoint = try pointAssumingValidated(
            at: candidate.parameter,
            tolerance: tolerance
        )
        let residual = (point - projectedPoint).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Point does not lie on the requested curve within tolerance."
            )
        }
        return try CurveParameterProjection(
            parameter: candidate.parameter,
            point: projectedPoint,
            residual: residual,
            iterations: candidate.iterations
        )
    }

    private func analyticParameter(
        _ point: Point3D,
        curve: AnalyticCurve3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int) {
        switch curve {
        case let .line(origin, direction):
            return (
                try lineParameter(
                    point,
                    line: Line3D(origin: origin, direction: direction),
                    options: options,
                    tolerance: tolerance
                ),
                0
            )
        case let .circle(center, normal, radius):
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            return (
                try periodicParameter(
                    point: point,
                    center: center,
                    firstAxis: basis.u,
                    secondAxis: basis.v,
                    firstRadius: radius,
                    secondRadius: radius,
                    domain: parameterDomain,
                    options: options,
                    tolerance: tolerance
                ),
                0
            )
        case let .arc(center, normal, radius, _, _):
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            return (
                try periodicParameter(
                    point: point,
                    center: center,
                    firstAxis: basis.u,
                    secondAxis: basis.v,
                    firstRadius: radius,
                    secondRadius: radius,
                    domain: parameterDomain,
                    options: options,
                    tolerance: tolerance
                ),
                0
            )
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            let minorAxis = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
            return (
                try periodicParameter(
                    point: point,
                    center: center,
                    firstAxis: majorAxis,
                    secondAxis: minorAxis,
                    firstRadius: majorRadius,
                    secondRadius: minorRadius,
                    domain: parameterDomain,
                    options: options,
                    tolerance: tolerance
                ),
                0
            )
        case let .hyperbola(curve):
            return (
                try curve.parameter(for: point, tolerance: tolerance),
                0
            )
        case let .parabola(curve):
            return (
                try curve.parameter(for: point, tolerance: tolerance),
                0
            )
        case .planeTorus:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Plane-torus curve projection must use the bounded iterative path."
            )
        }
    }

    private func lineParameter(
        _ point: Point3D,
        line: Line3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let denominator = line.direction.dot(line.direction)
        guard denominator > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve projection line direction is degenerate."
            )
        }
        let parameter = (point - line.origin).dot(line.direction) / denominator
        try validate(parameter: parameter, options: options, tolerance: tolerance)
        return parameter
    }

    private func periodicParameter(
        point: Point3D,
        center: Point3D,
        firstAxis: Vector3D,
        secondAxis: Vector3D,
        firstRadius: Double,
        secondRadius: Double,
        domain: ParameterDomain,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let offset = point - center
        var parameter = atan2(
            offset.dot(secondAxis) / secondRadius,
            offset.dot(firstAxis) / firstRadius
        )
        if parameter < 0.0 {
            parameter += 2.0 * Double.pi
        }
        switch domain {
        case let .closed(lower, upper):
            while parameter < lower - tolerance.angle {
                parameter += 2.0 * Double.pi
            }
            while parameter > upper + tolerance.angle {
                parameter -= 2.0 * Double.pi
            }
        case .periodic, .unbounded:
            break
        }
        if let parameterRange = options.parameterRange {
            let period = 2.0 * Double.pi
            parameter += ((parameterRange.midpoint - parameter) / period).rounded() * period
            if parameter < parameterRange.lower - tolerance.angle {
                parameter += period
            } else if parameter > parameterRange.upper + tolerance.angle {
                parameter -= period
            }
        }
        try validate(parameter: parameter, options: options, tolerance: tolerance)
        return parameter
    }

    private func iterativeParameter(
        _ point: Point3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int) {
        let interval = try resolvedProjectionInterval(options: options, tolerance: tolerance)
        var bestParameter = interval.lower
        var bestSquaredDistance = Double.infinity
        for parameter in try projectionSeedParameters(
            interval: interval,
            options: options,
            tolerance: tolerance
        ) {
            let candidate = try pointAssumingValidated(
                at: parameter,
                tolerance: tolerance
            )
            let offset = candidate - point
            let squaredDistance = offset.dot(offset)
            if squaredDistance < bestSquaredDistance {
                bestSquaredDistance = squaredDistance
                bestParameter = parameter
            }
        }

        var parameter = bestParameter
        var completedIterations = 0
        for iteration in 0..<options.maximumIterations {
            completedIterations = iteration + 1
            let geometry = try differentialGeometryAssumingValidated(
                at: parameter,
                tolerance: tolerance
            )
            let offset = geometry.position - point
            let numerator = offset.dot(geometry.firstDerivative)
            let denominator = geometry.firstDerivative.dot(geometry.firstDerivative)
                + offset.dot(geometry.secondDerivative)
            guard abs(denominator) > tolerance.angle else { break }
            let updated = min(max(parameter - numerator / denominator, interval.lower), interval.upper)
            if abs(updated - parameter) <= max(tolerance.angle, Double.ulpOfOne * 16.0) {
                parameter = updated
                break
            }
            parameter = updated
        }
        try validate(parameter: parameter, options: options, tolerance: tolerance)
        return (parameter, completedIterations)
    }

    private func projectionSeedParameters(
        interval: ScalarInterval,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard case let .bSpline(curve) = self else {
            return (0...options.seedCount).map { index in
                interval.lower + interval.width * Double(index)
                    / Double(options.seedCount)
            }
        }

        var boundaries = [interval.lower]
        for knot in curve.knots where knot > interval.lower && knot < interval.upper {
            if knot - (boundaries.last ?? interval.lower) > tolerance.angle {
                boundaries.append(knot)
            }
        }
        if interval.upper - (boundaries.last ?? interval.lower) > tolerance.angle {
            boundaries.append(interval.upper)
        } else {
            boundaries[boundaries.count - 1] = interval.upper
        }
        let spanCount = boundaries.count - 1
        guard spanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline curve projection has no non-degenerate knot span."
            )
        }
        let minimumSeedsPerSpan = 8
        let seedsPerSpan = max(
            minimumSeedsPerSpan,
            Int(ceil(Double(options.seedCount) / Double(spanCount)))
        )
        let totalSeedIntervals = spanCount * seedsPerSpan
        guard totalSeedIntervals <= 65_536 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "B-spline curve projection exceeded its knot-span seed limit."
            )
        }

        var result = [interval.lower]
        result.reserveCapacity(totalSeedIntervals + 1)
        for index in 1..<boundaries.count {
            let lower = boundaries[index - 1]
            let upper = boundaries[index]
            for subdivision in 1...seedsPerSpan {
                result.append(
                    lower + (upper - lower) * Double(subdivision)
                        / Double(seedsPerSpan)
                )
            }
        }
        return result
    }

    private func pointAssumingValidated(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch self {
        case let .bSpline(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .implicit(curve):
            return try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case .line, .circle, .analytic, .surfaceLift:
            return try point(at: parameter, tolerance: tolerance)
        }
    }

    private func differentialGeometryAssumingValidated(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Curve3D.DifferentialGeometry {
        switch self {
        case let .bSpline(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            return Curve3D.DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tangent: geometry.tangent,
                curvatureVector: geometry.curvatureVector,
                curvature: geometry.curvature
            )
        case let .implicit(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            let tangent = try geometry.firstDerivative.normalized(
                tolerance: tolerance.distance
            )
            let speed = geometry.firstDerivative.length
            let tangentialAcceleration = tangent * geometry.secondDerivative.dot(tangent)
            let curvatureVector = (geometry.secondDerivative - tangentialAcceleration)
                / (speed * speed)
            return Curve3D.DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tangent: tangent,
                curvatureVector: curvatureVector,
                curvature: curvatureVector.length
            )
        case .line, .circle, .analytic, .surfaceLift:
            return try differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
        }
    }

    private func resolvedProjectionInterval(
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let parameterRange = options.parameterRange {
            return parameterRange
        }
        switch parameterDomain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Unbounded iterative curve projection requires an explicit parameter range."
            )
        }
    }

    private func validate(
        parameter: Double,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws {
        let isInsideRequestedRange: Bool
        if let parameterRange = options.parameterRange {
            let parameterTolerance = max(tolerance.distance, tolerance.angle)
            isInsideRequestedRange = parameter >= parameterRange.lower - parameterTolerance
                && parameter <= parameterRange.upper + parameterTolerance
        } else {
            isInsideRequestedRange = true
        }
        guard parameter.isFinite,
              try parameterDomain.contains(parameter, tolerance: tolerance),
              isInsideRequestedRange else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Curve parameter projection lies outside the requested domain."
            )
        }
    }

    private func directCircleBasis(
        _ normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let normalized = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalized.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normalized).normalized(tolerance: tolerance.distance)
        return (u, normalized.cross(u))
    }
}
