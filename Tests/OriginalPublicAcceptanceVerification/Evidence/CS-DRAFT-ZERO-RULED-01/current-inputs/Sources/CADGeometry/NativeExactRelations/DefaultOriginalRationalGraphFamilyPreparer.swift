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

public struct DefaultOriginalRationalGraphFamilyPreparer<S:Sendable,C:Sendable>:OriginalIssuedGraphFamilyPreparing {
    public typealias Source=S
    public typealias Evidence=OriginalRationalChartReceipt<S,C,OriginalExactScalarDomain>
    public typealias Cover=OriginalIssuedDomainCover<S,C,OriginalExactScalarDomain>
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(cover:borrowing Cover,field:borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        maximumGraphs:Int,limits:OriginalDomainIdentityLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<S,Evidence,Cover> {
        do {
            try admission.checkpoint()
            guard maximumGraphs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard cover.laws.count <= limits.maximumCharts,cover.charts.count <= maximumGraphs else { throw OriginalDomainIdentityFailure.chartLimit }
            let request=cover.coverage.request,source=request.frame.source
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            _=try field.importingBase(request.frame.scalarField.integer(0,using:&admission),using:&admission)
            var v=0,c=0
            for axis in request.frame.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for axis in request.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for law in cover.laws {
                try admission.consumeWork(1);try law.admitProof(using:&admission)
                if let depth=law.proofDepth {v=max(v,depth.value);c=max(c,depth.coefficient)}
                for p in law.homogeneous { try admission.consumeWork(1);v=max(v,p.depth.value);c=max(c,p.depth.coefficient) }
                for p in law.parameterTransport.numerators { try admission.consumeWork(1);v=max(v,p.depth.value);c=max(c,p.depth.coefficient) }
                for p in law.parameterTransport.denominators { try admission.consumeWork(1);v=max(v,p.depth.value);c=max(c,p.depth.coefficient) }
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:cover.charts.count,of:OriginalIssuedGraphPreparation<S,Evidence>.self))
            var graphs:[OriginalIssuedGraphPreparation<S,Evidence>]=[];graphs.reserveCapacity(cover.charts.count)
            for chart in cover.charts {
                try admission.consumeWork(1)
                let graph=try DefaultOriginalRationalGraphIssuer().issue(cover.laws[chart.lawIndex],limits:limits.source,using:&admission)
                let binding=try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,request:request,limits:limits,using:&admission)
                let prepared=try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:copy field,limits:limits,using:&admission)
                v=max(v,prepared.depth.value);c=max(c,prepared.depth.coefficient);graphs.append(prepared)
            }
            let depth=try ExactScalarDepth(value:v,coefficient:c);try admission.admitDepth(value:v,coefficient:c)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphFamily<S,Evidence,Cover>.self))
            let result=OriginalIssuedGraphFamily(coverage:copy cover,source:source,field:copy field,graphs:graphs,parameterCount:request.arity,templateCount:cover.laws.count,depth:depth)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
