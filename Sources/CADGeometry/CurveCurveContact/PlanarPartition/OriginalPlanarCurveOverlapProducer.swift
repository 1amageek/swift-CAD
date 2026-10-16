import CADCore

/// Binds retained original atlas strips to complete merged source segments.
struct OriginalPlanarCurveOverlapProducer {
  private struct Knot {
    let first: Int
    let second: Int
  }

  func produce(
    partition: OriginalPlanarCurveContactPartition,
    first: OriginalPlanarCurveMergedPartition,
    second: OriginalPlanarCurveMergedPartition,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [OriginalPlanarCurveMonotoneOverlap] {
    for source in [partition.first, partition.second, first.source, second.source] {
      try GeometryStructuralComparisonWork.charge(curve: .bSpline(source), using: &execution)
    }
    guard first.source == partition.first, second.source == partition.second,
      first.parameters == partition.firstParameters,
      second.parameters == partition.secondParameters,
      first.tolerance == tolerance, second.tolerance == tolerance,
      partition.tolerance == tolerance
    else {
      throw GeometryConversionError.invalidInput(
        "Directional overlaps require the same original sources, full trims and tolerance as the pair receipt."
      )
    }
    let maximumDepth = min(32, execution.effectiveLimits.maximumValueDepth)
    for cut in partition.firstCuts {
      _ = try match(
        coordinate(
          cut.endpoint,
          tolerance: tolerance,
          using: &execution),
        owner: cut.nativeSpanIndex,
        cuts: first.cuts,
        tolerance: tolerance,
        using: &execution)
    }
    for cut in partition.secondCuts {
      _ = try match(
        coordinate(
          cut.endpoint,
          tolerance: tolerance,
          using: &execution),
        owner: cut.nativeSpanIndex,
        cuts: second.cuts,
        tolerance: tolerance,
        using: &execution)
    }
    var result: [OriginalPlanarCurveMonotoneOverlap] = []
    for overlap in partition.overlaps {
      guard let firstOwner = overlap.firstSpan.nativeSpanIndex,
        let secondOwner = overlap.secondSpan.nativeSpanIndex
      else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      if try constant(
        partition.first,
        owner: firstOwner,
        tolerance: tolerance,
        using: &execution)
        || constant(
          partition.second,
          owner: secondOwner,
          tolerance: tolerance,
          using: &execution)
      {
        continue
      }
      guard let atlas = overlap.originalAtlas else {
        throw GeometryConversionError.invalidInput(
          "A nonconstant original overlap lacks its complete retained regular/singular atlas.")
      }
      try RationalAlgebraStorage.retain(
        first.cuts.count, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
      try RationalAlgebraStorage.retain(
        second.cuts.count, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
      var uCuts: [ExactMonotoneGraphEndpoint] = []
      var vCuts: [ExactMonotoneGraphEndpoint] = []
      for cut in first.cuts where cut.nativeSpanIndex == firstOwner {
        uCuts.append(
          try coordinate(
            cut.endpoint,
            tolerance: tolerance,
            using: &execution))
      }
      for cut in second.cuts where cut.nativeSpanIndex == secondOwner {
        vCuts.append(
          try coordinate(
            cut.endpoint,
            tolerance: tolerance,
            using: &execution))
      }
      let sliced = try OriginalRationalStripCoordinateCuts(
        retaining: atlas, uCuts: uCuts,
        vCuts: vCuts, maximumDepth: maximumDepth, usage: &execution)
      for (stripIndex, strip) in atlas.strips.enumerated() {
        var knots: [Knot] = []
        for incidenceIndex in [strip.lowerIncidenceIndex, strip.upperIncidenceIndex] {
          let station = atlas.stations[atlas.incidences[incidenceIndex].stationIndex].originalRoot
          let u = try station.originalCoordinate(
            alongU: true, maximumDepth: maximumDepth, usage: &execution)
          let v = try station.originalCoordinate(
            alongU: false, maximumDepth: maximumDepth, usage: &execution)
          try RationalAlgebraStorage.retain(1, of: Knot.self, usage: &execution)
          knots.append(
            try .init(
              first: match(
                u,
                owner: firstOwner,
                cuts: first.cuts,
                tolerance: tolerance,
                using: &execution),
              second: match(
                v,
                owner: secondOwner,
                cuts: second.cuts,
                tolerance: tolerance,
                using: &execution)))
        }
        for point in sliced.points where point.stripIndex == stripIndex {
          try RationalAlgebraStorage.retain(1, of: Knot.self, usage: &execution)
          knots.append(
            try .init(
              first: match(
                point.originalU,
                owner: firstOwner,
                cuts: first.cuts,
                tolerance: tolerance,
                using: &execution),
              second: match(
                point.originalV,
                owner: secondOwner,
                cuts: second.cuts,
                tolerance: tolerance,
                using: &execution)))
        }
        try RationalAlgebraStorage.retain(knots.count, of: Knot.self, usage: &execution)
        var ordered: [Knot] = []
        for knot in knots {
          var insertion = ordered.count
          var duplicate = false
          for index in ordered.indices {
            try execution.consumeWork(1)
            if ordered[index].first == knot.first {
              guard ordered[index].second == knot.second else {
                throw GeometryConversionError.resourceLimitExceeded(
                  "Original curve contact exhausted its local source or proof ceiling.")
              }
              duplicate = true
              break
            }
            if ordered[index].first > knot.first {
              insertion = index
              break
            }
          }
          if !duplicate { ordered.insert(knot, at: insertion) }
        }
        guard ordered.count > 1 else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        for index in 0..<(ordered.count - 1) {
          let a = ordered[index]
          let b = ordered[index + 1]
          guard a.second != b.second else {
            throw GeometryConversionError.invalidInput(
              "A directional overlap has a constant native parameter without an original constant-owner proof."
            )
          }
          let direction = a.second < b.second ? 1 : -1
          let firstIndex = try segment(
            lower: a.first,
            upper: b.first,
            in: first,
            tolerance: tolerance,
            using: &execution)
          let secondIndex = try segment(
            lower: min(a.second, b.second),
            upper: max(a.second, b.second),
            in: second,
            tolerance: tolerance,
            using: &execution)
          var lower = try coordinate(
            first.cuts[a.first].endpoint,
            tolerance: tolerance,
            using: &execution)
          var upper = try coordinate(
            first.cuts[b.first].endpoint,
            tolerance: tolerance,
            using: &execution)
          let witness = try ExactOrderedRealEndpoints.between(
            &lower, &upper, maximumDepth: maximumDepth, usage: &execution)
          let projection = atlas.projection
          let fiber = try projection.primitive.restricted(
            alongU: true, station: witness, usage: &execution)
          let roots = try OriginalRationalPlaneCurveProjection.sliceRoots(
            fiber,
            lower: .originalDouble(projection.domain.v.lower, usage: &execution),
            upper: .originalDouble(projection.domain.v.upper, usage: &execution),
            parentDepth: max(lower.depth, upper.depth), maximumDepth: maximumDepth,
            usage: &execution)
          guard roots.count == projection.sectors[strip.sectorIndex].fiberRoots.count,
            strip.branchOrdinal < roots.count
          else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          let selected = roots[strip.branchOrdinal]
          let du = try projection.primitive.differentiated(alongU: true, usage: &execution)
            .restricted(alongU: true, station: witness, usage: &execution)
          let dv = try projection.primitive.differentiated(alongU: false, usage: &execution)
            .restricted(alongU: true, station: witness, usage: &execution)
          let uSign = try selected.sign(of: du, maximumDepth: maximumDepth, usage: &execution)
          let vSign = try selected.sign(of: dv, maximumDepth: maximumDepth, usage: &execution)
          let derivativeDirection: Int
          switch (uSign, vSign) {
          case (.positive, .positive), (.negative, .negative): derivativeDirection = -1
          case (.positive, .negative), (.negative, .positive): derivativeDirection = 1
          default:
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          guard derivativeDirection == direction else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          // The retained first-axis atlas excludes Fv events; all
          // opposite-axis critical point cuts were required above.
          // Hence no Fu zero or branch change lies in this piece.
          var duplicate = false
          for existing in result {
            try execution.consumeWork(1)
            if existing.firstSegmentIndex == firstIndex, existing.secondSegmentIndex == secondIndex
            {
              guard existing.direction == direction else {
                throw GeometryConversionError.resourceLimitExceeded(
                  "Original curve contact exhausted its local source or proof ceiling.")
              }
              duplicate = true
              break
            }
          }
          if !duplicate {
            try RationalAlgebraStorage.retain(
              1, of: OriginalPlanarCurveMonotoneOverlap.self, usage: &execution)
            result.append(
              .init(
                firstSegmentIndex: firstIndex, secondSegmentIndex: secondIndex,
                direction: direction, firstSpan: first.segments[firstIndex].originalSpan,
                secondSpan: second.segments[secondIndex].originalSpan))
          }
        }
      }
    }
    return result
  }

  private func constant(
    _ source: BSplineCurve3D,
    owner: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let original = try OriginalRationalCurvePolynomial(
      source: source, spanIndex: owner,
      tolerance: tolerance, usage: &execution)
    let law = try OriginalRationalCurveDerivativeLaw(
      original: original, throughOrder: 1, usage: &execution)
    try execution.consumeWork(3)
    return law.numerators[1].allSatisfy { $0.isZero }
  }

  private func coordinate(
    _ endpoint: OriginalCurveRootEndpoint,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactMonotoneGraphEndpoint {
    switch endpoint {
    case .authored(let value): return try .authored(.originalDouble(value, usage: &execution))
    case .algebraic(let root): return root.retainedRootEndpoint
    }
  }

  private func match(
    _ point: ExactMonotoneGraphEndpoint,
    owner: Int,
    cuts: [OriginalPlanarCurveMergedCut],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Int {
    for index in cuts.indices where cuts[index].nativeSpanIndex == owner {
      try execution.consumeWork(1)
      var candidate = try coordinate(
        cuts[index].endpoint,
        tolerance: tolerance,
        using: &execution)
      var original = point
      if try ExactOrderedRealEndpoints.compare(
        &candidate, &original, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
        usage: &execution) == 0
      {
        return index
      }
    }
    throw GeometryConversionError.invalidInput(
      "Merged source cuts do not retain every original contact or native chart event.")
  }

  private func match(
    _ point: OriginalSingularFieldElement,
    owner: Int,
    cuts: [OriginalPlanarCurveMergedCut],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let transport = OriginalSingularFieldTransport()
    for index in cuts.indices where cuts[index].nativeSpanIndex == owner {
      try execution.consumeWork(1)
      let original = try coordinate(
        cuts[index].endpoint,
        tolerance: tolerance,
        using: &execution)
      let candidate = try transport.originalScalarValue(
        original, into: point.context,
        maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
      let retained = try point.embedded(
        in: candidate.context, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
        usage: &execution)
      if case .zero = try retained.subtracting(
        candidate, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
        usage: &execution
      ).sign(maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
      {
        return index
      }
    }
    throw GeometryConversionError.invalidInput(
      "Original overlap correspondence requires propagation of an additional exact cut to the other source."
    )
  }

  private func segment(
    lower: Int,
    upper: Int,
    in source: OriginalPlanarCurveMergedPartition,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Int {
    for index in source.segments.indices {
      try execution.consumeWork(1)
      if source.segments[index].lowerCutIndex == lower,
        source.segments[index].upperCutIndex == upper
      {
        return index
      }
    }
    throw GeometryConversionError.invalidInput(
      "Original overlap knots are not consecutive complete merged source cuts.")
  }
}
