#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Each selected chart pair is compiled and resolved once under the query admission.
public struct OriginalIssuedRelationPair: Sendable {
    public let firstMapIndex: Int
    public let secondMapIndex: Int
    public let relation: ExactParametricRelation<OriginalExactScalarDomain>
    init(firstMapIndex: Int, secondMapIndex: Int, relation: ExactParametricRelation<OriginalExactScalarDomain>) {
        self.firstMapIndex = firstMapIndex; self.secondMapIndex = secondMapIndex; self.relation = relation
    }
}
