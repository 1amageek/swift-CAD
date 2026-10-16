import CADCore

/// Original guide law with original section endpoint expressions.
public struct OriginalGuideEndpointConnectorCurve3D: Hashable, Sendable {
  public let source: OriginalCurveRootSpan3D
  public let startBoundary: OriginalCurveRootSpan3D
  public let startAtEnd: Bool
  public let endBoundary: OriginalCurveRootSpan3D
  public let endAtEnd: Bool
  public let correctionBasis: OriginalEndpointCorrectionBasis
  private let originalStart: IntervalVector3DBounds
  private let originalEnd: IntervalVector3DBounds
  private let sourceStart: IntervalVector3DBounds
  private let sourceEnd: IntervalVector3DBounds
  private let retainedSourceDepth: Int

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    source: OriginalCurveRootSpan3D, startBoundary: OriginalCurveRootSpan3D, startAtEnd: Bool,
    endBoundary: OriginalCurveRootSpan3D, endAtEnd: Bool,
    correctionBasis: OriginalEndpointCorrectionBasis, remainingSourceDepth: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try execution.withSourceDepthOffset(1) { execution in
        try source.admitPreparation(using: &execution)
        try startBoundary.admitPreparation(using: &execution)
        try endBoundary.admitPreparation(using: &execution)
      }

