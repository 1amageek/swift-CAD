import CADCore

/// Descendant visits retain the original raw proof's causal depth on the same caller ledger.
struct OriginalBoundaryAdmission: Sendable {
    let parameterDepth: Int
    let coefficientDepth: Int

    func withScope<A: ExactScalarAdmission & ~Copyable, Result>(
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: inout A,
        _ body: (inout A) throws -> Result
    ) throws -> Result {
        guard parameterDepth <= maximumDepth, coefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Boundary query cannot reset its retained source depth.")
        }
        return try usage.withProofScope(
            inherited: .init(value: parameterDepth, coefficient: coefficientDepth),
            maximum: .init(value: maximumDepth, coefficient: maximumCoefficientDepth), body)
    }
}
