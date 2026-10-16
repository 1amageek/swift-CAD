import CADCore

/// Original quadratic branches retain separate whole real correspondence sectors.
struct OriginalCurveCurveQuadraticCorrespondence {
  func certificate(
    common: OriginalNativeCurveCurveCommonFactor,
    over domain: SurfaceParameterBox,
    firstNativeSpan: Int,
    secondNativeSpan: Int,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws
    -> NativeCurveCurveAlgebraicCorrespondence?
  {
    guard maximumDepth >= 0,
      maximumDepth <= min(32, execution.effectiveLimits.maximumSubdivisionDepth)
    else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    guard
      let branches = try OriginalRationalQuadraticBranches.proven(
        original: common.factor,
        usage: &execution)
    else { return nil }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 2, of: ExactBivariatePolynomial.self))
    for source in [branches.first, branches.second] {
      let branch = try OriginalNativeCurveCurveCommonFactor(
        retainingSubfactor: source,
        of: common,
        tolerance: tolerance,
        using: &execution)
      guard
        let graph = try ExactMonotoneRectangleGraphProducer.graph(
          of: branch.factor,
          over: domain, freeAlongU: branches.freeAlongU,
          maximumDepth: maximumDepth, usage: &execution)
      else { continue }
      if let receipt = try OriginalNativeCurveCurveClippedCorrespondence().certificate(
        common: branch,
        graph: graph,
        firstNativeSpan: firstNativeSpan,
        secondNativeSpan: secondNativeSpan,
        tolerance: tolerance,
        using: &execution)
      {
        return receipt
      }
    }
    // Separate original branch clips prove no absence in the distance domain.
    return nil
  }
}
