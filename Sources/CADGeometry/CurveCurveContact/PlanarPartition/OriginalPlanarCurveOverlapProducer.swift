import CADCore

/// Binds retained original atlas strips to complete merged source segments.
struct OriginalPlanarCurveOverlapProducer {
    private struct Knot { let first: Int; let second: Int }

    func produce(partition: OriginalPlanarCurveContactPartition,
        first: OriginalPlanarCurveMergedPartition, second: OriginalPlanarCurveMergedPartition,
        budget: inout NativeCurveCurveContactBudget) throws -> [OriginalPlanarCurveMonotoneOverlap] {
        for source in [partition.first, partition.second, first.source, second.source] {
            try GeometryStructuralComparisonWork.charge(curve: .bSpline(source), using: { try budget.work($0) })
        }
        guard first.source == partition.first, second.source == partition.second,
            first.parameters == partition.firstParameters, second.parameters == partition.secondParameters,
            first.tolerance == budget.tolerance, second.tolerance == budget.tolerance,
            partition.tolerance == budget.tolerance else {
            throw GeometryConversionError.invalidInput("Directional overlaps require the same original sources, full trims and tolerance as the pair receipt.")
        }
        let maximumDepth = budget.maximumDepth
        for cut in partition.firstCuts {
            _ = try match(coordinate(cut.endpoint, budget: &budget), owner: cut.nativeSpanIndex,
                cuts: first.cuts, budget: &budget)
        }
        for cut in partition.secondCuts {
            _ = try match(coordinate(cut.endpoint, budget: &budget), owner: cut.nativeSpanIndex,
                cuts: second.cuts, budget: &budget)
        }
        var result: [OriginalPlanarCurveMonotoneOverlap] = []
        for overlap in partition.overlaps {
            guard let firstOwner = overlap.firstSpan.nativeSpanIndex, let secondOwner = overlap.secondSpan.nativeSpanIndex else {
                throw budget.exhausted()
            }
            if try constant(partition.first, owner: firstOwner, budget: &budget)
                || constant(partition.second, owner: secondOwner, budget: &budget) { continue }
            guard let atlas = overlap.originalAtlas else {
                throw GeometryConversionError.invalidInput("A nonconstant original overlap lacks its complete retained regular/singular atlas.")
            }
            try RationalAlgebraStorage.retain(first.cuts.count, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
            try RationalAlgebraStorage.retain(second.cuts.count, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
            var uCuts: [ExactMonotoneGraphEndpoint] = [], vCuts: [ExactMonotoneGraphEndpoint] = []
            for cut in first.cuts where cut.nativeSpanIndex == firstOwner { uCuts.append(try coordinate(cut.endpoint, budget: &budget)) }
            for cut in second.cuts where cut.nativeSpanIndex == secondOwner { vCuts.append(try coordinate(cut.endpoint, budget: &budget)) }
            let sliced = try OriginalRationalStripCoordinateCuts(retaining: atlas, uCuts: uCuts,
                vCuts: vCuts, maximumDepth: maximumDepth, usage: &budget)
            for (stripIndex, strip) in atlas.strips.enumerated() {
                var knots: [Knot] = []
                for incidenceIndex in [strip.lowerIncidenceIndex, strip.upperIncidenceIndex] {
                    let station = atlas.stations[atlas.incidences[incidenceIndex].stationIndex].originalRoot
                    let u = try station.originalCoordinate(alongU: true, maximumDepth: maximumDepth, usage: &budget)
                    let v = try station.originalCoordinate(alongU: false, maximumDepth: maximumDepth, usage: &budget)
                    try RationalAlgebraStorage.retain(1, of: Knot.self, usage: &budget)
                    knots.append(try .init(first: match(u, owner: firstOwner, cuts: first.cuts, budget: &budget),
                        second: match(v, owner: secondOwner, cuts: second.cuts, budget: &budget)))
                }
                for point in sliced.points where point.stripIndex == stripIndex {
                    try RationalAlgebraStorage.retain(1, of: Knot.self, usage: &budget)
                    knots.append(try .init(first: match(point.originalU, owner: firstOwner, cuts: first.cuts, budget: &budget),
                        second: match(point.originalV, owner: secondOwner, cuts: second.cuts, budget: &budget)))
                }
                try RationalAlgebraStorage.retain(knots.count, of: Knot.self, usage: &budget)
                var ordered: [Knot] = []
                for knot in knots {
                    var insertion = ordered.count, duplicate = false
                    for index in ordered.indices {
                        try budget.work(1)
                        if ordered[index].first == knot.first {
                            guard ordered[index].second == knot.second else { throw budget.exhausted() }
                            duplicate = true; break
                        }
                        if ordered[index].first > knot.first { insertion = index; break }
                    }
                    if !duplicate { ordered.insert(knot, at: insertion) }
                }
                guard ordered.count > 1 else { throw budget.exhausted() }
                for index in 0..<(ordered.count - 1) {
                    let a = ordered[index], b = ordered[index + 1]
                    guard a.second != b.second else {
                        throw GeometryConversionError.invalidInput("A directional overlap has a constant native parameter without an original constant-owner proof.")
                    }
                    let direction = a.second < b.second ? 1 : -1
                    let firstIndex = try segment(lower: a.first, upper: b.first, in: first, budget: &budget)
                    let secondIndex = try segment(lower: min(a.second, b.second), upper: max(a.second, b.second),
                        in: second, budget: &budget)
                    var lower = try coordinate(first.cuts[a.first].endpoint, budget: &budget)
                    var upper = try coordinate(first.cuts[b.first].endpoint, budget: &budget)
                    let witness = try ExactOrderedRealEndpoints.between(&lower, &upper, maximumDepth: maximumDepth, usage: &budget)
                    let projection = atlas.projection
                    let fiber = try projection.primitive.restricted(alongU: true, station: witness, usage: &budget)
                    let roots = try OriginalRationalPlaneCurveProjection.sliceRoots(fiber,
                        lower: .originalDouble(projection.domain.v.lower, usage: &budget),
                        upper: .originalDouble(projection.domain.v.upper, usage: &budget),
                        parentDepth: max(lower.depth, upper.depth), maximumDepth: maximumDepth, usage: &budget)
                    guard roots.count == projection.sectors[strip.sectorIndex].fiberRoots.count,
                        strip.branchOrdinal < roots.count else { throw budget.exhausted() }
                    let selected = roots[strip.branchOrdinal]
                    let du = try projection.primitive.differentiated(alongU: true, usage: &budget)
                        .restricted(alongU: true, station: witness, usage: &budget)
                    let dv = try projection.primitive.differentiated(alongU: false, usage: &budget)
                        .restricted(alongU: true, station: witness, usage: &budget)
                    let uSign = try selected.sign(of: du, maximumDepth: maximumDepth, usage: &budget)
                    let vSign = try selected.sign(of: dv, maximumDepth: maximumDepth, usage: &budget)
                    let derivativeDirection: Int
                    switch (uSign, vSign) {
                    case (.positive, .positive), (.negative, .negative): derivativeDirection = -1
                    case (.positive, .negative), (.negative, .positive): derivativeDirection = 1
                    default: throw budget.exhausted()
                    }
                    guard derivativeDirection == direction else { throw budget.exhausted() }
                    // The retained first-axis atlas excludes Fv events; all
                    // opposite-axis critical point cuts were required above.
                    // Hence no Fu zero or branch change lies in this piece.
                    var duplicate = false
                    for existing in result {
                        try budget.work(1)
                        if existing.firstSegmentIndex == firstIndex, existing.secondSegmentIndex == secondIndex {
                            guard existing.direction == direction else { throw budget.exhausted() }
                            duplicate = true; break
                        }
                    }
                    if !duplicate {
                        try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveMonotoneOverlap.self, usage: &budget)
                        result.append(.init(firstSegmentIndex: firstIndex, secondSegmentIndex: secondIndex,
                            direction: direction, firstSpan: first.segments[firstIndex].originalSpan,
                            secondSpan: second.segments[secondIndex].originalSpan))
                    }
                }
            }
        }
        return result
    }

    private func constant(_ source: BSplineCurve3D, owner: Int, budget: inout NativeCurveCurveContactBudget) throws -> Bool {
        let original = try OriginalRationalCurvePolynomial(source: source, spanIndex: owner,
            tolerance: budget.tolerance, usage: &budget)
        let law = try OriginalRationalCurveDerivativeLaw(original: original, throughOrder: 1, usage: &budget)
        try budget.work(3)
        return law.numerators[1].allSatisfy { $0.isZero }
    }

    private func coordinate(_ endpoint: OriginalCurveRootEndpoint, budget: inout NativeCurveCurveContactBudget) throws -> ExactMonotoneGraphEndpoint {
        switch endpoint {
        case .authored(let value): return try .authored(.originalDouble(value, usage: &budget))
        case .algebraic(let root): return root.retainedRootEndpoint
        }
    }

    private func match(_ point: ExactMonotoneGraphEndpoint, owner: Int,
        cuts: [OriginalPlanarCurveMergedCut], budget: inout NativeCurveCurveContactBudget) throws -> Int {
        for index in cuts.indices where cuts[index].nativeSpanIndex == owner {
            try budget.work(1)
            var candidate = try coordinate(cuts[index].endpoint, budget: &budget), original = point
            if try ExactOrderedRealEndpoints.compare(&candidate, &original, maximumDepth: budget.maximumDepth, usage: &budget) == 0 { return index }
        }
        throw GeometryConversionError.invalidInput("Merged source cuts do not retain every original contact or native chart event.")
    }

    private func match(_ point: OriginalSingularFieldElement, owner: Int,
        cuts: [OriginalPlanarCurveMergedCut], budget: inout NativeCurveCurveContactBudget) throws -> Int {
        let transport = OriginalSingularFieldTransport()
        for index in cuts.indices where cuts[index].nativeSpanIndex == owner {
            try budget.work(1)
            let original = try coordinate(cuts[index].endpoint, budget: &budget)
            let candidate = try transport.originalScalarValue(original, into: point.context,
                maximumDepth: budget.maximumDepth, usage: &budget)
            let retained = try point.embedded(in: candidate.context, maximumDepth: budget.maximumDepth, usage: &budget)
            if case .zero = try retained.subtracting(candidate, maximumDepth: budget.maximumDepth,
                usage: &budget).sign(maximumDepth: budget.maximumDepth, usage: &budget) { return index }
        }
        throw GeometryConversionError.invalidInput("Original overlap correspondence requires propagation of an additional exact cut to the other source.")
    }

    private func segment(lower: Int, upper: Int, in source: OriginalPlanarCurveMergedPartition,
        budget: inout NativeCurveCurveContactBudget) throws -> Int {
        for index in source.segments.indices {
            try budget.work(1)
            if source.segments[index].lowerCutIndex == lower, source.segments[index].upperCutIndex == upper { return index }
        }
        throw GeometryConversionError.invalidInput("Original overlap knots are not consecutive complete merged source cuts.")
    }
}
