import CADCore

/// Complete closed regular tubes over a supplied event-free original strip interval.
package struct OriginalFieldRegularStripCover: Sendable {
    package struct Piece: Sendable {
        package let lower: ExactRationalCoefficient
        package let upper: ExactRationalCoefficient
        package let domain: SurfaceParameterBox
        package let originalMidpointFiber: OriginalSingularFieldRoot
        package let sourceDepth: Int
    }
    private struct Pending: Sendable {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let depth: Int
    }
    package let projection: OriginalSingularFieldPlaneProjection
    package let sectorIndex: Int
    package let branchOrdinal: Int
    package let pieces: [Piece]

    package init<B: RationalAlgebraAdmitting>(projection: OriginalSingularFieldPlaneProjection,
        sectorIndex: Int, branchOrdinal: Int, lower: ExactRationalCoefficient,
        upper: ExactRationalCoefficient, inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws {
        guard sectorIndex >= 0, sectorIndex < projection.sectors.count,
            try upper.subtracting(lower, usage: &usage).isPositive,
            inheritedDepth >= 0, inheritedDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original field strip requires positive original bounds and admitted depth.")
        }
        let sector = projection.sectors[sectorIndex]
        guard branchOrdinal >= 0, branchOrdinal < sector.fiberRoots.count else {
            throw rationalAlgebraFailure("Original field strip ordinal is outside its complete real fiber.")
        }
        var low = projection.stations[sector.lowerStation].endpoint
        var high = projection.stations[sector.upperStation].endpoint
        var first = OriginalSingularFieldEndpoint.authored(lower), second = OriginalSingularFieldEndpoint.authored(upper)
        guard try OriginalSingularFieldEndpoint.compare(&low, &first, maximumDepth: maximumDepth, usage: &usage) < 0,
            try OriginalSingularFieldEndpoint.compare(&second, &high, maximumDepth: maximumDepth, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original field strip crosses a retained projection event.")
        }
        let depth = max(inheritedDepth, max(low.depth, high.depth))
        try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
        var pending = [Pending(lower: lower, upper: upper, depth: depth)]
        var retained: [Piece] = []
        while let cell = pending.popLast() {
            try usage.visitExactCell(depth: cell.depth)
            let midpoint = try cell.lower.adding(cell.upper, usage: &usage)
                .divided(by: .natural(2, usage: &usage), usage: &usage)
            let fiber = try OriginalSingularFieldPlaneProjection.restricted(projection.primitive,
                alongU: true, station: midpoint, maximumDepth: maximumDepth, usage: &usage)
            let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(fiber,
                lower: .originalDouble(projection.domain.v.lower, usage: &usage),
                upper: .originalDouble(projection.domain.v.upper, usage: &usage),
                inheritedDepth: cell.depth, maximumDepth: maximumDepth, usage: &usage)
            guard roots.count == sector.fiberRoots.count else {
                throw rationalAlgebraFailure("Original field strip lost its complete root ordinal coverage.")
            }
            let a = try cell.lower.outwardInterval(usage: &usage), b = try cell.upper.outwardInterval(usage: &usage)
            let u = try ScalarInterval(lower: max(projection.domain.u.lower, a.lower),
                upper: min(projection.domain.u.upper, b.upper))
            var rawLow = OriginalSingularFieldEndpoint.authored(try .originalDouble(u.lower, usage: &usage))
            var rawHigh = OriginalSingularFieldEndpoint.authored(try .originalDouble(u.upper, usage: &usage))
            guard try OriginalSingularFieldEndpoint.compare(&low, &rawLow, maximumDepth: maximumDepth, usage: &usage) < 0,
                try OriginalSingularFieldEndpoint.compare(&rawHigh, &high, maximumDepth: maximumDepth, usage: &usage) < 0 else {
                throw rationalAlgebraFailure("Original field strip has no outward binary box separated from its events.")
            }
            let radius = u.width.squareRoot()
            guard radius.isFinite, radius > 0 else { throw rationalAlgebraFailure("Original field strip has no positive finite tube radius.") }
            let requestedWidth = try ExactRationalCoefficient.originalDouble(radius, usage: &usage)
                .divided(by: .natural(4, usage: &usage), usage: &usage)
            let selected = try roots[branchOrdinal].refined(maximumWidth: requestedWidth,
                maximumDepth: maximumDepth, usage: &usage)
            let lowerBound = try selected.isolation.lower.outwardInterval(usage: &usage)
            let upperBound = try selected.isolation.upper.outwardInterval(usage: &usage)
            let lowerEdge = max(projection.domain.v.lower, (lowerBound.lower - radius).nextDown)
            let upperEdge = min(projection.domain.v.upper, (upperBound.upper + radius).nextUp)
            let v = try ScalarInterval(lower: lowerEdge, upper: upperEdge)
            let tube = SurfaceParameterBox(u: u, v: v)
            let sourceDepth = max(cell.depth, selected.isolation.depth)
            let derivative = try projection.primitive.partial(over: tube, uOrder: 0, vOrder: 1,
                maximumCoefficientWidth: requestedWidth, inheritedDepth: sourceDepth,
                maximumDepth: maximumDepth, usage: &usage)
            let lowerValue = try projection.primitive.partial(over: .init(u: u,
                v: ScalarInterval(lower: lowerEdge, upper: lowerEdge)), uOrder: 0, vOrder: 0,
                maximumCoefficientWidth: requestedWidth, inheritedDepth: sourceDepth,
                maximumDepth: maximumDepth, usage: &usage)
            let upperValue = try projection.primitive.partial(over: .init(u: u,
                v: ScalarInterval(lower: upperEdge, upper: upperEdge)), uOrder: 0, vOrder: 0,
                maximumCoefficientWidth: requestedWidth, inheritedDepth: sourceDepth,
                maximumDepth: maximumDepth, usage: &usage)
            if derivative.excludesZero,
                (lowerValue.upper < 0 && upperValue.lower > 0 || lowerValue.lower > 0 && upperValue.upper < 0) {
                try RationalAlgebraStorage.retain(1, of: Piece.self, usage: &usage)
                retained.append(Piece(lower: cell.lower, upper: cell.upper, domain: tube,
                    originalMidpointFiber: selected, sourceDepth: sourceDepth))
                continue
            }
            guard sourceDepth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original field strip tube exhausted inherited caller depth.")
            }
            let next = try rationalAlgebraCount(sourceDepth, 1)
            try RationalAlgebraStorage.retain(2, of: Pending.self, usage: &usage)
            pending.append(Pending(lower: midpoint, upper: cell.upper, depth: next))
            pending.append(Pending(lower: cell.lower, upper: midpoint, depth: next))
        }
        self.projection = projection; self.sectorIndex = sectorIndex
        self.branchOrdinal = branchOrdinal; pieces = retained
    }
}
