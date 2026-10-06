/// Shared exact original Euclidean-length authority over a retained ordered field.
package extension OriginalSingularFieldElement {
    func nonnegativeSquareRoot<B: RationalAlgebraAdmitting>(inheritedDepth: Int,
        maximumDepth: Int, admissionDomain: OriginalSingularFieldRoot.AdmissionDomain = .parameter,
        usage: inout B) throws -> Self {
        let parentDepth = max(admissionDomain.inheritedDepth(of: context), inheritedDepth)
        guard inheritedDepth >= 0, parentDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original square root requires admitted inherited source depth.")
        }
        switch try sign(maximumDepth: maximumDepth, usage: &usage) {
        case .negative: throw rationalAlgebraFailure("Original square root radicand is negative.")
        case .zero: return try .constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        case .positive: break
        }
        if let rational = try rationalValue(usage: &usage),
            let root = try rational.exactSquareRoot(usage: &usage) {
            return try .constant(root, in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        let zero = try Self.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        let one = try Self.constant(.one, in: context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: Self.self, usage: &usage)
        let polynomial = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [negated(maximumDepth: maximumDepth, usage: &usage), zero, one],
            maximumDepth: maximumDepth, usage: &usage)
        let roots = try OriginalSingularFieldRoot.allRealRoots(polynomial,
            inheritedDepth: parentDepth, maximumDepth: maximumDepth, admissionDomain: admissionDomain, usage: &usage)
        var selected: Self?
        for root in roots {
            let value = try root.value(maximumDepth: maximumDepth, usage: &usage)
            if case .positive = try value.sign(maximumDepth: maximumDepth, usage: &usage) {
                if case .some = selected { throw rationalAlgebraFailure("Original positive square root is not unique.") }
                selected = value
            }
        }
        guard let retained = selected else { throw rationalAlgebraFailure("Original positive radicand has no retained positive square root.") }
        return retained
    }
}