      try tolerance.validate()
      try execution.consumeWork(1)
      guard remainingSourceDepth > 0, source.certificationTolerance == tolerance,
        startBoundary.certificationTolerance == tolerance,
        endBoundary.certificationTolerance == tolerance,
        try OriginalCurveTraversalContinuityAdmission().proves(source, usage: &execution)
      else {
        throw GeometryConversionError.invalidInput(
          "Original guide correction requires matching original source tolerance and positional continuity."
        )
      }
      try RationalAlgebraStorage.retain(4, of: IntervalVector3DBounds.self, usage: &execution)
      func position(_ traversal: OriginalCurveRootSpan3D, atEnd: Bool) throws
        -> IntervalVector3DBounds
      {
        let value = atEnd ? 1.0 : 0.0
        let jet = try traversal.intervalTaylorJet(
          over: .init(lower: value, upper: value), throughOrder: 0, tolerance: tolerance,
          maximumSpanCount: traversal.maximumSpanCount,
          remainingSourceDepth: min(remainingSourceDepth - 1, traversal.remainingSourceDepth),
          using: &execution)
        return try .init(
          x: jet.x.coefficient(0, 0), y: jet.y.coefficient(0, 0), z: jet.z.coefficient(0, 0))
      }
      originalStart = try position(startBoundary, atEnd: startAtEnd)
      originalEnd = try position(endBoundary, atEnd: endAtEnd)
      sourceStart = try position(source, atEnd: false)
      sourceEnd = try position(source, atEnd: true)
      self.source = source
      self.startBoundary = startBoundary
      self.startAtEnd = startAtEnd
      self.endBoundary = endBoundary
      self.endAtEnd = endAtEnd
      self.correctionBasis = correctionBasis
      retainedSourceDepth = remainingSourceDepth

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
  public var certificationTolerance: ModelingTolerance { source.certificationTolerance }
  package var remainingSourceDepth: Int { retainedSourceDepth }
  package var maximumSpanCount: Int {
    min(source.maximumSpanCount, startBoundary.maximumSpanCount, endBoundary.maximumSpanCount)
  }
  package var maximumSubdivisionDepth: Int {
    min(
      source.maximumSubdivisionDepth, startBoundary.maximumSubdivisionDepth,
      endBoundary.maximumSubdivisionDepth)
  }
  package var maximumAlgebraicDepth: Int {
    min(
      source.maximumAlgebraicDepth, startBoundary.maximumAlgebraicDepth,
      endBoundary.maximumAlgebraicDepth)
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
        "Original guide correction changed its original tolerance.")
    }
  }
  package func originalEndpoint(at parameter: Double) -> (
    boundary: OriginalCurveRootSpan3D, atEnd: Bool
  )? {
    if parameter == 0 { return (startBoundary, startAtEnd) }
    if parameter == 1 { return (endBoundary, endAtEnd) }
    return nil
  }
  public static func == (a: Self, b: Self) -> Bool {
    a.source == b.source && a.startBoundary == b.startBoundary && a.startAtEnd == b.startAtEnd
      && a.endBoundary == b.endBoundary && a.endAtEnd == b.endAtEnd
      && a.correctionBasis == b.correctionBasis
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(source)
    hasher.combine(startBoundary)
    hasher.combine(startAtEnd)
    hasher.combine(endBoundary)
    hasher.combine(endAtEnd)
    hasher.combine(correctionBasis)
  }

  package func admittingQuerySource(
    maximumAlgebraicDepth requested: Int?, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveRootSpan3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      guard let requested else { return source }
      guard requested >= 0, remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput(
          "Original guide correction requires an independent selected algebra capability.")
      }
      let selected = requested
      func admit(_ span: OriginalCurveRootSpan3D) throws -> OriginalCurveRootSpan3D {
        try span.admittingQueryAlgebra(
          selected, tolerance: tolerance,
          maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
          remainingSourceDepth: min(
            min(remainingSourceDepth, self.remainingSourceDepth) - 1, span.remainingSourceDepth),
          using: &execution)
      }
      _ = try admit(startBoundary)
      _ = try admit(endBoundary)
      return try admit(source)

    }
  }

  package func corrected(
    _ original: SurfaceAreaIntervalTaylorVectorJet, over parameters: ScalarInterval,
    throughOrder order: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let h = try OriginalEndpointCorrectionTaylor.jet(
        basis: correctionBasis, over: parameters, throughOrder: order, tolerance: tolerance,
        using: &execution)
      func axis(
        _ q: SurfaceAreaIntervalTaylorScalarJet, first: OutwardScalarInterval,
        last: OutwardScalarInterval, guideFirst: OutwardScalarInterval,
        guideLast: OutwardScalarInterval
      )
        throws -> SurfaceAreaIntervalTaylorScalarJet
      {
        for _ in 0..<3 { try execution.consumeWork(1) }
        // These intervals enclose original endpoint differences. The raw
        // retained endpoints define the law; no midpoint becomes a coefficient.
        let a = first - guideFirst
        let b = last - guideLast
        let constant = try SurfaceAreaIntervalTaylorScalarJet.constant(
          a, order: order, axis: .u, tolerance: tolerance, using: &execution)
        var result = try q.adding(constant, using: &execution)
          .adding(h.scaled(by: b - a, using: &execution), using: &execution)
        if parameters.lower == parameters.upper, parameters.lower == 0 {
          try result.set(first, 0, 0)
        } else if parameters.lower == parameters.upper, parameters.lower == 1 {
          try result.set(last, 0, 0)
        }
        return result
      }
      return try .init(
        x: axis(
          original.x, first: originalStart.x, last: originalEnd.x, guideFirst: sourceStart.x,
          guideLast: sourceEnd.x),
        y: axis(
          original.y, first: originalStart.y, last: originalEnd.y, guideFirst: sourceStart.y,
          guideLast: sourceEnd.y),
        z: axis(
          original.z, first: originalStart.z, last: originalEnd.z, guideFirst: sourceStart.z,
          guideLast: sourceEnd.z))

    }
  }

  package func intervalTaylorJet(
    over parameters: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
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
        guard order >= 0, parameters.lower >= 0, parameters.upper <= 1,
          maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0
        else {
          throw GeometryConversionError.invalidInput(
            "Original guide correction requires its normalized domain and independent capabilities."
          )
        }
        let admittedSource = try admittingQuerySource(
          maximumAlgebraicDepth: maximumAlgebraicDepth, tolerance: tolerance,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth,
          using: &execution)
        let original = try admittedSource.intervalTaylorJet(
          over: parameters, throughOrder: order, tolerance: tolerance,
          maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
          maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
          remainingSourceDepth: min(
            min(remainingSourceDepth, self.remainingSourceDepth) - 1, source.remainingSourceDepth),
          using: &execution)
        return try corrected(
          original, over: parameters, throughOrder: order, tolerance: tolerance, using: &execution)

      }

    }
  }

  package func preparedFirstOrder(
    over parameters: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveFirstOrderJet {
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
        guard parameters.lower >= 0, parameters.upper <= 1, remainingSourceDepth > 0 else {
          throw GeometryConversionError.invalidInput(
            "Original guide first-order correction requires normalized parameters and source descent."
          )
        }
        let admittedSource = try admittingQuerySource(
          maximumAlgebraicDepth: maximumAlgebraicDepth, tolerance: tolerance,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth,
          using: &execution)
        let q = try admittedSource.preparedFirstOrder(
          over: parameters, tolerance: tolerance,
          maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
          maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
          remainingSourceDepth: min(
            min(remainingSourceDepth, self.remainingSourceDepth) - 1, source.remainingSourceDepth),
          using: &execution)
        let h = try OriginalEndpointCorrectionTaylor.jet(
          basis: correctionBasis, over: parameters, throughOrder: 1, tolerance: tolerance,
          using: &execution)
        let value = try h.coefficient(0, 0)
        let derivative = try h.coefficient(1, 0)
        let a = IntervalVector3DBounds(
          x: originalStart.x - sourceStart.x, y: originalStart.y - sourceStart.y,
          z: originalStart.z - sourceStart.z)
        let b = IntervalVector3DBounds(
          x: originalEnd.x - sourceEnd.x - a.x, y: originalEnd.y - sourceEnd.y - a.y,
          z: originalEnd.z - sourceEnd.z - a.z)
        try execution.consumeWork(1)
        var position = IntervalVector3DBounds(
          x: q.position.x + a.x + b.x * value, y: q.position.y + a.y + b.y * value,
          z: q.position.z + a.z + b.z * value)
        if parameters.lower == parameters.upper, parameters.lower == 0 {
          position = originalStart
        } else if parameters.lower == parameters.upper, parameters.lower == 1 {
          position = originalEnd
        }
        return .init(
          position: position,
          firstDerivative: .init(
            x: q.firstDerivative.x + b.x * derivative,
            y: q.firstDerivative.y + b.y * derivative, z: q.firstDerivative.z + b.z * derivative))

      }

    }
  }
}
