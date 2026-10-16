import CADCore

/// Complete original regular graph tubes between two retained singular attachments.
package struct OriginalRationalRegularStripCover: Sendable {
    package struct Piece: Sendable {
        package let lower: ExactRationalCoefficient
        package let upper: ExactRationalCoefficient
        package let domain: SurfaceParameterBox
        package let originalMidpointFiber: ExactAlgebraicRealRoot
        package let sourceDepth: Int
    }
    private struct Pending: Sendable {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let depth: Int
    }
    package let projection: OriginalRationalPlaneCurveProjection
    package let sectorIndex: Int
    package let branchOrdinal: Int
    package let pieces: [Piece]

    package init<B: ExactScalarAdmission & ~Copyable>(projection: OriginalRationalPlaneCurveProjection,
        sectorIndex: Int, branchOrdinal: Int, lower: ExactRationalCoefficient,
        upper: ExactRationalCoefficient, inheritedDepth: Int, maximumDepth: Int,
        usage: inout B) throws {
        guard sectorIndex >= 0, sectorIndex < projection.sectors.count,
            try upper.subtracting(lower, usage: &usage).isPositive,
            inheritedDepth >= 0, inheritedDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original regular strip needs positive source endpoints and inherited depth.")
        }
        let sector = projection.sectors[sectorIndex]
        guard branchOrdinal >= 0, branchOrdinal < sector.fiberRoots.count else {
            throw rationalAlgebraFailure("Original regular strip branch ordinal is outside its complete real fiber.")
        }
        var a = ExactMonotoneGraphEndpoint.authored(lower), b = ExactMonotoneGraphEndpoint.authored(upper)
        var lo = projection.stations[sector.lowerStation].endpoint
        var hi = projection.stations[sector.upperStation].endpoint
        guard try ExactOrderedRealEndpoints.compare(&lo, &a, maximumDepth: maximumDepth, usage: &usage) < 0,
            try ExactOrderedRealEndpoints.compare(&b, &hi, maximumDepth: maximumDepth, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original regular strip anchors meet or cross a retained projection event.")
        }
        let depth = max(inheritedDepth, max(lo.depth, hi.depth))
        let derivative = try projection.primitive.differentiated(alongU: false, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
        var pending = [Pending(lower: lower, upper: upper, depth: depth)]
        var retained: [Piece] = []
        while let cell = pending.popLast() {
            try usage.visitCell(axis: .value, depth: cell.depth)
            let midpoint = try cell.lower.adding(cell.upper, usage: &usage)
                .divided(by: .natural(2, usage: &usage), usage: &usage)
            let source = try projection.primitive.restricted(alongU: true, station: midpoint, usage: &usage)
            let roots = try OriginalRationalPlaneCurveProjection.sliceRoots(source,
                lower: .originalDouble(projection.domain.v.lower, usage: &usage),
                upper: .originalDouble(projection.domain.v.upper, usage: &usage),
                parentDepth: cell.depth, maximumDepth: maximumDepth, usage: &usage)
            guard roots.count == sector.fiberRoots.count, case .algebraic(let selected) = roots[branchOrdinal] else {
                throw rationalAlgebraFailure("Original regular strip lost its complete midpoint root count or ordinal.")
            }
            let low = try cell.lower.outwardInterval(usage: &usage)
            let high = try cell.upper.outwardInterval(usage: &usage)
            let u = try ScalarInterval(lower: max(projection.domain.u.lower, low.lower),
                upper: min(projection.domain.u.upper, high.upper))
            var rawLow = ExactMonotoneGraphEndpoint.authored(try .originalDouble(u.lower, usage: &usage))
            var rawHigh = ExactMonotoneGraphEndpoint.authored(try .originalDouble(u.upper, usage: &usage))
            guard try ExactOrderedRealEndpoints.compare(&lo, &rawLow, maximumDepth: maximumDepth, usage: &usage) < 0,
                try ExactOrderedRealEndpoints.compare(&rawHigh, &hi, maximumDepth: maximumDepth, usage: &usage) < 0 else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: nil,
                    message: "Original strip tube has no binary outward enclosure separated from its exact projection events.")
            }
            let radius = u.width.squareRoot()
            guard radius.isFinite, radius > 0 else { throw rationalAlgebraFailure("Original regular strip tube has no finite transverse candidate radius.") }
            let target = try ExactRationalCoefficient.originalDouble(radius, usage: &usage)
                .divided(by: .natural(4, usage: &usage), usage: &usage)
            let fiber = try selected.refined(maximumWidth: target, maximumDepth: maximumDepth, usage: &usage)
            let first = try fiber.isolation.lower.outwardInterval(usage: &usage)
            let second = try fiber.isolation.upper.outwardInterval(usage: &usage)
            let lowerEdge = max(projection.domain.v.lower, (first.lower - radius).nextDown)
            let upperEdge = min(projection.domain.v.upper, (second.upper + radius).nextUp)
            let v = try ScalarInterval(lower: lowerEdge, upper: upperEdge)
            let tube = SurfaceParameterBox(u: u, v: v)
            let gradient = try derivative.enclosure(over: tube, usage: &usage)
            let lowerValue = try projection.primitive.enclosure(over: .init(u: u,
                v: ScalarInterval(lower: lowerEdge, upper: lowerEdge)), usage: &usage)
            let upperValue = try projection.primitive.enclosure(over: .init(u: u,
                v: ScalarInterval(lower: upperEdge, upper: upperEdge)), usage: &usage)
            let sourceDepth = max(cell.depth, fiber.isolation.isolationDepth)
            if gradient.excludesZero,
                (lowerValue.upper < 0 && upperValue.lower > 0 || lowerValue.lower > 0 && upperValue.upper < 0) {
                try RationalAlgebraStorage.retain(1, of: Piece.self, usage: &usage)
                retained.append(Piece(lower: cell.lower, upper: cell.upper, domain: tube,
                    originalMidpointFiber: fiber, sourceDepth: sourceDepth))
                continue
            }
            guard sourceDepth < maximumDepth else { throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original regular strip tube cover exhausted causal caller depth.") }
            let nextDepth = try rationalAlgebraCount(sourceDepth, 1)
            try RationalAlgebraStorage.retain(2, of: Pending.self, usage: &usage)
            pending.append(Pending(lower: midpoint, upper: cell.upper, depth: nextDepth))
            pending.append(Pending(lower: cell.lower, upper: midpoint, depth: nextDepth))
        }
        self.projection = projection; self.sectorIndex = sectorIndex
        self.branchOrdinal = branchOrdinal; pieces = retained
    }
}
