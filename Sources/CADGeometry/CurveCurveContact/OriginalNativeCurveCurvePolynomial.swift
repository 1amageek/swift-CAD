import CADCore

/// Original XYZ homogeneous differences in the two original native parameters.
struct OriginalNativeCurveCurvePolynomial: Sendable {
    let equations: [ExactBivariatePolynomial]
    let denominator: ExactBivariatePolynomial
    let commonFactor: OriginalNativeCurveCurveCommonFactor?

    init(firstSource: BSplineCurve3D, first: RationalBezierCurveJetEncloser.NativeSpan,
         secondSource: BSplineCurve3D, second: RationalBezierCurveJetEncloser.NativeSpan,
         budget: inout NativeCurveCurveContactBudget) throws {
        func homogeneous(_ source: BSplineCurve3D, span: RationalBezierCurveJetEncloser.NativeSpan,
                         alongU: Bool, budget: inout NativeCurveCurveContactBudget) throws -> [ExactBivariatePolynomial] {
            guard span.index >= source.degree, span.index < source.controlPointCount,
                  source.knots[span.index] == span.lower, source.knots[span.index + 1] == span.upper else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: budget.tolerance,
                    message: "Exact original curve algebra lost its validated native source span.")
            }
            let basis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.knots,
                degree: source.degree, span: span.index, alongU: alongU, translation: 0, usage: &budget)
            try budget.retainExactStorage(4)
            var values = [ExactBivariatePolynomial](repeating: .zero, count: 4)
            for index in (span.index - source.degree)...span.index {
                guard let coefficient = basis[index] else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: budget.tolerance,
                        message: "An original curve polynomial has no coefficient for its owning native control.")
                }
                let weight = try ExactRationalCoefficient.originalDouble(source.weights[index], usage: &budget)
                let point = source.controlPoints[index]
                for (axis, coordinate) in [point.x, point.y, point.z].enumerated() {
                    let value = try ExactRationalCoefficient.originalDouble(coordinate, usage: &budget)
                        .multiplied(by: weight, usage: &budget)
                    values[axis] = try values[axis].adding(coefficient.scaled(by: value, usage: &budget), usage: &budget)
                }
                values[3] = try values[3].adding(coefficient.scaled(by: weight, usage: &budget), usage: &budget)
            }
            return values
        }
        let a = try homogeneous(firstSource, span: first, alongU: true, budget: &budget)
        let b = try homogeneous(secondSource, span: second, alongU: false, budget: &budget)
        try budget.retainExactStorage(3)
        var output: [ExactBivariatePolynomial] = []
        for axis in 0..<3 {
            output.append(try a[axis].multiplied(by: b[3], usage: &budget)
                .subtracting(b[axis].multiplied(by: a[3], usage: &budget), usage: &budget))
        }
        equations = output
        denominator = try a[3].multiplied(by: b[3], usage: &budget)
        commonFactor = try OriginalNativeCurveCurveCommonFactor(equations: output, budget: &budget)
    }
}
