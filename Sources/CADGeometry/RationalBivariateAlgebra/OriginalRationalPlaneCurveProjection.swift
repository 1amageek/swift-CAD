import CADCore

/// Complete original projection cells, real station fibers and ordered open-strip branches.
package struct OriginalRationalPlaneCurveProjection: Sendable {
    package struct Station: Sendable {
        package let endpoint: ExactMonotoneGraphEndpoint
        package let roots: [ExactBivariateSystemRoot]
    }
    package struct Sector: Sendable {
        package let lowerStation: Int
        package let upperStation: Int
        package let originalFreeStation: ExactRationalCoefficient
        package let fiberRoots: [ExactAlgebraicRealRoot]
    }
    package let original: OriginalRationalZeroSetAuthority
    package let domain: SurfaceParameterBox
    package let sourceDepth: Int
    package let primitive: ExactBivariatePolynomial
    package let projection: ExactBivariatePolynomial
    package let verticalComponents: [ExactMonotoneGraphEndpoint]
    package let horizontalComponents: [ExactRationalCoefficient]
    package let stations: [Station]
    package let sectors: [Sector]

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalRationalZeroSetAuthority,
        over domain: SurfaceParameterBox, maximumDepth: Int, inheritedDepth: Int = 0, usage: inout B) throws {
        guard !original.squareFree.isZero, domain.u.width > 0, domain.v.width > 0,
              inheritedDepth >= 0, maximumDepth >= inheritedDepth else {
            throw rationalAlgebraFailure("Original plane projection needs a nonzero law and positive closed source rectangle.")
        }
        self.original = original; self.domain = domain; sourceDepth = inheritedDepth
        let u0 = try ExactRationalCoefficient.originalDouble(domain.u.lower, usage: &usage)
        let u1 = try ExactRationalCoefficient.originalDouble(domain.u.upper, usage: &usage)
        let v0 = try ExactRationalCoefficient.originalDouble(domain.v.lower, usage: &usage)
        let v1 = try ExactRationalCoefficient.originalDouble(domain.v.upper, usage: &usage)
        let gcd = ExactBivariateGCD()
        let content = try gcd.content(original.squareFree, usage: &usage)
        var remaining = try gcd.divideCoefficients(original.squareFree, by: content, usage: &usage)
        var vertical: [ExactMonotoneGraphEndpoint] = []
        if content.uDegree > 0 {
            for root in try Self.sliceRoots(content, lower: u0, upper: u1,
                parentDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage) {
                try RationalAlgebraStorage.retain(1, of: ExactMonotoneGraphEndpoint.self, usage: &usage)
                vertical.append(root)
            }
        }
        verticalComponents = try ExactOrderedRealEndpoints.ordered(vertical, maximumDepth: maximumDepth, usage: &usage)
        var horizontal: [ExactRationalCoefficient] = []
        for boundary in [v0, v1] {
            if try remaining.restricted(alongU: false, station: boundary, usage: &usage).isZero {
                let factor = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
                    .subtracting(.constant(boundary, usage: &usage), usage: &usage)
                remaining = try remaining.dividedExactly(by: factor, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: ExactRationalCoefficient.self, usage: &usage); horizontal.append(boundary)
            }
        }
        horizontalComponents = horizontal; primitive = remaining
        if remaining.vDegree <= 0 {
            guard remaining.uDegree <= 0, !remaining.isZero else {
                throw rationalAlgebraFailure("Original plane primitive remainder retained an unresolved coordinate factor.")
            }
            projection = try .constant(.one, usage: &usage); stations = []; sectors = []
            return
        }
        let derivative = try remaining.differentiated(alongU: false, usage: &usage)
        let discriminant = try ExactBivariateResultant().eliminatingV(remaining, derivative, usage: &usage)
        guard !discriminant.isZero else {
            throw rationalAlgebraFailure("Original square-free primitive plane law has a zero discriminant projection.")
        }
        let leading = try remaining.coefficient(ofV: remaining.vDegree, usage: &usage)
        let lowBoundary = try remaining.restricted(alongU: false, station: v0, usage: &usage)
        let highBoundary = try remaining.restricted(alongU: false, station: v1, usage: &usage)
        guard !leading.isZero, !lowBoundary.isZero, !highBoundary.isZero else {
            throw rationalAlgebraFailure("Original plane projection lost a degree or closed-boundary source law.")
        }
        let events = try discriminant.multiplied(by: leading, usage: &usage)
            .multiplied(by: lowBoundary, usage: &usage).multiplied(by: highBoundary, usage: &usage)
        let eventDerivative = try events.differentiated(alongU: true, usage: &usage)
        let repeated = try gcd.univariateGCD(events, eventDerivative, usage: &usage)
        projection = try events.dividedExactly(by: repeated, usage: &usage).normalized(usage: &usage)
        try RationalAlgebraStorage.retain(2, of: ExactMonotoneGraphEndpoint.self, usage: &usage)
        var endpoints: [ExactMonotoneGraphEndpoint] = [.authored(u0), .authored(u1)]
        if projection.uDegree > 0 {
            for root in try Self.sliceRoots(projection, lower: u0, upper: u1,
                parentDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage) {
                try RationalAlgebraStorage.retain(1, of: ExactMonotoneGraphEndpoint.self, usage: &usage)
                endpoints.append(root)
            }
        }
        endpoints = try ExactOrderedRealEndpoints.ordered(endpoints, maximumDepth: maximumDepth, usage: &usage)
        var strips: [Sector] = []
        for index in 0..<(endpoints.count - 1) {
            var lower = endpoints[index], upper = endpoints[index + 1]
            let witness = try ExactOrderedRealEndpoints.between(&lower, &upper,
                maximumDepth: maximumDepth, usage: &usage)
            endpoints[index] = lower; endpoints[index + 1] = upper
            let fiber = try remaining.restricted(alongU: true, station: witness, usage: &usage)
            guard !fiber.isZero else { throw rationalAlgebraFailure("Original primitive source has an identically zero regular fiber.") }
            let ordered = try Self.sliceRoots(fiber, lower: v0, upper: v1,
                parentDepth: max(inheritedDepth, max(lower.depth, upper.depth)), maximumDepth: maximumDepth, usage: &usage)
            var retained: [ExactAlgebraicRealRoot] = []
            try RationalAlgebraStorage.retain(ordered.count, of: ExactAlgebraicRealRoot.self, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: Sector.self, usage: &usage)
            for endpoint in ordered {
                guard case .algebraic(let value) = endpoint else { throw rationalAlgebraFailure("Original regular fiber lost its root authority.") }
                retained.append(value)
            }
            strips.append(Sector(lowerStation: index, upperStation: index + 1,
                originalFreeStation: witness, fiberRoots: retained))
        }
        var fibers: [Station] = []
        for endpoint in endpoints {
            let base = try Self.root(endpoint, inheritedDepth: inheritedDepth, usage: &usage)
            let fiber = try ExactAlgebraicFiberPolynomial(source: remaining, at: base,
                maximumDepth: maximumDepth, usage: &usage)
            guard !fiber.isZero else { throw rationalAlgebraFailure("Original primitive source retained an entire vertical station fiber.") }
            var values: [ExactBivariateSystemRoot] = []
            if fiber.degree > 0 {
                for isolation in try ExactAlgebraicFiberRootIsolator.isolate(fiber,
                    lower: v0, upper: v1, maximumDepth: maximumDepth, usage: &usage) {
                    let multiplicity = try ExactBivariateSystemSolver.multiplicity(fiber,
                        at: isolation, maximumDepth: maximumDepth, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: ExactBivariateSystemRoot.self, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
                    values.append(ExactBivariateSystemRoot(equations: [original.squareFree], projectionRoot: base,
                        fiber: fiber, fiberRoot: isolation, sourceDomain: domain,
                        projectionMultiplicity: 1, fiberMultiplicity: multiplicity))
                }
            }
            try RationalAlgebraStorage.retain(1, of: Station.self, usage: &usage); fibers.append(Station(endpoint: endpoint, roots: values))
        }
        stations = fibers; sectors = strips
    }

    /// Non-nil only when the complete original real locus in this rectangle is finite.
    package func finiteOriginalRoots<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> [ExactBivariateSystemRoot]? {
        if !verticalComponents.isEmpty || !horizontalComponents.isEmpty { return nil }
        for sector in sectors { try usage.consumeWork(1); if !sector.fiberRoots.isEmpty { return nil } }
        var values: [ExactBivariateSystemRoot] = []
        for station in stations {
            try RationalAlgebraStorage.retain(station.roots.count, of: ExactBivariateSystemRoot.self, usage: &usage)
            values.append(contentsOf: station.roots)
        }
        return values
    }

    static func sliceRoots<B: ExactScalarAdmission & ~Copyable>(_ source: ExactBivariatePolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, parentDepth: Int,
        maximumDepth: Int, usage: inout B) throws -> [ExactMonotoneGraphEndpoint] {
        guard maximumDepth >= parentDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original regular fiber inherited projection depth beyond caller admission.")
        }
        let retained = try usage.withProofScope(original: .init(value: 0, coefficient: 0),
            inherited: .init(value: parentDepth, coefficient: 0)) { usage in
            var retained: [ExactMonotoneGraphEndpoint] = []
            let roots = try ExactUnivariateRootIsolator().isolate(source, lower: lower, upper: upper,
                maximumDepth: maximumDepth - parentDepth, usage: &usage)
            for isolation in roots {
                let root = try ExactAlgebraicRealRoot(polynomial: source, isolation: isolation, usage: &usage)
                    .retainingDepth(rationalAlgebraCount(parentDepth, isolation.isolationDepth))
                try RationalAlgebraStorage.retain(1, of: ExactMonotoneGraphEndpoint.self, usage: &usage)
                retained.append(.algebraic(root))
            }
            return retained
        }
        return try ExactOrderedRealEndpoints.ordered(retained, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func root<B: ExactScalarAdmission & ~Copyable>(_ endpoint: ExactMonotoneGraphEndpoint, inheritedDepth: Int,
        usage: inout B) throws -> ExactAlgebraicRealRoot {
        switch endpoint {
        case .algebraic(let root): return try root.retainingDepth(max(inheritedDepth, root.isolation.isolationDepth))
        case .authored(let station):
            let linear = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                .subtracting(.constant(station, usage: &usage), usage: &usage)
            let isolation = ExactUnivariateRootIsolator.Root(lower: station, upper: station,
                isRationalStation: true, isolationDepth: inheritedDepth, excludesLowerEndpoint: false, excludesUpperEndpoint: false)
            return try ExactAlgebraicRealRoot(polynomial: linear, isolation: isolation, usage: &usage)
        }
    }
}
