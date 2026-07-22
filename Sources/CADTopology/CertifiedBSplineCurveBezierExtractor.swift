import CADCore
import CADGeometry

/// Extracts every active rational B-spline span as a homogeneous Bezier patch.
/// All basis, derivative, and Bernstein reconstruction arithmetic is enclosed
/// with outward-rounded scalar bounds.
struct CertifiedBSplineCurveBezierExtractor {
    private typealias Patch = CertifiedHomogeneousBezierCurvePatch
    private typealias Point = Patch.HomogeneousPoint
    private typealias Scalar = Patch.ScalarBounds

    private let maximumControlOperations: Int

    init(maximumControlOperations: Int = 1_000_000) {
        self.maximumControlOperations = maximumControlOperations
    }

    func patches(
        curve: BSplineCurve2D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard curve.degree >= 1,
              case let .closed(domainLower, domainUpper) = curve.domain,
              domainUpper > domainLower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified B-spline curve extraction requires a positive bounded domain."
            )
        }
        let breaks = parameterBreaks(
            knots: curve.knots,
            lower: domainLower,
            upper: domainUpper
        )
        guard breaks.count >= 2 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified B-spline curve extraction found no active Bezier span."
            )
        }

        var operationCount = 0
        var result: [CertifiedHomogeneousBezierCurvePatch] = []
        result.reserveCapacity(breaks.count - 1)
        for spanIndex in 0..<(breaks.count - 1) {
            let lower = breaks[spanIndex]
            let upper = breaks[spanIndex + 1]
            let span = Scalar.exact(upper) - Scalar.exact(lower)
            guard span.lower > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: span.lower,
                    tolerance: tolerance,
                    message: "Certified B-spline curve extraction found a non-positive active span."
                )
            }
            var derivatives: [Point] = []
            derivatives.reserveCapacity(curve.degree + 1)
            for derivativeOrder in 0...curve.degree {
                let basis = try basisDerivativeValues(
                    parameter: lower,
                    degree: curve.degree,
                    derivativeOrder: derivativeOrder,
                    knots: curve.knots,
                    count: curve.controlPointCount,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                derivatives.append(try homogeneousDerivative(
                    curve: curve,
                    basis: basis,
                    operationCount: &operationCount,
                    tolerance: tolerance
                ))
            }
            let controls = try bernsteinControls(
                derivatives: derivatives,
                degree: curve.degree,
                span: span,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            guard controls.allSatisfy(\.isFiniteAndPositiveWeight) else {
                throw KernelError(
                    phase: .topology,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Certified B-spline curve extraction could not prove positive finite homogeneous weights."
                )
            }
            result.append(Patch(
                controls: controls,
                lower: lower,
                upper: upper
            ))
        }
        return result
    }

    private func basisDerivativeValues(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double],
        count: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Scalar] {
        if derivativeOrder == 0 {
            return try basisValues(
                parameter: parameter,
                degree: degree,
                knots: knots,
                count: count,
                operationCount: &operationCount,
                tolerance: tolerance
            )
        }
        guard derivativeOrder <= degree else {
            return Array(repeating: .exact(0.0), count: count)
        }
        let lowerDegree = try basisDerivativeValues(
            parameter: parameter,
            degree: degree - 1,
            derivativeOrder: derivativeOrder - 1,
            knots: knots,
            count: count + 1,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        let factor = Scalar.exact(Double(degree))
        var result = Array(repeating: Scalar.exact(0.0), count: count)
        for index in 0..<count {
            try consume(
                4,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0
                ? factor * lowerDegree[index] / Scalar.exact(leftDenominator)
                : Scalar.exact(0.0)
            let right = rightDenominator > 0.0
                ? factor * lowerDegree[index + 1] / Scalar.exact(rightDenominator)
                : Scalar.exact(0.0)
            result[index] = left - right
        }
        return result
    }

    private func basisValues(
        parameter: Double,
        degree: Int,
        knots: [Double],
        count: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Scalar] {
        guard degree > 0 else {
            return (0..<count).map { index in
                parameter >= knots[index] && parameter < knots[index + 1]
                    ? Scalar.exact(1.0)
                    : Scalar.exact(0.0)
            }
        }
        let lowerDegree = try basisValues(
            parameter: parameter,
            degree: degree - 1,
            knots: knots,
            count: count + 1,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        var result = Array(repeating: Scalar.exact(0.0), count: count)
        for index in 0..<count {
            try consume(
                6,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0 && !isExactlyZero(lowerDegree[index])
                ? (Scalar.exact(parameter) - Scalar.exact(knots[index]))
                    * lowerDegree[index]
                    / Scalar.exact(leftDenominator)
                : Scalar.exact(0.0)
            let right = rightDenominator > 0.0 && !isExactlyZero(lowerDegree[index + 1])
                ? (Scalar.exact(knots[index + degree + 1]) - Scalar.exact(parameter))
                    * lowerDegree[index + 1]
                    / Scalar.exact(rightDenominator)
                : Scalar.exact(0.0)
            result[index] = left + right
        }
        return result
    }

    private func homogeneousDerivative(
        curve: BSplineCurve2D,
        basis: [Scalar],
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> Point {
        var result = zeroPoint
        for index in 0..<curve.controlPointCount where !isExactlyZero(basis[index]) {
            try consume(
                10,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let weight = Scalar.exact(curve.weights[index])
            let coefficient = basis[index] * weight
            result = adding(
                result,
                Point(
                    x: Scalar.exact(curve.controlPoints[index].x) * coefficient,
                    y: Scalar.exact(curve.controlPoints[index].y) * coefficient,
                    weight: coefficient
                )
            )
        }
        return result
    }

    private func bernsteinControls(
        derivatives: [Point],
        degree: Int,
        span: Scalar,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Point] {
        var result: [Point] = []
        result.reserveCapacity(degree + 1)
        for controlIndex in 0...degree {
            var control = zeroPoint
            var scale = Scalar.exact(1.0)
            for derivativeOrder in 0...controlIndex {
                try consume(
                    12,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                control = adding(
                    control,
                    scaled(derivatives[derivativeOrder], by: scale)
                )
                guard derivativeOrder < controlIndex else { continue }
                scale = scale
                    * Scalar.exact(Double(controlIndex - derivativeOrder))
                    * span
                    / Scalar.exact(Double(derivativeOrder + 1))
                    / Scalar.exact(Double(degree - derivativeOrder))
            }
            result.append(control)
        }
        return result
    }

    private func consume(
        _ amount: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws {
        guard amount >= 0,
              operationCount <= maximumControlOperations - amount else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: Double(operationCount),
                tolerance: tolerance,
                message: "Certified B-spline curve extraction exhausted its control-operation budget."
            )
        }
        operationCount += amount
    }

    private func parameterBreaks(
        knots: [Double],
        lower: Double,
        upper: Double
    ) -> [Double] {
        var result = [lower]
        for knot in knots where knot > lower && knot < upper && result.last != knot {
            result.append(knot)
        }
        result.append(upper)
        return result
    }

    private func adding(_ lhs: Point, _ rhs: Point) -> Point {
        Point(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            weight: lhs.weight + rhs.weight
        )
    }

    private func scaled(_ point: Point, by scalar: Scalar) -> Point {
        Point(
            x: point.x * scalar,
            y: point.y * scalar,
            weight: point.weight * scalar
        )
    }

    private func isExactlyZero(_ value: Scalar) -> Bool {
        value.lower == 0.0 && value.upper == 0.0
    }

    private var zeroPoint: Point {
        Point(
            x: .exact(0.0),
            y: .exact(0.0),
            weight: .exact(0.0)
        )
    }
}
