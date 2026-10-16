#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteNativeOffsetLawPreparer<S:OriginalOffsetSourceReading>:OriginalFiniteNativeOffsetLawPreparing where S.Child:OriginalBSplineSourceReading {
    public typealias Source=S
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        child:borrowing OriginalFiniteBSplineCharts<S.Child>,maximumCharts:Int,limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteNativeOffsetLawFamily<S> {
        let source=copy source,child=copy child
        do {
            return try a.withProofScope { a in
                try a.checkpoint();try source.require(limits)
                guard source.original.originalChild.owner === child.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                guard child.support.count==2,child.source.original.parameterCount==2,!child.laws.isEmpty else { throw OriginalSourceIssuanceFailure.invalidChart }
                guard maximumCharts>=0,child.laws.count<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                typealias Law=OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:child.laws.count,of:Law.self))
                var laws:[Law]=[];laws.reserveCapacity(child.laws.count)
                let issuer=DefaultOriginalOffsetLawIssuer<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>()
                for law in child.laws {
                    try a.consumeWork(1)
                    laws.append(try issuer.issue(source:source,child:law,field:child.field,limits:limits,using:&a))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalFiniteNativeOffsetLawFamily<S>.self))
                let result=OriginalFiniteNativeOffsetLawFamily(source:source,child:child,laws:laws,proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
