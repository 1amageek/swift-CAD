#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalBSplineDomainIssuer<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalBSplineDomainIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: F,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalBSplineDomainSpace<S,F> {
        let source = copy source
        return try OriginalDomainAccess.run(&admission) { a in
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            let s = source.original, n = s.parameterCount
            guard n == 1 || n == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
            let depth = try ExactScalarDepth(value:0,coefficient:0)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(n,[Int].self,&a)
            try OriginalDomainAccess.storage(n,OriginalCoordinateSemantics.self,&a)
            var support: [[ExactParameterInterval<F.Value>]] = [], base: [[ExactParameterInterval<F.Value>]] = []
            var spans: [[Int]] = [], periods: [OriginalSourcePeriodReceipt<S,F>] = []
            support.reserveCapacity(n); base.reserveCapacity(n); spans.reserveCapacity(n)
            for axis in 0..<n {
                try a.consumeWork(1)
                let p = s.degree(in:axis), count = s.controlCount(in:axis)
                guard p > 0, count > p else { throw OriginalDomainIdentityFailure.invalidDomain }
                let lo = try field.binary64(exactly:s.knot(at:p,in:axis),using:&a)
                let hi = try field.binary64(exactly:s.knot(at:count,in:axis),using:&a)
                let interval = try ExactParameterInterval.checked(field:field,lower:.finite(lo),upper:.finite(hi),depth:depth,using:&a)
                try OriginalDomainAccess.storage(2,ExactParameterInterval<F.Value>.self,&a)
                base.append([interval])
                if s.isPeriodic(in:axis) {
                    guard periods.count < limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
                    let proof = try DefaultOriginalBSplinePeriodIssuer<S,F>().issue(source:source,axis:axis,field:field,limits:limits.source,using:&a)
                    try OriginalDomainAccess.storage(1,OriginalSourcePeriodReceipt<S,F>.self,&a); periods.append(proof)
                    support.append([try .checked(field:field,lower:.negativeInfinity,upper:.positiveInfinity,depth:depth,using:&a)])
                } else { support.append([interval]) }
                var active: [Int] = []
                for span in p..<count {
                    try a.consumeWork(1)
                    if s.knot(at:span,in:axis) < s.knot(at:span+1,in:axis) {
                        guard active.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                        try OriginalDomainAccess.storage(1,Int.self,&a); active.append(span)
                    }
                }
                guard !active.isEmpty else { throw OriginalDomainIdentityFailure.invalidDomain }
                spans.append(active)
            }
            let transporter = DefaultOriginalParameterTransporter<S,F>()
            let semantics = [OriginalCoordinateSemantics](repeating:.authoredScalar,count:n)
            let frame = try transporter.frame(source:source,field:field,support:support,semantics:semantics,limits:limits,using:&a)
            let fundamental = try transporter.frame(source:source,field:field,support:base,semantics:semantics,limits:limits,using:&a)
            let rows = n == 2 ? spans[1].count : 1
            let count = try OriginalDomainAccess.multiplied(spans[0].count,rows)
            guard count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            try OriginalDomainAccess.storage(count,OriginalParameterTransport<S,F>.self,&a)
            try OriginalDomainAccess.storage(count,OriginalSourceChart<S,OriginalBSplineChartSelection>.self,&a)
            var maps: [OriginalParameterTransport<S,F>] = [], charts: [OriginalSourceChart<S,OriginalBSplineChartSelection>] = []
            maps.reserveCapacity(count); charts.reserveCapacity(count)
            for row in 0..<rows {
                for column in spans[0].indices {
                    try a.consumeWork(1)
                    try OriginalDomainAccess.storage(n,Int.self,&a)
                    var selection = [spans[0][column]]
                    if n == 2 { selection.append(spans[1][row]) }
                    try OriginalDomainAccess.storage(n,[ExactParameterInterval<F.Value>].self,&a)
                    var intervals: [[ExactParameterInterval<F.Value>]] = []
                    for axis in 0..<n {
                        try a.consumeWork(1); let span = selection[axis]
                        try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
                        intervals.append([try .checked(field:field,
                            lower:.finite(field.binary64(exactly:s.knot(at:span,in:axis),using:&a)),
                            upper:.finite(field.binary64(exactly:s.knot(at:span+1,in:axis),using:&a)),depth:depth,using:&a)])
                    }
                    let local = try transporter.frame(source:source,field:field,support:intervals,semantics:semantics,limits:limits,using:&a)
                    try OriginalDomainAccess.storage(n,Int.self,&a)
                    try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
                    var permutation: [Int] = [], gains: [F.Value] = [], offsets: [F.Value] = []
                    for i in 0..<n { try a.consumeWork(1); permutation.append(i); gains.append(try field.integer(1,using:&a)); offsets.append(try field.integer(0,using:&a)) }
                    maps.append(try transporter.affine(from:local.fullSelection(limits:limits,using:&a),to:fundamental,
                        permutation:permutation,gains:gains,offsets:offsets,limits:limits,using:&a))
                    charts.append(try source.chart(.init(spans:selection),limits:limits.source,using:&a))
                }
            }
            let cover = try DefaultOriginalDomainCoverIssuer<S,F>().issue(request:fundamental.fullSelection(limits:limits,using:&a),charts:maps,limits:limits,using:&a)
            return .init(frame:frame,fundamental:cover,periods:periods,sourceCharts:charts)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(space: borrowing OriginalBSplineDomainSpace<S,F>,
        request: borrowing OriginalParameterSelection<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalBSplineDomainCover<S,F> {
        let space = copy space, request = copy request
        return try OriginalDomainAccess.run(&admission) { a in
            let support = try space.frame.fullSelection(limits:limits,using:&a)
            guard request.sharesFrame(with:support) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard space.sourceCharts.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard space.periods.count <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            let effective = try request.intersection(support,limits:limits,using:&a)
            var finite: OriginalDomainCover<S,F>? = nil
            if space.periods.isEmpty {
                let t = DefaultOriginalParameterTransporter<S,F>()
                try OriginalDomainAccess.storage(space.sourceCharts.count,OriginalParameterTransport<S,F>.self,&a)
                var maps: [OriginalParameterTransport<S,F>] = []
                for chart in space.fundamental.charts {
                    try a.consumeWork(1)
                    maps.append(try t.reframed(chart.transport,to:space.frame,limits:limits,using:&a))
                }
                finite = try DefaultOriginalDomainCoverIssuer<S,F>().issue(request:request,charts:maps,limits:limits,using:&a)
            }
            // Every finite coordinate has an exact integer reduction into the closed
            // fundamental interval. Independent period laws give the Cartesian family.
            return .init(space:space,request:request,effective:effective,finite:finite)
        }
    }
}
