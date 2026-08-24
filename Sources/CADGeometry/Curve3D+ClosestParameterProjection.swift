import CADCore
import Foundation

public extension Curve3D {
    /// Returns a globally certified closest point over a finite curve interval.
    func closestParameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterProjection {
        try closestParameterProjection(
            of: point,
            options: options,
            positionEncloser: DefaultCurvePositionEncloser(),
            tolerance: tolerance
        )
    }

    package func closestParameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions,
        positionEncloser: any CurvePositionEnclosing,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterProjection {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()

        struct Cell {
            let interval: ScalarInterval
            let depth: Int
        }

        let interval = try closestProjectionInterval(
            options: options,
            tolerance: tolerance
        )
        var best = try closestProjectionWitness(
            initialParameter: interval.midpoint,
            interval: interval,
            point: point,
            maximumIterations: options.maximumIterations,
            tolerance: tolerance
        )
        for endpoint in [interval.lower, interval.upper] {
            let candidate = try closestProjectionWitness(
                initialParameter: endpoint,
                interval: interval,
                point: point,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            )
            if candidate.residual < best.residual
                || candidate.residual == best.residual
                    && candidate.parameter < best.parameter {
                best = candidate
            }
        }

        var remainingCells = options.maximumSubdivisionCells
        var pending = [Cell(interval: interval, depth: 0)]
        while let cell = pending.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: best.residual,
                    tolerance: tolerance,
                    message: "Closest curve projection exceeded its certified cell budget."
                )
            }
            remainingCells -= 1
            let enclosure = try positionEncloser.enclosure(
                of: self,
                over: cell.interval,
                tolerance: tolerance
            )
            let lowerBound = closestProjectionDistanceLowerBound(
                from: point,
                to: enclosure
            )
            if lowerBound + tolerance.distance >= best.residual {
                continue
            }
            let witness = try closestProjectionWitness(
                initialParameter: cell.interval.midpoint,
                interval: cell.interval,
                point: point,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            )
            if witness.residual < best.residual
                || witness.residual == best.residual
                    && witness.parameter < best.parameter {
                best = witness
            }
            if lowerBound + tolerance.distance >= best.residual {
                continue
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(0.0, best.residual - lowerBound),
                    tolerance: tolerance,
                    message: "Closest curve projection did not close its global distance bound."
                )
            }
            let middle = cell.interval.midpoint
            guard middle > cell.interval.lower,
                  middle < cell.interval.upper else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(0.0, best.residual - lowerBound),
                    tolerance: tolerance,
                    message: "Closest curve projection reached floating-point subdivision resolution."
                )
            }
            let depth = cell.depth + 1
            pending.append(Cell(
                interval: try ScalarInterval(
                    lower: middle,
                    upper: cell.interval.upper
                ),
                depth: depth
            ))
            pending.append(Cell(
                interval: try ScalarInterval(
                    lower: cell.interval.lower,
                    upper: middle
                ),
                depth: depth
            ))
        }

        return try CurveParameterProjection(
            parameter: best.parameter,
            point: best.point,
            residual: best.residual,
            iterations: best.iterations
        )
    }

    private func closestProjectionInterval(
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let interval: ScalarInterval
        if let requested = options.parameterRange {
            interval = requested
        } else {
            switch parameterDomain {
            case let .closed(lower, upper):
                interval = try ScalarInterval(lower: lower, upper: upper)
            case let .periodic(period):
                interval = try ScalarInterval(lower: 0.0, upper: period)
            case .unbounded:
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Closest projection on an unbounded curve requires a finite parameter range."
                )
            }
        }
        guard try parameterDomain.containsSpan(
            from: interval.lower,
            to: interval.upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closest curve projection range lies outside the curve domain."
            )
        }
        return interval
    }

    private func closestProjectionWitness(
        initialParameter: Double,
        interval: ScalarInterval,
        point: Point3D,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> (
        parameter: Double,
        point: Point3D,
        residual: Double,
        iterations: Int
    ) {
        var parameter = min(max(
            initialParameter,
            interval.lower
        ), interval.upper)
        var completedIterations = 0
        for iteration in 0..<maximumIterations {
            completedIterations = iteration + 1
            let geometry = try differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let residual = geometry.position - point
            let gradient = residual.dot(geometry.firstDerivative)
            let hessian = geometry.firstDerivative.dot(
                geometry.firstDerivative
            ) + residual.dot(geometry.secondDerivative)
            let scale = max(
                1.0,
                geometry.firstDerivative.dot(geometry.firstDerivative),
                abs(residual.dot(geometry.secondDerivative))
            )
            guard hessian.isFinite,
                  abs(hessian) > Double.ulpOfOne * scale else {
                break
            }
            let delta = gradient / hessian
            guard delta.isFinite else {
                throw GeometryError.invalidDistance(delta)
            }
            let next = min(max(
                parameter - delta,
                interval.lower
            ), interval.upper)
            if abs(next - parameter) <= max(
                tolerance.relative * max(1.0, abs(parameter)),
                Double.ulpOfOne * max(1.0, abs(parameter)) * 128.0
            ) {
                parameter = next
                break
            }
            let currentPoint = geometry.position
            let nextPoint = try self.point(
                at: next,
                tolerance: tolerance
            )
            if (nextPoint - point).length <= (currentPoint - point).length {
                parameter = next
            } else {
                break
            }
        }
        let projected = try self.point(at: parameter, tolerance: tolerance)
        return (
            parameter: parameter,
            point: projected,
            residual: (projected - point).length.nextUp,
            iterations: completedIterations
        )
    }

    private func closestProjectionDistanceLowerBound(
        from point: Point3D,
        to enclosure: CoordinateEnclosure3D
    ) -> Double {
        func axisDistance(
            _ value: Double,
            interval: ScalarInterval
        ) -> Double {
            if value < interval.lower {
                return max(0.0, (interval.lower - value).nextDown)
            }
            if value > interval.upper {
                return max(0.0, (value - interval.upper).nextDown)
            }
            return 0.0
        }
        let x = axisDistance(point.x, interval: enclosure.x)
        let y = axisDistance(point.y, interval: enclosure.y)
        let z = axisDistance(point.z, interval: enclosure.z)
        return hypot(x, hypot(y, z)).nextDown
    }

}
