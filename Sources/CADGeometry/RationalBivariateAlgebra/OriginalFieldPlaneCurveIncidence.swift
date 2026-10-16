import CADCore

/// Exhaustive limiting fibers of every original ordered regular strip branch.
package struct OriginalFieldPlaneCurveIncidence: Sendable {
    package enum Side: Equatable, Sendable { case lowerStation, upperStation }
    package struct HalfBranch: Sendable {
        package let sectorIndex: Int
        package let branchOrdinal: Int
        package let stationIndex: Int
        /// Rank in the exact ordered station fiber, not an offset into the unsorted producer array.
        package let stationRootOrdinal: Int
        package let side: Side
        package let originalStationRoot: OriginalSingularFieldSystemRoot
        package let safeFreeStation: ExactRationalCoefficient
        package let originalSafeFiber: OriginalSingularFieldRoot
        package let sourceDepth: Int
    }
    package let projection: OriginalSingularFieldPlaneProjection
    package let halfBranches: [HalfBranch]

    package init<B: ExactScalarAdmission & ~Copyable>(projection: OriginalSingularFieldPlaneProjection,
        maximumDepth: Int, usage: inout B) throws {
        self.projection = projection
        var published: [HalfBranch] = []
        let v0 = try ExactRationalCoefficient.originalDouble(projection.domain.v.lower, usage: &usage)
        let v1 = try ExactRationalCoefficient.originalDouble(projection.domain.v.upper, usage: &usage)
        for (sectorIndex, sector) in projection.sectors.enumerated() where !sector.fiberRoots.isEmpty {
            for sideIndex in 0..<2 {
                let side = sideIndex == 0 ? Side.lowerStation : .upperStation
                let index = side == .lowerStation ? sector.lowerStation : sector.upperStation
                let station = projection.stations[index]
                var roots = try Self.ordered(station.roots, maximumDepth: maximumDepth, usage: &usage)
                guard !roots.isEmpty else { throw rationalAlgebraFailure("Original bounded strip branch has no limiting station fiber.") }
                try RationalAlgebraStorage.retain(rationalAlgebraCount(roots.count, 1), of: ExactRationalCoefficient.self, usage: &usage)
                var cuts = [v0]; cuts.reserveCapacity(roots.count + 1)
                if roots.count > 1 { for i in 0..<(roots.count - 1) {
                    let gap = try roots[i + 1].fiberRoot.isolation.lower.subtracting(roots[i].fiberRoot.isolation.upper, usage: &usage)
                    guard gap.isPositive else { throw rationalAlgebraFailure("Original limiting station fibers have no separated cut.") }
                    cuts.append(try roots[i].fiberRoot.isolation.upper.adding(roots[i + 1].fiberRoot.isolation.lower, usage: &usage)
                        .divided(by: .natural(2, usage: &usage), usage: &usage))
                } }
                cuts.append(v1)
                var causalDepth = max(projection.sourceDepth, station.endpoint.depth)
                for root in roots { causalDepth = max(causalDepth, root.fiberRoot.isolation.depth) }
                var endpoint = station.endpoint, threshold = OriginalSingularFieldEndpoint.authored(sector.originalFreeStation)
                for cut in cuts.dropFirst().dropLast() {
                    let crossing = try OriginalSingularFieldPlaneProjection.restricted(projection.primitive, alongU: false, station: cut, maximumDepth: maximumDepth, usage: &usage)
                    guard !crossing.isZero else { throw rationalAlgebraFailure("Original transverse cut is itself an entire source component.") }
                    if case .zero = try endpoint.sign(of: crossing, maximumDepth: maximumDepth, usage: &usage) {
                        throw rationalAlgebraFailure("Original station cut intersects a retained station fiber.")
                    }
                    let candidates = try OriginalSingularFieldPlaneProjection.sliceRoots(crossing,
                        lower: .originalDouble(projection.domain.u.lower, usage: &usage),
                        upper: .originalDouble(projection.domain.u.upper, usage: &usage),
                        inheritedDepth: causalDepth, maximumDepth: maximumDepth, usage: &usage)
                    for candidate in candidates {
                        var event = OriginalSingularFieldEndpoint.algebraic(candidate)
                        let eventFromStation = try OriginalSingularFieldEndpoint.compare(&event, &endpoint,
                            maximumDepth: maximumDepth, usage: &usage)
                        if side == .lowerStation {
                            if eventFromStation <= 0 { continue }
                            if try OriginalSingularFieldEndpoint.compare(&event, &threshold,
                                maximumDepth: maximumDepth, usage: &usage) < 0 { threshold = event }
                        } else {
                            if eventFromStation >= 0 { continue }
                            if try OriginalSingularFieldEndpoint.compare(&event, &threshold,
                                maximumDepth: maximumDepth, usage: &usage) > 0 { threshold = event }
                        }
                    }
                }
                let witness: ExactRationalCoefficient
                if side == .lowerStation {
                    witness = try OriginalSingularFieldEndpoint.between(&endpoint, &threshold,
                        maximumDepth: maximumDepth, usage: &usage)
                } else {
                    witness = try OriginalSingularFieldEndpoint.between(&threshold, &endpoint,
                        maximumDepth: maximumDepth, usage: &usage)
                }
                causalDepth = max(causalDepth, max(endpoint.depth, threshold.depth))
                let fiber = try OriginalSingularFieldPlaneProjection.restricted(projection.primitive, alongU: true, station: witness, maximumDepth: maximumDepth, usage: &usage)
                let near = try OriginalSingularFieldPlaneProjection.sliceRoots(fiber, lower: v0, upper: v1,
                    inheritedDepth: causalDepth, maximumDepth: maximumDepth, usage: &usage)
                guard near.count == sector.fiberRoots.count else {
                    throw rationalAlgebraFailure("Original strip root count changed without a projection event.")
                }
                for (ordinal, root) in near.enumerated() {
                    var selected: Int?
                    for i in roots.indices {
                        var endpoint = OriginalSingularFieldEndpoint.algebraic(root)
                        var lowerCut = OriginalSingularFieldEndpoint.authored(cuts[i])
                        var upperCut = OriginalSingularFieldEndpoint.authored(cuts[i + 1])
                        if try OriginalSingularFieldEndpoint.compare(&endpoint, &lowerCut, maximumDepth: maximumDepth, usage: &usage) > 0,
                           try OriginalSingularFieldEndpoint.compare(&endpoint, &upperCut, maximumDepth: maximumDepth, usage: &usage) < 0 {
                            guard selected == nil else { throw rationalAlgebraFailure("Original branch is in two limiting fiber neighborhoods.") }
                            selected = i
                        }
                    }
                    guard let selected else { throw rationalAlgebraFailure("Original safe branch has no retained limiting station fiber.") }
                    let depth = max(root.isolation.depth, roots[selected].fiberRoot.isolation.depth)
                    try RationalAlgebraStorage.retain(1, of: HalfBranch.self, usage: &usage)
                    published.append(HalfBranch(sectorIndex: sectorIndex, branchOrdinal: ordinal,
                        stationIndex: index, stationRootOrdinal: selected, side: side,
                        originalStationRoot: roots[selected], safeFreeStation: witness, originalSafeFiber: root, sourceDepth: depth))
                }
            }
        }
        halfBranches = published
    }

    private static func ordered<B: ExactScalarAdmission & ~Copyable>(_ input: [OriginalSingularFieldSystemRoot],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldSystemRoot] {
        try RationalAlgebraStorage.retain(input.count, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
        var values: [OriginalSingularFieldSystemRoot] = []
        for var root in input {
            var index = values.count
            for i in values.indices {
                var retained = values[i]
                while true {
                    if try root.fiberRoot.isolation.lower.subtracting(retained.fiberRoot.isolation.upper, usage: &usage).isPositive { break }
                    if try retained.fiberRoot.isolation.lower.subtracting(root.fiberRoot.isolation.upper, usage: &usage).isPositive { index = i; break }
                    root = try refine(root, maximumDepth: maximumDepth, usage: &usage)
                    retained = try refine(retained, maximumDepth: maximumDepth, usage: &usage)
                }
                values[i] = retained
                if index == i { break }
            }
            try usage.consumeWork(values.count - index)
            values.insert(root, at: index)
        }
        return values
    }

    private static func refine<B: ExactScalarAdmission & ~Copyable>(_ root: OriginalSingularFieldSystemRoot,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldSystemRoot {
        let width = try root.fiberRoot.isolation.upper.subtracting(root.fiberRoot.isolation.lower, usage: &usage)
        if width.isZero { return root }
        let uWidth = try root.projectionRoot.isolation.upper.subtracting(root.projectionRoot.isolation.lower, usage: &usage)
        return try root.refined(maximumUWidth: uWidth.isZero ? .one : uWidth,
            maximumVWidth: width.divided(by: .natural(2, usage: &usage), usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }
}
