/// Exact original coordinate events on retained field atlas strips and closed stations.
package struct OriginalFieldStripCoordinateCuts: Sendable {
    package enum Incidence: Sendable { case strip(Int), station(Int) }
    package struct Point: Sendable {
        package let incidence: Incidence
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
    package let originalAtlas: OriginalFieldPlaneAtlas
    package let originalUCuts: [ExactMonotoneGraphEndpoint]
    package let originalVCuts: [ExactMonotoneGraphEndpoint]
    package let points: [Point]
    package let coincident: [Coincident]

    package init<B: ExactScalarAdmission & ~Copyable>(retaining atlas: OriginalFieldPlaneAtlas,
        uCuts: [ExactMonotoneGraphEndpoint], vCuts: [ExactMonotoneGraphEndpoint],
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        guard maximumDepth >= atlas.projection.sourceDepth, maximumAlgebraicDepth >= 0,
            atlas.projection.original.context.coefficientDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Original field coordinate cuts exceed parameter or coefficient admission.")
        }
        let result = try usage.withProofScope(maximum: .init(value: Int.max, coefficient: maximumAlgebraicDepth)) { usage in
            let projection = atlas.projection
            var transport = OriginalSingularFieldTransport()
            var retained: [Point] = [], overlaps: [Coincident] = []
            for axis in 0..<2 {
                let alongU = axis == 0
                let cuts = alongU ? uCuts : vCuts
                for (cutIndex, cut) in cuts.enumerated() {
                    let fixed = try transport.originalScalarValue(cut, into: projection.original.context,
                        maximumDepth: maximumDepth, usage: &usage)
                    let interval = alongU ? projection.domain.u : projection.domain.v
                    guard try Self.inside(fixed, interval: interval, maximumDepth: maximumDepth, usage: &usage) else { continue }
                    for (stationIndex, station) in atlas.stations.enumerated() {
                        let coordinate = alongU ? station.originalRoot.u : station.originalRoot.v
                        var comparisonTransport = OriginalSingularFieldTransport()
                        let context = try comparisonTransport.importing(fixed.context, into: coordinate.context,
                            maximumDepth: maximumDepth, usage: &usage)
                        let selected = try comparisonTransport.applying(to: fixed, in: context, maximumDepth: maximumDepth, usage: &usage)
                        let candidate = try coordinate.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
                        guard case .zero = try candidate.subtracting(selected, maximumDepth: maximumDepth, usage: &usage)
                            .sign(maximumDepth: maximumDepth, usage: &usage) else { continue }
                        try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
                        retained.append(Point(incidence: .station(stationIndex), cutAlongU: alongU, cutIndex: cutIndex,
                            originalU: station.originalRoot.u, originalV: station.originalRoot.v,
                            sourceDepth: max(station.originalRoot.projectionRoot.isolation.depth,
                                station.originalRoot.fiberRoot.isolation.depth)))
                    }
                    let fiber = try Self.fiber(projection.primitive, fixedAlongU: alongU, at: fixed,
                        transport: &transport, maximumDepth: maximumDepth, usage: &usage)
                    if alongU {
                        guard !fiber.isZero else {
                            throw rationalAlgebraFailure("Original primitive field cut retained a vertical content component.")
                        }
                        for (stripIndex, strip) in atlas.strips.enumerated() {
                            guard try Self.inside(fixed, sector: projection.sectors[strip.sectorIndex],
                                projection: projection, transport: &transport,
                                maximumDepth: maximumDepth, usage: &usage) else { continue }
                            let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(fiber,
                                lower: .originalDouble(projection.domain.v.lower, usage: &usage),
                                upper: .originalDouble(projection.domain.v.upper, usage: &usage),
                                inheritedDepth: max(projection.sourceDepth, fixed.context.depth),
                                maximumDepth: maximumDepth, usage: &usage)
                            guard roots.count == projection.sectors[strip.sectorIndex].fiberRoots.count,
                                strip.branchOrdinal < roots.count else {
                                throw rationalAlgebraFailure("Original field cut changed its retained strip fiber ordinal.")
                            }
                            let root = roots[strip.branchOrdinal]
                            let v = try root.value(maximumDepth: maximumDepth, usage: &usage)
                            let u = try fixed.embedded(in: v.context, maximumDepth: maximumDepth, usage: &usage)
                            try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
                            retained.append(Point(incidence: .strip(stripIndex), cutAlongU: true, cutIndex: cutIndex,
                                originalU: u, originalV: v, sourceDepth: max(root.isolation.depth, projection.sourceDepth)))
                        }
                    } else if fiber.isZero {
                        for (stripIndex, strip) in atlas.strips.enumerated() {
                            let u = try OriginalSingularFieldElement.constant(projection.sectors[strip.sectorIndex].originalFreeStation,
                                in: fixed.context, maximumDepth: maximumDepth, usage: &usage)
                            let transverse = try Self.fiber(projection.primitive, fixedAlongU: true, at: u,
                                transport: &transport, maximumDepth: maximumDepth, usage: &usage)
                            if try OriginalRationalStripCoordinateCuts.rank(of: fixed, in: transverse,
                                lower: projection.domain.v.lower, maximumDepth: maximumDepth, usage: &usage) == strip.branchOrdinal {
                                try RationalAlgebraStorage.retain(1, of: Coincident.self, usage: &usage)
                                overlaps.append(Coincident(stripIndex: stripIndex, cutIndex: cutIndex, originalV: fixed))
                            }
                        }
                    } else {
                        let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(fiber,
                            lower: .originalDouble(projection.domain.u.lower, usage: &usage),
                            upper: .originalDouble(projection.domain.u.upper, usage: &usage),
                            inheritedDepth: max(projection.sourceDepth, fixed.context.depth),
                            maximumDepth: maximumDepth, usage: &usage)
                        for root in roots {
                            let u = try root.value(maximumDepth: maximumDepth, usage: &usage)
                            let v = try fixed.embedded(in: u.context, maximumDepth: maximumDepth, usage: &usage)
                            for (stripIndex, strip) in atlas.strips.enumerated() {
                                guard try Self.inside(u, sector: projection.sectors[strip.sectorIndex],
                                    projection: projection, transport: &transport, maximumDepth: maximumDepth, usage: &usage) else { continue }
                                let transverse = try Self.fiber(projection.primitive, fixedAlongU: true, at: u,
                                    transport: &transport, maximumDepth: maximumDepth, usage: &usage)
                                guard try OriginalRationalStripCoordinateCuts.rank(of: v, in: transverse,
                                    lower: projection.domain.v.lower, maximumDepth: maximumDepth, usage: &usage) == strip.branchOrdinal else { continue }
                                try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
                                retained.append(Point(incidence: .strip(stripIndex), cutAlongU: false, cutIndex: cutIndex,
                                    originalU: u, originalV: v, sourceDepth: max(root.isolation.depth, projection.sourceDepth)))
                            }
                        }
                    }
                }
            }
            return (points: retained, coincident: overlaps)
        }
        originalAtlas = atlas; originalUCuts = uCuts; originalVCuts = vCuts
        points = result.points; coincident = result.coincident
    }

    package static func fiber<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalSingularFieldPlanePolynomial,
        fixedAlongU: Bool, at fixed: OriginalSingularFieldElement, transport: inout OriginalSingularFieldTransport,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        let context = try transport.importing(original.context, into: fixed.context, maximumDepth: maximumDepth, usage: &usage)
        let selected = try fixed.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        let count = try rationalAlgebraCount(max(0, fixedAlongU ? original.vDegree : original.uDegree), 1)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for (power, coefficient) in try original.orderedTerms(usage: &usage) {
            var term = try transport.applying(to: coefficient, in: context, maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<(fixedAlongU ? power.u : power.v) { term = try term.multiplied(by: selected, maximumDepth: maximumDepth, usage: &usage) }
            let index = fixedAlongU ? power.v : power.u
            values[index] = try values[index].adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return try .init(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func inside<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        interval: ScalarInterval, maximumDepth: Int, usage: inout B) throws -> Bool {
        let low = try OriginalSingularFieldElement.constant(.originalDouble(interval.lower, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        let high = try OriginalSingularFieldElement.constant(.originalDouble(interval.upper, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        if case .negative = try value.subtracting(low, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        if case .positive = try value.subtracting(high, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        return true
    }

    private static func inside<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        sector: OriginalSingularFieldPlaneProjection.Sector, projection: OriginalSingularFieldPlaneProjection,
        transport: inout OriginalSingularFieldTransport, maximumDepth: Int, usage: inout B) throws -> Bool {
        func endpoint(_ source: OriginalSingularFieldEndpoint, into context: OriginalSingularFieldContext,
            transport: inout OriginalSingularFieldTransport, usage: inout B) throws -> OriginalSingularFieldElement {
            switch source {
            case .authored(let value): return try .constant(value, in: context, maximumDepth: maximumDepth, usage: &usage)
            case .algebraic(let root):
                let value = try root.value(maximumDepth: maximumDepth, usage: &usage)
                let target = try transport.importing(value.context, into: context, maximumDepth: maximumDepth, usage: &usage)
                return try transport.applying(to: value,
                    in: target, maximumDepth: maximumDepth, usage: &usage)
            }
        }
        var comparisonTransport = OriginalSingularFieldTransport()
        let lower = try endpoint(projection.stations[sector.lowerStation].endpoint,
            into: value.context, transport: &comparisonTransport, usage: &usage)
        let upper = try endpoint(projection.stations[sector.upperStation].endpoint,
            into: lower.context, transport: &comparisonTransport, usage: &usage)
        let selected = try value.embedded(in: upper.context, maximumDepth: maximumDepth, usage: &usage)
        guard case .positive = try selected.subtracting(lower.embedded(in: upper.context, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage),
            case .negative = try selected.subtracting(upper, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) else { return false }
        return true
    }
}
