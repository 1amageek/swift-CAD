import CADCore

struct RationalBezierCurveJetEncloser: Sendable {
    func enclosure(
        of patch: RationalBezierCurvePatch3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try enclosure(
            of: patch,
            over: try ScalarInterval(lower: patch.lower, upper: patch.upper),
            tolerance: tolerance
        )
    }

    func enclosure(
        of patch: RationalBezierCurvePatch3D,
        over parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        guard patch.controlPoints.isEmpty == false,
              patch.controlPoints.count == patch.weights.count,
              patch.upper > patch.lower,
              parameters.lower >= patch.lower,
              parameters.upper <= patch.upper,
              parameters.upper > parameters.lower else {
            throw invalidPatchError(tolerance: tolerance)
        }
        let sourceControls = try homogeneousControls(
            patch,
            tolerance: tolerance
        )
        let controls = try trimmedHomogeneousControls(
            patch,
            sourceControls: sourceControls,
            lower: parameters.lower,
            upper: parameters.upper,
            tolerance: tolerance
        )
        let normalizedLower = try normalizedParameter(
            parameters.lower,
            lower: patch.lower,
            upper: patch.upper,
            tolerance: tolerance
        )
        let normalizedUpper = try normalizedParameter(
            parameters.upper,
            lower: patch.lower,
            upper: patch.upper,
            tolerance: tolerance
        )
        let normalizedParameters = OutwardScalarInterval(
            lower: max(0.0, normalizedLower.lower),
            upper: min(1.0, normalizedUpper.upper)
        )
        let sourceSpan = OutwardScalarInterval(patch.upper)
            - OutwardScalarInterval(patch.lower)
        let weight = try jet(
            coefficients: sourceControls.map(\.weight),
            value: .enclosing(controls.map(\.weight)),
            parameters: normalizedParameters,
            sourceSpan: sourceSpan,
            tolerance: tolerance
        )
        guard let reciprocalWeight = weight.reciprocal() else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: weight.value.lower,
                tolerance: tolerance,
                message: "A rational curve enclosure requires a certified positive weight range."
            )
        }
        return SurfaceIntervalVectorJet(
            x: try jet(
                coefficients: sourceControls.map(\.x),
                value: .enclosing(controls.map(\.x)),
                parameters: normalizedParameters,
                sourceSpan: sourceSpan,
                tolerance: tolerance
            ) * reciprocalWeight,
            y: try jet(
                coefficients: sourceControls.map(\.y),
                value: .enclosing(controls.map(\.y)),
                parameters: normalizedParameters,
                sourceSpan: sourceSpan,
                tolerance: tolerance
            ) * reciprocalWeight,
            z: try jet(
                coefficients: sourceControls.map(\.z),
                value: .enclosing(controls.map(\.z)),
                parameters: normalizedParameters,
                sourceSpan: sourceSpan,
                tolerance: tolerance
            ) * reciprocalWeight
        )
    }

    private func homogeneousControls(
        _ patch: RationalBezierCurvePatch3D,
        tolerance: ModelingTolerance
    ) throws -> [IntervalHomogeneousControl] {
        try patch.controlPoints.indices.map { index in
            let point = patch.controlPoints[index]
            let weight = patch.weights[index]
            guard weight.isFinite, weight > 0.0 else {
                throw invalidPatchError(tolerance: tolerance)
            }
            return IntervalHomogeneousControl(
                x: OutwardScalarInterval(point.x) * OutwardScalarInterval(weight),
                y: OutwardScalarInterval(point.y) * OutwardScalarInterval(weight),
                z: OutwardScalarInterval(point.z) * OutwardScalarInterval(weight),
                weight: OutwardScalarInterval(weight)
            )
        }
    }

    private func trimmedHomogeneousControls(
        _ patch: RationalBezierCurvePatch3D,
        sourceControls: [IntervalHomogeneousControl],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> [IntervalHomogeneousControl] {
        var controls = sourceControls
        var currentLower = patch.lower
        let currentUpper = patch.upper
        if lower > currentLower {
            let parameter = try normalizedParameter(
                lower,
                lower: currentLower,
                upper: currentUpper,
                tolerance: tolerance
            )
            controls = split(controls, parameter: parameter).upper
            currentLower = lower
        }
        if upper < currentUpper {
            let parameter = try normalizedParameter(
                upper,
                lower: currentLower,
                upper: currentUpper,
                tolerance: tolerance
            )
            controls = split(controls, parameter: parameter).lower
        }
        return controls
    }

    private func jet(
        coefficients: [OutwardScalarInterval],
        value: OutwardScalarInterval,
        parameters: OutwardScalarInterval,
        sourceSpan: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalJet {
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy(\.isFinite),
              parameters.isFinite,
              parameters.lower >= 0.0,
              parameters.upper <= 1.0,
              parameters.lower <= parameters.upper,
              sourceSpan.isFinite,
              sourceSpan.lower > 0.0 else {
            throw invalidPatchError(tolerance: tolerance)
        }
        let first = try differentiated(
            coefficients,
            span: sourceSpan,
            tolerance: tolerance
        )
        let second = try differentiated(
            first,
            span: sourceSpan,
            tolerance: tolerance
        )
        let third = try differentiated(
            second,
            span: sourceSpan,
            tolerance: tolerance
        )
        let zero = OutwardScalarInterval(0.0)
        let result = SurfaceIntervalJet(
            value: value,
            derivativeU: evaluated(first, at: parameters),
            derivativeV: zero,
            secondDerivativeUU: evaluated(second, at: parameters),
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: evaluated(third, at: parameters),
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
        guard result.value.isFinite,
              result.derivativeU.isFinite,
              result.secondDerivativeUU.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational curve differential enclosure exceeded finite arithmetic."
            )
        }
        return result
    }

    private func evaluated(
        _ coefficients: [OutwardScalarInterval],
        at parameter: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        var level = coefficients
        let complement = OutwardScalarInterval(1.0) - parameter
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index] * complement + level[index + 1] * parameter
            }
        }
        return level.first ?? OutwardScalarInterval(
            lower: -.infinity,
            upper: .infinity
        )
    }

    private func differentiated(
        _ coefficients: [OutwardScalarInterval],
        span: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [OutwardScalarInterval] {
        guard coefficients.count > 1 else {
            return [OutwardScalarInterval(0.0)]
        }
        guard let scale = OutwardScalarInterval(
            Double(coefficients.count - 1)
        ).divided(by: span) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        return (0..<(coefficients.count - 1)).map { index in
            (coefficients[index + 1] - coefficients[index]) * scale
        }
    }

    private func normalizedParameter(
        _ value: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardScalarInterval {
        let numerator = OutwardScalarInterval(value)
            - OutwardScalarInterval(lower)
        let denominator = OutwardScalarInterval(upper)
            - OutwardScalarInterval(lower)
        guard let parameter = numerator.divided(by: denominator),
              parameter.isFinite else {
            throw invalidPatchError(tolerance: tolerance)
        }
        return parameter
    }

    private func split(
        _ controls: [IntervalHomogeneousControl],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [IntervalHomogeneousControl],
        upper: [IntervalHomogeneousControl]
    ) {
        guard controls.count > 1 else {
            return (controls, controls)
        }
        var levels = [controls]
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

    private func invalidPatchError(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: "A rational Bezier curve enclosure requires a finite positive patch."
        )
    }
}

private struct IntervalHomogeneousControl: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval
    let weight: OutwardScalarInterval

    func interpolated(
        to other: IntervalHomogeneousControl,
        parameter: OutwardScalarInterval
    ) -> IntervalHomogeneousControl {
        let complement = OutwardScalarInterval(1.0) - parameter
        return IntervalHomogeneousControl(
            x: x * complement + other.x * parameter,
            y: y * complement + other.y * parameter,
            z: z * complement + other.z * parameter,
            weight: weight * complement + other.weight * parameter
        )
    }
}
