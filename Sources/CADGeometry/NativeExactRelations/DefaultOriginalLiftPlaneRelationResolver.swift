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

public struct DefaultOriginalLiftPlaneRelationResolver: OriginalLiftPlaneRelationResolving {
    public init() {}
    public func resolve<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading,A: ExactScalarAdmission & ~Copyable>(
        lift: borrowing OriginalRetainedSurfaceLiftDomainCover<S>,plane: borrowing OriginalIssuedPlaneGraph<P>,
        maximumPairs: Int,limits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using a: inout A)
        throws(NativeExactRelationFailure) -> OriginalLiftPlaneRelations<S,P> {
        do {
            try a.checkpoint(); try lift.family.admitProof(limits:limits.source,using:&a)
            try plane.admitProof(limits:limits,using:&a)
            guard maximumPairs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard lift.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            _ = try plane.field.importingBase(lift.family.field.integer(0,using:&a),using:&a)
            let count = lift.effectiveEnclosure.isEmpty ? 0:lift.templateCount
            guard count <= maximumPairs else { throw OriginalDomainIdentityFailure.chartLimit }
            typealias Preparation = OriginalIssuedGraphPreparation<S,OriginalSurfaceLiftGraphEvidence<S>>
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Preparation.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalIssuedGraphRelationPair.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalPolynomialSurfaceLiftGraphReduction<S>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalLiftPlaneParameterRestriction<S,P>.self))
            var restrictions: [OriginalLiftPlaneParameterRestriction<S,P>] = []; restrictions.reserveCapacity(count)
            var reductions: [OriginalPolynomialSurfaceLiftGraphReduction<S>] = []; reductions.reserveCapacity(count)
            var graphs: [Preparation] = []; graphs.reserveCapacity(count)
            var pairs: [OriginalIssuedGraphRelationPair] = []; pairs.reserveCapacity(count)
            typealias Base = OriginalExactScalarDomain
            typealias Cells = ExactRealCellDomain<Base>
            let solver = ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
            for template in 0..<count {
                try a.consumeWork(1)
                let member = try lift.member(template:template,limits:limits,using:&a)
                // FIXME(INCOMPLETE_IMPLEMENTATION): This prepared consumer currently requires
                // polynomial UV elimination. Required rational/nonlinear witness families must
                // retain their complete correspondence before this route claims general coverage.
                let reduction = try DefaultOriginalPolynomialSurfaceLiftGraphReducer<S>().reduce(member.graph,limits:limits.source,using:&a)
                let binding = try DefaultOriginalParametricGraphDomainBinder().bind(graph:reduction.graph,request:member.request,limits:limits,using:&a)
                let restriction = try restrict(binding,plane:plane,limits:limits,using:&a)
                let prepared = try DefaultOriginalIssuedGraphCompiler().compile(binding:restriction.selected,field:plane.field,limits:limits,using:&a)
                restrictions.append(restriction); reductions.append(reduction); graphs.append(prepared)
                if restriction.selected.request.isEmpty { continue }
                let input = try solver.compile(kind:.curveSurface,first:prepared.graph,second:plane.graph,using:&a)
                let relation = try solver.resolve(input,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
                pairs.append(.init(firstGraphIndex:template,secondGraphIndex:0,relation:relation))
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalLiftPlaneRelations<S,P>.self))
            let result = OriginalLiftPlaneRelations(first:copy lift,firstGraphs:graphs,firstReductions:reductions,firstRestrictions:restrictions,second:copy plane,pairs:pairs)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
    private func restrict<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading,A: ExactScalarAdmission & ~Copyable>(
        _ binding: OriginalLiftPlaneParameterRestriction<S,P>.Member,plane: OriginalIssuedPlaneGraph<P>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws -> OriginalLiftPlaneParameterRestriction<S,P> {
        try admission.withProofScope() { a in
            let restriction = try OriginalAffinePlaneParameterRestriction().select(binding,
                plane: plane, limits: limits, using: &a)
            let kind: OriginalLiftPlaneParameterRestriction<S,P>.Kind
            switch restriction.kind {
            case .unchanged: kind = .unchanged
            case .excluded: kind = .excluded
            case .singleton(let value): kind = .singleton(value)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalLiftPlaneParameterRestriction<S,P>.self))
            let result = OriginalLiftPlaneParameterRestriction(original:binding,selected:restriction.selected,plane:plane.original.source,
                equation:restriction.equation,kind:kind,depth:try a.depth)
            try a.checkpoint(); return result
        }
    }

}
