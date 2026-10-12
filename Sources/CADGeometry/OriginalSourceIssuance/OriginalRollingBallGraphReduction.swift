#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed exact lift from reduced rolling UV to every retained original witness.
public struct OriginalRollingBallGraphReduction<S: OriginalRollingBallChildSourceReading,E: Sendable>: Sendable {
    public let original: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalRollingBallChildGraphEvidence<S,E>>
    public let originalCoordinates: [ExactPolynomial<OriginalExactScalarDomain>]
    init(original: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalRollingBallChildGraphEvidence<S,E>>,
        originalCoordinates: [ExactPolynomial<OriginalExactScalarDomain>]) {
        self.original = original; self.originalCoordinates = originalCoordinates
    }
}
