import CADCore

/// A persistent normalized curve whose authority is the original chart law.
public struct OriginalCurveConstructionChartImage: Hashable, Sendable {
  public let chart: OriginalCurveConstructionChart
  public let certificationTolerance: ModelingTolerance
  package let maximumSpanCount: Int
  package let maximumSubdivisionDepth: Int
  package let remainingSourceDepth: Int
  private let preparedSource: PreparedCurveDifferentialEncloser?
  private let preparationMaximumAlgebraicDepth: Int?
  public var source: Curve3D { chart.source }
  public var parameterDomain: ParameterDomain { .closed(0, 1) }

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    traversal: OriginalCurveRootSpan3D, maximumSpanCount: Int,
    using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try execution.withSourceDepthOffset(1) { execution in
        try traversal.admitPreparation(using: &execution)
      }

      guard maximumSpanCount > 0 else {
        throw GeometryConversionError.invalidInput(
          "Original normalized traversal requires a positive span capability.")
      }
      try execution.consumeWork(1)
      try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
      preparedSource = nil
      preparationMaximumAlgebraicDepth = nil
      chart = .traversal(traversal)
      certificationTolerance = traversal.certificationTolerance
      self.maximumSpanCount = maximumSpanCount
      maximumSubdivisionDepth = traversal.maximumSubdivisionDepth
      remainingSourceDepth = traversal.remainingSourceDepth

