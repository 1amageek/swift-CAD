import CADCore
import Foundation

struct RationalBezierCurvePatch3D: Sendable {
    let controlPoints: [Point3D]
    let weights: [Double]
    let lower: Double
    let upper: Double

    func trimmed(
        from requestedLower: Double,
        to requestedUpper: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierCurvePatch3D {
        let scale = max(1.0, abs(lower), abs(upper))
        let parameterTolerance = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        guard requestedLower.isFinite,
              requestedUpper.isFinite,
              requestedLower >= lower - parameterTolerance,
              requestedUpper <= upper + parameterTolerance,
              requestedUpper - requestedLower > parameterTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier curve trimming requires a positive subdomain of the source patch."
            )
        }
        let targetLower = abs(requestedLower - lower) <= parameterTolerance
            ? lower
            : requestedLower
        let targetUpper = abs(requestedUpper - upper) <= parameterTolerance
            ? upper
            : requestedUpper
        var controls = homogeneousControls()
        var currentLower = lower
        var currentUpper = upper
        if targetLower > currentLower {
            let parameter = (targetLower - currentLower) / (currentUpper - currentLower)
            controls = split(controls, parameter: parameter).upper
            currentLower = targetLower
        }
        if targetUpper < currentUpper {
            let parameter = (targetUpper - currentLower) / (currentUpper - currentLower)
            controls = split(controls, parameter: parameter).lower
            currentUpper = targetUpper
        }
        return try Self.patch(
            controls: controls,
            lower: currentLower,
            upper: currentUpper,
            tolerance: tolerance
        )
    }

    func subdivided(tolerance: ModelingTolerance) throws -> [RationalBezierCurvePatch3D] {
        let middle = lower + (upper - lower) * 0.5
        let halves = split(homogeneousControls(), parameter: 0.5)
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
            let point = controlPoints[index]
            let weight = weights[index]
            return HomogeneousPoint(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight,
                weight: weight
            )
        }
    }

    private func split(
        _ values: [HomogeneousPoint],
        parameter: Double
    ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        guard values.count > 1 else { return (values, values) }
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
    ) throws -> RationalBezierCurvePatch3D {
        var points: [Point3D] = []
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
                    message: "Rational Bezier curve control has a non-positive homogeneous weight."
                )
            }
            points.append(Point3D(
                x: control.x / control.weight,
                y: control.y / control.weight,
                z: control.z / control.weight
            ))
            weights.append(control.weight)
        }
        return RationalBezierCurvePatch3D(
            controlPoints: points,
            weights: weights,
            lower: lower,
            upper: upper
        )
    }

    private struct HomogeneousPoint: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        func interpolated(
            to other: HomogeneousPoint,
            parameter: Double
        ) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x * (1.0 - parameter) + other.x * parameter,
                y: y * (1.0 - parameter) + other.y * parameter,
                z: z * (1.0 - parameter) + other.z * parameter,
                weight: weight * (1.0 - parameter) + other.weight * parameter
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite && weight.isFinite
        }
    }
}
