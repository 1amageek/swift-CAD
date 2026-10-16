import CADCore

/// Declared aggregate chart retaining every original directed guide traversal.
public struct OriginalGuideTraversalChain3D: Hashable, Sendable {
  public let traversals: [OriginalCurveRootSpan3D]
  public let stations: [ExactRationalCoefficient]
  public let sourceSegmentOrdinals: [Int]
  private let retainedSourceDepth: Int
  private let rationalPieces: [[OriginalSplineTraversalPolynomialPiece]?]
  private let continuousThroughOrder: Int
  private let retainedMaximumSpanCount: Int
  private let retainedMaximumSubdivisionDepth: Int
  private let retainedMaximumAlgebraicDepth: Int

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    traversals: [OriginalCurveRootSpan3D],
    stations: [ExactRationalCoefficient], sourceSegmentOrdinals: [Int],
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try execution.withSourceDepthOffset(1) { execution in
        for traversal in traversals { try traversal.admitPreparation(using: &execution) }
      }

      try tolerance.validate()
      let stationCount = traversals.count.addingReportingOverflow(1)
      guard !traversals.isEmpty, !stationCount.overflow,
        stations.count == stationCount.partialValue,
        sourceSegmentOrdinals.count == traversals.count, stations.first == .zero,
        stations.last == .one, remainingSourceDepth > 0
      else {
        throw GeometryConversionError.invalidInput(
          "Original guide chain requires a complete exact normalized partition.")
      }
      try RationalAlgebraStorage.retain(
        traversals.count, of: OriginalCurveRootSpan3D.self, usage: &execution)
      try RationalAlgebraStorage.retain(
        stations.count, of: ExactRationalCoefficient.self, usage: &execution)
      try RationalAlgebraStorage.retain(
        sourceSegmentOrdinals.count, of: Int.self, usage: &execution)
      try RationalAlgebraStorage.retain(
        traversals.count, of: [OriginalSplineTraversalPolynomialPiece]?.self, usage: &execution)
      var pieces: [[OriginalSplineTraversalPolynomialPiece]?] = []
      pieces.reserveCapacity(traversals.count)
      var continuity = 3
      var spanCap = Int.max
      var subdivisionCap = Int.max
      var algebraCap = Int.max
      for index in traversals.indices {
        let span = traversals[index]
        try execution.consumeWork(1)
        let hasC0: Bool
        if case .authored(let first) = span.start, case .authored(let last) = span.end {
          hasC0 = try OriginalCurveTraversalContinuityAdmission().proves(
            source: span.source,
            first: .originalDouble(first, usage: &execution),
            last: .originalDouble(last, usage: &execution),
            remainingSourceDepth: min(remainingSourceDepth - 1, span.remainingSourceDepth),
            maximumSubdivisionDepth: span.maximumSubdivisionDepth,
            maximumAlgebraicDepth: nil, tolerance: tolerance, usage: &execution)
        } else if case .bSpline = span.source, span.nativeSpanIndex != nil {
          hasC0 = true
        } else {
          hasC0 = false
        }
        guard span.certificationTolerance == tolerance, sourceSegmentOrdinals[index] >= 0,
          try stations[index + 1].subtracting(stations[index], usage: &execution).isPositive, hasC0
        else {
          throw GeometryConversionError.invalidInput(
            "Original guide traversal lacks its exact positional continuity or station order.")
        }
        spanCap = min(spanCap, span.maximumSpanCount)
        subdivisionCap = min(subdivisionCap, span.maximumSubdivisionDepth)
        algebraCap = min(algebraCap, span.maximumAlgebraicDepth)
        if index > 0 {
          guard sourceSegmentOrdinals[index] >= sourceSegmentOrdinals[index - 1],
            try OriginalCurveTraversalEndpointRelation().proves(
              first: traversals[index - 1], firstAtEnd: true,
              second: span, secondAtEnd: false, remainingSourceDepth: remainingSourceDepth - 1,
              usage: &execution)
          else {
            throw GeometryConversionError.invalidInput(
              "Original guide traversals have unequal source endpoints or source order.")
          }
        }
        if try OriginalSplineTraversalPolynomialPiece.supports(span, usage: &execution) {
          let original = try OriginalSplineTraversalPolynomialPiece.pieces(span, usage: &execution)
          for adjacent in 1..<original.count {
            if continuity == 0 { break }
            for order in 1...continuity {
              try RationalAlgebraStorage.retain(
                2, of: OriginalSplineTraversalPolynomialPiece.self, usage: &execution)
              let a = try OriginalSplineTraversalPolynomialPiece.derivative(
                [original[adjacent - 1]],
                at: original[adjacent - 1].upper, order: order, usage: &execution)
              let b = try OriginalSplineTraversalPolynomialPiece.derivative(
                [original[adjacent]],
                at: original[adjacent].lower, order: order, usage: &execution)
              if try !a.subtracting(b, usage: &execution).isZero {
                continuity = order - 1
                break
              }
            }
          }
          pieces.append(original)
        } else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Nonrational/algebraic-endpoint
          // guide traversals retain their original C0 law here. Higher join
          // publication needs the exact original derivative equality issuer;
          // interval derivative hulls cannot authorize smooth continuity.
          pieces.append(nil)
          continuity = 0
        }
        if index > 0, continuity > 0, let first = pieces[index - 1], let second = pieces[index] {
          let firstWidth = try stations[index].subtracting(stations[index - 1], usage: &execution)
          let secondWidth = try stations[index + 1].subtracting(stations[index], usage: &execution)
          var firstGain = ExactRationalCoefficient.one
          var secondGain = ExactRationalCoefficient.one
          for order in 1...continuity {
            firstGain = try firstGain.divided(by: firstWidth, usage: &execution)
            secondGain = try secondGain.divided(by: secondWidth, usage: &execution)
            let a = try OriginalSplineTraversalPolynomialPiece.derivative(
              first, at: .one,
              order: order, usage: &execution
            ).scaled(by: firstGain, usage: &execution)
            let b = try OriginalSplineTraversalPolynomialPiece.derivative(
              second, at: .zero,
              order: order, usage: &execution
            ).scaled(by: secondGain, usage: &execution)
            if try !a.subtracting(b, usage: &execution).isZero {
              continuity = order - 1
              break
            }
          }
        }
      }
      self.traversals = traversals
      self.stations = stations
      self.sourceSegmentOrdinals = sourceSegmentOrdinals
      retainedSourceDepth = remainingSourceDepth
      rationalPieces = pieces
      continuousThroughOrder = continuity
      retainedMaximumSpanCount = spanCap
      retainedMaximumSubdivisionDepth = subdivisionCap
      retainedMaximumAlgebraicDepth = algebraCap

      let preparationDepth = try execution.closePreparationScope(preparationToken)
      preparationClosed = true
      preparationReceipt = try OriginalGeometryPreparationReceipt(
        tolerance: tolerance, depth: preparationDepth, using: &execution)
    } catch {
      if !preparationClosed {
        do { _ = try execution.closePreparationScope(preparationToken) } catch {}
      }
      throw error
    }
  }

  public var domain: ParameterDomain { .closed(0, 1) }
  public var certificationTolerance: ModelingTolerance { traversals[0].certificationTolerance }
  package var remainingSourceDepth: Int { retainedSourceDepth }
  package var maximumSpanCount: Int { retainedMaximumSpanCount }
  package var maximumSubdivisionDepth: Int { retainedMaximumSubdivisionDepth }
  package var maximumAlgebraicDepth: Int { retainedMaximumAlgebraicDepth }
  package var provenContinuityOrder: Int { continuousThroughOrder }
  package func originalEndpoint(at parameter: Double) -> (
    boundary: OriginalCurveRootSpan3D, atEnd: Bool
  )? {
    if parameter == 0 { return (traversals[0], false) }
    if parameter == 1 { return (traversals[traversals.count - 1], true) }
    return nil
  }

  public static func == (a: Self, b: Self) -> Bool {
    a.traversals == b.traversals && a.stations == b.stations
      && a.sourceSegmentOrdinals == b.sourceSegmentOrdinals
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(traversals)
    hasher.combine(sourceSegmentOrdinals)
    for station in stations {
      hasher.combine(station.canonicalSign)
      hasher.combine(station.canonicalNumeratorWords)
      hasher.combine(station.canonicalDenominatorWords)
    }
  }
  package func admitPreparation(using execution: inout OriginalQueryExecution) throws {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in

      try preparationReceipt.admit(tolerance: certificationTolerance, using: &execution)

    }
  }

  package func admitScalarPreparation<A: ExactScalarAdmission & ~Copyable>(using execution: inout A)
    throws
  {
    try execution.admitDepth(
      value: preparationReceipt.depth.scalar.value,
      coefficient: preparationReceipt.depth.scalar.coefficient)
    try execution.checkpoint()
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in

      try validatePreparationBinding(tolerance: tolerance)
      try preparationReceipt.admit(tolerance: tolerance, using: &execution)

    }
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = try preparationReceipt.makeExecution()
    try validate(tolerance: tolerance, using: &execution)
  }

  package func validatePreparationBinding(tolerance: ModelingTolerance) throws {
    try tolerance.validate()
    guard tolerance == certificationTolerance else {
      throw GeometryConversionError.invalidInput(
        "Original guide chain changed its source tolerance.")
    }
  }

  package func selected<B: ExactScalarAdmission & ~Copyable>(
    over range: ScalarInterval,
    usage: inout B
  ) throws -> [(
    index: Int, local: ScalarInterval, inverseWidth: ExactRationalCoefficient,
    lower: ExactRationalCoefficient, upper: ExactRationalCoefficient
  )] {
    try admitScalarPreparation(using: &usage)
    guard range.lower >= 0, range.upper <= 1 else {
      throw GeometryConversionError.invalidInput(
        "Original guide query exceeds its exact normalized source domain.")
    }
    let lower = try ExactRationalCoefficient.originalDouble(range.lower, usage: &usage)
    let upper = try ExactRationalCoefficient.originalDouble(range.upper, usage: &usage)
    try RationalAlgebraStorage.retain(
      traversals.count,
      of: (
        Int, ScalarInterval, ExactRationalCoefficient, ExactRationalCoefficient,
        ExactRationalCoefficient
      ).self, usage: &usage)
    var result:
      [(
        index: Int, local: ScalarInterval, inverseWidth: ExactRationalCoefficient,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient
      )] = []
    result.reserveCapacity(traversals.count)
    for index in traversals.indices {
      let a = stations[index]
      let b = stations[index + 1]
      if try upper.subtracting(a, usage: &usage).isNegative
        || b.subtracting(lower, usage: &usage).isNegative
      {
        continue
      }
      let clippedLower = try lower.subtracting(a, usage: &usage).isPositive ? lower : a
      let clippedUpper = try upper.subtracting(b, usage: &usage).isNegative ? upper : b
      let width = try b.subtracting(a, usage: &usage)
      let first = try clippedLower.subtracting(a, usage: &usage).divided(by: width, usage: &usage)
      let last = try clippedUpper.subtracting(a, usage: &usage).divided(by: width, usage: &usage)
      let firstBounds = try first.outwardInterval(usage: &usage)
      let lastBounds = try last.outwardInterval(usage: &usage)
      // Exact source clipping above proves these local parameters belong
      // to [0,1]; clamping only limits their outward query localization.
      let local = try ScalarInterval(
        lower: max(0, firstBounds.lower), upper: min(1, lastBounds.upper))
      result.append(
        (index, local, try .one.divided(by: width, usage: &usage), clippedLower, clippedUpper))
    }
    guard !result.isEmpty else {
      throw GeometryConversionError.invalidInput("Original guide query has no selected traversal.")
    }
    return result
  }
}
