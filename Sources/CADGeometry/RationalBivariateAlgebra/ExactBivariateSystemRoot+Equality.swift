/// Equality of retained original pairs by common selected source roots.
extension ExactBivariateSystemRoot {
    package func hasSameValue<B: RationalAlgebraAdmitting>(as other: Self,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        guard try ExactMonotoneGraphEndpoint.algebraic(projectionRoot).hasSameValue(
            as: .algebraic(other.projectionRoot), maximumDepth: maximumDepth, usage: &usage) else { return false }
        let rebound = ExactAlgebraicFiberPolynomial(root: projectionRoot, coefficients: other.fiber.coefficients)
        let common = try ExactAlgebraicFiberPolynomial.gcd(fiber, rebound, maximumDepth: maximumDepth, usage: &usage)
        if common.degree <= 0 { return false }
        let a = fiberRoot, b = other.fiberRoot
        let lowerDifference = try a.lower.subtracting(b.lower, usage: &usage)
        let upperDifference = try a.upper.subtracting(b.upper, usage: &usage)
        let lower = lowerDifference.isPositive ? a.lower : b.lower
        let upper = upperDifference.isNegative ? a.upper : b.upper
        if try upper.subtracting(lower, usage: &usage).isNegative { return false }
        let excludesLower = lowerDifference.isPositive ? a.excludesLower : lowerDifference.isNegative ? b.excludesLower : a.excludesLower || b.excludesLower
        let excludesUpper = upperDifference.isNegative ? a.excludesUpper : upperDifference.isPositive ? b.excludesUpper : a.excludesUpper || b.excludesUpper
        let sturm = try ExactAlgebraicFiberSturmSequence(common, maximumDepth: maximumDepth, usage: &usage)
        return try sturm.count(lower: lower, upper: upper, excludesLower: excludesLower,
            excludesUpper: excludesUpper, maximumDepth: maximumDepth, usage: &usage) == 1
    }
}
