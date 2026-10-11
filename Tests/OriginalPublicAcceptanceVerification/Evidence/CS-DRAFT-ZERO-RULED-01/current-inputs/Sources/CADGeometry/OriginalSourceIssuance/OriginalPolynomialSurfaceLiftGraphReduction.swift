#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact forward bijection from a reduced graph to its retained original UV witnesses.
public struct OriginalPolynomialSurfaceLiftGraphReduction<S: OriginalLiftGraphSourceReading>: Sendable {
    public typealias Graph = OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>
    public let original: Graph
    public let graph: Graph
    public let originalCoordinates: [ExactPolynomial<OriginalExactScalarDomain>]
    init(original: Graph,graph: Graph,originalCoordinates: [ExactPolynomial<OriginalExactScalarDomain>]) {
        self.original = original; self.graph = graph; self.originalCoordinates = originalCoordinates
    }
}
