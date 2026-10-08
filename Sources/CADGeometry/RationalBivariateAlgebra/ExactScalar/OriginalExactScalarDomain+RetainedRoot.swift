extension OriginalExactScalarDomain {
    /// Adjoins a sealed original rational root to this parent's immutable real field.
    /// Exact rational embedding preserves its unique-root selector; no search runs.
    public init<A: ExactScalarAdmission & ~Copyable>(extending parent: borrowing Self,
        root: ExactAlgebraicRealRoot, axis: ExactScalarRootAxis, using admission: inout A
    ) throws(ExactScalarFailure) {
        try admission.checkpoint()
        let parent = copy parent
        let inherited = try ExactScalarDepth(
            value: max(parent.originalDepth.value, axis == .value ? root.isolation.isolationDepth : 0),
            coefficient: max(parent.originalDepth.coefficient, axis == .coefficient ? root.isolation.isolationDepth : 0))
        guard inherited.value <= parent.maximumValueDepth else { throw .resourceLimit(.valueDepth) }
        guard inherited.coefficient <= parent.maximumCoefficientDepth else { throw .resourceLimit(.coefficientDepth) }
        try admission.admitDepth(value: inherited.value, coefficient: inherited.coefficient)
        let result = try ExactScalarNumericAccess.withAdmission(&admission,
            original: parent.originalDepth, inherited: inherited,
            maximum: .init(value: parent.maximumValueDepth, coefficient: parent.maximumCoefficientDepth)) { usage in
            // Degree getters each scan the canonical original coefficient dictionary.
            try usage.consumeExactWork(try exactScalarCount(root.polynomial.coefficients.count, 2, multiply: true))
            let count = try exactScalarCount(root.polynomial.uDegree, 1)
            guard count > 1, root.polynomial.vDegree <= 0 else { throw ExactScalarFailure.invalidEvidence }
            try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
            var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(count)
            for index in 0..<count {
                try usage.consumeExactWork(1)
                let coefficient = root.polynomial.coefficients[try .init(u: index, v: 0)] ?? .zero
                coefficients.append(try .constant(coefficient, in: parent.context,
                    maximumDepth: parent.maximumValueDepth, usage: &usage))
            }
            let polynomial = try OriginalSingularFieldPolynomial(context: parent.context,
                coefficients: coefficients, maximumDepth: parent.maximumValueDepth, usage: &usage)
            let selected = OriginalSingularFieldRoot(polynomial: polynomial,
                isolation: .init(lower: root.isolation.lower, upper: root.isolation.upper,
                    excludesLower: root.isolation.excludesLowerEndpoint,
                    excludesUpper: root.isolation.excludesUpperEndpoint, depth: root.isolation.isolationDepth),
                admissionDomain: axis == .value ? .parameter : .coefficient(maximumDepth: parent.maximumCoefficientDepth))
            let child = try OriginalSingularFieldContext(root: selected, usage: &usage)
            guard case .extended(let zero, let unit) = child.constantAuthority else {
                throw ExactScalarFailure.invalidEvidence
            }
            // Share the child's already-owned zero/unit; retain its context through
            // the existing public domain constructor without another payload.
            return OriginalSingularFieldElement(context: child, storage: .extended(zero, unit))
        }
        try self.init(retaining: .init(original: result.value, depth: result.depth),
            maximumValueDepth: parent.maximumValueDepth, maximumCoefficientDepth: parent.maximumCoefficientDepth,
            using: &admission)
        try admission.checkpoint()
    }
}
