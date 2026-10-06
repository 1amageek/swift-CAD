import CADCore

/// Exhaustive limiting fibers of every original ordered regular strip branch.
package struct OriginalRationalPlaneCurveIncidence: Sendable {
    package enum Side: Equatable, Sendable { case lowerStation, upperStation }
    package struct HalfBranch: Sendable {
        package let sectorIndex: Int
        package let branchOrdinal: Int
        package let stationIndex: Int
        /// Rank in the exact ordered station fiber, not an offset into the unsorted producer array.
        package let stationRootOrdinal: Int
        package let side: Side
        package let originalStationRoot: ExactBivariateSystemRoot
        package let safeFreeStation: ExactRationalCoefficient
        package let originalSafeFiber: ExactAlgebraicRealRoot
    }
    package let projection: OriginalRationalPlaneCurveProjection
    package let halfBranches: [HalfBranch]

    package init<B: RationalAlgebraAdmitting>(projection: OriginalRationalPlaneCurveProjection,
        maximumDepth: Int, usage: inout B) throws {
        self.projection = projection
        var published: [HalfBranch] = []
        let v0 = try ExactRationalCoefficient.originalDouble(projection.domain.v.lower, usage: &usage)
        let v1 = try ExactRationalCoefficient.originalDouble(projection.domain.v.upper, usage: &usage)
        for (sectorIndex, sector) in projection.sectors.enumerated() where !sector.fiberRoots.isEmpty {
            for side in [Side.lowerStation, .upperStation] {
                let index = side == .lowerStation ? sector.lowerStation : sector.upperStation
                let station = projection.stations[index]
                var roots = try Self.ordered(station.roots, maximumDepth: maximumDepth, usage: &usage)
                guard !roots.isEmpty else { throw rationalAlgebraFailure("Original bounded strip branch has no limiting station fiber.") }
                var cuts = [v0]
                try usage.retainExactStorage(roots.count + 1)
                if roots.count > 1 { for i in 0..<(roots.count - 1) {
                    let gap = try roots[i + 1].fiberRoot.lower.subtracting(roots[i].fiberRoot.upper, usage: &usage)
                    guard gap.isPositive else { throw rationalAlgebraFailure("Original limiting station fibers have no separated cut.") }
                    cuts.append(try roots[i].fiberRoot.upper.adding(roots[i + 1].fiberRoot.lower, usage: &usage)
                        .divided(by: .natural(2, usage: &usage), usage: &usage))
                } }
                cuts.append(v1)
                var causalDepth = max(projection.sourceDepth, station.endpoint.depth)
                for root in roots { causalDepth = max(causalDepth, root.fiberRoot.isolationDepth) }
                var endpoint = station.endpoint, threshold = ExactMonotoneGraphEndpoint.authored(sector.originalFreeStation)
                for cut in cuts.dropFirst().dropLast() {
                    let crossing = try projection.primitive.restricted(alongU: false, station: cut, usage: &usage)
                    guard !crossing.isZero else { throw rationalAlgebraFailure("Original transverse cut is itself an entire source component.") }
                    if case .zero = try endpoint.sign(of: crossing, maximumDepth: maximumDepth, usage: &usage) {
                        throw rationalAlgebraFailure("Original station cut intersects a retained station fiber.")
                    }
                    let candidates = try OriginalRationalPlaneCurveProjection.sliceRoots(crossing,
                        lower: .originalDouble(projection.domain.u.lower, usage: &usage),
                        upper: .originalDouble(projection.domain.u.upper, usage: &usage),
                        parentDepth: causalDepth, maximumDepth: maximumDepth, usage: &usage)
                    for var event in candidates {
                        let eventFromStation = try ExactOrderedRealEndpoints.compare(&event, &endpoint,
                            maximumDepth: maximumDepth, usage: &usage)
                        if side == .lowerStation {
                            if eventFromStation <= 0 { continue }
                            if try ExactOrderedRealEndpoints.compare(&event, &threshold,
                                maximumDepth: maximumDepth, usage: &usage) < 0 { threshold = event }
                        } else {
                            if eventFromStation >= 0 { continue }
                            if try ExactOrderedRealEndpoints.compare(&event, &threshold,
                                maximumDepth: maximumDepth, usage: &usage) > 0 { threshold = event }
                        }
                    }
                }
                let witness: ExactRationalCoefficient
                if side == .lowerStation {
                    witness = try ExactOrderedRealEndpoints.between(&endpoint, &threshold,
                        maximumDepth: maximumDepth, usage: &usage)
                } else {
                    witness = try ExactOrderedRealEndpoints.between(&threshold, &endpoint,
                        maximumDepth: maximumDepth, usage: &usage)
                }
                causalDepth = max(causalDepth, max(endpoint.depth, threshold.depth))
                let fiber = try projection.primitive.restricted(alongU: true, station: witness, usage: &usage)
                let near = try OriginalRationalPlaneCurveProjection.sliceRoots(fiber, lower: v0, upper: v1,
                    parentDepth: causalDepth, maximumDepth: maximumDepth, usage: &usage)
                guard near.count == sector.fiberRoots.count else {
                    throw rationalAlgebraFailure("Original strip root count changed without a projection event.")
                }
                let coordinate = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                for (ordinal, value) in near.enumerated() {
                    guard case .algebraic(let root) = value else { throw rationalAlgebraFailure("Original safe fiber lost its algebraic authority.") }
                    var selected: Int?
                    for i in roots.indices {
                        let low = try coordinate.subtracting(.constant(cuts[i], usage: &usage), usage: &usage)
                        let high = try coordinate.subtracting(.constant(cuts[i + 1], usage: &usage), usage: &usage)
                        if case .positive = try root.sign(of: low, maximumDepth: maximumDepth, usage: &usage),
                           case .negative = try root.sign(of: high, maximumDepth: maximumDepth, usage: &usage) {
                            guard selected == nil else { throw rationalAlgebraFailure("Original branch is in two limiting fiber neighborhoods.") }
                            selected = i
                        }
                    }
                    guard let selected else { throw rationalAlgebraFailure("Original safe branch has no retained limiting station fiber.") }
                    let depth = max(root.isolation.isolationDepth, roots[selected].fiberRoot.isolationDepth)
                    roots[selected] = try roots[selected].retainingDepth(depth, usage: &usage)
                    try usage.retainExactStorage(1)
                    published.append(HalfBranch(sectorIndex: sectorIndex, branchOrdinal: ordinal,
                        stationIndex: index, stationRootOrdinal: selected, side: side,
                        originalStationRoot: roots[selected], safeFreeStation: witness, originalSafeFiber: root))
                }
            }
        }
        halfBranches = published
    }

    private static func ordered<B: RationalAlgebraAdmitting>(_ input: [ExactBivariateSystemRoot],
        maximumDepth: Int, usage: inout B) throws -> [ExactBivariateSystemRoot] {
        try usage.retainExactStorage(input.count)
        var values: [ExactBivariateSystemRoot] = []
        for var root in input {
            var index = values.count
            for i in values.indices {
                var retained = values[i]
                while true {
                    if try root.fiberRoot.lower.subtracting(retained.fiberRoot.upper, usage: &usage).isPositive { break }
                    if try retained.fiberRoot.lower.subtracting(root.fiberRoot.upper, usage: &usage).isPositive { index = i; break }
                    root = try refine(root, maximumDepth: maximumDepth, usage: &usage)
                    retained = try refine(retained, maximumDepth: maximumDepth, usage: &usage)
                }
                values[i] = retained
                if index == i { break }
            }
            values.insert(root, at: index)
        }
        return values
    }

    private static func refine<B: RationalAlgebraAdmitting>(_ root: ExactBivariateSystemRoot,
        maximumDepth: Int, usage: inout B) throws -> ExactBivariateSystemRoot {
        let width = try root.fiberRoot.upper.subtracting(root.fiberRoot.lower, usage: &usage)
        if width.isZero { return root }
        let uWidth = try root.projectionRoot.isolation.upper.subtracting(root.projectionRoot.isolation.lower, usage: &usage)
        return try root.refined(maximumUWidth: uWidth.isZero ? .one : uWidth,
            maximumVWidth: width.divided(by: .natural(2, usage: &usage), usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }
}
