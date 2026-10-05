import CADCore

/// Exact complete original rectangle clipping of a polynomial parameter law.
package struct OriginalRationalPolynomialParameterDomain: Sendable {
    package struct Station: Sendable {
        package let parameter: ExactMonotoneGraphEndpoint
        package let isInside: Bool
    }
    package struct Span: Sendable {
        package let first: Int
        package let last: Int
    }
    package let u: ExactBivariatePolynomial
    package let v: ExactBivariatePolynomial
    package let originalDomain: SurfaceParameterBox
    package let stations: [Station]
    package let spans: [Span]
    package let isolatedStationIndices: [Int]

    package static func clipped<B: RationalAlgebraAdmitting>(u: ExactBivariatePolynomial,
        v: ExactBivariatePolynomial, originalDomain: SurfaceParameterBox,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B, interiorStations: [ExactRationalCoefficient] = []) throws -> Self {
        guard u.vDegree <= 0, v.vDegree <= 0,
              try upper.subtracting(lower, usage: &usage).isPositive else {
            throw rationalAlgebraFailure("Original polynomial parameter clipping needs a univariate map and increasing exact cover.")
        }
        try usage.retainExactStorage(4)
        let boundaries = try [u.subtracting(.constant(.originalDouble(originalDomain.u.lower, usage: &usage), usage: &usage), usage: &usage),
            u.subtracting(.constant(.originalDouble(originalDomain.u.upper, usage: &usage), usage: &usage), usage: &usage),
            v.subtracting(.constant(.originalDouble(originalDomain.v.lower, usage: &usage), usage: &usage), usage: &usage),
            v.subtracting(.constant(.originalDouble(originalDomain.v.upper, usage: &usage), usage: &usage), usage: &usage)]
        var product = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        for boundary in boundaries where boundary.uDegree > 0 {
            product = try product.multiplied(by: boundary, usage: &usage)
        }
        try usage.retainExactStorage(2)
        var endpoints: [ExactMonotoneGraphEndpoint] = [.authored(lower), .authored(upper)]
        if product.uDegree > 0 {
            for isolation in try ExactUnivariateRootIsolator().isolate(product, lower: lower,
                upper: upper, maximumDepth: maximumDepth, usage: &usage) {
                let endpoint = try ExactMonotoneGraphEndpoint.algebraic(ExactAlgebraicRealRoot(
                    polynomial: product, isolation: isolation, usage: &usage))
                if try endpoint.hasSameValue(as: .authored(lower), maximumDepth: maximumDepth, usage: &usage)
                    || endpoint.hasSameValue(as: .authored(upper), maximumDepth: maximumDepth, usage: &usage) { continue }
                try usage.retainExactStorage(1); endpoints.append(endpoint)
            }
        }
        for station in interiorStations {
            try usage.consumeExactWork(1)
            guard try station.subtracting(lower, usage: &usage).isPositive,
                try upper.subtracting(station, usage: &usage).isPositive else { continue }
            let endpoint = ExactMonotoneGraphEndpoint.authored(station)
            var exists = false
            for original in endpoints {
                if try original.hasSameValue(as: endpoint, maximumDepth: maximumDepth, usage: &usage) {
                    exists = true; break
                }
            }
            if !exists { try usage.retainExactStorage(1); endpoints.append(endpoint) }
        }
        for i in 1..<endpoints.count {
            var j = i
            while j > 0 {
                let order = try endpoints[j].lower.subtracting(endpoints[j - 1].lower, usage: &usage)
                let before = order.isNegative || order.isZero && endpoints[j].lower == endpoints[j].upper
                    && endpoints[j - 1].lower != endpoints[j - 1].upper
                if !before { break }
                try usage.consumeExactWork(1); endpoints.swapAt(j, j - 1); j -= 1
            }
        }
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        for index in 0..<(endpoints.count - 1) {
            while !(try endpoints[index + 1].lower.subtracting(endpoints[index].upper, usage: &usage)).isPositive {
                var refined = false
                for next in [index, index + 1] {
                    let width = try endpoints[next].upper.subtracting(endpoints[next].lower, usage: &usage)
                    if width.isPositive {
                        endpoints[next] = try endpoints[next].refined(maximumWidth: width.divided(by: two, usage: &usage),
                            maximumDepth: maximumDepth, usage: &usage); refined = true
                    }
                }
                guard refined else { throw rationalAlgebraFailure("Original parameter boundary roots have conflicting exact identity.") }
            }
        }
        func inside(_ endpoint: ExactMonotoneGraphEndpoint, usage: inout B) throws -> Bool {
            for index in boundaries.indices {
                let sign = try endpoint.sign(of: boundaries[index], maximumDepth: maximumDepth, usage: &usage)
                if index % 2 == 0 { if case .negative = sign { return false } }
                else { if case .positive = sign { return false } }
            }
            return true
        }
        try usage.retainExactStorage(endpoints.count)
        var stations: [Station] = []
        for endpoint in endpoints { stations.append(try .init(parameter: endpoint, isInside: inside(endpoint, usage: &usage))) }
        try usage.retainExactStorage(stations.count)
        var incident = [Bool](repeating: false, count: stations.count)
        var spans: [Span] = []
        for index in 0..<(stations.count - 1) {
            let middle = try endpoints[index].upper.adding(endpoints[index + 1].lower, usage: &usage)
                .divided(by: two, usage: &usage)
            if try inside(.authored(middle), usage: &usage) {
                guard stations[index].isInside, stations[index + 1].isInside else {
                    throw rationalAlgebraFailure("Original closed polynomial parameter sector lost its endpoint incidence.")
                }
                try usage.retainExactStorage(1); spans.append(.init(first: index, last: index + 1))
                incident[index] = true; incident[index + 1] = true
            }
        }
        var isolated: [Int] = []
        for index in stations.indices where stations[index].isInside && !incident[index] {
            try usage.retainExactStorage(1); isolated.append(index)
        }
        return Self(u: u, v: v, originalDomain: originalDomain, stations: stations,
            spans: spans, isolatedStationIndices: isolated)
    }
}
