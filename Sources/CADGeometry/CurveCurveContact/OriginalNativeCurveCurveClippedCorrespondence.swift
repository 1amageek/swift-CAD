import CADCore

/// Consumes exact original edge sectors to retain partial regular correspondence.
struct OriginalNativeCurveCurveClippedCorrespondence {
  func certificate(
    common: OriginalNativeCurveCurveCommonFactor,
    graph: ExactMonotoneRectangleGraph,
    firstNativeSpan: Int,
    secondNativeSpan: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeCurveCurveAlgebraicCorrespondence? {
    try execution.consumeWork(graph.spans.count)
    for span in graph.spans {
      let lower = try graph.stations[span.lowerStation].endpoint.upper.outwardInterval(
        usage: &execution
      ).upper
      let upper = try graph.stations[span.upperStation].endpoint.lower.outwardInterval(
        usage: &execution
      ).lower
      guard lower.isFinite, upper.isFinite, lower < upper else { continue }
      let free = graph.freeAlongU ? graph.sourceDomain.u : graph.sourceDomain.v
      guard lower >= free.lower, upper <= free.upper else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "An original clipped graph sector escaped its authored native domain.")
      }
      let interval = try ScalarInterval(lower: lower, upper: upper)
      let parameters =
        graph.freeAlongU
        ? SurfaceParameterBox(u: interval, v: graph.sourceDomain.v)
        : SurfaceParameterBox(u: graph.sourceDomain.u, v: interval)
      try execution.retainStorage(
        bytes: exactScalarPayloadBytes(count: 1, of: NativeCurveCurveAlgebraicCorrespondence.self))
      return NativeCurveCurveAlgebraicCorrespondence(
        parameters: parameters, commonFactor: common.factor,
        originalEquationQuotients: common.quotients,
        dependentParameter: graph.freeAlongU ? .second : .first,
        firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan,
        originalMonotoneGraph: graph)
    }
    return nil
  }
}
