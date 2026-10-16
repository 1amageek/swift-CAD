import CADCore

/// Complete isolated original factor authority independent of the spatial jet representation.
struct OriginalCurveCurveIsolatedFactorRoots {
  struct Proof {
    let axes: (Int, Int)
    let roots: [ExactBivariateSystemRoot]
  }

  enum Outcome {
    case isolated(Proof)
    case continuous(SurfaceParameterBox)
  }

  func certificate(
    common: OriginalNativeCurveCurveCommonFactor,
    over domain: SurfaceParameterBox,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Proof? {
    switch try outcome(
      common: common,
      over: domain,
      maximumDepth: maximumDepth,
      tolerance: tolerance,
      using: &execution)
    {
    case .isolated(let proof): return proof
    case .continuous, .none: return nil
    }
  }

  func outcome(
    common: OriginalNativeCurveCurveCommonFactor,
    over domain: SurfaceParameterBox,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Outcome? {
    guard maximumDepth >= 0,
      maximumDepth <= min(32, execution.effectiveLimits.maximumSubdivisionDepth)
    else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    try execution.consumeWork(common.quotients.count)
    // One original coordinate equation is equivalent to the factor, so
    // no off-factor projected contacts are excluded by this zero cover.
    let axis = common.quotients.indices.first(where: {
      let value = common.quotients[$0]
      return !value.isZero && value.uDegree == 0 && value.vDegree == 0
    })
    let authority = try OriginalRationalZeroSetAuthority(original: common.factor, usage: &execution)
    let projection = try OriginalRationalPlaneCurveProjection(
      original: authority,
      over: domain, maximumDepth: maximumDepth, usage: &execution)
    if let roots = try projection.finiteOriginalRoots(usage: &execution) {
      if let axis, !roots.isEmpty {
        return .isolated(Proof(axes: (axis, axis == 0 ? 1 : 0), roots: roots))
      }
      // Exact zero absence is not original tolerance-contact exclusion.
      return nil
    }
    let atlas = try OriginalRationalPlaneCurveAtlas(
      retaining: projection,
      maximumDepth: maximumDepth, usage: &execution)
    for strip in atlas.strips {
      for piece in strip.originalCover.pieces {
        try execution.consumeWork(1)
        guard piece.domain.u.width > 0, piece.domain.v.width > 0 else { continue }
        // The algebra owner proved the complete graph tube, nonzero
        // transverse derivative and original opposite-edge signs.
        // Every original XYZ equation is divisible by common.factor.
        return .continuous(piece.domain)
      }
    }
    let criticalU = try authority.squareFree.differentiated(alongU: true, usage: &execution)
    let criticalV = try authority.squareFree.differentiated(alongU: false, usage: &execution)
    let roots: [ExactBivariateSystemRoot]
    do {
      try execution.retainStorage(
        bytes: exactScalarPayloadBytes(count: 3, of: ExactBivariatePolynomial.self))
      roots = try ExactBivariateSystemSolver.isolatedRoots(
        of: [authority.squareFree, criticalU, criticalV],
        over: domain, maximumDepth: maximumDepth, usage: &execution)
    } catch let classification as ExactBivariateSystemClassification {
      switch classification {
      case .positiveDimensionalOriginalIdeal: return nil
      }
    }
    if !roots.isEmpty,
      let continuation = try OriginalCurveCurveSingularContinuation().certificate(
        common: common,
        at: roots,
        over: domain,
        maximumDepth: maximumDepth,
        tolerance: tolerance,
        using: &execution)
    {
      return .continuous(continuation)
    }
    return nil
  }
}
