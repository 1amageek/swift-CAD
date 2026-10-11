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
    public let canonicalFirstGraphIndex:Int
    public let canonicalSecondGraphIndex:Int
    public let firstEquivalence:OriginalIssuedGraphSolverEquivalence?
    public let secondEquivalence:OriginalIssuedGraphSolverEquivalence?
    private final class SolverOwner: Sendable {
        let relation: ExactParametricGraphRelation<OriginalExactScalarDomain>
        init(_ relation: ExactParametricGraphRelation<OriginalExactScalarDomain>) { self.relation=relation }
    }
    private let solverOwner: SolverOwner?
    init(firstGraphIndex:Int,secondGraphIndex:Int,relation:ExactParametricGraphRelation<OriginalExactScalarDomain>,
        canonicalFirstGraphIndex:Int? = nil,canonicalSecondGraphIndex:Int? = nil,
        firstEquivalence:OriginalIssuedGraphSolverEquivalence? = nil,secondEquivalence:OriginalIssuedGraphSolverEquivalence? = nil) {
        self.solverOwner=nil
        self.firstGraphIndex=firstGraphIndex;self.secondGraphIndex=secondGraphIndex;self.relation=relation
        self.canonicalFirstGraphIndex=canonicalFirstGraphIndex ?? firstGraphIndex
        self.canonicalSecondGraphIndex=canonicalSecondGraphIndex ?? secondGraphIndex
        self.firstEquivalence=firstEquivalence;self.secondEquivalence=secondEquivalence
    }

    private init(firstGraphIndex:Int,secondGraphIndex:Int,owner:SolverOwner,
        canonicalFirstGraphIndex:Int,canonicalSecondGraphIndex:Int,
        firstEquivalence:OriginalIssuedGraphSolverEquivalence?,secondEquivalence:OriginalIssuedGraphSolverEquivalence?) {
        self.firstGraphIndex=firstGraphIndex;self.secondGraphIndex=secondGraphIndex
        self.solverOwner=owner;self.relation=owner.relation
        self.canonicalFirstGraphIndex=canonicalFirstGraphIndex;self.canonicalSecondGraphIndex=canonicalSecondGraphIndex
        self.firstEquivalence=firstEquivalence;self.secondEquivalence=secondEquivalence
    }
    static func solved<A:ExactScalarAdmission & ~Copyable>(firstGraphIndex:Int,secondGraphIndex:Int,
        relation:ExactParametricGraphRelation<OriginalExactScalarDomain>,using a:inout A) throws(NativeExactRelationFailure) -> Self {
        do {
            try a.checkpoint()
            try OriginalDomainAccess.owner(ExactParametricGraphRelation<OriginalExactScalarDomain>.self,&a)
            let result=Self(firstGraphIndex:firstGraphIndex,secondGraphIndex:secondGraphIndex,owner:SolverOwner(relation),
                canonicalFirstGraphIndex:firstGraphIndex,canonicalSecondGraphIndex:secondGraphIndex,
                firstEquivalence:nil,secondEquivalence:nil)
            try a.checkpoint();return result
        } catch { throw .preserving(error) }
    }
    func alias(firstGraphIndex:Int,secondGraphIndex:Int,
        firstEquivalence:OriginalIssuedGraphSolverEquivalence?,secondEquivalence:OriginalIssuedGraphSolverEquivalence?)
        throws(NativeExactRelationFailure) -> Self {
        guard let solverOwner else { throw NativeExactRelationFailure.invalidDomain }
        return Self(firstGraphIndex:firstGraphIndex,secondGraphIndex:secondGraphIndex,owner:solverOwner,
            canonicalFirstGraphIndex:canonicalFirstGraphIndex,canonicalSecondGraphIndex:canonicalSecondGraphIndex,
            firstEquivalence:firstEquivalence,secondEquivalence:secondEquivalence)
    }
    func sharesSolver(with other:Self) -> Bool {
        guard let solverOwner,let otherOwner=other.solverOwner else { return false }
        return solverOwner === otherOwner
    }
}
