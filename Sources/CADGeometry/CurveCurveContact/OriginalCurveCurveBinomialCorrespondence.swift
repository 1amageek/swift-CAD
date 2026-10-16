import CADCore

/// Exact reducible source factors retain separate real correspondence sectors.
struct OriginalCurveCurveBinomialCorrespondence {
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
      let source = try OriginalRationalBinomialBranches.proven(
        original: common.factor,
        usage: &execution)
    else { return nil }
    for factor in source.factors {
      let branch = try OriginalNativeCurveCurveCommonFactor(
        retainingSubfactor: factor,
        of: common,
        tolerance: tolerance,
        using: &execution)
      if let receipt = try OriginalCurveCurveCuspCorrespondence().certificate(
        common: branch,
        over: domain,
        firstNativeSpan: firstNativeSpan,
        secondNativeSpan: secondNativeSpan,
        maximumDepth: maximumDepth,
        tolerance: tolerance,
        using: &execution)
      {
        return receipt
      }
      for alongU in [true, false] {
        guard
          let graph = try ExactMonotoneRectangleGraphProducer.graph(
            of: branch.factor,
            over: domain, freeAlongU: alongU, maximumDepth: maximumDepth, usage: &execution)
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
    }
    return nil
  }
}
