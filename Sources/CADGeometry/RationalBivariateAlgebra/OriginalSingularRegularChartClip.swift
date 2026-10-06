/// Complete authored-rectangle clipping of one original regular ramified graph.
package struct OriginalSingularRegularChartClip: Sendable {
    package struct Station: Sendable {
        package let endpoint: OriginalSingularFieldEndpoint
        package let point: OriginalSingularFieldSystemRoot
        package let insideClosedSource: Bool
    }
    package struct Span: Sendable {
        package let lowerStation: Int
        package let upperStation: Int
        package let originalFreeWitness: ExactRationalCoefficient
        package let originalPoint: OriginalSingularFieldSystemRoot
    }
    package let chart: OriginalSingularRegularChart
    package let sourceDomain: SurfaceParameterBox
    package let stations: [Station]
    package let spans: [Span]
    /// A true entry retains an entire admitted graph on that exact original source boundary.
    package let coincidentBoundaries: [Bool]

    package init<B: RationalAlgebraAdmitting>(chart: OriginalSingularRegularChart,
        over sourceDomain: SurfaceParameterBox, maximumDepth: Int, usage: inout B) throws {
        self.chart = chart; self.sourceDomain = sourceDomain
        let original = chart.germ
        let law = chart.freeAlongU ? original.strictTransform
            : try original.strictTransform.exchangedAxes(maximumDepth: maximumDepth, usage: &usage)
        let mapU = chart.freeAlongU ? original.originalU
            : try original.originalU.exchangedAxes(maximumDepth: maximumDepth, usage: &usage)
        let mapV = chart.freeAlongU ? original.originalV
            : try original.originalV.exchangedAxes(maximumDepth: maximumDepth, usage: &usage)
        let domain = chart.freeAlongU ? chart.localDomain : SurfaceParameterBox(u: chart.localDomain.v, v: chart.localDomain.u)
        let context = law.context
        var boundaries: [OriginalSingularFieldPlanePolynomial] = []
        for (map, station) in [(mapU, sourceDomain.u.lower), (mapU, sourceDomain.u.upper),
                               (mapV, sourceDomain.v.lower), (mapV, sourceDomain.v.upper)] {
            let scalar = try OriginalSingularFieldElement.constant(.originalDouble(station, usage: &usage),
                in: context, maximumDepth: maximumDepth, usage: &usage)
            try usage.retainExactStorage(1)
            boundaries.append(try map.subtracting(.constant(scalar, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage))
        }
        var endpoints: [OriginalSingularFieldEndpoint] = [
            .authored(try .originalDouble(domain.u.lower, usage: &usage)),
            .authored(try .originalDouble(domain.u.upper, usage: &usage))]
        try usage.retainExactStorage(2)
        var coincident: [Bool] = []
        for boundary in boundaries {
            if boundary.isZero { try usage.retainExactStorage(1); coincident.append(true); continue }
            let common = try OriginalSingularFieldPlaneGCD.gcd(law, boundary, maximumDepth: maximumDepth, usage: &usage)
            let atOrigin = common.coefficients[try .init(u: 0, v: 0)]
            if atOrigin == nil {
                // The admitted graph has one simple root everywhere. A common
                // original factor through its origin must therefore own that
                // entire connected graph; any factor crossing would contradict
                // the whole transverse derivative exclusion.
                try usage.retainExactStorage(1); coincident.append(true); continue
            }
            try usage.retainExactStorage(1); coincident.append(false)
            let first = try law.dividedExactly(by: common, maximumDepth: maximumDepth, usage: &usage)
            let second = try boundary.dividedExactly(by: common, maximumDepth: maximumDepth, usage: &usage)
            switch try OriginalSingularFieldSystemSolver.roots(of: [first, second], over: domain,
                inheritedDepth: chart.sourceDepth, maximumDepth: maximumDepth, usage: &usage) {
            case .finite(let roots):
                for root in roots {
                    guard case .zero = try root.sign(of: law, maximumDepth: maximumDepth, usage: &usage) else {
                        throw rationalAlgebraFailure("Original clipped event is not on its admitted strict graph.")
                    }
                    try usage.retainExactStorage(1); endpoints.append(.algebraic(root.projectionRoot))
                }
            case .positiveDimension:
                throw rationalAlgebraFailure("Coprime original graph and boundary retained a positive-dimensional ideal.")
            }
        }
        var ordered: [OriginalSingularFieldEndpoint] = []
        for var endpoint in endpoints {
            var insertion = ordered.count, duplicate = false
            for i in ordered.indices {
                var retained = ordered[i]
                let comparison = try OriginalSingularFieldEndpoint.compare(&endpoint, &retained,
                    maximumDepth: maximumDepth, usage: &usage)
                ordered[i] = retained
                if comparison == 0 { duplicate = true; break }
                if comparison < 0 { insertion = i; break }
            }
            if !duplicate { try usage.retainExactStorage(1); ordered.insert(endpoint, at: insertion) }
        }
        var retainedStations: [Station] = []
        for endpoint in ordered {
            let point = try Self.point(on: law, endpoint: endpoint, domain: domain,
                sourceDepth: chart.sourceDepth, maximumDepth: maximumDepth, usage: &usage)
            try usage.retainExactStorage(1)
            retainedStations.append(Station(endpoint: endpoint, point: point,
                insideClosedSource: try Self.inside(point, boundaries: boundaries, maximumDepth: maximumDepth, usage: &usage)))
        }
        var positive: [Span] = []
        if ordered.count > 1 { for index in 0..<(ordered.count - 1) {
            var lower = ordered[index], upper = ordered[index + 1]
            let witness = try OriginalSingularFieldEndpoint.between(&lower, &upper, maximumDepth: maximumDepth, usage: &usage)
            ordered[index] = lower; ordered[index + 1] = upper
            let point = try Self.point(on: law, endpoint: .authored(witness), domain: domain,
                sourceDepth: max(chart.sourceDepth, max(lower.depth, upper.depth)), maximumDepth: maximumDepth, usage: &usage)
            if try Self.inside(point, boundaries: boundaries, maximumDepth: maximumDepth, usage: &usage) {
                try usage.retainExactStorage(1)
                positive.append(Span(lowerStation: index, upperStation: index + 1,
                    originalFreeWitness: witness, originalPoint: point))
            }
        } }
        // Retain the refined endpoint authorities selected while forming each
        // positive-width sector; original point receipts remain source-identical.
        var finished: [Station] = []
        try usage.retainExactStorage(retainedStations.count)
        for i in retainedStations.indices {
            finished.append(Station(endpoint: ordered[i], point: retainedStations[i].point,
                insideClosedSource: retainedStations[i].insideClosedSource))
        }
        stations = finished; spans = positive; coincidentBoundaries = coincident
    }

    private static func inside<B: RationalAlgebraAdmitting>(_ point: OriginalSingularFieldSystemRoot,
        boundaries: [OriginalSingularFieldPlanePolynomial], maximumDepth: Int, usage: inout B) throws -> Bool {
        for i in boundaries.indices {
            let direction = try point.sign(of: boundaries[i], maximumDepth: maximumDepth, usage: &usage)
            switch direction { case .zero: break
            case .positive: if i % 2 == 1 { return false }
            case .negative: if i % 2 == 0 { return false } }
        }
        return true
    }

    private static func point<B: RationalAlgebraAdmitting>(on law: OriginalSingularFieldPlanePolynomial,
        endpoint: OriginalSingularFieldEndpoint, domain: SurfaceParameterBox, sourceDepth: Int,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldSystemRoot {
        let projected: OriginalSingularFieldRoot, u: OriginalSingularFieldElement
        switch endpoint {
        case .algebraic(let root): projected = root; u = try root.value(maximumDepth: maximumDepth, usage: &usage)
        case .authored(let value):
            let zero = try OriginalSingularFieldElement.constant(value.negated, in: law.context, maximumDepth: maximumDepth, usage: &usage)
            let one = try OriginalSingularFieldElement.constant(.one, in: law.context, maximumDepth: maximumDepth, usage: &usage)
            let polynomial = try OriginalSingularFieldPolynomial(context: law.context, coefficients: [zero, one], maximumDepth: maximumDepth, usage: &usage)
            projected = .init(polynomial: polynomial, isolation: .init(lower: value, upper: value,
                excludesLower: false, excludesUpper: false, depth: sourceDepth))
            u = try .constant(value, in: law.context, maximumDepth: maximumDepth, usage: &usage)
        }
        let fiber = try OriginalSingularFieldSystemSolver.fiber(law, at: u, maximumDepth: maximumDepth, usage: &usage)
        let roots = try OriginalSingularFieldRoot.allRealRoots(fiber, inheritedDepth: max(sourceDepth, endpoint.depth),
            maximumDepth: maximumDepth, usage: &usage)
        var selected: OriginalSingularFieldSystemRoot?
        for root in roots {
            let v = try root.value(maximumDepth: maximumDepth, usage: &usage)
            let low = try OriginalSingularFieldElement.constant(.originalDouble(domain.v.lower, usage: &usage), in: v.context, maximumDepth: maximumDepth, usage: &usage)
            let high = try OriginalSingularFieldElement.constant(.originalDouble(domain.v.upper, usage: &usage), in: v.context, maximumDepth: maximumDepth, usage: &usage)
            if case .negative = try v.subtracting(low, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) { continue }
            if case .positive = try v.subtracting(high, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) { continue }
            guard selected == nil else { throw rationalAlgebraFailure("Original regular clipped station has two transverse roots.") }
            let point = OriginalSingularFieldSystemRoot(equations: [law], projectionRoot: projected,
                fiberRoot: root, u: u, v: v, sourceDomain: domain)
            guard case .zero = try point.sign(of: law, maximumDepth: maximumDepth, usage: &usage) else { throw rationalAlgebraFailure("Original clipped station lost source identity.") }
            selected = point
        }
        guard let selected else { throw rationalAlgebraFailure("Original regular clipped station has no original transverse root.") }
        return selected
    }
}
