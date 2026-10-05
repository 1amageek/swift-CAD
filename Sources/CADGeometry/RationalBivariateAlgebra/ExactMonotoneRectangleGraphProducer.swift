import CADCore

/// Original exact clipped regular graphs, including adjacent-edge branch domains.
package struct ExactMonotoneRectangleGraphProducer {
    package static func graph<B: RationalAlgebraAdmitting>(of original: ExactBivariatePolynomial,
        over domain: SurfaceParameterBox, freeAlongU: Bool, maximumDepth: Int,
        usage: inout B, additionalStations: [ExactMonotoneGraphEndpoint] = []) throws -> ExactMonotoneRectangleGraph? {
        guard maximumDepth >= 0, domain.u.width > 0, domain.v.width > 0 else {
            throw rationalAlgebraFailure("Original graph projection needs a positive native rectangle and caller depth.")
        }
        let derivative = try original.differentiated(alongU: !freeAlongU, usage: &usage)
            .enclosure(over: domain, usage: &usage)
        guard derivative.excludesZero else { return nil }
        let source = freeAlongU ? original : try original.exchangedAxes(usage: &usage)
        let free = freeAlongU ? domain.u : domain.v
        let transverse = freeAlongU ? domain.v : domain.u
        let lower = try ExactRationalCoefficient.originalDouble(free.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(free.upper, usage: &usage)
        let low = try source.restricted(alongU: false, station: .originalDouble(transverse.lower, usage: &usage),
            usage: &usage)
        let high = try source.restricted(alongU: false, station: .originalDouble(transverse.upper, usage: &usage),
            usage: &usage)
        var projection = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        if !low.isZero { projection = try projection.multiplied(by: low, usage: &usage) }
        if !high.isZero { projection = try projection.multiplied(by: high, usage: &usage) }
        try usage.retainExactStorage(2)
        var endpoints: [ExactMonotoneGraphEndpoint] = [.authored(lower), .authored(upper)]
        if projection.uDegree > 0 {
            let roots = try ExactUnivariateRootIsolator().isolate(projection, lower: lower, upper: upper,
                maximumDepth: maximumDepth, usage: &usage)
            for root in roots {
                let value = try ExactAlgebraicRealRoot(polynomial: projection, isolation: root, usage: &usage)
                let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                let atLower = try u.subtracting(.constant(lower, usage: &usage), usage: &usage)
                let atUpper = try u.subtracting(.constant(upper, usage: &usage), usage: &usage)
                if case .zero = try value.sign(of: atLower, maximumDepth: maximumDepth, usage: &usage) { continue }
                if case .zero = try value.sign(of: atUpper, maximumDepth: maximumDepth, usage: &usage) { continue }
                try usage.retainExactStorage(1); endpoints.append(.algebraic(value))
            }
        }
        for endpoint in additionalStations {
            let coordinate = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            let atLower = try coordinate.subtracting(.constant(lower, usage: &usage), usage: &usage)
            let atUpper = try coordinate.subtracting(.constant(upper, usage: &usage), usage: &usage)
            if case .negative = try endpoint.sign(of: atLower, maximumDepth: maximumDepth, usage: &usage) { continue }
            if case .positive = try endpoint.sign(of: atUpper, maximumDepth: maximumDepth, usage: &usage) { continue }
            var duplicate = false
            for prior in endpoints {
                if try prior.hasSameValue(as: endpoint, maximumDepth: maximumDepth, usage: &usage) {
                    duplicate = true; break
                }
            }
            if !duplicate { try usage.retainExactStorage(1); endpoints.append(endpoint) }
        }
        // Order by exact lower bounds, then authored point before an open root
        // interval at the same bound. Each distinct original root is retained once.
        try usage.consumeExactWork(try rationalAlgebraCount(endpoints.count, endpoints.count, multiply: true))
        for i in 1..<endpoints.count {
            var j = i
            while j > 0 {
                let difference = try endpoints[j].lower.subtracting(endpoints[j - 1].lower, usage: &usage)
                let before = difference.isNegative || difference.isZero && endpoints[j].lower == endpoints[j].upper
                    && endpoints[j - 1].lower != endpoints[j - 1].upper
                if !before { break }
                endpoints.swapAt(j, j - 1); j -= 1
            }
        }
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        for i in 0..<(endpoints.count - 1) {
            while !(try endpoints[i + 1].lower.subtracting(endpoints[i].upper, usage: &usage)).isPositive {
                try usage.visitExactCell(depth: max(endpoints[i].depth, endpoints[i + 1].depth))
                var refined = false
                for index in [i, i + 1] {
                    let width = try endpoints[index].upper.subtracting(endpoints[index].lower, usage: &usage)
                    if width.isPositive {
                        endpoints[index] = try endpoints[index].refined(maximumWidth: width.divided(by: two, usage: &usage),
                            maximumDepth: maximumDepth, usage: &usage); refined = true
                    }
                }
                guard refined else { throw rationalAlgebraFailure("Distinct original graph stations have conflicting exact endpoint identity.") }
            }
        }
        var stations: [ExactMonotoneRectangleGraph.Station] = []
        for endpoint in endpoints {
            let a = try endpoint.sign(of: low, maximumDepth: maximumDepth, usage: &usage)
            let b = try endpoint.sign(of: high, maximumDepth: maximumDepth, usage: &usage)
            try usage.retainExactStorage(1)
            stations.append(.init(endpoint: endpoint, containsRoot: brackets(a, b)))
        }
        var spans: [ExactMonotoneRectangleGraph.Span] = []
        var incident: [Bool] = []
        try usage.retainExactStorage(stations.count)
        incident = [Bool](repeating: false, count: stations.count)
        for i in 0..<(stations.count - 1) {
            let middle = try endpoints[i].upper.adding(endpoints[i + 1].lower, usage: &usage)
                .divided(by: two, usage: &usage)
            let a = try sign(low.evaluated(atU: middle, v: .zero, usage: &usage))
            let b = try sign(high.evaluated(atU: middle, v: .zero, usage: &usage))
            if !low.isZero, case .zero = a {
                throw rationalAlgebraFailure("Original graph sector anchor is an omitted lower-edge source root.")
            }
            if !high.isZero, case .zero = b {
                throw rationalAlgebraFailure("Original graph sector anchor is an omitted upper-edge source root.")
            }
            if brackets(a, b) {
                guard stations[i].containsRoot, stations[i + 1].containsRoot else {
                    throw rationalAlgebraFailure("Closed original regular graph sector lost endpoint incidence.")
                }
                try usage.retainExactStorage(1); spans.append(.init(lowerStation: i, upperStation: i + 1))
                incident[i] = true; incident[i + 1] = true
            }
        }
        var isolated: [Int] = []
        for index in stations.indices where stations[index].containsRoot && !incident[index] {
            try usage.retainExactStorage(1); isolated.append(index)
        }
        return ExactMonotoneRectangleGraph(original: original, sourceDomain: domain, freeAlongU: freeAlongU,
            transverseDerivative: derivative, stations: stations, spans: spans, isolatedStationIndices: isolated)
    }
    private static func sign(_ value: ExactRationalCoefficient) -> ExactAlgebraicRealRoot.Sign {
        value.isZero ? .zero : value.isPositive ? .positive : .negative
    }
    private static func brackets(_ a: ExactAlgebraicRealRoot.Sign, _ b: ExactAlgebraicRealRoot.Sign) -> Bool {
        switch (a, b) {
        case (.zero, _), (_, .zero), (.negative, .positive), (.positive, .negative): true
        default: false
        }
    }
}
