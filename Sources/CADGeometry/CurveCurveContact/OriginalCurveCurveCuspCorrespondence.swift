import CADCore

/// Consumes an exact original cusp map without replacing native contact parameters.
struct OriginalCurveCurveCuspCorrespondence {
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
      let cusp = try OriginalRationalBinomialCusp.proven(
        original: common.factor,
        usage: &execution)
    else { return nil }
    let clipped = try cusp.clipped(over: domain, maximumDepth: maximumDepth, usage: &execution)
    // Complete clipping retains isolated stations separately. An empty
    // positive sector cannot exclude nearby distance-tolerance contacts.
    guard !clipped.spans.isEmpty else { return nil }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 1, of: NativeCurveCurveAlgebraicCorrespondence.self))
    return NativeCurveCurveAlgebraicCorrespondence(
      parameters: domain,
      commonFactor: common.factor, originalEquationQuotients: common.quotients,
      dependentParameter: .polynomialMap,
      firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan,
      originalPolynomialParameterDomain: clipped)
  }
}
