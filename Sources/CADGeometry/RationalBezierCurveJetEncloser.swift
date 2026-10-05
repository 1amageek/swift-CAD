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

    struct NativeSpan: Sendable {
        let index: Int
        let lower: Double
        let upper: Double
        let coefficients: [[OutwardScalarInterval]]
        let weightRange: OutwardScalarInterval
        let commonWeight: Double?
    }

    /// Original coefficient authority; no rounded Cartesian extraction is retained.
    func originalNativeSpans(of curve: BSplineCurve3D, tolerance: ModelingTolerance,
                             consumeWork: () throws -> Void) throws -> [NativeSpan] {
        try Task.checkCancellation()
        try curve.validate(tolerance: tolerance)
        let n = curve.degree.addingReportingOverflow(1)
        let square = n.partialValue.multipliedReportingOverflow(by: n.partialValue)
        let payload = square.partialValue.multipliedReportingOverflow(by: 4)
        let total = payload.partialValue.multipliedReportingOverflow(by: curve.controlPointCount)
        guard !n.overflow, !square.overflow, !payload.overflow, !total.overflow else {
            throw finiteFailure(tolerance)
        }
        var spans: [NativeSpan] = []
        for span in curve.degree..<curve.controlPointCount where curve.knots[span] < curve.knots[span + 1] {
            try Task.checkCancellation()
            try consumeWork()
            let lower = curve.knots[span], upper = curve.knots[span + 1]
            let indices = (span - curve.degree)...span
            let firstWeight = curve.weights[indices.lowerBound]
            var weightLower = firstWeight, weightUpper = firstWeight
            for index in indices {
                weightLower = min(weightLower, curve.weights[index])
                weightUpper = max(weightUpper, curve.weights[index])
            }
            let commonWeight = weightLower == weightUpper
            let weightRange = OutwardScalarInterval(lower: weightLower, upper: weightUpper)
            var nets = Array(repeating: Array(repeating: OutwardScalarInterval.exact(0), count: n.partialValue), count: 4)
            let isolated = curve.knots[(span - curve.degree + 1)...span].allSatisfy { $0 == lower }
                && curve.knots[(span + 1)...(span + curve.degree)].allSatisfy { $0 == upper }
            if isolated {
                for (offset, index) in indices.enumerated() {
                    let p = curve.controlPoints[index], w = OutwardScalarInterval.exact(curve.weights[index])
                    nets[0][offset] = .exact(p.x) * w
                    nets[1][offset] = .exact(p.y) * w
                    nets[2][offset] = .exact(p.z) * w
                    nets[3][offset] = w
                }
            } else {
                let basis = try BSplineBasis.nonzeroIntervalDerivativeValues(parameter: lower, degree: curve.degree,
                    throughDerivativeOrder: curve.degree, knots: curve.knots, count: curve.controlPointCount,
                    owningSpan: span, tolerance: tolerance)
                var derivatives = nets
                for order in 0...curve.degree {
                    try Task.checkCancellation()
                    for offset in basis[order].values.indices {
                        let index = basis[order].startIndex + offset
                        let p = curve.controlPoints[index]
                        let c = basis[order].values[offset] * .exact(curve.weights[index])
                        derivatives[0][order] = derivatives[0][order] + .exact(p.x) * c
                        derivatives[1][order] = derivatives[1][order] + .exact(p.y) * c
                        derivatives[2][order] = derivatives[2][order] + .exact(p.z) * c
                        derivatives[3][order] = derivatives[3][order] + c
                    }
                }
                let width = OutwardScalarInterval.exact(upper) - .exact(lower)
                for index in 0...curve.degree {
                    for order in 0...index {
                        var scale = OutwardScalarInterval.exact(1)
                        for j in 0..<order {
                            guard let next = (scale * .exact(Double(index - j)) * width)
                                .divided(by: .exact(Double(j + 1)) * .exact(Double(curve.degree - j))), next.isFinite else {
                                throw finiteFailure(tolerance)
                            }
                            scale = next
                        }
                        for axis in 0..<4 { nets[axis][index] = nets[axis][index] + derivatives[axis][order] * scale }
                    }
                }
            }
            if commonWeight { nets[3] = Array(repeating: .exact(firstWeight), count: n.partialValue) }
            guard nets.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw finiteFailure(tolerance) }
            spans.append(NativeSpan(index: span, lower: lower, upper: upper,
                                    coefficients: nets, weightRange: weightRange, commonWeight: commonWeight ? firstWeight : nil))
        }
        try Task.checkCancellation()
        return spans
    }

    func enclosure(of span: NativeSpan, over parameters: ScalarInterval,
                   tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        try Task.checkCancellation()
        guard parameters.lower >= span.lower, parameters.upper <= span.upper,
              parameters.lower <= parameters.upper else { throw invalidPatchError(tolerance: tolerance) }
        let a = try normalizedParameter(parameters.lower, lower: span.lower, upper: span.upper, tolerance: tolerance)
        let b = try normalizedParameter(parameters.upper, lower: span.lower, upper: span.upper, tolerance: tolerance)
        let q = OutwardScalarInterval(lower: max(0, a.lower), upper: min(1, b.upper))
        let width = OutwardScalarInterval.exact(span.upper) - .exact(span.lower)
        guard width.isFinite, width.lower > 0 else { throw finiteFailure(tolerance) }
        let weightValue = try evaluated(span.coefficients[3], at: q, tolerance: tolerance)
        guard let boundedWeight = weightValue.intersection(with: span.weightRange) else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                message: "Original curve denominator and positive source-weight hull are inconsistent.")
        }
        let weight: SurfaceIntervalJet
        if let commonWeight = span.commonWeight {
            weight = .constant(commonWeight)
        } else {
            weight = try jet(coefficients: span.coefficients[3], value: boundedWeight,
                             parameters: q, sourceSpan: width, tolerance: tolerance)
        }
        guard let inverse = weight.reciprocal() else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Original curve denominator has no certified positive reciprocal.")
        }
        func coordinate(_ axis: Int) throws -> SurfaceIntervalJet {
            let coefficients = span.coefficients[axis]
            return try jet(coefficients: coefficients,
                value: evaluated(coefficients, at: q, tolerance: tolerance),
                parameters: q, sourceSpan: width, tolerance: tolerance) * inverse
        }
        let result = try SurfaceIntervalVectorJet(x: coordinate(0), y: coordinate(1), z: coordinate(2))
        guard [result.x, result.y, result.z].allSatisfy({
            [$0.value, $0.derivativeU, $0.secondDerivativeUU, $0.thirdDerivativeUUU].allSatisfy(\.isFinite)
        }) else { throw finiteFailure(tolerance) }
        try Task.checkCancellation()
        return result
    }

    private func finiteFailure(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original native curve coefficient work exceeds finite storage or arithmetic.")
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
            derivativeU: try evaluated(first, at: parameters, tolerance: tolerance),
            derivativeV: zero,
            secondDerivativeUU: try evaluated(second, at: parameters, tolerance: tolerance),
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: try evaluated(third, at: parameters, tolerance: tolerance),
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
        at parameter: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> OutwardScalarInterval {
        guard !coefficients.isEmpty, coefficients.allSatisfy(\.isFinite),
              parameter.isFinite, parameter.lower >= 0, parameter.upper <= 1,
              parameter.lower <= parameter.upper else { throw invalidPatchError(tolerance: tolerance) }
        // Patch containment proves exact normalized parameters lie in [0,1].
        // Both interval de Casteljau and the Bernstein convex hull contain the value.
        let hull = OutwardScalarInterval.enclosing(coefficients)
        var level = coefficients
        let complement = OutwardScalarInterval(1.0) - parameter
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index] * complement + level[index + 1] * parameter
            }
        }
        guard let value = level.first, let result = value.intersection(with: hull) else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                message: "Interval Bernstein evaluation and its certified coefficient hull are disjoint.")
        }
        return result
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
        if value == lower { return .exact(0) }
        if value == upper { return .exact(1) }
        let numerator = OutwardScalarInterval.exact(value)
            - .exact(lower)
        let denominator = OutwardScalarInterval.exact(upper)
            - .exact(lower)
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
