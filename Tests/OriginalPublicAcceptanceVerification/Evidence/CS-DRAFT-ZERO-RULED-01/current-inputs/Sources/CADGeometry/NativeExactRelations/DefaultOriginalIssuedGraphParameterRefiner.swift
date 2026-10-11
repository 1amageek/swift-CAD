#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L3
import L4
import L5
import DI
#endif

public struct DefaultOriginalIssuedGraphParameterRefiner<S: Sendable,E: Sendable,C: Sendable,T: Sendable,F: Sendable,D: Sendable>: OriginalIssuedGraphParameterRefining {
    public typealias First = S
    public typealias FirstEvidence = E
    public typealias FirstCover = C
    public typealias Second = T
    public typealias SecondEvidence = F
    public typealias SecondCover = D
    public init() {}

    public func refine<A: ExactScalarAdmission & ~Copyable>(
        in raw: borrowing OriginalIssuedGraphRelations<S,E,C,T,F,D>,
        pairOrdinal: Int, matching predicate: borrowing ExactRealCellPredicate<OriginalExactScalarDomain>,
        limits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphParameterRefinement<S,E,C,T,F,D> {
        do {
            try admission.checkpoint()
            guard raw.pairs.indices.contains(pairOrdinal) else { throw NativeExactRelationFailure.invalidDomain }
            try raw.admitProof(limits: limits, using: &admission)
            let lifted = raw.pairs[pairOrdinal].relation.projection.original
            let count = lifted.partition.source.variableCount
            guard predicate.source.variableCount == count else { throw NativeExactRelationFailure.invalidDomain }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Int.self))
            var coordinates: [Int] = []
            coordinates.reserveCapacity(count)
            for axis in 0..<count {
                try admission.consumeWork(1)
                coordinates.append(axis)
            }
            let topology = ExactRealTopologyDomain<OriginalExactScalarDomain,ExactRealCellDomain<OriginalExactScalarDomain>>(
                cells: ExactRealCellDomain<OriginalExactScalarDomain>.self)
            let pullback: ExactRealCellPullback<OriginalExactScalarDomain>
            do {
                pullback = try topology.refinePullback(of: lifted, onto: predicate,
                    coordinateMap: coordinates, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
            } catch {
                if case .scalar(let cause) = error { throw NativeExactRelationFailure.scalar(cause) }
                throw NativeExactRelationFailure.geometry(error)
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalIssuedGraphParameterRefinement<S,E,C,T,F,D>.self))
            let result = OriginalIssuedGraphParameterRefinement(raw: copy raw, pairOrdinal: pairOrdinal, pullback: pullback)
            try admission.checkpoint()
            return result
        } catch let failure as NativeExactRelationFailure { throw failure }
        catch { throw .preserving(error) }
    }
}
