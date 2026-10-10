#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// All original child witnesses remain independently scoped and retained.
public struct OriginalRollingBallChildGraphEvidence<S: OriginalRollingBallChildSourceReading,E: Sendable>: Sendable {
    public typealias ChildGraph = OriginalParametricGraphReceipt<S.Child,OriginalExactScalarDomain,E>
    public let center: ChildGraph
    public let first: ChildGraph
    public let second: ChildGraph
    init(center: ChildGraph,first: ChildGraph,second: ChildGraph) {
        self.center=center;self.first=first;self.second=second
    }
}
