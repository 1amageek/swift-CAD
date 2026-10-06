/// Evaluates the original local law at a retained descendant-field point.
extension OriginalSingularFieldPlanePolynomial {
    package func evaluated<B: RationalAlgebraAdmitting>(atU u: OriginalSingularFieldElement,
        v: OriginalSingularFieldElement, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        guard u.context === v.context else { throw rationalAlgebraFailure("Original local point has unrelated coordinate fields.") }
        var result = try OriginalSingularFieldElement.constant(.zero, in: u.context,
            maximumDepth: maximumDepth, usage: &usage)
        for (power, coefficient) in try orderedTerms(usage: &usage) {
            var term = try coefficient.embedded(in: u.context, maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<power.u { term = try term.multiplied(by: u, maximumDepth: maximumDepth, usage: &usage) }
            for _ in 0..<power.v { term = try term.multiplied(by: v, maximumDepth: maximumDepth, usage: &usage) }
            result = try result.adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
}
