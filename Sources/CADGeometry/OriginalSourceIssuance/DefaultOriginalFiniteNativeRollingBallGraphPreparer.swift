#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteNativeRollingBallGraphPreparer<S: OriginalRollingBallSourceReading>: OriginalFiniteNativeRollingBallGraphPreparing {
    public typealias Source = S
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        center: borrowing OriginalFiniteBSplineCharts<S.Child>, first: borrowing OriginalFiniteBSplineCharts<S.Child>,
        second: borrowing OriginalFiniteBSplineCharts<S.Child>, maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteNativeRollingBallGraphs<S> {
        let source = copy source, center = copy center, first = copy first, second = copy second
        do {
            return try a.withProofScope { a in
                try a.checkpoint(); try source.require(limits)
                guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.chartLimit }
                guard source.original.originalCenter.owner === center.source.owner,
                    source.original.originalFirstContact.owner === first.source.owner,
                    source.original.originalSecondContact.owner === second.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let r = source.original.originalRadius, t = source.original.originalDistanceTolerance
                let threshold = source.original.originalRadialCrossThreshold
                guard r.isFinite, t.isFinite, t > 0, r > t, threshold.isFinite, threshold >= 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let f = center.field, zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
                // Immutable sealed child families prove whole support; local law unions are
                // not guessed from their boxes. All children use original authored U.
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: OriginalFiniteBSplineCharts<S.Child>.self))
                let children = [center,first,second]
                for family in children {
                    try family.source.require(.init(remainingSourceDepth: limits.remainingSourceDepth - 1))
                    guard family.source.original.parameterCount == 1, family.support.count == 1,
                        !family.laws.isEmpty, try f.compare(family.support[0].lower,zero,using:&a) == .equal,
                        try f.compare(family.support[0].upper,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
                    for law in family.laws {
                        try a.consumeWork(1); try law.admitProof(using:&a)
                        guard family.source.owns(law.chart), law.polynomials.variableCount == 1,
                            law.support.count == 1, law.homogeneous.count == 4,
                            law.parameterTransport.numerators.count == 1, law.parameterTransport.denominators.count == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
                        let ring = law.polynomials
                        let n = law.parameterTransport.numerators[0], d = law.parameterTransport.denominators[0]
                        guard try !ring.isZero(d,using:&a), try ring.isZero(ring.subtracting(n,
                            ring.multiplying(ring.variable(0,using:&a),d,using:&a),using:&a),using:&a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    }
                }
                func overlap(_ c: OriginalSourceParameterInterval<OriginalExactScalar>,
                    _ x: OriginalSourceParameterInterval<OriginalExactScalar>, _ y: OriginalSourceParameterInterval<OriginalExactScalar>,
                    _ a: inout A) throws -> OriginalSourceParameterInterval<OriginalExactScalar>? {
                    var lower = c.lower, upper = c.upper
                    if try f.compare(x.lower,lower,using:&a) == .greater { lower = x.lower }
                    if try f.compare(y.lower,lower,using:&a) == .greater { lower = y.lower }
                    if try f.compare(x.upper,upper,using:&a) == .less { upper = x.upper }
                    if try f.compare(y.upper,upper,using:&a) == .less { upper = y.upper }
                    if try f.compare(lower,upper,using:&a) == .greater { return nil }
                    return .init(lower: lower,upper: upper)
                }
                var count = 0
                for c in center.laws { for x in first.laws { for y in second.laws {
                    try a.consumeWork(1)
                    if try overlap(c.support[0],x.support[0],y.support[0],&a) != nil {
                        let next = count.addingReportingOverflow(1)
                        guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                        count = next.partialValue
                        guard count <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                    }
                } } }
                guard count > 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                typealias Family = OriginalFiniteNativeRollingBallGraphs<S>
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Family.Graph.self))
                var graphs: [Family.Graph] = []; graphs.reserveCapacity(count)
                let producer = OriginalRollingBallGraphProducer<S>()
                for c in center.laws { for x in first.laws { for y in second.laws {
                    try a.consumeWork(1)
                    if let interval = try overlap(c.support[0],x.support[0],y.support[0],&a) {
                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalRollingBallGraphEvidence<S>.self))
                        graphs.append(try producer.issue(source: source, evidence: .init(center:c,first:x,second:y),
                            lower: interval.lower,upper: interval.upper,using:&a))
                    }
                } } }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalSourceParameterInterval<OriginalExactScalar>.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Family.self))
                let result = Family(source:source,center:center,first:first,second:second,graphs:graphs,
                    support:[.init(lower:zero,upper:one),.init(lower:zero,upper:one)],proofDepth:try a.depth)
                try a.checkpoint(); return result
            }
        } catch { throw .init(preserving: error) }
    }
}
