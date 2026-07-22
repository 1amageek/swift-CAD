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

    public func subdivided(
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch2D] {
        try tolerance.validate()
        guard controlPoints.count >= 2,
              controlPoints.count == weights.count,
              weights.allSatisfy({ $0.isFinite && $0 > Double.ulpOfOne }),
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
        let controls = homogeneousControls()
        let halves = split(controls, parameter: 0.5)
        let middle = lower + (upper - lower) * 0.5
        return [
            try Self.patch(
                controls: halves.lower,
                lower: lower,
                upper: middle,
                tolerance: tolerance
            ),
            try Self.patch(
                controls: halves.upper,
                lower: middle,
                upper: upper,
                tolerance: tolerance
            ),
        ]
    }

    private func homogeneousControls() -> [HomogeneousPoint] {
        controlPoints.indices.map { index in
            HomogeneousPoint(
                x: controlPoints[index].x * weights[index],
                y: controlPoints[index].y * weights[index],
                weight: weights[index]
            )
        }
    }

    private func split(
        _ values: [HomogeneousPoint],
        parameter: Double
    ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: parameter
                )
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private static func patch(
        controls: [HomogeneousPoint],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierCurvePatch2D {
        var points: [Point2D] = []
        var weights: [Double] = []
        points.reserveCapacity(controls.count)
        weights.reserveCapacity(controls.count)
        for control in controls {
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
