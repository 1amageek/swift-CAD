#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Imports one existing positional producer and proves its entire authored cover.
public struct DefaultOriginalFiniteRetainedSurfaceChartPreparer<S:OriginalRetainedSurfaceSourceReading>:OriginalFiniteRetainedSurfaceChartPreparing {
    public typealias Source=S
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedSurfaceCharts<S> {
        let source=copy source
        do {
            return try a.withProofScope { a in
                try compose(source:source,maximumCharts:maximumCharts,limits:limits,using:&a)
            }
        } catch { throw OriginalSourceIssuanceFailure(preserving:error) }
    }
    private func compose<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<S>,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws -> OriginalFiniteRetainedSurfaceCharts<S> {
        do {
            try a.checkpoint();try source.require(limits)
            let inherited=source.original.originalProofDepth
            try a.admitDepth(value:inherited.value,coefficient:inherited.coefficient)
            let count=source.original.originalCellCount,f=source.original.originalField
            guard count>0,maximumCharts>=0,source.original.originalPolynomials.variableCount==2 else { throw OriginalSourceIssuanceFailure.invalidSource }
            guard count<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
            let ring=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
            let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
            let d=try ring.constant(one,using:&a),u=try ring.variable(0,using:&a),v=try ring.variable(1,using:&a)
            typealias Law=OriginalRationalChartReceipt<S,Int,S.Field>
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Law.self))
            var laws:[Law]=[];laws.reserveCapacity(count)
            for index in 0..<count {
                try a.consumeWork(1)
                let original=source.original.originalCellHomogeneous(at:index)
                guard original.count==4 else { throw OriginalSourceIssuanceFailure.invalidChart }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<S.Field.Value>.self))
                var support:[OriginalSourceParameterInterval<S.Field.Value>]=[];support.reserveCapacity(2)
                for axis in 0..<2 {
                    let lo=try f.importing(source.original.originalCellLowerBound(at:index,axis:axis),using:&a),
                        hi=try f.importing(source.original.originalCellUpperBound(at:index,axis:axis),using:&a)
                    guard try f.compare(lo,zero,using:&a) != .less,try f.compare(hi,one,using:&a) != .greater,
                        try f.compare(lo,hi,using:&a) == .less else { throw OriginalSourceIssuanceFailure.invalidChart }
                    support.append(.init(lower:lo,upper:hi))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<S.Field>.self))
                var position:[ExactPolynomial<S.Field>]=[];position.reserveCapacity(4)
                for p in original { try a.consumeWork(1);position.append(try ring.importing(p,using:&a)) }
                guard try !ring.isZero(position[3],using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<S.Field>.self))
                let chart=try source.chart(index,limits:limits,using:&a)
                laws.append(.init(chart:chart,field:f,polynomials:ring,homogeneous:position,support:support,
                    parameterTransport:.init(numerators:[u,v],denominators:[d,d]),proofDepth:try a.depth))
            }
            try cover(laws,field:f,zero:zero,one:one,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<S.Field.Value>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalFiniteRetainedSurfaceCharts<S>.self))
            let result=OriginalFiniteRetainedSurfaceCharts(source:copy source,field:f,support:[.init(lower:zero,upper:one),.init(lower:zero,upper:one)],laws:laws,proofDepth:try a.depth)
            try a.checkpoint();return result
        } catch { throw OriginalSourceIssuanceFailure(preserving:error) }
    }
    private func cover<A:ExactScalarAdmission & ~Copyable>(_ laws:[OriginalRationalChartReceipt<S,Int,S.Field>],
        field f:S.Field,zero:S.Field.Value,one:S.Field.Value,using a:inout A) throws {
        let capacity=laws.count.multipliedReportingOverflow(by:2)
        guard !capacity.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:capacity.partialValue,of:S.Field.Value.self))
        var cuts:[S.Field.Value]=[];cuts.reserveCapacity(capacity.partialValue)
        for law in laws {
            for upper in 0...1 {
                let cut=upper==0 ? law.support[0].lower:law.support[0].upper
                var index=0,equal=false
                while index<cuts.count {
                    try a.consumeWork(1);let order=try f.compare(cut,cuts[index],using:&a)
                    if order == .equal { equal=true;break };if order == .less { break };index += 1
                }
                if !equal { cuts.insert(cut,at:index) }
            }
        }
        guard let first=cuts.first,let last=cuts.last,try f.compare(first,zero,using:&a) == .equal,
            try f.compare(last,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:laws.count,of:OriginalSourceParameterInterval<S.Field.Value>.self))
        var vertical:[OriginalSourceParameterInterval<S.Field.Value>]=[];vertical.reserveCapacity(laws.count)
        for index in 0..<(cuts.count-1) {
            vertical.removeAll(keepingCapacity:true)
            for law in laws {
                try a.consumeWork(1)
                guard try f.compare(law.support[0].lower,cuts[index],using:&a) != .greater,
                    try f.compare(law.support[0].upper,cuts[index+1],using:&a) != .less else { continue }
                let range=law.support[1];var order=0
                while order<vertical.count {
                    try a.consumeWork(1)
                    if try f.compare(range.lower,vertical[order].lower,using:&a) == .less { break };order += 1
                }
                vertical.insert(range,at:order)
            }
            var reached=zero
            for range in vertical {
                try a.consumeWork(1)
                guard try f.compare(range.lower,reached,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
                if try f.compare(range.upper,reached,using:&a) == .greater { reached=range.upper }
            }
            guard try f.compare(reached,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
        }
    }
}
