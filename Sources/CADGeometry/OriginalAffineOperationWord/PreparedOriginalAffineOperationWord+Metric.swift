import CADCore

extension PreparedOriginalAffineOperationWord {
    /// Proves a physical length threshold for an exact similarity; nil means nonsimilarity.
    public func similarityScaledLengthIsGreaterThan<B: RationalAlgebraAdmitting>(
        originalLength: Double, physicalThreshold: Double, usage: inout B) throws -> Bool? {
        guard originalLength.isFinite, originalLength >= 0,
              physicalThreshold.isFinite, physicalThreshold >= 0 else {
            throw rationalAlgebraFailure("Original physical length comparison requires finite nonnegative values.")
        }
        let length = try ExactRationalCoefficient.originalDouble(originalLength, usage: &usage)
        let threshold = try ExactRationalCoefficient.originalDouble(physicalThreshold, usage: &usage)
        let lengthSquared = try length.multiplied(by: length, usage: &usage)
        let thresholdSquared = try threshold.multiplied(by: threshold, usage: &usage)
        return try similarityScaledSquaredLengthIsGreaterThan(lengthSquared, thresholdSquared: thresholdSquared, usage: &usage)
    }

    /// Compares the original exact gap; subtraction is never rounded into source.
    public func similarityScaledDifferenceIsGreaterThan<B: RationalAlgebraAdmitting>(
        originalLower: Double, originalUpper: Double, physicalThreshold: Double,
        usage: inout B) throws -> Bool? {
        guard originalLower.isFinite, originalLower >= 0, originalUpper.isFinite,
              originalUpper >= originalLower, physicalThreshold.isFinite, physicalThreshold >= 0 else {
            throw rationalAlgebraFailure("Original physical gap comparison requires ordered finite nonnegative lengths.")
        }
        let lower = try ExactRationalCoefficient.originalDouble(originalLower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(originalUpper, usage: &usage)
        let difference = try upper.subtracting(lower, usage: &usage)
        let threshold = try ExactRationalCoefficient.originalDouble(physicalThreshold, usage: &usage)
        let squaredDifference = try difference.multiplied(by: difference, usage: &usage)
        let squaredThreshold = try threshold.multiplied(by: threshold, usage: &usage)
        return try similarityScaledSquaredLengthIsGreaterThan(squaredDifference,
            thresholdSquared: squaredThreshold, usage: &usage)
    }

    private func similarityScaledSquaredLengthIsGreaterThan<B: RationalAlgebraAdmitting>(
        _ lengthSquared: ExactRationalCoefficient, thresholdSquared: ExactRationalCoefficient,
        usage: inout B) throws -> Bool? {
        if source.isRational {
            let scale = try rationalGram(0, 0, usage: &usage)
            guard scale.isPositive else { throw rationalAlgebraFailure("Original similarity metric is singular.") }
            for axis in 1..<3 {
                if try !rationalGram(axis, axis, usage: &usage).subtracting(scale, usage: &usage).isZero { return nil }
            }
            for first in 0..<3 {
                for second in (first + 1)..<3 {
                    if try !rationalGram(first, second, usage: &usage).isZero { return nil }
                }
            }
            return try scale.multiplied(by: lengthSquared, usage: &usage)
                .subtracting(thresholdSquared, usage: &usage).isPositive
        }
        guard let frame = source.normalizedFrame else {
            throw rationalAlgebraFailure("Original similarity is missing its immutable field receipt.")
        }
        let depth = source.maximumDepth
        let scale = try fieldGram(0, 0, frame: frame, usage: &usage)
        guard case .positive = try scale.sign(maximumDepth: depth, usage: &usage) else {
            throw rationalAlgebraFailure("Original similarity metric is singular.")
        }
        for axis in 1..<3 {
            let other = try fieldGram(axis, axis, frame: frame, usage: &usage)
            guard case .zero = try other.subtracting(scale, maximumDepth: depth, usage: &usage)
                .sign(maximumDepth: depth, usage: &usage) else { return nil }
        }
        for first in 0..<3 {
            for second in (first + 1)..<3 {
                guard case .zero = try fieldGram(first, second, frame: frame, usage: &usage)
                    .sign(maximumDepth: depth, usage: &usage) else { return nil }
            }
        }
        let squaredLength = try OriginalSingularFieldElement.constant(lengthSquared,
            in: frame.context, maximumDepth: depth, usage: &usage)
        let squaredThreshold = try OriginalSingularFieldElement.constant(thresholdSquared,
            in: frame.context, maximumDepth: depth, usage: &usage)
        let difference = try scale.multiplied(by: squaredLength, maximumDepth: depth, usage: &usage)
            .subtracting(squaredThreshold, maximumDepth: depth, usage: &usage)
        if case .positive = try difference.sign(maximumDepth: depth, usage: &usage) { return true }
        return false
    }

    /// Bounds the inverse action without rounding inverse coefficients into source.
    public func inverseLinearNormUpper<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Double {
        if source.isRational {
            var sum = ExactRationalCoefficient.zero
            for row in 0..<3 {
                for column in 0..<3 {
                    try usage.consumeExactWork(1)
                    let coefficient = source.cofactorCoefficients[row * 4 + column]
                    sum = try sum.adding(coefficient.multiplied(by: coefficient, usage: &usage), usage: &usage)
                }
            }
            let determinantSquared = try source.determinantCoefficient.multiplied(by: source.determinantCoefficient, usage: &usage)
            return try OriginalAffineRationalMatrix.squareRootUpper(sum.divided(by: determinantSquared, usage: &usage), usage: &usage)
        }
        guard let frame = source.normalizedFrame, let determinant = source.normalizedDeterminant else {
            throw rationalAlgebraFailure("Original inverse metric is missing its immutable field receipt.")
        }
        let depth = source.maximumDepth
        var sum = try OriginalSingularFieldElement.constant(.zero,
            in: frame.context, maximumDepth: depth, usage: &usage)
        for coefficient in source.normalizedCofactors {
            try usage.consumeExactWork(1)
            sum = try sum.adding(coefficient.multiplied(by: coefficient, maximumDepth: depth, usage: &usage),
                maximumDepth: depth, usage: &usage)
        }
        let determinantSquared = try determinant.multiplied(by: determinant, maximumDepth: depth, usage: &usage)
        let square = try sum.divided(by: determinantSquared, maximumDepth: depth, usage: &usage)
        return try OriginalAffineFieldAction.squareRootUpper(square, maximumDepth: depth, usage: &usage)
    }

    private func rationalGram<B: RationalAlgebraAdmitting>(_ first: Int, _ second: Int,
        usage: inout B) throws -> ExactRationalCoefficient {
        var sum = ExactRationalCoefficient.zero
        for row in 0..<3 {
            try usage.consumeExactWork(1)
            sum = try sum.adding(source.coefficients[row * 4 + first]
                .multiplied(by: source.coefficients[row * 4 + second], usage: &usage), usage: &usage)
        }
        return sum
    }
    private func fieldGram<B: RationalAlgebraAdmitting>(_ first: Int, _ second: Int,
        frame: OriginalRationalNormalizedFrame, usage: inout B) throws -> OriginalSingularFieldElement {
        let depth = source.maximumDepth
        var sum = try OriginalSingularFieldElement.constant(.zero,
            in: frame.context, maximumDepth: depth, usage: &usage)
        for row in 0..<3 {
            try usage.consumeExactWork(1)
            let a = try OriginalAffineFieldAction.coefficient(frame, row: row, column: first, maximumDepth: depth, usage: &usage)
            let b = try OriginalAffineFieldAction.coefficient(frame, row: row, column: second, maximumDepth: depth, usage: &usage)
            sum = try sum.adding(a.multiplied(by: b, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        }
        return sum
    }
}
