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

public struct DefaultOriginalOffsetGraphFamilyPreparer<S:OriginalOffsetSourceReading>:OriginalIssuedGraphFamilyPreparing where S.Child:OriginalBSplineSourceReading {
    public typealias Source=S
    public typealias Evidence=OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    public typealias Cover=OriginalNativeOffsetDomainCover<S>
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(cover:borrowing Cover,field:borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        maximumGraphs:Int,limits:OriginalDomainIdentityLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<S,Evidence,Cover> {
        do {
            try admission.checkpoint();try cover.family.admitProof(limits:limits.source,using:&admission)
            guard maximumGraphs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard cover.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            _=try field.importingBase(cover.request.frame.scalarField.integer(0,using:&admission),using:&admission)
            let count=cover.effectiveEnclosure.isEmpty ? 0:cover.templateCount
            guard count <= maximumGraphs else { throw OriginalDomainIdentityFailure.chartLimit }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalIssuedGraphPreparation<S,Evidence>.self))
            var graphs:[OriginalIssuedGraphPreparation<S,Evidence>]=[];graphs.reserveCapacity(count)
            var v=cover.family.proofDepth.value,c=cover.family.proofDepth.coefficient
            for axis in cover.request.frame.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for axis in cover.request.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for template in 0..<count {
                try admission.consumeWork(1)
                let occurrence=try cover.member(template:template,limits:limits,using:&admission)
                let graph=try DefaultOriginalOffsetGraphIssuer().issue(occurrence.law,limits:limits.source,using:&admission)
                let binding=try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,request:cover.request,limits:limits,using:&admission)
                let prepared=try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:copy field,limits:limits,using:&admission)
                v=max(v,prepared.depth.value);c=max(c,prepared.depth.coefficient);graphs.append(prepared)
            }
            let depth=try ExactScalarDepth(value:v,coefficient:c);try admission.admitDepth(value:v,coefficient:c)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphFamily<S,Evidence,Cover>.self))
            let result=OriginalIssuedGraphFamily(coverage:copy cover,source:cover.source,field:copy field,graphs:graphs,parameterCount:2,templateCount:cover.templateCount,depth:depth)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
