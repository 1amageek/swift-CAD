import CADCore
import CADGeometry

/// Strict open-chart orbit signs, including original endpoint derivative factors.
package struct OriginalRevolutionMonotonicityProof: Sendable {
    package let axialSign: Int
    package let radialSign: Int

    private init(axialSign: Int, radialSign: Int) {
        self.axialSign = axialSign
        self.radialSign = radialSign
    }

    package static func prepare<B: RationalAlgebraAdmitting>(
        for span: OriginalRevolveGeneratorResolver.Span,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B
    ) throws -> Self {
        guard let spanIndex = span.chart.nativeSpanIndex,
              case let .bSpline(source) = span.chart.source,
              span.chart.certificationTolerance == tolerance,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32 else {
            throw GeometryConversionError.invalidInput("Original orbit signs require their retained native chart and caller depth.")
        }
        let original = try OriginalRationalCurvePolynomial(source: source,
            spanIndex: spanIndex, tolerance: tolerance, usage: &usage)
        let weight = original.homogeneous[3]
        let weightDerivative = try weight.differentiated(alongU: true, usage: &usage)
        let height = try original.planeIncidenceNumerator(origin: span.originalAxisOrigin,
            normal: span.originalAxisDirection, usage: &usage)
        let axialDerivative = try height.differentiated(alongU: true, usage: &usage)
            .multiplied(by: weight, usage: &usage)
            .subtracting(height.multiplied(by: weightDerivative, usage: &usage), usage: &usage)
        let cross = try original.axisIncidenceNumerators(origin: span.originalAxisOrigin,
            direction: span.originalAxisDirection, usage: &usage)
        var squaredRadius = ExactBivariatePolynomial.zero
        for coordinate in cross {
            squaredRadius = try squaredRadius.adding(
                coordinate.multiplied(by: coordinate, usage: &usage), usage: &usage)
        }
        let two = try ExactRationalCoefficient.one.adding(.one, usage: &usage)
        let radialDerivative = try squaredRadius.differentiated(alongU: true, usage: &usage)
            .multiplied(by: weight, usage: &usage)
            .subtracting(squaredRadius.multiplied(by: weightDerivative, usage: &usage)
                .scaled(by: two, usage: &usage), usage: &usage)
        // Positive original weights make both rational derivative denominators
        // positive. Only the exact original numerator signs determine direction.
        let axial = try openSign(of: axialDerivative, span: span,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        let radial = try openSign(of: radialDerivative, span: span,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        return Self(axialSign: axial, radialSign: radial)
    }

    private static func endpointSign<B: RationalAlgebraAdmitting>(
        _ expression: ExactBivariatePolynomial, at endpoint: OriginalCurveRootEndpoint,
        maximumSubdivisionDepth: Int, usage: inout B
    ) throws -> Int {
        try usage.consumeExactWork(1)
        switch endpoint {
        case let .authored(parameter):
            let value = try expression.evaluated(atU:
                .originalDouble(parameter, usage: &usage), v: .zero, usage: &usage)
            return value.isPositive ? 1 : value.isNegative ? -1 : 0
        case let .algebraic(boundary):
            switch try boundary.sign(of: expression,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage) {
            case .positive: return 1
            case .negative: return -1
            case .zero: return 0
            }
        }
    }

    private static func variations<B: RationalAlgebraAdmitting>(
        _ chain: [ExactBivariatePolynomial], at endpoint: OriginalCurveRootEndpoint,
        maximumSubdivisionDepth: Int, usage: inout B
    ) throws -> Int {
        var previous = 0
        var count = 0
        for expression in chain {
            let sign = try endpointSign(expression, at: endpoint,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
            if sign == 0 { continue }
            if previous != 0, previous != sign { count += 1 }
            previous = sign
        }
        return count
    }

    private static func openSign<B: RationalAlgebraAdmitting>(
        of expression: ExactBivariatePolynomial, span: OriginalRevolveGeneratorResolver.Span,
        maximumSubdivisionDepth: Int, usage: inout B
    ) throws -> Int {
        if expression.isZero { return 0 }
        let sequence = try ExactUnivariateSturmSequence(expression, usage: &usage)
        let lower = span.followsOriginalParameterDirection ? span.chart.start : span.chart.end
        let upper = span.followsOriginalParameterDirection ? span.chart.end : span.chart.start
        var count = try variations(sequence.chain, at: lower,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
            - variations(sequence.chain, at: upper,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        // A square-free Sturm difference excludes the lower endpoint and includes
        // the upper endpoint. Remove that exact upper root for an open chart.
        if try endpointSign(sequence.source, at: upper,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage) == 0 {
            count -= 1
        }
        guard count >= 0 else {
            throw GeometryConversionError.invalidInput("Original open-chart Sturm signs contradict endpoint ordering.")
        }
        if count != 0 { return 0 }

        // With no interior roots, the first nonzero Taylor coefficient at the
        // actual start fixes the whole open sign. No approximate station is used.
        let direction = span.followsOriginalParameterDirection ? 1 : -1
        var derivative = expression
        var directedFactor = direction
        while !derivative.isZero {
            let sign = try endpointSign(derivative, at: span.chart.start,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
            if sign != 0 { return sign * directedFactor }
            derivative = try derivative.differentiated(alongU: true, usage: &usage)
            directedFactor *= direction
        }
        throw GeometryConversionError.invalidInput("A nonzero original orbit numerator has no finite endpoint sign.")
    }
}
