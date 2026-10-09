extension DefaultOriginalScalarTransporter {
    public func bindSelectedRoot<A: ExactScalarAdmission & ~Copyable>(
        coefficients: borrowing [OriginalExactScalar],
        in parent: borrowing OriginalExactScalarDomain,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        includesLower: Bool, includesUpper: Bool, depth: ExactScalarDepth,
        axis: ExactScalarRootAxis, using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalScalarSelectedRootReceipt {
        try admission.checkpoint()
        var inherited = try ExactScalarDepth(value: max(parent.originalDepth.value, depth.value),
            coefficient: max(parent.originalDepth.coefficient, depth.coefficient))
        for index in coefficients.indices {
            try admission.consumeWork(1)
            let value = coefficients[index]
            guard value.original.context === parent.context else { throw .incompatibleDomain }
            inherited = try .init(value: max(inherited.value, value.depth.value),
                coefficient: max(inherited.coefficient, value.depth.coefficient))
        }
        let result = try ExactScalarNumericAccess.withAdmission(&admission,
            original: try .init(value: max(parent.originalDepth.value, depth.value),
                coefficient: max(parent.originalDepth.coefficient, depth.coefficient)), inherited: inherited,
            maximum: .init(uncheckedValue: parent.maximumValueDepth,
                coefficient: parent.maximumCoefficientDepth)) { usage in
            guard coefficients.count >= 2,
                !(try upper.subtracting(lower, usage: &usage)).isNegative else {
                throw ExactScalarFailure.invalidEvidence
            }
            try RationalAlgebraStorage.retain(coefficients.count,
                of: OriginalSingularFieldElement.self, usage: &usage)
            var raw: [OriginalSingularFieldElement] = []; raw.reserveCapacity(coefficients.count)
            for index in coefficients.indices {
                try usage.consumeExactWork(1); raw.append(coefficients[index].original)
            }
            let limit = axis == .value ? parent.maximumValueDepth : parent.maximumCoefficientDepth
            let polynomial = try OriginalSingularFieldPolynomial(context: parent.context,
                coefficients: raw, maximumDepth: limit, usage: &usage)
            let sequence = try OriginalSingularFieldSturm(polynomial,
                maximumDepth: limit, usage: &usage)
            guard try sequence.count(lower: lower, upper: upper,
                excludesLower: !includesLower, excludesUpper: !includesUpper,
                maximumDepth: limit, usage: &usage) == 1 else {
                throw ExactScalarFailure.invalidEvidence
            }
            let root = OriginalSingularFieldRoot(polynomial: polynomial,
                isolation: .init(lower: lower, upper: upper,
                    excludesLower: !includesLower, excludesUpper: !includesUpper,
                    depth: axis == .value ? depth.value : depth.coefficient),
                admissionDomain: axis == .value ? .parameter : .coefficient(maximumDepth: limit))
            return try root.value(maximumDepth: limit, usage: &usage)
        }
        let value = OriginalExactScalar(original: result.value, depth: result.depth)
        let field = try OriginalExactScalarDomain(retaining: value,
            maximumValueDepth: parent.maximumValueDepth,
            maximumCoefficientDepth: parent.maximumCoefficientDepth, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: OriginalScalarSelectedRootReceipt.self))
        let receipt = OriginalScalarSelectedRootReceipt(coefficients: copy coefficients,
            field: field, value: value, lower: lower, upper: upper, axis: axis)
        try admission.checkpoint(); return receipt
    }
}
