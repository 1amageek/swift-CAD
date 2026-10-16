import CADCore

extension OriginalCurveCurveContact {
  /// Consumes the retained native scalar root; never rounds its parameter.
  package func firstNativeEndpoint(using execution: inout OriginalQueryExecution) throws
    -> OriginalCurveRootEndpoint?
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .membership, stage: .membership,
      first: .init(role: .curve, request: .curveRange(firstParameters)),
      second: .init(role: .curve, request: .curveRange(secondParameters)))
    do {
      try execution.checkpoint()
      let result = try resolveFirstNativeEndpoint(using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveFirstNativeEndpoint(using execution: inout OriginalQueryExecution) throws
    -> OriginalCurveRootEndpoint?
  {
    // FIXME(INCOMPLETE_IMPLEMENTATION): General original angular and
    // implicit guide events still need their own persistent scalar recipe.
    // This native root issuer must not infer such a recipe from a numerical
    // contact bracket or alias it to a B-spline construction parameter.
    guard let parameterAuthority, let index = firstNativeSpanIndex,
      case .bSpline(let source) = firstSource.curve
    else { return nil }
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      let depth = min(32, execution.effectiveLimits.maximumValueDepth)
      let root: ExactAlgebraicRealRoot
      switch parameterAuthority.originalRoot {
      case .rational(let pair): root = pair.projectionRoot
      case .field(let pair):
        let coordinate = try OriginalSingularRationalCoordinateRoot(
          original: pair.u,
          maximumDepth: depth,
          maximumAlgebraicDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution)
        switch coordinate.endpoint {
        case .algebraic(let retained): root = retained
        case .authored(let station):
          let bounds = try station.outwardInterval(usage: &execution)
          guard bounds.lower == bounds.upper else {
            throw KernelError(
              phase: .geometry, code: .classificationFailure, tolerance: tolerance,
              message:
                "Original field scalar endpoint issuer omitted its nonrepresentable retained root.")
          }
          return .authored(bounds.lower)
        }
      }
      let original = try OriginalRationalCurvePolynomial(
        source: source, spanIndex: index,
        tolerance: tolerance, usage: &execution)
      for station in [source.knots[index], source.knots[index + 1]] {
        let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &execution)
          .subtracting(
            .constant(
              .originalDouble(station, usage: &execution),
              usage: &execution), usage: &execution)
        if case .zero = try root.sign(of: equation, maximumDepth: depth, usage: &execution) {
          return .authored(station)
        }
      }
      var retained = root
      var width = try original.upperParameter.subtracting(
        original.lowerParameter, usage: &execution)
      let two = try ExactRationalCoefficient.natural(2, usage: &execution)
      while try retained.isolation.lower.subtracting(original.lowerParameter, usage: &execution)
        .isNegative
        || original.upperParameter.subtracting(retained.isolation.upper, usage: &execution)
          .isNegative
      {
        width = try width.divided(by: two, usage: &execution)
        retained = try retained.refined(maximumWidth: width, maximumDepth: depth, usage: &execution)
      }
      return try .algebraic(
        OriginalCurveRootBoundary.retaining(
          prepared: original, coordinate: retained,
          maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
          tolerance: tolerance,
          usage: &execution,
          maximumAlgebraicDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth)))

    }
  }
}
