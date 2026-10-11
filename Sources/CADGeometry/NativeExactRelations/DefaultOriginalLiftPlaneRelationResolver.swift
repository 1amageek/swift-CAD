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
        try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
            try binding.admitProof(limits:limits,using:&a)
            let g = binding.graph,f = g.field,r = g.polynomials,basis = plane.original.law
            var equation = try r.constant(f.integer(0,using:&a),using:&a)
            for axis in 0..<3 {
                try a.consumeWork(1)
                let offset = try r.scaled(g.homogeneous[3],by:f.importing(basis.origin[axis],using:&a),using:&a)
                equation = try r.adding(equation,r.scaled(r.subtracting(g.homogeneous[axis],offset,using:&a),
                    by:f.importing(basis.normal[axis],using:&a),using:&a),using:&a)
            }
            var kind: OriginalLiftPlaneParameterRestriction<S,P>.Kind = .unchanged
            var request = binding.request
            var candidate = equation
            var degree = try r.degree(of:equation,in:0,using:&a)
            let parameterRing = try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
            let identity = try parameterRing.equals(parameterRing.importing(g.parameterTransport.numerators[0],using:&a),parameterRing.variable(0,using:&a),using:&a)
                && parameterRing.equals(parameterRing.importing(g.parameterTransport.denominators[0],using:&a),parameterRing.constant(f.integer(1,using:&a),using:&a),using:&a)
            if identity,let originalDegree = degree,originalDegree > 1,
                let weightDegree = try r.degree(of:g.homogeneous[3],in:0,using:&a),weightDegree > 0 {
                // The existing L5 map retains Hw != 0; P = Hw * Q preserves its plane preimage.
                let division = try r.divided(equation,by:g.homogeneous[3],using:&a)
                if try r.isZero(division.remainder,using:&a),
                    let quotientDegree = try r.degree(of:division.quotient,in:0,using:&a),quotientDegree <= 1 {
                    candidate = division.quotient;degree = quotientDegree
                }
            }
            if identity,let degree,degree <= 1 {
                if degree == 0 {
                    kind = .excluded
                    request = try request.frame.selection(intervals:[[]],limits:limits,using:&a)
                } else {
                    var constant = try f.integer(0,using:&a),slope = try f.integer(0,using:&a)
                    for term in candidate.terms {
                        try a.consumeWork(1)
                        guard term.powers.count == 1 else { throw NativeExactRelationFailure.invalidDomain }
                        if term.powers[0] == 0 { constant = term.coefficient }
                        else if term.powers[0] == 1 { slope = term.coefficient }
                        else { throw NativeExactRelationFailure.invalidDomain }
                    }
                    let root = try f.dividing(f.negated(constant,using:&a),slope,using:&a)
                    let lower = try f.compare(root,g.support[0].lower,using:&a),upper = try f.compare(root,g.support[0].upper,using:&a)
                    if lower == .less || upper == .greater || (upper == .equal && !g.includesUpperBoundary[0]) {
                        kind = .excluded
                        request = try request.frame.selection(intervals:[[]],limits:limits,using:&a)
                    } else {
                        kind = .singleton(root)
                        let interval = try ExactParameterInterval.checked(field:f,lower:.finite(root),upper:.finite(root),
                            includesLower:true,includesUpper:true,depth:root.depth,using:&a)
                        let candidate = try request.frame.selection(intervals:[[interval]],limits:limits,using:&a)
                        request = try request.intersection(candidate,limits:limits,using:&a)
                    }
                }
            }
            let selected = try DefaultOriginalParametricGraphDomainBinder().bind(graph:g,request:request,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalLiftPlaneParameterRestriction<S,P>.self))
            let result = OriginalLiftPlaneParameterRestriction(original:binding,selected:selected,plane:plane.original.source,
                equation:equation,kind:kind,depth:try a.depth)
            try a.checkpoint(); return result
        }
    }

}
