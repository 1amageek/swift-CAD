import CADCore

/// A range certificate derived from a parent full-graph Krawczyk cell. It does
/// not claim a second independent existence proof; uniqueness is inherited
/// from the parent and the restricted bounds follow from its derivative proof.
public struct CertifiedImplicitIntersectionGraphSubcell: Sendable, Hashable {
  public let parameterBox: SurfaceIntersectionParameterBox
  public let parameterDerivativeBounds: [ScalarInterval]

  init(
    parameterBox: SurfaceIntersectionParameterBox,
    parameterDerivativeBounds: [ScalarInterval]
  ) {
    self.parameterBox = parameterBox
    self.parameterDerivativeBounds = parameterDerivativeBounds
  }
}

extension CertifiedImplicitIntersectionGraphCell {
  public func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try restrictedBounds(
        fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction,
        firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance,
        using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let parentDerivatives = try parameterDerivativeBounds(
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)
      return try restrictedBounds(
        fromNormalizedFraction: lowerFraction,
        toNormalizedFraction: upperFraction,
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        parentDerivativeBounds: parentDerivatives,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)

    }
  }

  package func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    parentDerivativeBounds: [ScalarInterval],
    tolerance: ModelingTolerance,
    maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let first = try PreparedSurfaceDifferentialEncloser(
        surface: firstSurface, tolerance: tolerance,
        remainingSourceDepth: min(
          remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
          execution.effectiveLimits.remainingSourceDepth),
        maximumSubdivisionDepth: min(
          maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
          execution.effectiveLimits.maximumSubdivisionDepth), maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)
      let second = try PreparedSurfaceDifferentialEncloser(
        surface: secondSurface, tolerance: tolerance,
        remainingSourceDepth: min(
          remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
          execution.effectiveLimits.remainingSourceDepth),
        maximumSubdivisionDepth: min(
          maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
          execution.effectiveLimits.maximumSubdivisionDepth), maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)
      return try restrictedBounds(
        fromNormalizedFraction: lowerFraction,
        toNormalizedFraction: upperFraction, firstSurface: first,
        secondSurface: second, parentDerivativeBounds: parentDerivativeBounds,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)

    }
  }

  package func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface: PreparedSurfaceDifferentialEncloser,
    parentDerivativeBounds: [ScalarInterval],
    tolerance: ModelingTolerance,
    maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try tolerance.validate()
      try execution.consumeWork(1)
      guard lowerFraction.isFinite, upperFraction.isFinite,
        lowerFraction >= 0, upperFraction <= 1, lowerFraction <= upperFraction,
        parentDerivativeBounds.count == 4
      else {
        throw GeometryConversionError.invalidInput(
          "A graph restriction requires four original derivative bounds and a closed normalized subinterval."
        )
      }
      let requested = OutwardScalarInterval(lower: lowerFraction, upper: upperFraction)
      let directed = direction == .forward ? requested : .exact(1) - requested
      let gauge = min(max(directed.midpoint, 0), 1)
      let traversalGauge =
        direction == .forward
        ? OutwardScalarInterval.exact(gauge) : .exact(1) - .exact(gauge)
      let displacement = requested - traversalGauge
      let span = OutwardScalarInterval.exact(upperFraction) - .exact(lowerFraction)
      let prover = try ParametricSurfaceIntersectionGraphProver(
        firstSurface: firstSurface,
        secondSurface: secondSurface, parameterBox: parameterBox,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)
      // The retained parent owns existence; contraction only encloses that root.
      let anchor = try prover.inheritedGaugeParameterBounds(
        freeParameter: freeParameter,
        atNormalizedFraction: gauge, tolerance: tolerance, using: &execution)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      var intervals: [ScalarInterval] = []
      intervals.reserveCapacity(4)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      var derivatives: [ScalarInterval] = []
      derivatives.reserveCapacity(4)
      for index in 0..<4 {
        try execution.consumeWork(1)
        guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
          throw GeometryConversionError.invalidInput("An original graph coordinate is invalid.")
        }
        let source = parameterBox.interval(for: coordinate)
        let domain = OutwardScalarInterval(lower: source.lower, upper: source.upper)
        let derivative = OutwardScalarInterval(
          lower: parentDerivativeBounds[index].lower,
          upper: parentDerivativeBounds[index].upper)
        let image: OutwardScalarInterval
        if coordinate == freeParameter {
          let width = OutwardScalarInterval.exact(source.upper) - .exact(source.lower)
          image = .exact(source.lower) + width * directed
        } else {
          image =
            OutwardScalarInterval(lower: anchor[index].lower, upper: anchor[index].upper)
            + derivative * displacement
        }
        guard let contained = image.intersection(with: domain), contained.isFinite else {
          throw GeometryConversionError.invalidInput(
            "An original restricted graph enclosure lost its retained root.")
        }
        let scaled = derivative * span
        guard scaled.isFinite else {
          throw GeometryConversionError.resourceLimitExceeded(
            "A restricted graph derivative has no finite original enclosure.")
        }
        intervals.append(try .init(lower: contained.lower, upper: contained.upper))
        derivatives.append(try .init(lower: scaled.lower, upper: scaled.upper))
      }
      return .init(
        parameterBox: .init(
          firstU: intervals[0], firstV: intervals[1],
          secondU: intervals[2], secondV: intervals[3]), parameterDerivativeBounds: derivatives)

    }
  }

}

extension CertifiedImplicitIntersectionGraphCell {
  public func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    try restrictedBounds(
      fromNormalizedFraction: lowerFraction,
      toNormalizedFraction: upperFraction,
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }
}

extension CertifiedImplicitIntersectionGraphCell {
  package func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    parentDerivativeBounds: [ScalarInterval],
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try restrictedBounds(
        fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction,
        firstSurface: firstSurface, secondSurface: secondSurface,
        parentDerivativeBounds: parentDerivativeBounds, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  package func restrictedBounds(
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    parentDerivativeBounds: [ScalarInterval],
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try restrictedBounds(
        fromNormalizedFraction: lowerFraction,
        toNormalizedFraction: upperFraction,
        firstSurface: .bSpline(firstSurface),
        secondSurface: .bSpline(secondSurface),
        parentDerivativeBounds: parentDerivativeBounds,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)

    }
  }
}
