#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteRollingBallGraphPreparer<S: OriginalRollingBallChildSourceReading,E: Sendable,C: Sendable>: OriginalFiniteRollingBallGraphPreparing {
    public typealias Source=S
    public typealias ChildEvidence=E
    public typealias ChildCoverage=C
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        center: borrowing OriginalCompleteCurveGraphs<S.Child,E,C>,first: borrowing OriginalCompleteCurveGraphs<S.Child,E,C>,
        second: borrowing OriginalCompleteCurveGraphs<S.Child,E,C>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRollingBallGraphs<S,E,C> {
        let source=copy source,center=copy center,first=copy first,second=copy second
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try source.require(limits)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard maximumCharts>=0 else { throw OriginalSourceIssuanceFailure.chartLimit }
                guard source.original.originalCenter.owner === center.source.owner,
                    source.original.originalFirstContact.owner === first.source.owner,
                    source.original.originalSecondContact.owner === second.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let radius=source.original.originalRadius,tolerance=source.original.originalDistanceTolerance
                let threshold=source.original.originalRadialCrossThreshold
                guard radius.isFinite,tolerance.isFinite,tolerance>0,radius>tolerance,
                    threshold.isFinite,threshold>=0 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let f=center.field,zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                let childLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalCompleteCurveGraphs<S.Child,E,C>.self))
                for family in [center,first,second] {
                    try family.admitProof(limits:childLimits,using:&a)
                    guard !family.graphs.isEmpty,
                        try f.compare(f.importing(family.support.lower,using:&a),zero,using:&a) == .equal,
                        try f.compare(f.importing(family.support.upper,using:&a),one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
                    for graph in family.graphs {
                        try a.consumeWork(1)
                        guard graph.source.owner === family.source.owner,graph.layout.parameters.count==1,
                            graph.layout.variableCount==graph.polynomials.variableCount,graph.support.count==1,
                            graph.includesUpperBoundary.count==1,graph.homogeneous.count==4,
                            graph.parameterTransport.numerators.count==1,graph.parameterTransport.denominators.count==1 else { throw OriginalSourceIssuanceFailure.invalidChart }
                        let ring=try ExactPolynomialDomain(field:graph.field,variableCount:1,using:&a)
                        let n=try ring.importing(graph.parameterTransport.numerators[0],using:&a),d=try ring.importing(graph.parameterTransport.denominators[0],using:&a)
                        guard try !ring.isZero(d,using:&a),try ring.isZero(ring.subtracting(n,
                            ring.multiplying(ring.variable(0,using:&a),d,using:&a),using:&a),using:&a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    }
                }
                func overlap(_ c: OriginalSourceParameterInterval<OriginalExactScalar>,_ x: OriginalSourceParameterInterval<OriginalExactScalar>,
                    _ y: OriginalSourceParameterInterval<OriginalExactScalar>,_ a: inout OriginalSourceProofAdmission<A>) throws -> OriginalSourceParameterInterval<OriginalExactScalar>? {
                    var lower=try f.importing(c.lower,using:&a),upper=try f.importing(c.upper,using:&a)
                    let xl=try f.importing(x.lower,using:&a),xu=try f.importing(x.upper,using:&a)
                    let yl=try f.importing(y.lower,using:&a),yu=try f.importing(y.upper,using:&a)
                    if try f.compare(xl,lower,using:&a) == .greater { lower=xl }
                    if try f.compare(yl,lower,using:&a) == .greater { lower=yl }
                    if try f.compare(xu,upper,using:&a) == .less { upper=xu }
                    if try f.compare(yu,upper,using:&a) == .less { upper=yu }
                    return try f.compare(lower,upper,using:&a) == .greater ? nil:.init(lower:lower,upper:upper)
                }
                var count=0
                for c in center.graphs { for x in first.graphs { for y in second.graphs {
                    try a.consumeWork(1)
                    if try overlap(c.support[0],x.support[0],y.support[0],&a) != nil {
                        let next=count.addingReportingOverflow(1)
                        guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                        count=next.partialValue
                        guard count<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                    }
                } } }
                guard count>0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                typealias Family=OriginalFiniteRollingBallGraphs<S,E,C>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Family.Graph.self))
                var graphs:[Family.Graph]=[];graphs.reserveCapacity(count)
                let producer=OriginalRollingBallGraphProducer<S>()
                for c in center.graphs { for x in first.graphs { for y in second.graphs {
                    try a.consumeWork(1)
                    if let interval=try overlap(c.support[0],x.support[0],y.support[0],&a) {
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRollingBallChildGraphEvidence<S,E>.self))
                        graphs.append(try producer.issue(source:source,evidence:.init(center:c,first:x,second:y),
                            field:f,lower:interval.lower,upper:interval.upper,using:&a))
                    }
                } } }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Family.self))
                let result=Family(source:source,center:center,first:first,second:second,graphs:graphs,
                    support:[.init(lower:zero,upper:one),.init(lower:zero,upper:one)],proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
