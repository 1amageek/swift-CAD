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

public struct DefaultOriginalIssuedGraphRelationResolver<S: Sendable,E: Sendable,C: Sendable,T: Sendable,F: Sendable,D: Sendable>: OriginalIssuedGraphRelationResolving {
    public typealias First=S
    public typealias FirstEvidence=E
    public typealias FirstCover=C
    public typealias Second=T
    public typealias SecondEvidence=F
    public typealias SecondCover=D
    public init() {}
    public func resolve<A: ExactScalarAdmission & ~Copyable>(kind:ExactParametricRelationKind,
        first:borrowing OriginalIssuedGraphFamily<S,E,C>,second:borrowing OriginalIssuedGraphFamily<T,F,D>,
        maximumPairs:Int,limits:OriginalDomainIdentityLimits,cellLimits:ExactRealCellLimits,topologyLimits:ExactRealTopologyLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphRelations<S,E,C,T,F,D> {
        do {
            try admission.checkpoint();try first.admitProof(limits:limits,using:&admission);try second.admitProof(limits:limits,using:&admission)
            guard maximumPairs >= 0,first.parameterCount == (kind == .curveSurface ? 1:2),second.parameterCount == 2 else { throw NativeExactRelationFailure.invalidDomain }
            _=try first.field.importing(second.field.integer(0,using:&admission),using:&admission)
            let count=first.graphs.count.multipliedReportingOverflow(by:second.graphs.count)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            guard count.partialValue <= maximumPairs else { throw OriginalDomainIdentityFailure.chartLimit }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:OriginalIssuedGraphRelationPair.self))
            var pairs:[OriginalIssuedGraphRelationPair]=[];pairs.reserveCapacity(count.partialValue)
            let left=try classes(first,using:&admission),right=try classes(second,using:&admission)
            typealias Cells=ExactRealCellDomain<OriginalExactScalarDomain>
            let domain=ExactParametricRelationDomain<OriginalExactScalarDomain,Cells,ExactRealTopology<OriginalExactScalarDomain>>(cells:Cells.self,topology:.init(cells:Cells.self))
            for i in first.graphs.indices { for j in second.graphs.indices {
                try admission.consumeWork(1)
                let ci=left[i].0,cj=right[j].0
                if ci == i && cj == j {
                    let input=try domain.compile(kind:kind,first:first.graphs[i].graph,second:second.graphs[j].graph,using:&admission)
                    let relation=try domain.resolve(input,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
                    pairs.append(try .solved(firstGraphIndex:i,secondGraphIndex:j,relation:relation,using:&admission))
                } else {
                    let canonical=ci*second.graphs.count+cj
                    guard canonical >= 0,canonical < pairs.count else { throw NativeExactRelationFailure.invalidDomain }
                    pairs.append(try pairs[canonical].alias(firstGraphIndex:i,secondGraphIndex:j,
                        firstEquivalence:left[i].1,secondEquivalence:right[j].1))
                }
            } }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphRelations<S,E,C,T,F,D>.self))
            let result=OriginalIssuedGraphRelations(first:copy first,second:copy second,kind:kind,pairs:pairs)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }

    private func classes<U: Sendable,V: Sendable,W: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ family:borrowing OriginalIssuedGraphFamily<U,V,W>,using a:inout A)
        throws(NativeExactRelationFailure) -> [(Int,OriginalIssuedGraphSolverEquivalence?)] {
        do {
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:family.graphs.count,of:(Int,OriginalIssuedGraphSolverEquivalence?).self))
            var result:[(Int,OriginalIssuedGraphSolverEquivalence?)]=[];result.reserveCapacity(family.graphs.count)
            for i in family.graphs.indices {
                try a.consumeWork(1)
                var entry:(Int,OriginalIssuedGraphSolverEquivalence?)=(i,nil)
                for j in result.indices where result[j].0 == j {
                    try a.consumeWork(1)
                    if let proof=try OriginalIssuedGraphSolverEquivalence.checked(family.graphs[i],family.graphs[j],using:&a) {
                        entry=(j,proof);break
                    }
                }
                result.append(entry)
            }
            try a.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
