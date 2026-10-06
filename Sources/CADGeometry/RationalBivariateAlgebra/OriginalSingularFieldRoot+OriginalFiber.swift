/// Transports a retained rational source fiber into an existing ordered field.
extension OriginalSingularFieldRoot {
    package static func retaining<B: RationalAlgebraAdmitting>(_ original: Self,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> Self {
        let maximumDepth = original.admissionDomain.limit(maximumDepth)
        var values: [OriginalSingularFieldElement] = []
        try RationalAlgebraStorage.retain(original.polynomial.coefficients.count,
            of: OriginalSingularFieldElement.self, usage: &usage)
        values.reserveCapacity(original.polynomial.coefficients.count)
        for coefficient in original.polynomial.coefficients {
            values.append(try coefficient.embedded(in: context, maximumDepth: maximumDepth, usage: &usage))
        }
        let polynomial = try OriginalSingularFieldPolynomial(context: context, coefficients: values,
            maximumDepth: maximumDepth, usage: &usage)
        let bounds = original.isolation
        let depth = max(original.admissionDomain.inheritedDepth(of: context), bounds.depth)
        guard depth <= maximumDepth else { throw rationalAlgebraFailure("Original field fiber exceeds causal caller depth.") }
        try original.admissionDomain.visit(depth, usage: &usage)
        let sequence = try OriginalSingularFieldSturm(polynomial, maximumDepth: maximumDepth, usage: &usage)
        guard try sequence.count(lower: bounds.lower, upper: bounds.upper,
            excludesLower: bounds.excludesLower, excludesUpper: bounds.excludesUpper,
            maximumDepth: maximumDepth, usage: &usage) == 1 else {
            throw rationalAlgebraFailure("Original field fiber transport lost unique original root authority.")
        }
        return Self(polynomial: sequence.source, isolation: .init(lower: bounds.lower, upper: bounds.upper,
            excludesLower: bounds.excludesLower, excludesUpper: bounds.excludesUpper, depth: depth),
            admissionDomain: original.admissionDomain)
    }
    package static func retaining<B: RationalAlgebraAdmitting>(_ original: ExactAlgebraicRealRoot,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> Self {
        guard original.polynomial.vDegree <= 0, original.polynomial.uDegree > 0 else {
            throw rationalAlgebraFailure("Original strip fiber is not a univariate nonconstant law.")
        }
        let count = try rationalAlgebraCount(original.polynomial.uDegree, 1)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for (power, coefficient) in try original.polynomial.orderedTerms(usage: &usage) {
            coefficients[power.u] = try .constant(coefficient, in: context,
                maximumDepth: maximumDepth, usage: &usage)
        }
        let polynomial = try OriginalSingularFieldPolynomial(context: context, coefficients: coefficients,
            maximumDepth: maximumDepth, usage: &usage)
        let depth = max(context.depth, original.isolation.isolationDepth)
        guard depth <= maximumDepth else { throw rationalAlgebraFailure("Original fiber exceeds inherited caller depth.") }
        try usage.visitExactCell(depth: depth)
        let sequence = try OriginalSingularFieldSturm(polynomial, maximumDepth: maximumDepth, usage: &usage)
        let isolation = original.isolation
        guard try sequence.count(lower: isolation.lower, upper: isolation.upper,
            excludesLower: isolation.excludesLowerEndpoint, excludesUpper: isolation.excludesUpperEndpoint,
            maximumDepth: maximumDepth, usage: &usage) == 1 else {
            throw rationalAlgebraFailure("Original fiber transport lost its retained unique source root.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(polynomial: polynomial, isolation: .init(lower: isolation.lower, upper: isolation.upper,
            excludesLower: isolation.excludesLowerEndpoint, excludesUpper: isolation.excludesUpperEndpoint, depth: depth))
    }
}
