import CADCore

extension OriginalAffineOperationWord {
    /// Inverts the original operation directions and exact derived action, never rounded columns.
    public func inverted<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        try OriginalAffineRationalMatrix.retain(factors.count, of: OriginalAffineOperation.self, usage: &usage)
        var inverseFactors: [OriginalAffineOperation] = []; inverseFactors.reserveCapacity(factors.count)
        for factor in factors.reversed() {
            try usage.consumeExactWork(1)
            switch factor {
            case .forward(let source): inverseFactors.append(.inverse(source))
            case .inverse(let source): inverseFactors.append(.forward(source))
            case .rationalForward(let source): inverseFactors.append(.rationalInverse(source))
            case .rationalInverse(let source): inverseFactors.append(.rationalForward(source))
            case .normalizedForward(let source): inverseFactors.append(.normalizedInverse(source))
            case .normalizedInverse(let source): inverseFactors.append(.normalizedForward(source))
            }
        }
        if isRational {
            let inverse = try OriginalAffineRationalMatrix.inverse(coefficients, determinant: determinantCoefficient, usage: &usage)
            let cofactor = try OriginalAffineRationalMatrix.cofactors(inverse, usage: &usage)
            let determinant = try ExactRationalCoefficient.one.divided(by: determinantCoefficient, usage: &usage)
            return Self(originalFactors: inverseFactors, coefficients: inverse, cofactors: cofactor,
                determinant: determinant, maximumDepth: maximumDepth, orientationSign: orientationSign)
        }
        guard let frame = normalizedFrame else { throw rationalAlgebraFailure("Original inverse is missing its action receipt.") }
        let inverse = try frame.inverse(maximumDepth: maximumDepth, usage: &usage)
        let cofactor = try OriginalAffineFieldAction.cofactors(inverse, maximumDepth: maximumDepth, usage: &usage)
        let determinant = try OriginalAffineFieldAction.determinant(inverse, cofactors: cofactor, maximumDepth: maximumDepth, usage: &usage)
        return Self(originalFactors: inverseFactors, frame: inverse, cofactors: cofactor,
            determinant: determinant, maximumDepth: maximumDepth, orientationSign: orientationSign)
    }
}
