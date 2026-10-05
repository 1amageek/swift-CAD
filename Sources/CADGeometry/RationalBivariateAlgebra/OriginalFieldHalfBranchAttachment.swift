import CADCore

/// Actual source strip incidence into exactly one retained ramified regular chart.
package struct OriginalFieldHalfBranchAttachment: Sendable {
    package let halfBranch: OriginalFieldPlaneCurveIncidence.HalfBranch
    package let chartIndex: Int
    package let originalFreeWitness: ExactRationalCoefficient
    package let originalFiber: OriginalSingularFieldRoot
    package let originalLocalPoint: OriginalSingularGermPoint
    package let approachDepth: Int

    package init<B: RationalAlgebraAdmitting>(halfBranch: OriginalFieldPlaneCurveIncidence.HalfBranch,
        projection: OriginalSingularFieldPlaneProjection, resolution: OriginalFieldSingularResolution,
        charts: [OriginalSingularRegularChart], maximumDepth: Int, usage: inout B) throws {
        guard resolution.original.context === projection.primitive.context,
            try resolution.original.subtracting(projection.primitive, maximumDepth: maximumDepth, usage: &usage).isZero,
            charts.count == resolution.germs.count,
            halfBranch.sectorIndex >= 0, halfBranch.sectorIndex < projection.sectors.count,
            halfBranch.stationIndex >= 0, halfBranch.stationIndex < projection.stations.count,
            try resolution.originalStation.hasSameValue(as: halfBranch.originalStationRoot,
                maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original half-branch attachment has a different source station or plane law.")
        }
        for index in charts.indices {
            guard charts[index].germ.strictTransform.context === resolution.germs[index].strictTransform.context else {
                throw rationalAlgebraFailure("Original half-branch chart order lost its retained resolution leaf.")
            }
        }
        let sector = projection.sectors[halfBranch.sectorIndex]
        guard halfBranch.branchOrdinal >= 0, halfBranch.branchOrdinal < sector.fiberRoots.count else {
            throw rationalAlgebraFailure("Original half-branch ordinal exceeds complete strip fiber coverage.")
        }
        var free = halfBranch.safeFreeStation
        var fiber = halfBranch.originalSafeFiber
        var event = projection.stations[halfBranch.stationIndex].endpoint
        var depth = max(halfBranch.sourceDepth, max(event.depth, fiber.isolation.depth))
        for chart in charts { depth = max(depth, chart.sourceDepth) }
        while true {
            try usage.visitExactCell(depth: depth)
            var selected: (Int, OriginalSingularGermPoint)?
            for index in charts.indices {
                if let point = try OriginalSingularGermPoint.proven(originalU: free, originalV: fiber,
                    in: charts[index].germ, maximumDepth: maximumDepth, usage: &usage),
                   try point.belongs(to: charts[index], strictly: true, maximumDepth: maximumDepth, usage: &usage) {
                    if case .some = selected { throw rationalAlgebraFailure("Original strip half-branch belongs to two ramified leaves.") }
                    selected = (index, point)
                }
            }
            if let selected {
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                self.halfBranch = halfBranch; chartIndex = selected.0
                originalFreeWitness = free; originalFiber = fiber; originalLocalPoint = selected.1
                approachDepth = depth; return
            }
            guard depth < maximumDepth else { throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original half-branch attachment exhausted causal caller depth.") }
            var threshold = OriginalSingularFieldEndpoint.authored(free)
            if halfBranch.side == .lowerStation {
                free = try OriginalSingularFieldEndpoint.between(&event, &threshold, maximumDepth: maximumDepth, usage: &usage)
            } else {
                free = try OriginalSingularFieldEndpoint.between(&threshold, &event, maximumDepth: maximumDepth, usage: &usage)
            }
            depth = max(try rationalAlgebraCount(depth, 1), event.depth)
            let slice = try OriginalSingularFieldPlaneProjection.restricted(projection.primitive, alongU: true, station: free, maximumDepth: maximumDepth, usage: &usage)
            let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(slice,
                lower: .originalDouble(projection.domain.v.lower, usage: &usage),
                upper: .originalDouble(projection.domain.v.upper, usage: &usage),
                inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
            guard roots.count == sector.fiberRoots.count else {
                throw rationalAlgebraFailure("Original singular approach lost complete strip root count or ordinal.")
            }
            let retained = roots[halfBranch.branchOrdinal]
            fiber = retained; depth = max(depth, retained.isolation.depth)
        }
    }
}
