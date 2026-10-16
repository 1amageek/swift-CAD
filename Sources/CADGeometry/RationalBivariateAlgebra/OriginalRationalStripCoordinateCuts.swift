/// Original native-coordinate events bound to retained regular atlas strips.
package struct OriginalRationalStripCoordinateCuts: Sendable {
    package struct Point: Sendable {
        package let stripIndex: Int
        package let cutAlongU: Bool
        package let cutIndex: Int
        package let originalU: OriginalSingularFieldElement
        package let originalV: OriginalSingularFieldElement
        package let sourceDepth: Int
    }
    package struct Coincident: Sendable {
        package let stripIndex: Int
        package let cutIndex: Int
        package let originalV: OriginalSingularFieldElement
    }
    package let originalAtlas: OriginalRationalPlaneCurveAtlas
    package let points: [Point]
    package let coincident: [Coincident]

    package init<B: ExactScalarAdmission & ~Copyable>(retaining atlas: OriginalRationalPlaneCurveAtlas,
        uCuts: [ExactMonotoneGraphEndpoint], vCuts: [ExactMonotoneGraphEndpoint],
        maximumDepth: Int, usage: inout B) throws {
        let projection = atlas.projection
        var retained: [Point] = [], overlaps: [Coincident] = []
        let transport = OriginalSingularFieldTransport()
        for (cutIndex, cut) in uCuts.enumerated() {
            let base = try OriginalSingularFieldContext(usage: &usage)
            let u = try transport.originalScalarValue(cut, into: base, maximumDepth: maximumDepth, usage: &usage)
            let fiber = try Self.fiber(projection.primitive, fixedAlongU: true, at: u,
                maximumDepth: maximumDepth, usage: &usage)
            for (stripIndex, strip) in atlas.strips.enumerated() {
                guard try Self.inside(u, sector: projection.sectors[strip.sectorIndex],
                    projection: projection, maximumDepth: maximumDepth, usage: &usage) else { continue }
                let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(fiber,
                    lower: .originalDouble(projection.domain.v.lower, usage: &usage),
                    upper: .originalDouble(projection.domain.v.upper, usage: &usage),
                    inheritedDepth: max(projection.sourceDepth, u.context.depth), maximumDepth: maximumDepth, usage: &usage)
                guard roots.count == projection.sectors[strip.sectorIndex].fiberRoots.count,
                    strip.branchOrdinal < roots.count else {
                    throw rationalAlgebraFailure("Original coordinate cut changed a retained regular strip fiber ordinal.")
                }
                let root = roots[strip.branchOrdinal]
                let v = try root.value(maximumDepth: maximumDepth, usage: &usage)
                let first = try u.embedded(in: v.context, maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
                retained.append(Point(stripIndex: stripIndex, cutAlongU: true, cutIndex: cutIndex,
                    originalU: first, originalV: v, sourceDepth: max(root.isolation.depth, projection.sourceDepth)))
            }
        }
        for (cutIndex, cut) in vCuts.enumerated() {
            let base = try OriginalSingularFieldContext(usage: &usage)
            let v = try transport.originalScalarValue(cut, into: base, maximumDepth: maximumDepth, usage: &usage)
            guard try Self.inside(v, interval: projection.domain.v, maximumDepth: maximumDepth, usage: &usage) else { continue }
            let horizontal = try Self.fiber(projection.primitive, fixedAlongU: false, at: v,
                maximumDepth: maximumDepth, usage: &usage)
            if horizontal.isZero {
                for (stripIndex, strip) in atlas.strips.enumerated() {
                    let u = try OriginalSingularFieldElement.constant(projection.sectors[strip.sectorIndex].originalFreeStation,
                        in: v.context, maximumDepth: maximumDepth, usage: &usage)
                    let fiber = try Self.fiber(projection.primitive, fixedAlongU: true, at: u,
                        maximumDepth: maximumDepth, usage: &usage)
                    if try Self.rank(of: v, in: fiber, lower: projection.domain.v.lower,
                        maximumDepth: maximumDepth, usage: &usage) == strip.branchOrdinal {
                        try RationalAlgebraStorage.retain(1, of: Coincident.self, usage: &usage)
                        overlaps.append(Coincident(stripIndex: stripIndex, cutIndex: cutIndex, originalV: v))
                    }
                }
                continue
            }
            let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(horizontal,
                lower: .originalDouble(projection.domain.u.lower, usage: &usage),
                upper: .originalDouble(projection.domain.u.upper, usage: &usage),
                inheritedDepth: max(projection.sourceDepth, v.context.depth), maximumDepth: maximumDepth, usage: &usage)
            for root in roots {
                let u = try root.value(maximumDepth: maximumDepth, usage: &usage)
                let second = try v.embedded(in: u.context, maximumDepth: maximumDepth, usage: &usage)
                for (stripIndex, strip) in atlas.strips.enumerated() {
                    guard try Self.inside(u, sector: projection.sectors[strip.sectorIndex],
                        projection: projection, maximumDepth: maximumDepth, usage: &usage) else { continue }
                    let fiber = try Self.fiber(projection.primitive, fixedAlongU: true, at: u,
                        maximumDepth: maximumDepth, usage: &usage)
                    let rank = try Self.rank(of: second, in: fiber, lower: projection.domain.v.lower,
                        maximumDepth: maximumDepth, usage: &usage)
                    if rank != strip.branchOrdinal { continue }
                    try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
                    retained.append(Point(stripIndex: stripIndex, cutAlongU: false, cutIndex: cutIndex,
                        originalU: u, originalV: second, sourceDepth: max(root.isolation.depth, projection.sourceDepth)))
                }
            }
        }
        originalAtlas = atlas; points = retained; coincident = overlaps
    }

    private static func fiber<B: ExactScalarAdmission & ~Copyable>(_ original: ExactBivariatePolynomial,
        fixedAlongU: Bool, at fixed: OriginalSingularFieldElement, maximumDepth: Int,
        usage: inout B) throws -> OriginalSingularFieldPolynomial {
        let count = try rationalAlgebraCount(max(0, fixedAlongU ? original.vDegree : original.uDegree), 1)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: fixed.context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for (power, coefficient) in try original.orderedTerms(usage: &usage) {
            var term = try OriginalSingularFieldElement.constant(coefficient, in: fixed.context,
                maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<(fixedAlongU ? power.u : power.v) {
                term = try term.multiplied(by: fixed, maximumDepth: maximumDepth, usage: &usage)
            }
            let index = fixedAlongU ? power.v : power.u
            values[index] = try values[index].adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return try .init(context: fixed.context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func inside<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        interval: ScalarInterval, maximumDepth: Int, usage: inout B) throws -> Bool {
        let low = try OriginalSingularFieldElement.constant(.originalDouble(interval.lower, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        let high = try OriginalSingularFieldElement.constant(.originalDouble(interval.upper, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        if case .negative = try value.subtracting(low, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        if case .positive = try value.subtracting(high, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        return true
    }

    private static func inside<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        sector: OriginalRationalPlaneCurveProjection.Sector, projection: OriginalRationalPlaneCurveProjection,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        let transport = OriginalSingularFieldTransport()
        let a = try transport.originalScalarValue(projection.stations[sector.lowerStation].endpoint,
            into: value.context, maximumDepth: maximumDepth, usage: &usage)
        let b = try transport.originalScalarValue(projection.stations[sector.upperStation].endpoint,
            into: a.context, maximumDepth: maximumDepth, usage: &usage)
        let selected = try value.embedded(in: b.context, maximumDepth: maximumDepth, usage: &usage)
        guard case .positive = try selected.subtracting(a.embedded(in: b.context, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage),
            case .negative = try selected.subtracting(b, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) else { return false }
        return true
    }

    package static func rank<B: ExactScalarAdmission & ~Copyable>(of value: OriginalSingularFieldElement,
        in fiber: OriginalSingularFieldPolynomial, lower: Double, maximumDepth: Int, usage: inout B) throws -> Int {
        guard case .zero = try fiber.evaluated(at: value, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original transverse cut is not a zero of its native fiber.")
        }
        let sequence = try OriginalSingularFieldSturm(fiber, maximumDepth: maximumDepth, usage: &usage)
        let low = try OriginalSingularFieldElement.constant(.originalDouble(lower, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        func variations(_ endpoint: OriginalSingularFieldElement, usage: inout B) throws -> Int {
            var previous = 0, changes = 0
            for polynomial in sequence.chain {
                let direction: Int
                switch try polynomial.evaluated(at: endpoint, maximumDepth: maximumDepth, usage: &usage)
                    .sign(maximumDepth: maximumDepth, usage: &usage) {
                case .zero: continue
                case .negative: direction = -1
                case .positive: direction = 1
                }
                if previous != 0, previous != direction { changes += 1 }; previous = direction
            }
            return changes
        }
        var result = try variations(low, usage: &usage) - variations(value, usage: &usage) - 1
        if case .zero = try fiber.evaluated(at: low, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { result += 1 }
        guard result >= 0 else { throw rationalAlgebraFailure("Original strip cut has an inconsistent transverse Sturm rank.") }
        return result
    }
}
