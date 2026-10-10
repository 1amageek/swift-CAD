#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L5
#endif

/// Erases source types while retaining the complete immutable source/DI owner value.
public protocol OriginalIssuedGraphRelationOwning: Sendable {
    var kind: ExactParametricRelationKind { get }
    var pairs: [OriginalIssuedGraphRelationPair] { get }
}
