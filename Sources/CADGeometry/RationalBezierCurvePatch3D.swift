import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

struct RationalBezierCurvePatch3D: Sendable {
    let controlPoints: [Point3D]
    let weights: [Double]
    let lower: Double
    let upper: Double

    func trimmed<A: ExactScalarAdmission & ~Copyable>(
        from requestedLower: Double,
        to requestedUpper: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> RationalBezierCurvePatch3D {
        try execution.consumeWork(1)
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
        var controls = try homogeneousControls(using: &execution)
        var currentLower = lower
        var currentUpper = upper
        if targetLower > currentLower {
            let parameter = (targetLower - currentLower) / (currentUpper - currentLower)
            controls = try split(controls, parameter: parameter, using: &execution).upper
            currentLower = targetLower
        }
        if targetUpper < currentUpper {
            let parameter = (targetUpper - currentLower) / (currentUpper - currentLower)
            controls = try split(controls, parameter: parameter, using: &execution).lower
            currentUpper = targetUpper
        }
        let result = try Self.patch(
            controls: controls,
            lower: currentLower,
            upper: currentUpper,
            tolerance: tolerance, using: &execution
        )
        if targetLower == lower, targetUpper == upper { return self }
        // Subdivision leaves these source controls unchanged; avoid a lossy
        // homogeneous multiply/divide round-trip at retained boundaries.
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: result.controlPoints.count, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: result.weights.count, of: Double.self))
        var points = result.controlPoints
        var resultWeights = result.weights
        if targetLower == lower {
            points[0] = controlPoints[0]
            resultWeights[0] = weights[0]
        }
        if targetUpper == upper {
            points[points.count - 1] = controlPoints[controlPoints.count - 1]
            resultWeights[resultWeights.count - 1] = weights[weights.count - 1]
        }
        return Self(controlPoints: points, weights: resultWeights, lower: currentLower, upper: currentUpper)
    }

    func subdivided<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws -> [RationalBezierCurvePatch3D] {
        try execution.consumeWork(1)
        let middle = lower + (upper - lower) * 0.5
        let halves = try split(try homogeneousControls(using: &execution), parameter: 0.5, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Self.self))
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

    private func homogeneousControls<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [HomogeneousPoint] {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: HomogeneousPoint.self))
        return try controlPoints.indices.map { index in
            try execution.consumeWork(1)
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

    private func split<A: ExactScalarAdmission & ~Copyable>(
        _ values: [HomogeneousPoint],
        parameter: Double, using execution: inout A
    ) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        try execution.consumeWork(1)
        guard values.count > 1 else { return (values, values) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [HomogeneousPoint].self))
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [HomogeneousPoint].self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: previous.count - 1, of: HomogeneousPoint.self))
            levels.append(try (0..<(previous.count - 1)).map { index in
                try execution.consumeWork(1)
                return previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: parameter
                )
            })
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: levels.count, of: HomogeneousPoint.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: levels.count, of: HomogeneousPoint.self))
        return (
            try levels.map { try execution.consumeWork(1); return $0[0] },
            try levels.reversed().map { try execution.consumeWork(1); return $0[$0.count - 1] }
        )
    }

    private static func patch<A: ExactScalarAdmission & ~Copyable>(
        controls: [HomogeneousPoint],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> RationalBezierCurvePatch3D {
        try execution.consumeWork(1)
        var points: [Point3D] = []
        var weights: [Double] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Point3D.self))
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
