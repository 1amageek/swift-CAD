import CADCore

public struct RationalBezierCurvePatch2D: Sendable, Hashable {
    public let controlPoints: [Point2D]
    public let weights: [Double]
    public let lower: Double
    public let upper: Double

    public var degree: Int {
        controlPoints.count - 1
    }

    init(
        controlPoints: [Point2D],
        weights: [Double],
        lower: Double,
        upper: Double
    ) {
        self.controlPoints = controlPoints
        self.weights = weights
        self.lower = lower
        self.upper = upper
    }

    public func subdivided(tolerance: ModelingTolerance) throws -> [RationalBezierCurvePatch2D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subdivided(tolerance: tolerance, using: &execution)
    }

    public func subdivided<A: ExactScalarAdmission & ~Copyable>(
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [RationalBezierCurvePatch2D] {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard controlPoints.count >= 2,
              controlPoints.count == weights.count,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier subdivision requires a valid positive-weight patch."
            )
        }
        for weight in weights {
            try execution.consumeWork(1)
            guard weight.isFinite, weight > Double.ulpOfOne else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Rational Bezier subdivision requires a valid positive-weight patch.")
            }
        }
        let controls = try homogeneousControls(using: &execution)
        let halves = try split(controls, parameter: 0.5, using: &execution)
        let middle = lower + (upper - lower) * 0.5
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: RationalBezierCurvePatch2D.self))
        return [
            try Self.patch(
                controls: halves.lower,
                lower: lower,
                upper: middle,
                tolerance: tolerance, using: &execution
            ),
            try Self.patch(
                controls: halves.upper,
                lower: middle,
                upper: upper,
                tolerance: tolerance, using: &execution
            ),
        ]
    }

    package func translated(u: Double, v: Double) throws -> RationalBezierCurvePatch2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try translated(u: u, v: v, using: &execution)
    }

    package func translated<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double,
        using execution: inout A) throws -> RationalBezierCurvePatch2D {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: Point2D.self))
        var points: [Point2D] = []
        points.reserveCapacity(controlPoints.count)
        for point in controlPoints {
            try execution.consumeWork(1)
            points.append(Point2D(x: point.x + u, y: point.y + v))
        }
        return RationalBezierCurvePatch2D(controlPoints: points, weights: weights, lower: lower, upper: upper)
    }

    private func homogeneousControls<A: ExactScalarAdmission & ~Copyable>(using execution: inout A)
        throws -> [HomogeneousPoint] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: HomogeneousPoint.self))
        var result: [HomogeneousPoint] = []
        result.reserveCapacity(controlPoints.count)
        for index in controlPoints.indices {
            try execution.consumeWork(1)
            result.append(HomogeneousPoint(x: controlPoints[index].x * weights[index],
                y: controlPoints[index].y * weights[index], weight: weights[index]))
        }
        return result
    }

    private func split<A: ExactScalarAdmission & ~Copyable>(_ values: [HomogeneousPoint],
        parameter: Double, using execution: inout A) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: values.count, of: [HomogeneousPoint].self))
        var levels: [[HomogeneousPoint]] = []
        levels.reserveCapacity(values.count)
        levels.append(values)
        while let previous = levels.last, previous.count > 1 {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: previous.count - 1, of: HomogeneousPoint.self))
            var next: [HomogeneousPoint] = []
            next.reserveCapacity(previous.count - 1)
            for index in 0..<(previous.count - 1) {
                try execution.consumeWork(1)
                next.append(previous[index].interpolated(to: previous[index + 1], parameter: parameter))
            }
            levels.append(next)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: levels.count, of: HomogeneousPoint.self))
        var lower: [HomogeneousPoint] = []
        lower.reserveCapacity(levels.count)
        for level in levels { try execution.consumeWork(1); lower.append(level[0]) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: levels.count, of: HomogeneousPoint.self))
        var upper: [HomogeneousPoint] = []
        upper.reserveCapacity(levels.count)
        for level in levels.reversed() { try execution.consumeWork(1); upper.append(level[level.count - 1]) }
        return (lower, upper)
    }

    private static func patch<A: ExactScalarAdmission & ~Copyable>(
        controls: [HomogeneousPoint],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> RationalBezierCurvePatch2D {
        var points: [Point2D] = []
        var weights: [Double] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Point2D.self))
        points.reserveCapacity(controls.count)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Double.self))
        weights.reserveCapacity(controls.count)
        for control in controls {
            try execution.consumeWork(1)
            guard control.isFinite,
                  control.weight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: control.weight,
                    tolerance: tolerance,
                    message: "Rational Bezier subdivision produced a non-positive homogeneous weight."
                )
            }
            points.append(Point2D(
                x: control.x / control.weight,
                y: control.y / control.weight
            ))
            weights.append(control.weight)
        }
        return RationalBezierCurvePatch2D(
            controlPoints: points,
            weights: weights,
            lower: lower,
            upper: upper
        )
    }

    private struct HomogeneousPoint {
        let x: Double
        let y: Double
        let weight: Double

        func interpolated(
            to other: HomogeneousPoint,
            parameter: Double
        ) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x * (1.0 - parameter) + other.x * parameter,
                y: y * (1.0 - parameter) + other.y * parameter,
                weight: weight * (1.0 - parameter) + other.weight * parameter
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && weight.isFinite
        }
    }
}
