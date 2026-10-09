extension OriginalSingularFieldTransport {
    /// Imports an existing scalar parameter authority without solving its source again.
    package func originalScalarValue<B: RationalAlgebraAdmitting>(
        _ endpoint: ExactMonotoneGraphEndpoint, into destination: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        switch endpoint {
        case .authored(let value):
            return try .constant(value, in: destination, maximumDepth: maximumDepth, usage: &usage)
        case .algebraic(let root):
            let polynomial = try rationalUnivariate(root.polynomial, in: destination,
                maximumDepth: maximumDepth, usage: &usage)
            let bounds = root.isolation
            return try retainedRoot(polynomial, isolation: .init(lower: bounds.lower,
                upper: bounds.upper, excludesLower: bounds.excludesLowerEndpoint,
                excludesUpper: bounds.excludesUpperEndpoint, depth: bounds.isolationDepth),
                maximumDepth: maximumDepth, usage: &usage)
        }
    }

}
