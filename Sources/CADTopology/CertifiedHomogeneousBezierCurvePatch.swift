import CADCore

struct CertifiedHomogeneousBezierCurvePatch: Sendable, Hashable {
    typealias ScalarBounds = CertifiedHomogeneousBezierSurfacePatch.ScalarBounds

    struct HomogeneousPoint: Sendable, Hashable {
        let x: ScalarBounds
        let y: ScalarBounds
        let weight: ScalarBounds

        func interpolated(
            to other: HomogeneousPoint,
            parameter: ScalarBounds
        ) -> HomogeneousPoint {
            let complement = ScalarBounds.exact(1.0) - parameter
            return HomogeneousPoint(
                x: x * complement + other.x * parameter,
                y: y * complement + other.y * parameter,
                weight: weight * complement + other.weight * parameter
            )
        }

        var isFiniteAndPositiveWeight: Bool {
            x.isFinite && y.isFinite && weight.isFinite && weight.lower > 0.0
        }
    }

    let controls: [HomogeneousPoint]
    let lower: Double
    let upper: Double

    var degree: Int { controls.count - 1 }

    func restrictedControls(
        fractionLower: Double,
        fractionUpper: Double,
        tolerance: ModelingTolerance
    ) throws -> [HomogeneousPoint] {
        guard controls.count >= 2,
              controls.allSatisfy(\.isFiniteAndPositiveWeight),
              fractionLower.isFinite,
              fractionUpper.isFinite,
              fractionLower >= 0.0,
              fractionUpper <= 1.0,
              fractionUpper >= fractionLower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified homogeneous Bezier restriction requires an ordered unit fraction range."
            )
        }
        if fractionLower == fractionUpper {
            let point = evaluatedControl(
                controls,
                parameter: .exact(fractionLower)
            )
            return Array(repeating: point, count: controls.count)
        }
        let upperControls = fractionUpper == 1.0
            ? controls
            : splitControls(
                controls,
                parameter: .exact(fractionUpper)
            ).lower
        guard fractionLower > 0.0 else { return upperControls }
        let normalizedLower = ScalarBounds.exact(fractionLower)
            / .exact(fractionUpper)
        return splitControls(
            upperControls,
            parameter: normalizedLower
        ).upper
    }

    func subdivided(
        tolerance: ModelingTolerance
    ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
        guard controls.count >= 2,
              controls.allSatisfy(\.isFiniteAndPositiveWeight),
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified homogeneous Bezier subdivision requires a valid positive-weight patch."
            )
        }
        var levels = [controls]
        let midpoint = ScalarBounds.exact(0.5)
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: midpoint
                )
            })
        }
        let middle = lower + (upper - lower) * 0.5
        let lowerControls = levels.map { $0[0] }
        let upperControls = levels.reversed().map { $0[$0.count - 1] }
        guard lowerControls.allSatisfy(\.isFiniteAndPositiveWeight),
              upperControls.allSatisfy(\.isFiniteAndPositiveWeight) else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Certified homogeneous Bezier subdivision lost finite positive weights."
            )
        }
        return [
            CertifiedHomogeneousBezierCurvePatch(
                controls: lowerControls,
                lower: lower,
                upper: middle
            ),
            CertifiedHomogeneousBezierCurvePatch(
                controls: upperControls,
                lower: middle,
                upper: upper
            ),
        ]
    }

    private func splitControls(
        _ source: [HomogeneousPoint],
        parameter: ScalarBounds
    ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        var levels = [source]
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

    private func evaluatedControl(
        _ source: [HomogeneousPoint],
        parameter: ScalarBounds
    ) -> HomogeneousPoint {
        var level = source
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index].interpolated(
                    to: level[index + 1],
                    parameter: parameter
                )
            }
        }
        return level[0]
    }
}
