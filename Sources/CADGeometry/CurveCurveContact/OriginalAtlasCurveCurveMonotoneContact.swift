import CADCore

/// Original rational atlas factor coverage retains actual line/image/native charts.
struct OriginalAtlasCurveCurveMonotoneContact {
  enum Result {
    case continuous(SurfaceParameterBox)
    case isolated([ExactBivariateSystemRoot], axes: (Int, Int))
  }

  func certificate(
    equations: [ExactBivariatePolynomial],
    common: OriginalNativeCurveCurveCommonFactor?,
    over domain: SurfaceParameterBox,
    firstNativeSpan: Int,
    secondNativeSpan: Int,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Result? {
    try execution.consumeWork(equations.count)
    if equations.allSatisfy({ $0.isZero }) { return .continuous(domain) }
    guard let common else { return nil }
    if let branch = try OriginalCurveCurveBinomialCorrespondence().certificate(
      common: common,
      over: domain,
      firstNativeSpan: firstNativeSpan,
      secondNativeSpan: secondNativeSpan,
      maximumDepth: maximumDepth,
      tolerance: tolerance,
      using: &execution)
    {
      return .continuous(branch.parameters)
    }
    if let branch = try OriginalCurveCurveQuadraticCorrespondence().certificate(
      common: common,
      over: domain,
      firstNativeSpan: firstNativeSpan,
      secondNativeSpan: secondNativeSpan,
      maximumDepth: maximumDepth,
      tolerance: tolerance,
      using: &execution)
    {
      return .continuous(branch.parameters)
    }
    if let cusp = try OriginalCurveCurveCuspCorrespondence().certificate(
      common: common,
      over: domain,
      firstNativeSpan: firstNativeSpan,
      secondNativeSpan: secondNativeSpan,
      maximumDepth: maximumDepth,
      tolerance: tolerance,
      using: &execution)
    {
      return .continuous(cusp.parameters)
    }
    for freeAlongU in [true, false] {
      guard
        let graph = try ExactMonotoneRectangleGraphProducer.graph(
          of: common.factor,
          over: domain, freeAlongU: freeAlongU, maximumDepth: maximumDepth, usage: &execution)
      else { continue }
      if !graph.spans.isEmpty {
        if let receipt = try OriginalNativeCurveCurveClippedCorrespondence().certificate(
          common: common,
          graph: graph,
          firstNativeSpan: firstNativeSpan,
          secondNativeSpan: secondNativeSpan,
          tolerance: tolerance,
          using: &execution)
        {
          return .continuous(receipt.parameters)
        }
        continue
      }
      try execution.consumeWork(common.quotients.count)
      guard
        let axis = common.quotients.indices.first(where: {
          let value = common.quotients[$0]
          return !value.isZero && value.uDegree == 0 && value.vDegree == 0
        })
      else { continue }
      let roots = try graph.isolatedRoots(maximumDepth: maximumDepth, usage: &execution)
      if roots.isEmpty { continue }
      return .isolated(roots, axes: (axis, axis == 0 ? 1 : 0))
    }
    // The signed-box authority also applies to transformed original charts.
    // Slice isolation only steers this existence proof; failure is unresolved.
    if let receipt = try OriginalNativeCurveCurveRegularBranchSeed().certificate(
      common: common,
      firstRange: domain.u,
      secondRange: domain.v,
      firstNativeSpan: firstNativeSpan,
      secondNativeSpan: secondNativeSpan,
      maximumDepth: maximumDepth,
      tolerance: tolerance,
      using: &execution)
    {
      return .continuous(receipt.parameters)
    }
    return nil
  }
}
