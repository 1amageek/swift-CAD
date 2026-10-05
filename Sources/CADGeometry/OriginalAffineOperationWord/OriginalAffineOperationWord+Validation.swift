import CADCore

extension OriginalAffineOperationWord {
    /// Reuses the immutable constructor's algebra-depth authority, not curve splitting.
    package func validateOriginal<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        usage: inout B) throws {
        try validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
    }

    /// Traverses complete immutable source under the composing caller's admission.
    /// Constructor receipts prove exact inversion/nonsingularity; caches are not source.
    package func validateOriginal<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, usage: inout B) throws {
        try tolerance.validate()
        guard maximumDepth >= 0, !factors.isEmpty, orientationSign == 1 || orientationSign == -1 else {
            throw rationalAlgebraFailure("Original affine word has invalid source or caller depth.")
        }
        for operation in factors {
            try usage.consumeExactWork(1)
            switch operation {
            case .forward(let transform), .inverse(let transform):
                try usage.consumeExactWork(12)
                try transform.validate()
            case .rationalForward(let source), .rationalInverse(let source):
                try source.validateOriginalPayload(usage: &usage)
            case .normalizedForward(let source), .normalizedInverse(let source):
                try source.validateOriginalPayload(usage: &usage)
            }
        }
        if let frame = normalizedFrame {
            try frame.validateNormalization(tolerance: tolerance, normalizationPolicy: .dimensionlessOriginalDirections,
                maximumDepth: maximumDepth, usage: &usage)
        }
    }
}
