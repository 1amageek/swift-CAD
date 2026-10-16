/// Original homogeneous geometry acted on by an exact authored placement word.
package struct OriginalFieldHomogeneousImage: Sendable {
    package let original: [ExactBivariatePolynomial]
    package let sourceWord: OriginalAffineOperationWord
    package let context: OriginalSingularFieldContext
    package let homogeneous: [OriginalSingularFieldPlanePolynomial]
    package let maximumAlgebraicDepth: Int

    package init<B: ExactScalarAdmission & ~Copyable>(original: [ExactBivariatePolynomial],
        prepared: PreparedOriginalAffineOperationWord, into destination: OriginalSingularFieldContext,
        transport: inout OriginalSingularFieldTransport, maximumDepth: Int, usage: inout B) throws {
        guard original.count == 4, !original[3].isZero, maximumDepth >= 0 else {
            throw rationalAlgebraFailure("Original homogeneous word action requires exactly XYZ/W and a caller depth.")
        }
        let frame = try prepared.originalNormalizedFrame(usage: &usage)
        let depth = frame.map { min(maximumDepth, $0.maximumAlgebraicDepth) } ?? maximumDepth
        let target: OriginalSingularFieldContext
        if let frame {
            guard frame.frame.basisX.count == 3, frame.frame.basisY.count == 3,
                frame.frame.basisZ.count == 3, frame.frame.translation.count == 3 else {
                throw rationalAlgebraFailure("Original normalized frame lost its three exact columns.")
            }
            target = try transport.importing(frame.frame.basisX[0].context, into: destination,
                maximumDepth: depth, usage: &usage)
        } else { target = destination }
        guard target.depth <= depth else {
            throw rationalAlgebraFailure("Original homogeneous image inherited a field beyond the composing caller depth.")
        }
        var lifted: [OriginalSingularFieldPlanePolynomial] = []
        try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        lifted.reserveCapacity(4)
        for polynomial in original {
            lifted.append(try Self.lift(polynomial, into: target, maximumDepth: depth, usage: &usage))
        }
        var result: [OriginalSingularFieldPlanePolynomial] = []
        try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        result.reserveCapacity(4)
        for row in 0..<3 {
            var coordinate = try OriginalSingularFieldPlanePolynomial(context: target,
                coefficients: [:], maximumDepth: depth, usage: &usage)
            for column in 0..<4 {
                try usage.consumeWork(1)
                let coefficient: OriginalSingularFieldElement
                if let frame {
                    let source: OriginalSingularFieldElement
                    switch column {
                    case 0: source = frame.frame.basisX[row]
                    case 1: source = frame.frame.basisY[row]
                    case 2: source = frame.frame.basisZ[row]
                    default: source = frame.frame.translation[row]
                    }
                    coefficient = try transport.applying(to: source, in: target,
                        maximumDepth: depth, usage: &usage)
                } else {
                    let source = try column == 3 ? prepared.translationCoefficient(row: row)
                        : prepared.linearCoefficient(row: row, column: column)
                    coefficient = try .constant(source, in: target, maximumDepth: depth, usage: &usage)
                }
                let scale = try OriginalSingularFieldPlanePolynomial.constant(coefficient,
                    maximumDepth: depth, usage: &usage)
                coordinate = try coordinate.adding(lifted[column].multiplied(by: scale,
                    maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            }
            result.append(coordinate)
        }
        result.append(lifted[3])
        self.original = original; sourceWord = prepared.source; context = target
        homogeneous = result; maximumAlgebraicDepth = depth
    }

    /// Embeds an earlier image after another original word extends the shared tower.
    package func embedded<B: ExactScalarAdmission & ~Copyable>(in target: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldPlanePolynomial] {
        var result: [OriginalSingularFieldPlanePolynomial] = []
        try RationalAlgebraStorage.retain(homogeneous.count, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        result.reserveCapacity(homogeneous.count)
        let depth = min(maximumDepth, maximumAlgebraicDepth)
        for polynomial in homogeneous {
            result.append(try polynomial.embedded(in: target, maximumDepth: depth, usage: &usage))
        }
        return result
    }

    /// Composes another immutable original word without reconstructing prior source coefficients.
    package static func applying<B: ExactScalarAdmission & ~Copyable>(prepared: PreparedOriginalAffineOperationWord,
        to original: [OriginalSingularFieldPlanePolynomial], transport: inout OriginalSingularFieldTransport,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldPlanePolynomial] {
        guard original.count == 4, let first = original.first, !original[3].isZero else {
            throw rationalAlgebraFailure("Original field word composition requires complete homogeneous coefficients.")
        }
        let frame = try prepared.originalNormalizedFrame(usage: &usage)
        // Both bounds refer to coefficient-field refinement, never UV-cell depth.
        let coefficientDepth = frame.map { min(maximumDepth, $0.maximumAlgebraicDepth) } ?? maximumDepth
        let target: OriginalSingularFieldContext
        if let frame {
            target = try transport.importing(frame.frame.context, into: first.context,
                maximumDepth: coefficientDepth, usage: &usage)
        } else { target = first.context }
        return try action(prepared: prepared, frame: frame?.frame, original: original,
            target: target, transport: &transport, maximumDepth: coefficientDepth, usage: &usage)
    }

    private static func action<B: ExactScalarAdmission & ~Copyable>(prepared: PreparedOriginalAffineOperationWord,
        frame: OriginalRationalNormalizedFrame?, original: [OriginalSingularFieldPlanePolynomial],
        target: OriginalSingularFieldContext, transport: inout OriginalSingularFieldTransport,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldPlanePolynomial] {
        try RationalAlgebraStorage.retain(8, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        var lifted: [OriginalSingularFieldPlanePolynomial] = []; lifted.reserveCapacity(4)
        for polynomial in original {
            guard polynomial.context === original[0].context else {
                throw rationalAlgebraFailure("Original field homogeneous coordinates have unrelated coefficient owners.")
            }
            lifted.append(try polynomial.embedded(in: target, maximumDepth: maximumDepth, usage: &usage))
        }
        var result: [OriginalSingularFieldPlanePolynomial] = []; result.reserveCapacity(4)
        for row in 0..<3 {
            var coordinate = try OriginalSingularFieldPlanePolynomial(context: target,
                coefficients: [:], maximumDepth: maximumDepth, usage: &usage)
            for column in 0..<4 {
                try usage.consumeWork(1)
                let coefficient: OriginalSingularFieldElement
                if let frame {
                    let raw: OriginalSingularFieldElement
                    switch column {
                    case 0: raw = frame.basisX[row]
                    case 1: raw = frame.basisY[row]
                    case 2: raw = frame.basisZ[row]
                    default: raw = frame.translation[row]
                    }
                    coefficient = try transport.applying(to: raw, in: target,
                        maximumDepth: maximumDepth, usage: &usage)
                } else {
                    let raw = try column == 3 ? prepared.translationCoefficient(row: row)
                        : prepared.linearCoefficient(row: row, column: column)
                    coefficient = try .constant(raw, in: target, maximumDepth: maximumDepth, usage: &usage)
                }
                coordinate = try coordinate.adding(lifted[column].multiplied(by:
                    .constant(coefficient, maximumDepth: maximumDepth, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            }
            result.append(coordinate)
        }
        result.append(lifted[3]); return result
    }

    package static func lift<B: ExactScalarAdmission & ~Copyable>(_ original: ExactBivariatePolynomial,
        into context: OriginalSingularFieldContext, maximumDepth: Int,
        usage: inout B) throws -> OriginalSingularFieldPlanePolynomial {
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        try RationalAlgebraStorage.retain(original.coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        for (power, coefficient) in try original.orderedTerms(usage: &usage) {
            values[power] = try .constant(coefficient, in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        return try OriginalSingularFieldPlanePolynomial(context: context, coefficients: values,
            maximumDepth: maximumDepth, usage: &usage)
    }
}
