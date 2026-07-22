import CADCore

public struct DefaultBSplineCurveCommonBasisResolver: BSplineCurveCommonBasisResolving {
    public var maximumSpanCount: Int

    public init(maximumSpanCount: Int = 16_384) {
        self.maximumSpanCount = maximumSpanCount
    }

    public func resolve(
        first: BSplineCurve3D,
        second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurveCommonBasisPair {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        guard maximumSpanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Common B-spline basis resolution requires a positive span budget."
            )
        }

        let firstSource = try normalizedSource(first, tolerance: tolerance)
        let secondSource = try normalizedSource(second, tolerance: tolerance)
        let breaks = mergedBreaks(
            firstSource.patches.flatMap { [$0.normalizedLower, $0.normalizedUpper] },
            secondSource.patches.flatMap { [$0.normalizedLower, $0.normalizedUpper] }
        )
        guard breaks.count >= 2, breaks.count - 1 <= maximumSpanCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(max(0, breaks.count - 1)),
                tolerance: tolerance,
                message: "Common B-spline basis resolution exceeded its span budget."
            )
        }
        let degree = max(first.degree, second.degree)
        let firstResolved = try resolvedCurve(
            source: firstSource,
            breaks: breaks,
            degree: degree,
            tolerance: tolerance
        )
        let secondResolved = try resolvedCurve(
            source: secondSource,
            breaks: breaks,
            degree: degree,
            tolerance: tolerance
        )
        guard firstResolved.degree == secondResolved.degree,
              firstResolved.knots == secondResolved.knots,
              firstResolved.controlPointCount == secondResolved.controlPointCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Common B-spline basis construction did not produce identical bases."
            )
        }
        return BSplineCurveCommonBasisPair(
            first: firstResolved,
            second: secondResolved
        )
    }

    private struct Source: Sendable {
        let lower: Double
        let upper: Double
        let patches: [NormalizedPatch]
    }

    private struct NormalizedPatch: Sendable {
        let patch: RationalBezierCurvePatch3D
        let normalizedLower: Double
        let normalizedUpper: Double
    }

    private struct HomogeneousControl: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        init(point: Point3D, weight: Double) {
            x = point.x * weight
            y = point.y * weight
            z = point.z * weight
            self.weight = weight
        }

        private init(x: Double, y: Double, z: Double, weight: Double) {
            self.x = x
            self.y = y
            self.z = z
            self.weight = weight
        }

        static func + (
            lhs: HomogeneousControl,
            rhs: HomogeneousControl
        ) -> HomogeneousControl {
            HomogeneousControl(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z,
                weight: lhs.weight + rhs.weight
            )
        }

        static func * (
            lhs: HomogeneousControl,
            rhs: Double
        ) -> HomogeneousControl {
            HomogeneousControl(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite && weight.isFinite
        }
    }

    private func normalizedSource(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Source {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Common B-spline basis resolution requires finite curve domains."
            )
        }
        let span = upper - lower
        guard span.isFinite, span > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: span,
                tolerance: tolerance,
                message: "Common B-spline basis resolution requires non-degenerate curve domains."
            )
        }
        let patches = try BSplineCurveBezierDecomposer()
            .curvePatches(curve: curve, tolerance: tolerance)
            .map { patch in
                NormalizedPatch(
                    patch: patch,
                    normalizedLower: normalized(
                        patch.lower,
                        lower: lower,
                        span: span
                    ),
                    normalizedUpper: normalized(
                        patch.upper,
                        lower: lower,
                        span: span
                    )
                )
            }
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Common B-spline basis resolution found no curve spans."
            )
        }
        return Source(lower: lower, upper: upper, patches: patches)
    }

    private func normalized(
        _ value: Double,
        lower: Double,
        span: Double
    ) -> Double {
        if value == lower { return 0.0 }
        if value == lower + span { return 1.0 }
        return (value - lower) / span
    }

    private func mergedBreaks(_ first: [Double], _ second: [Double]) -> [Double] {
        let sorted = (first + second + [0.0, 1.0]).sorted()
        var result: [Double] = []
        result.reserveCapacity(sorted.count)
        for value in sorted where result.last != value {
            result.append(value)
        }
        if result.first != 0.0 {
            result.insert(0.0, at: 0)
        }
        if result.last != 1.0 {
            result.append(1.0)
        }
        return result
    }

    private func resolvedCurve(
        source: Source,
        breaks: [Double],
        degree: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        var spanControls: [[HomogeneousControl]] = []
        spanControls.reserveCapacity(breaks.count - 1)
        for index in 0..<(breaks.count - 1) {
            let lower = breaks[index]
            let upper = breaks[index + 1]
            guard upper > lower else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    residual: upper - lower,
                    tolerance: tolerance,
                    message: "Common B-spline basis contains a non-positive normalized span."
                )
            }
            let sourcePatch = try containingPatch(
                source.patches,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let sourceSpan = source.upper - source.lower
            let actualLower = source.lower + sourceSpan * lower
            let actualUpper = source.lower + sourceSpan * upper
            let trimmed = try sourcePatch.patch.trimmed(
                from: actualLower,
                to: actualUpper,
                tolerance: tolerance
            )
            let controls = trimmed.controlPoints.indices.map { controlIndex in
                HomogeneousControl(
                    point: trimmed.controlPoints[controlIndex],
                    weight: trimmed.weights[controlIndex]
                )
            }
            spanControls.append(try elevated(
                controls,
                to: degree,
                tolerance: tolerance
            ))
        }
        return try assembledCurve(
            spanControls: spanControls,
            breaks: breaks,
            degree: degree,
            tolerance: tolerance
        )
    }

    private func containingPatch(
        _ patches: [NormalizedPatch],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> NormalizedPatch {
        if let patch = patches.first(where: {
            lower >= $0.normalizedLower && upper <= $0.normalizedUpper
        }) {
            return patch
        }
        let parameterTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 512.0
        )
        if let patch = patches.first(where: {
            lower >= $0.normalizedLower - parameterTolerance
                && upper <= $0.normalizedUpper + parameterTolerance
        }) {
            return patch
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "A normalized common-basis span could not be associated with its exact source span."
        )
    }

    private func elevated(
        _ source: [HomogeneousControl],
        to targetDegree: Int,
        tolerance: ModelingTolerance
    ) throws -> [HomogeneousControl] {
        var result = source
        while result.count - 1 < targetDegree {
            let degree = result.count - 1
            var next = Array(repeating: result[0], count: result.count + 1)
            next[0] = result[0]
            next[next.count - 1] = result[result.count - 1]
            if degree > 0 {
                for index in 1...degree {
                    let alpha = Double(index) / Double(degree + 1)
                    next[index] = result[index - 1] * alpha
                        + result[index] * (1.0 - alpha)
                }
            }
            result = next
        }
        guard result.count == targetDegree + 1,
              result.allSatisfy({ $0.isFinite && $0.weight > 0.0 }) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Homogeneous B-spline degree elevation exceeded the finite positive-weight range."
            )
        }
        return result
    }

    private func assembledCurve(
        spanControls: [[HomogeneousControl]],
        breaks: [Double],
        degree: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        guard let firstSpan = spanControls.first else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Common B-spline assembly requires at least one span."
            )
        }
        var controls = firstSpan
        for span in spanControls.dropFirst() {
            let previousEndpoint = controls[controls.count - 1]
            try validateSharedEndpoint(
                previousEndpoint,
                span[0],
                tolerance: tolerance
            )
            let homogeneousScale = previousEndpoint.weight / span[0].weight
            guard homogeneousScale.isFinite, homogeneousScale > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: homogeneousScale,
                    tolerance: tolerance,
                    message: "Adjacent rational B-spline spans could not be homogenously aligned."
                )
            }
            let alignedSpan = span.map { $0 * homogeneousScale }
            controls.append(contentsOf: alignedSpan.dropFirst())
        }
        var knots = Array(repeating: 0.0, count: degree + 1)
        if breaks.count > 2 {
            for value in breaks.dropFirst().dropLast() {
                knots.append(contentsOf: repeatElement(value, count: degree))
            }
        }
        knots.append(contentsOf: repeatElement(1.0, count: degree + 1))
        let points = try controls.map { control -> Point3D in
            guard control.weight.isFinite, control.weight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: control.weight,
                    tolerance: tolerance,
                    message: "Common B-spline assembly produced a non-positive weight."
                )
            }
            return Point3D(
                x: control.x / control.weight,
                y: control.y / control.weight,
                z: control.z / control.weight
            )
        }
        let result = BSplineCurve3D(
            degree: degree,
            knots: knots,
            controlPoints: points,
            weights: controls.map(\.weight)
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    private func validateSharedEndpoint(
        _ first: HomogeneousControl,
        _ second: HomogeneousControl,
        tolerance: ModelingTolerance
    ) throws {
        let firstPoint = Point3D(
            x: first.x / first.weight,
            y: first.y / first.weight,
            z: first.z / first.weight
        )
        let secondPoint = Point3D(
            x: second.x / second.weight,
            y: second.y / second.weight,
            z: second.z / second.weight
        )
        let residual = (firstPoint - secondPoint).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: residual,
                tolerance: tolerance,
                message: "Adjacent exact B-spline spans did not retain a common endpoint."
            )
        }
    }
}