      let preparationDepth = try execution.closePreparationScope(preparationToken)
      preparationClosed = true
      preparationReceipt = try OriginalGeometryPreparationReceipt(
        tolerance: traversal.certificationTolerance, depth: preparationDepth, using: &execution)
    } catch {
      if !preparationClosed {
        do { _ = try execution.closePreparationScope(preparationToken) } catch {}
      }
      throw error
    }
  }

  public init(
    parameterSource: OriginalCurveConstructionParameterSource, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try tolerance.validate()
      try execution.consumeWork(1)
      guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0,
        parameterSource.startParameter.isFinite,
        parameterSource.endParameter.isFinite,
        parameterSource.startParameter != parameterSource.endParameter,
        !parameterSource.firstFraction.isNegative, !parameterSource.lastFraction.isNegative,
        !(try ExactRationalCoefficient.one.subtracting(
          parameterSource.firstFraction, usage: &execution)).isNegative,
        !(try ExactRationalCoefficient.one.subtracting(
          parameterSource.lastFraction, usage: &execution)).isNegative,
        parameterSource.firstFraction != parameterSource.lastFraction
      else {
        throw GeometryConversionError.invalidInput(
          "Original construction chart requires distinct finite source labels and exact contained fractions."
        )
      }

      preparedSource = try execution.withSourceDepthOffset(1) {
        execution -> PreparedCurveDifferentialEncloser? in
        if parameterSource.law != .affine {
          try parameterSource.source.validateOriginalSource(
            tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
        if parameterSource.law != .affine {
          guard
            try Self.admitsConic(
              parameterSource.source, law: parameterSource.law,
              remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
          else {
            throw GeometryConversionError.invalidInput(
              "Original construction chart requires its original conic family.")
          }
        }
        if parameterSource.law == .affine {
          return try PreparedCurveDifferentialEncloser(
            curve: parameterSource.source, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        } else {
          return nil
        }
      }
      try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
      preparationMaximumAlgebraicDepth = maximumAlgebraicDepth
      chart = .parameterLaw(parameterSource)
      certificationTolerance = tolerance
      self.maximumSpanCount = maximumSpanCount
      self.maximumSubdivisionDepth = maximumSubdivisionDepth
      self.remainingSourceDepth = remainingSourceDepth - 1

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

  private static func admitsConic(
    _ source: Curve3D, law: OriginalCurveConstructionParameterLaw, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let child: Curve3D
    switch source {
    case .circle, .analytic(.circle), .analytic(.arc), .analytic(.ellipse):
      return law == .circularRational
    case .analytic(.hyperbola): return law == .hyperbolicRational
    case .rigidImage(let image): child = image.source
    case .affineImage(let image): child = image.source
    case .originalAffineWord(let image): child = image.source
    case .parameterImage:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Conic construction consumers
      // require a retained transported parameter-law receipt before a
      // parameter image may inherit the raw conic's authored labels.
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: nil,
        message: "Original conic parameter image needs its transported construction chart.")
    default: return false
    }
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original conic family traversal exhausted source depth.")
    }
    return try admitsConic(
      child, law: law, remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
  }

  public static func == (a: Self, b: Self) -> Bool {
    a.chart == b.chart && a.certificationTolerance == b.certificationTolerance
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(chart)
    hasher.combine(certificationTolerance)
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
        "Original construction chart requires its admitted tolerance.")
    }
  }

  /// Proves smoothness from original selected sides, never a synthetic hull.
  package func hasSmoothNativeInterval(
    over range: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
        throw GeometryConversionError.invalidInput(
          "Original query scalar proof cap must be nonnegative.")
      }
      return try execution.withProofScope(
        maximum: try maximumAlgebraicDepth.map {
          try ExactScalarDepth(value: $0, coefficient: $0)
        }
      ) { execution in

        try validate(tolerance: tolerance, using: &execution)
        try execution.consumeWork(1)
        if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
          throw GeometryConversionError.invalidInput(
            "Original chart smoothness requires an nonnegative independent algebra cap.")
        }
        guard range.lower.isFinite, range.upper.isFinite, range.lower >= 0,
          range.upper <= 1, range.lower < range.upper, maximumSpanCount > 0,
          maximumSubdivisionDepth >= 0, remainingSourceDepth > 0
        else {
          throw GeometryConversionError.invalidInput(
            "Original chart smoothness requires a positive contained interval and source capabilities."
          )
        }
        let spans = min(maximumSpanCount, self.maximumSpanCount)
        let depth = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
        let sourceDepth = min(remainingSourceDepth - 1, self.remainingSourceDepth)
        switch chart {
        case .traversal(let traversal):
          return try traversal.hasSmoothNativeInterval(
            over: range, tolerance: tolerance, maximumSpanCount: spans,
            maximumSubdivisionDepth: depth,
            remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
            using: &execution)
        case .parameterLaw(let source):
          if source.law != .affine { return true }
          guard
            let requiresOwner = try Self.smoothFamilyRequiresNativeOwner(
              source.source, remainingSourceDepth: sourceDepth, using: &execution)
          else { return false }
          if !requiresOwner { return true }
          guard let preparedSource else {
            throw GeometryConversionError.invalidInput(
              "Original smooth affine chart lost source preparation.")
          }

          let start = try ExactRationalCoefficient.originalDouble(
            source.startParameter, usage: &execution)
          let width = try ExactRationalCoefficient.originalDouble(
            source.endParameter, usage: &execution
          ).subtracting(start, usage: &execution)
          let gain = try source.lastFraction.subtracting(source.firstFraction, usage: &execution)
          func label(_ value: Double) throws -> OutwardScalarInterval {
            let fraction = try source.firstFraction.adding(
              gain.multiplied(by: .originalDouble(value, usage: &execution), usage: &execution),
              usage: &execution)
            return try start.adding(
              width.multiplied(by: fraction, usage: &execution), usage: &execution
            ).outwardInterval(usage: &execution)
          }
          let a = try label(range.lower)
          let b = try label(range.upper)
          let receipt = try preparedSource.closedNativeJets(
            over: .init(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper)),
            tolerance: tolerance, maximumSpanCount: spans, maximumSubdivisionDepth: depth,
            remainingSourceDepth: sourceDepth, using: &execution)
          return try Self.hasOnePositiveOwner(receipt, using: &execution)
        }

      }

    }
  }

  /// nil means this source family has no original smoothness issuer here.
  package static func smoothFamilyRequiresNativeOwner(
    _ curve: Curve3D, remainingSourceDepth: Int, using execution: inout OriginalQueryExecution
  ) throws -> Bool? {
    guard remainingSourceDepth >= 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original smooth-family traversal exhausted source depth.")
    }
    try execution.consumeWork(1)
    let child: Curve3D
    switch curve {
    case .bSpline: return true
    case .line, .circle, .analytic(.line), .analytic(.circle), .analytic(.arc),
      .analytic(.ellipse), .analytic(.hyperbola), .analytic(.parabola):
      return false
    case .rigidImage(let image): child = image.source
    case .affineImage(let image): child = image.source
    case .originalAffineWord(let image): child = image.source
    case .parameterImage(let image): child = image.source
    default: return nil
    }
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original smooth-family descendant exhausted source depth.")
    }
    return try smoothFamilyRequiresNativeOwner(
      child, remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
  }

  package static func hasOnePositiveOwner(
    _ receipt: PreparedCurveDifferentialEncloser.ClosedNativeJet,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    var count = 0
    for owner in receipt.spans {
      try execution.consumeWork(1)
      if owner.parameters.lower < owner.parameters.upper {
        count += 1
        if count > 1 { return false }
      }
    }
    return count == 1
  }

  package func selectedAffineOwningJet<B: ExactScalarAdmission & ~Copyable>(
    owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    normalizedLower: ExactRationalCoefficient, normalizedUpper: ExactRationalCoefficient,
    throughOrder: Int, tolerance: ModelingTolerance, remainingSourceDepth: Int,
    usage execution: inout B
  ) throws -> OriginalRationalCurveIntervalJet {
    try validatePreparationBinding(tolerance: tolerance)
    try admitScalarPreparation(using: &execution)
    guard case .parameterLaw(let originalChart) = chart,
      originalChart.law == .affine, remainingSourceDepth > 0,
      let map = owner.originalAffineParameterMap,
      !(try normalizedLower.subtracting(.zero, usage: &execution)).isNegative,
      !(try ExactRationalCoefficient.one.subtracting(normalizedUpper, usage: &execution)).isNegative
    else {
      throw GeometryConversionError.invalidInput(
        "Exact native chart query requires its affine source map and normalized interval.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): General mapped original contacts
    // still require exact translated-periodic and parameter-changing source
    // transport. This selected source issuer accepts base-native affine
    // chart owners only, never an outward localization box as an exact cut.
    guard owner.originalPeriodicCycle == nil || owner.originalPeriodicCycle == 0 else {
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "Exact mapped periodic owner requires retained source translation authority.")
    }
    let start = try ExactRationalCoefficient.originalDouble(
      originalChart.startParameter, usage: &execution)
    let width = try ExactRationalCoefficient.originalDouble(
      originalChart.endParameter, usage: &execution
    )
    .subtracting(start, usage: &execution)
    let gain = try width.multiplied(
      by: originalChart.lastFraction.subtracting(
        originalChart.firstFraction, usage: &execution), usage: &execution)
    let offset = try start.adding(
      width.multiplied(
        by: originalChart.firstFraction,
        usage: &execution), usage: &execution)
    func charge<C: ExactScalarAdmission & ~Copyable>(
      _ value: ExactRationalCoefficient, using execution: inout C
    )
      throws
    {
      try execution.consumeWork(1)
      try execution.consumeWork(value.canonicalNumeratorWords.count)
      try execution.consumeWork(value.canonicalDenominatorWords.count)
    }
    try charge(map.gain, using: &execution)
    try charge(map.offset, using: &execution)
    try charge(gain, using: &execution)
    try charge(offset, using: &execution)
    guard map.gain == gain, map.offset == offset else {
      throw GeometryConversionError.invalidInput(
        "Selected owner does not retain this original affine chart law.")
    }
    let original: OriginalRationalCurvePolynomial
    if case .bSpline(let source) = originalChart.source {
      original = try .init(
        source: source, spanIndex: owner.nativeIndex,
        tolerance: tolerance, usage: &execution)
    } else {
      original = try .init(
        source: originalChart.source, spanIndex: owner.nativeIndex,
        tolerance: tolerance,
        remainingSourceDepth: min(
          remainingSourceDepth - 1,
          self.remainingSourceDepth), usage: &execution)
    }
    guard owner.nativeDomain.lower == original.source.knots[owner.nativeIndex],
      owner.nativeDomain.upper == original.source.knots[owner.nativeIndex + 1]
    else {
      throw GeometryConversionError.invalidInput(
        "Selected affine owner is not the original full native knot span.")
    }
    return try OriginalRationalCurveIntervalJet(
      original: original, parameterMap: map,
      normalizedLower: normalizedLower, normalizedUpper: normalizedUpper,
      throughOrder: throughOrder, usage: &execution)
  }

  /// Per-original-side affine cover; normalized bounds localize exact source cuts.
  package func affineOwningJets(
    over range: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  )
    throws -> [PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan]?
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      try execution.consumeWork(1)
      guard case .parameterLaw(let chart) = chart, chart.law == .affine else { return nil }
      func hasOriginalNativeOwner(_ source: Curve3D, depth: Int) throws -> Bool {
        try execution.consumeWork(1)
        guard depth >= 0 else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original affine owner exhausted source depth.")
        }
        switch source {
        case .bSpline: return true
        case .rigidImage(let image):
          return try hasOriginalNativeOwner(image.source, depth: depth - 1)
        case .affineImage(let image):
          return try hasOriginalNativeOwner(image.source, depth: depth - 1)
        case .originalAffineWord(let image):
          return try hasOriginalNativeOwner(image.source, depth: depth - 1)
        default: return false
        }
      }
      guard
        try hasOriginalNativeOwner(
          chart.source, depth: min(remainingSourceDepth - 1, self.remainingSourceDepth))
      else { return nil }
      guard range.lower >= 0, range.upper <= 1, maximumSpanCount > 0,
        maximumSubdivisionDepth >= 0, remainingSourceDepth > 0, let preparedSource
      else {
        throw GeometryConversionError.invalidInput(
          "Original affine owning cover requires retained source preparation and capabilities.")
      }

      let start = try ExactRationalCoefficient.originalDouble(
        chart.startParameter, usage: &execution)
      let width = try ExactRationalCoefficient.originalDouble(chart.endParameter, usage: &execution)
        .subtracting(start, usage: &execution)
      let gain = try width.multiplied(
        by: chart.lastFraction.subtracting(chart.firstFraction, usage: &execution),
        usage: &execution)
      let offset = try start.adding(
        width.multiplied(by: chart.firstFraction, usage: &execution), usage: &execution)
      guard !gain.isZero else {
        throw GeometryConversionError.invalidInput("Original affine chart has zero parameter gain.")
      }
      func label(_ value: Double) throws -> OutwardScalarInterval {
        try gain.multiplied(by: .originalDouble(value, usage: &execution), usage: &execution)
          .adding(offset, usage: &execution).outwardInterval(usage: &execution)
      }
      let a = try label(range.lower)
      let b = try label(range.upper)
      let original = try preparedSource.closedNativeJets(
        over: .init(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper)),
        tolerance: tolerance,
        maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
        maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
        remainingSourceDepth: min(remainingSourceDepth - 1, self.remainingSourceDepth),
        using: &execution)
      try OriginalCoefficientAllocation.reserve(
        count: original.spans.count,
        of: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan.self, using: &execution)
      let d = try gain.outwardInterval(usage: &execution)
      let d2 = d * d
      let d3 = d2 * d
      let zero = OutwardScalarInterval.exact(0)
      func scalar(_ q: SurfaceIntervalJet) -> SurfaceIntervalJet {
        .init(
          value: q.value, derivativeU: q.derivativeU * d, derivativeV: zero,
          secondDerivativeUU: q.secondDerivativeUU * d2, secondDerivativeUV: zero,
          secondDerivativeVV: zero,
          thirdDerivativeUUU: q.thirdDerivativeUUU * d3, thirdDerivativeUUV: zero,
          thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
      }
      var result: [PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan] = []
      result.reserveCapacity(original.spans.count)
      for owner in original.spans {
        try execution.consumeWork(1)
        func inverse(_ value: Double) throws -> OutwardScalarInterval {
          try ExactRationalCoefficient.originalDouble(value, usage: &execution)
            .subtracting(offset, usage: &execution).divided(by: gain, usage: &execution)
            .outwardInterval(usage: &execution)
        }
        let lower = try inverse(owner.parameters.lower)
        let upper = try inverse(owner.parameters.upper)
        let localization = OutwardScalarInterval(
          lower: min(lower.lower, upper.lower), upper: max(lower.upper, upper.upper))
        guard
          let selected = localization.intersection(
            with: .init(lower: range.lower, upper: range.upper))
        else { continue }
        result.append(
          .init(
            nativeIndex: owner.nativeIndex, nativeDomain: owner.nativeDomain,
            parameters: try .init(lower: selected.lower, upper: selected.upper),
            jet: .init(x: scalar(owner.jet.x), y: scalar(owner.jet.y), z: scalar(owner.jet.z)),
            originalPeriodicCycle: owner.originalPeriodicCycle,
            originalAffineParameterMap: .init(gain: gain, offset: offset)))
      }
      return result

    }
  }

  package func preparedFirstOrder(
    over range: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalCurveFirstOrderJet
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      guard range.lower >= 0, range.upper <= 1, maximumSpanCount > 0,
        maximumSubdivisionDepth >= 0, remainingSourceDepth > 0
      else {
        throw GeometryConversionError.invalidInput(
          "Original chart first-order query requires its contained source capabilities.")
      }
      let spans = min(maximumSpanCount, self.maximumSpanCount)
      let depth = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
      let sourceDepth = min(remainingSourceDepth - 1, self.remainingSourceDepth)
      switch chart {
      case .traversal(let traversal):
        return try traversal.preparedFirstOrder(
          over: range, tolerance: tolerance, maximumSpanCount: spans,
          maximumSubdivisionDepth: depth,
          remainingSourceDepth: sourceDepth, using: &execution)
      case .parameterLaw(let source):
        guard source.law == .affine else {
          let value = try intervalTaylorJet(
            over: range, throughOrder: 1, tolerance: tolerance, maximumSpanCount: spans,
            maximumSubdivisionDepth: depth, remainingSourceDepth: remainingSourceDepth,
            using: &execution)
          return try .init(
            position: .init(
              x: value.x.coefficient(0, 0), y: value.y.coefficient(0, 0),
              z: value.z.coefficient(0, 0)
            ),
            firstDerivative: .init(
              x: value.x.coefficient(1, 0), y: value.y.coefficient(1, 0),
              z: value.z.coefficient(1, 0)
            ))
        }
        guard let preparedSource else {
          throw GeometryConversionError.invalidInput(
            "Original affine chart lost its retained source preparation.")
        }

        let start = try ExactRationalCoefficient.originalDouble(
          source.startParameter, usage: &execution)
        let width = try ExactRationalCoefficient.originalDouble(
          source.endParameter, usage: &execution
        ).subtracting(start, usage: &execution)
        let fractionGain = try source.lastFraction.subtracting(
          source.firstFraction, usage: &execution)
        let slope = try width.multiplied(by: fractionGain, usage: &execution).outwardInterval(
          usage: &execution)
        func label(_ parameter: Double) throws -> OutwardScalarInterval {
          let fraction = try source.firstFraction.adding(
            fractionGain.multiplied(
              by: .originalDouble(parameter, usage: &execution), usage: &execution),
            usage: &execution
          )
          return try start.adding(
            width.multiplied(by: fraction, usage: &execution), usage: &execution
          ).outwardInterval(usage: &execution)
        }
        let a = try label(range.lower)
        let b = try label(range.upper)
        let receipt = try preparedSource.closedNativeJets(
          over: .init(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper)),
          tolerance: tolerance, maximumSpanCount: spans, maximumSubdivisionDepth: depth,
          remainingSourceDepth: sourceDepth, using: &execution)
        guard let first = receipt.spans.first else {
          throw GeometryConversionError.invalidInput(
            "Original affine chart has no source owning cover.")
        }
        var jet = first.jet
        for owner in receipt.spans.dropFirst() {
          try execution.consumeWork(1)
          jet = jet.union(owner.jet)
        }
        return .init(
          position: .init(x: jet.x.value, y: jet.y.value, z: jet.z.value),
          firstDerivative: .init(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
            * slope)
      }

    }
  }

  package func intervalTaylorJet(
    over range: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      try execution.consumeWork(1)
      guard order >= 0, range.lower >= 0, range.upper <= 1, maximumSpanCount > 0,
        maximumSubdivisionDepth >= 0, remainingSourceDepth > 0
      else {
        throw GeometryConversionError.invalidInput(
          "Original chart query requires contained normalized range and caller capabilities.")
      }
      let spans = min(maximumSpanCount, self.maximumSpanCount)
      let depth = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
      let sourceDepth = min(remainingSourceDepth - 1, self.remainingSourceDepth)
      switch chart {
      case .traversal(let traversal):
        return try traversal.intervalTaylorJet(
          over: range, throughOrder: order, tolerance: tolerance, maximumSpanCount: spans,
          maximumSubdivisionDepth: depth, remainingSourceDepth: sourceDepth, using: &execution)
      case .parameterLaw(let value):
        return try mappedJet(
          value, over: range, throughOrder: order, tolerance: tolerance, maximumSpanCount: spans,
          maximumSubdivisionDepth: depth, remainingSourceDepth: sourceDepth, using: &execution)
      }

    }
  }

  private func mappedJet(
    _ value: OriginalCurveConstructionParameterSource, over range: ScalarInterval,
    throughOrder order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let exactGain = try value.lastFraction.subtracting(value.firstFraction, usage: &execution)
      func endpoint(_ original: Double) throws -> OutwardScalarInterval {
        try value.firstFraction.adding(
          exactGain.multiplied(
            by:
              .originalDouble(original, usage: &execution), usage: &execution), usage: &execution
        ).outwardInterval(usage: &execution)
      }
      let a = try endpoint(range.lower)
      let b = try endpoint(range.upper)
      let fractions = OutwardScalarInterval(
        lower: max(0, min(a.lower, b.lower)),
        upper: min(1, max(a.upper, b.upper)))
      let fractionGain = try exactGain.outwardInterval(usage: &execution)
      let label: IntervalDerivativeJet
      switch value.law {
      case .affine:
        let start = try ExactRationalCoefficient.originalDouble(
          value.startParameter, usage: &execution)
        let gain = try ExactRationalCoefficient.originalDouble(
          value.endParameter, usage: &execution
        )
        .subtracting(start, usage: &execution)
        let first = try start.adding(
          gain.multiplied(
            by:
              value.firstFraction.adding(
                exactGain.multiplied(
                  by:
                    .originalDouble(range.lower, usage: &execution), usage: &execution),
                usage: &execution), usage: &execution), usage: &execution)
        let last = try start.adding(
          gain.multiplied(
            by:
              value.firstFraction.adding(
                exactGain.multiplied(
                  by:
                    .originalDouble(range.upper, usage: &execution), usage: &execution),
                usage: &execution), usage: &execution), usage: &execution)
        let lo = try first.outwardInterval(usage: &execution)
        let hi = try last.outwardInterval(usage: &execution)
        try OriginalCoefficientAllocation.reserve(
          count: order + 1, of: OutwardScalarInterval.self, using: &execution)
        var derivatives = [OutwardScalarInterval](repeating: .exact(0), count: order + 1)
        derivatives[0] = .init(lower: min(lo.lower, hi.lower), upper: max(lo.upper, hi.upper))
        if order > 0 { derivatives[1] = try gain.outwardInterval(usage: &execution) }
        label = .init(derivatives: derivatives)
      case .circularRational:
        label = try OriginalCircularRationalParameterLaw(
          start: value.startParameter, end: value.endParameter
        )
        .jet(over: fractions, throughOrder: order, tolerance: tolerance, using: &execution)
      case .hyperbolicRational:
        label = try OriginalHyperbolicRationalParameterLaw(
          start: value.startParameter, end: value.endParameter
        )
        .jet(over: fractions, throughOrder: order, tolerance: tolerance, using: &execution)
      }
      let sourceRange = try ScalarInterval(
        lower: label.derivatives[0].lower, upper: label.derivatives[0].upper)
      let original = try OriginalCurveHigherJetProvider.intervalTaylorJet(
        of: value.source, over: sourceRange, tolerance: tolerance, throughOrder: order,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth,
        maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
      var u = try SurfaceAreaIntervalTaylorScalarJet(
        order: order, axis: .u, tolerance: tolerance, using: &execution)
      var gain = OutwardScalarInterval.exact(1)
      var factorial = 1.0
      for index in 0...order {
        try execution.consumeWork(1)
        if index > 0 {
          factorial *= Double(index)
          gain = gain * fractionGain
        }
        guard let coefficient = (label.derivatives[index] * gain).divided(by: .exact(factorial))
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original chart Taylor composition is nonfinite.")
        }
        try u.set(coefficient, index, 0)
      }
      let zero = try SurfaceAreaIntervalTaylorScalarJet.constant(
        .exact(0), order: order, axis: .u, tolerance: tolerance, using: &execution)
      return try OriginalCurveTaylorComposition.compose(
        surface: original, u: u, v: zero, order: order, using: &execution)

    }
  }

  public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var execution = try preparationReceipt.makeExecution()
    return try point(at: parameter, tolerance: tolerance, using: &execution)
  }

  public func point(
    at parameter: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let jet = try intervalTaylorJet(
        over: .init(lower: parameter, upper: parameter), throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth == Int.max ? Int.max : remainingSourceDepth + 1,
        using: &execution)
      let x = try jet.x.coefficient(0, 0)
      let y = try jet.y.coefficient(0, 0)
      let z = try jet.z.coefficient(0, 0)
      let uncertainty = IntervalVector3DBounds(
        x: x - .exact(x.midpoint),
        y: y - .exact(y.midpoint), z: z - .exact(z.midpoint)
      ).lengthUpperBound
      guard uncertainty <= tolerance.distance else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original chart point uncertainty exceeds the caller tolerance.")
      }
      return .init(x: x.midpoint, y: y.midpoint, z: z.midpoint)

    }
  }
}
