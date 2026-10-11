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

public struct OriginalIssuedGraphRelationPair: Sendable {
    public let firstGraphIndex:Int
    public let secondGraphIndex:Int
    public let relation:ExactParametricGraphRelation<OriginalExactScalarDomain>
    init(firstGraphIndex:Int,secondGraphIndex:Int,relation:ExactParametricGraphRelation<OriginalExactScalarDomain>) {
        self.firstGraphIndex=firstGraphIndex;self.secondGraphIndex=secondGraphIndex;self.relation=relation
    }
}
