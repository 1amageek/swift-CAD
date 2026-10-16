/// Complete original plane projection and real fibers over a retained coefficient tower.
package struct OriginalSingularFieldPlaneProjection: Sendable {
    package struct Station: Sendable {
        package let endpoint: OriginalSingularFieldEndpoint
        package let roots: [OriginalSingularFieldSystemRoot]
    }
    package struct Sector: Sendable {
        package let lowerStation: Int
        package let upperStation: Int
        package let originalFreeStation: ExactRationalCoefficient
        package let fiberRoots: [OriginalSingularFieldRoot]
    }
    package let original: OriginalSingularFieldPlanePolynomial
    package let squareFree: OriginalSingularFieldPlanePolynomial
    package let primitive: OriginalSingularFieldPlanePolynomial
    package let domain: SurfaceParameterBox
    package let sourceDepth: Int
    package let projection: OriginalSingularFieldPolynomial
    package let verticalComponents: [OriginalSingularFieldRoot]
    package let horizontalComponents: [ExactRationalCoefficient]
    package let stations: [Station]
    package let sectors: [Sector]

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldPlanePolynomial,
        over domain: SurfaceParameterBox, inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws {
        guard !original.isZero, domain.u.width > 0, domain.v.width > 0,
            inheritedDepth >= 0, inheritedDepth <= maximumDepth, original.context.depth <= maximumDepth else {
            throw rationalAlgebraFailure("Original field plane projection needs a nonzero source and admitted positive rectangle.")
        }
        self.original = original; self.domain = domain
        sourceDepth = max(inheritedDepth, original.context.depth)
        let u0 = try ExactRationalCoefficient.originalDouble(domain.u.lower, usage: &usage)
        let u1 = try ExactRationalCoefficient.originalDouble(domain.u.upper, usage: &usage)
        let v0 = try ExactRationalCoefficient.originalDouble(domain.v.lower, usage: &usage)
        let v1 = try ExactRationalCoefficient.originalDouble(domain.v.upper, usage: &usage)
        let first = try OriginalSingularFieldPlaneGCD.gcd(original,
            original.differentiated(alongU: true, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        let repeated = try OriginalSingularFieldPlaneGCD.gcd(first,
            original.differentiated(alongU: false, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        squareFree = try original.dividedExactly(by: repeated, maximumDepth: maximumDepth, usage: &usage)
            .normalized(maximumDepth: maximumDepth, usage: &usage)
        let content = try OriginalSingularFieldPlaneGCD.content(squareFree, maximumDepth: maximumDepth, usage: &usage)
        verticalComponents = try Self.sliceRoots(content, lower: u0, upper: u1,
            inheritedDepth: sourceDepth, maximumDepth: maximumDepth, usage: &usage)
        var remaining = try OriginalSingularFieldPlaneGCD.primitive(squareFree,
            content: content, maximumDepth: maximumDepth, usage: &usage)
        var horizontal: [ExactRationalCoefficient] = []
        for boundaryIndex in 0..<2 {
            let boundary = boundaryIndex == 0 ? v0 : v1
            let restriction = try Self.restricted(remaining, alongU: false, station: boundary,
                maximumDepth: maximumDepth, usage: &usage)
            if restriction.isZero {
                let factor = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: false,
                    in: original.context, maximumDepth: maximumDepth, usage: &usage).subtracting(
                        .constant(.constant(boundary, in: original.context, maximumDepth: maximumDepth, usage: &usage),
                            maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                remaining = try remaining.dividedExactly(by: factor, maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: ExactRationalCoefficient.self, usage: &usage)
                horizontal.append(boundary)
            }
        }
        horizontalComponents = horizontal; primitive = remaining
        let one = try OriginalSingularFieldElement.constant(.one, in: original.context, maximumDepth: maximumDepth, usage: &usage)
        if remaining.vDegree <= 0 {
            guard remaining.uDegree <= 0, !remaining.isZero else {
                throw rationalAlgebraFailure("Original field primitive retained an unresolved coordinate component.")
            }
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
            projection = try .init(context: original.context, coefficients: [one], maximumDepth: maximumDepth, usage: &usage)
            stations = []; sectors = []; return
        }
        let discriminant = try OriginalSingularFieldResultant.eliminatingV(remaining,
            remaining.differentiated(alongU: false, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        guard !discriminant.isZero else { throw rationalAlgebraFailure("Original square-free field primitive has a zero discriminant.") }
        let leading = try OriginalSingularFieldPlaneGCD.coefficient(remaining, vPower: remaining.vDegree,
            maximumDepth: maximumDepth, usage: &usage)
        let lowerBoundary = try Self.restricted(remaining, alongU: false, station: v0, maximumDepth: maximumDepth, usage: &usage)
        let upperBoundary = try Self.restricted(remaining, alongU: false, station: v1, maximumDepth: maximumDepth, usage: &usage)
        guard !leading.isZero, !lowerBoundary.isZero, !upperBoundary.isZero else {
            throw rationalAlgebraFailure("Original field projection lost its leading or transverse boundary law.")
        }
        let events = try discriminant.multiplied(by: content, maximumDepth: maximumDepth, usage: &usage)
            .multiplied(by: leading, maximumDepth: maximumDepth, usage: &usage)
            .multiplied(by: lowerBoundary, maximumDepth: maximumDepth, usage: &usage)
            .multiplied(by: upperBoundary, maximumDepth: maximumDepth, usage: &usage)
        let sequence = try OriginalSingularFieldSturm(events, maximumDepth: maximumDepth, usage: &usage)
        projection = sequence.source
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldEndpoint.self, usage: &usage)
        var endpoints: [OriginalSingularFieldEndpoint] = [.authored(u0), .authored(u1)]
        for root in try Self.sliceRoots(projection, lower: u0, upper: u1,
            inheritedDepth: sourceDepth, maximumDepth: maximumDepth, usage: &usage) {
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldEndpoint.self, usage: &usage)
            endpoints.append(.algebraic(root))
        }
        endpoints = try Self.ordered(endpoints, maximumDepth: maximumDepth, usage: &usage)
        var strips: [Sector] = []
        for index in 0..<(endpoints.count - 1) {
            var lower = endpoints[index], upper = endpoints[index + 1]
            let witness = try OriginalSingularFieldEndpoint.between(&lower, &upper,
                maximumDepth: maximumDepth, usage: &usage)
            endpoints[index] = lower; endpoints[index + 1] = upper
            let fiber = try Self.restricted(remaining, alongU: true, station: witness,
                maximumDepth: maximumDepth, usage: &usage)
            guard !fiber.isZero else { throw rationalAlgebraFailure("Original primitive field law has an entire regular vertical fiber.") }
            let roots = try Self.sliceRoots(fiber, lower: v0, upper: v1,
                inheritedDepth: max(sourceDepth, max(lower.depth, upper.depth)),
                maximumDepth: maximumDepth, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: Sector.self, usage: &usage)
            strips.append(Sector(lowerStation: index, upperStation: index + 1,
                originalFreeStation: witness, fiberRoots: roots))
        }
        var fibers: [Station] = []
        for endpoint in endpoints {
            let station = try Self.root(endpoint, context: original.context, inheritedDepth: sourceDepth,
                maximumDepth: maximumDepth, usage: &usage)
            let u = try station.value(maximumDepth: maximumDepth, usage: &usage)
            let fiber = try OriginalSingularFieldSystemSolver.fiber(remaining, at: u,
                maximumDepth: maximumDepth, usage: &usage)
            guard !fiber.isZero else { throw rationalAlgebraFailure("Original field primitive retained an entire station fiber.") }
            var points: [OriginalSingularFieldSystemRoot] = []
            for transverse in try Self.sliceRoots(fiber, lower: v0, upper: v1,
                inheritedDepth: station.isolation.depth, maximumDepth: maximumDepth, usage: &usage) {
                let v = try transverse.value(maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
                let point = OriginalSingularFieldSystemRoot(equations: [squareFree], projectionRoot: station,
                    fiberRoot: transverse, u: u, v: v, sourceDomain: domain)
                guard case .zero = try point.sign(of: squareFree, maximumDepth: maximumDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("Original field station is not a zero of its original plane law.")
                }
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
                points.append(point)
            }
            try RationalAlgebraStorage.retain(1, of: Station.self, usage: &usage)
            fibers.append(Station(endpoint: endpoint, roots: points))
        }
        stations = fibers; sectors = strips
    }

    package func finiteOriginalRoots<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> [OriginalSingularFieldSystemRoot]? {
        if !verticalComponents.isEmpty || !horizontalComponents.isEmpty { return nil }
        for sector in sectors { try usage.consumeWork(1); if !sector.fiberRoots.isEmpty { return nil } }
        var result: [OriginalSingularFieldSystemRoot] = []
        for station in stations {
            try RationalAlgebraStorage.retain(station.roots.count, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
            result.append(contentsOf: station.roots)
        }
        return result
    }

    static func restricted<B: ExactScalarAdmission & ~Copyable>(_ polynomial: OriginalSingularFieldPlanePolynomial,
        alongU: Bool, station: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        let count = try rationalAlgebraCount(alongU ? polynomial.vDegree : polynomial.uDegree, 1)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        let value = try OriginalSingularFieldElement.constant(station, in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for (power, coefficient) in try polynomial.orderedTerms(usage: &usage) {
            var term = coefficient
            for _ in 0..<(alongU ? power.u : power.v) { term = try term.multiplied(by: value, maximumDepth: maximumDepth, usage: &usage) }
            let index = alongU ? power.v : power.u
            coefficients[index] = try coefficients[index].adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return try .init(context: polynomial.context, coefficients: coefficients, maximumDepth: maximumDepth, usage: &usage)
    }

    static func sliceRoots<B: ExactScalarAdmission & ~Copyable>(_ polynomial: OriginalSingularFieldPolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, inheritedDepth: Int,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldRoot] {
        guard !polynomial.isZero else { throw rationalAlgebraFailure("Original field slice cannot isolate an identically zero source.") }
        var roots: [OriginalSingularFieldRoot] = []
        for root in try OriginalSingularFieldRoot.allRealRoots(polynomial,
            inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage) {
            var endpoint = OriginalSingularFieldEndpoint.algebraic(root)
            var low = OriginalSingularFieldEndpoint.authored(lower), high = OriginalSingularFieldEndpoint.authored(upper)
            if try OriginalSingularFieldEndpoint.compare(&endpoint, &low, maximumDepth: maximumDepth, usage: &usage) < 0 { continue }
            if try OriginalSingularFieldEndpoint.compare(&endpoint, &high, maximumDepth: maximumDepth, usage: &usage) > 0 { continue }
            guard case .algebraic(let retained) = endpoint else { throw rationalAlgebraFailure("Original field slice lost its root receipt.") }
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldRoot.self, usage: &usage)
            roots.append(retained)
        }
        return roots
    }

    private static func ordered<B: ExactScalarAdmission & ~Copyable>(_ values: [OriginalSingularFieldEndpoint],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldEndpoint] {
        var result: [OriginalSingularFieldEndpoint] = []
        for value in values {
            var candidate = value, index = 0, duplicate = false
            while index < result.count {
                var existing = result[index]
                let order = try OriginalSingularFieldEndpoint.compare(&candidate, &existing,
                    maximumDepth: maximumDepth, usage: &usage)
                result[index] = existing
                if order == 0 { duplicate = true; break }
                if order < 0 { break }; index += 1
            }
            if !duplicate {
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldEndpoint.self, usage: &usage)
                try usage.consumeWork(result.count - index)
                result.insert(candidate, at: index)
            }
        }
        return result
    }

    package static func root<B: ExactScalarAdmission & ~Copyable>(_ endpoint: OriginalSingularFieldEndpoint,
        context: OriginalSingularFieldContext, inheritedDepth: Int, maximumDepth: Int,
        usage: inout B) throws -> OriginalSingularFieldRoot {
        switch endpoint {
        case .algebraic(let root): return root
        case .authored(let value):
            let negative = try OriginalSingularFieldElement.constant(value.negated, in: context, maximumDepth: maximumDepth, usage: &usage)
            let one = try OriginalSingularFieldElement.constant(.one, in: context, maximumDepth: maximumDepth, usage: &usage)
            try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
            let polynomial = try OriginalSingularFieldPolynomial(context: context, coefficients: [negative, one], maximumDepth: maximumDepth, usage: &usage)
            return OriginalSingularFieldRoot(polynomial: polynomial, isolation: .init(lower: value, upper: value,
                excludesLower: false, excludesUpper: false, depth: inheritedDepth))
        }
    }
}
