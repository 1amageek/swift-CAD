import CADCore

/// One retained square-free original factor divided exactly from every XYZ equation.
struct OriginalNativeCurveCurveCommonFactor: Sendable {
    let factor: ExactBivariatePolynomial
    let quotients: [ExactBivariatePolynomial]
    let derivativeU: ExactBivariatePolynomial
    let derivativeV: ExactBivariatePolynomial

    init(retainingSubfactor source: ExactBivariatePolynomial,
        of original: OriginalNativeCurveCurveCommonFactor,
        budget: inout NativeCurveCurveContactBudget) throws {
        guard !source.isZero, source.uDegree > 0 || source.vDegree > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: budget.tolerance,
                message: "An original contact subfactor must retain a nonconstant original law.")
        }
        let other = try original.factor.dividedExactly(by: source, usage: &budget)
        try budget.retainExactStorage(original.quotients.count)
        quotients = try original.quotients.map { try $0.multiplied(by: other, usage: &budget) }
        factor = source
        derivativeU = try source.differentiated(alongU: true, usage: &budget)
        derivativeV = try source.differentiated(alongU: false, usage: &budget)
    }

    init?(equations: [ExactBivariatePolynomial], budget: inout NativeCurveCurveContactBudget) throws {
        guard equations.count == 3 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: budget.tolerance,
                message: "An original curve common factor requires every XYZ equation.")
        }
        let gcd = ExactBivariateGCD()
        var source = try gcd.greatestCommonDivisor(equations[0], equations[1], usage: &budget)
        source = try gcd.greatestCommonDivisor(source, equations[2], usage: &budget)
        guard !source.isZero, source.uDegree > 0 || source.vDegree > 0 else { return nil }
        let repeatedU = try gcd.greatestCommonDivisor(source,
            source.differentiated(alongU: true, usage: &budget), usage: &budget)
        let repeated = try gcd.greatestCommonDivisor(repeatedU,
            source.differentiated(alongU: false, usage: &budget), usage: &budget)
        source = try source.dividedExactly(by: repeated, usage: &budget)
        try budget.retainExactStorage(3)
        quotients = try equations.map { try $0.dividedExactly(by: source, usage: &budget) }
        factor = source
        derivativeU = try source.differentiated(alongU: true, usage: &budget)
        derivativeV = try source.differentiated(alongU: false, usage: &budget)
    }
}
