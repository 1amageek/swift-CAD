import CADCore

/// Reuses both immutable boundary-curve representations of one ruled surface.
struct PreparedRuledSurfaceDifferentialEncloser: Sendable {
  let surface: RuledSurface3D
  private let startBoundary: PreparedCurveDifferentialEncloser
  private let endBoundary: PreparedCurveDifferentialEncloser

  init(surface: RuledSurface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
    try self.init(surface: surface, tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
  }


  init(surface: RuledSurface3D, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws {
    try execution.consumeWork(1); try tolerance.validate()
    guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original ruled preparation exhausts caller source depth.")
    }
    self.surface = surface
    startBoundary = try PreparedCurveDifferentialEncloser(curve: surface.startBoundary,
      tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
      using: &execution)
    endBoundary = try PreparedCurveDifferentialEncloser(curve: surface.endBoundary,
      tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
      using: &execution)
    try execution.consumeWork(1)
    guard case .closed(let lower, let upper) = surface.uDomain,
          lower.isFinite, upper.isFinite,
          upper - lower > max(tolerance.angle, tolerance.distance),
          try surface.startBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance),
          try surface.endBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance) else {
      throw GeometryConversionError.invalidInput("Original ruled support requires both complete finite rails.")
    }
  }

  func intervalJet(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    return try intervalJet(overClosedBox: parameters, tolerance: tolerance,
      maximumSpanCount: execution.effectiveLimits.maximumSpans, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
  }

  func intervalJet(overClosedBox parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
    try intervalJet(overClosedBox: parameters, tolerance: tolerance,
      maximumSpanCount: execution.effectiveLimits.maximumSpans, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
  }

  func intervalJet(overClosedBox parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
    guard parameters.u.lower <= parameters.u.upper, parameters.v.lower >= 0,
          parameters.v.upper <= 1,
          try surface.uDomain.containsSpan(from: parameters.u.lower, to: parameters.u.upper, tolerance: tolerance) else {
      throw GeometryConversionError.invalidInput("Original ruled query exceeds its complete closed parameter domain.")
    }
    func enclosed(_ prepared: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
      let result = try prepared.closedNativeJets(over: parameters.u, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      guard let first = result.spans.first else {
        throw GeometryConversionError.invalidInput("Original ruled query has no retained owning rail range.")
      }
      var hull = first.jet
      for span in result.spans.dropFirst() { try execution.consumeWork(1); hull = hull.union(span.jet) }
      return hull
    }
    let start = try enclosed(startBoundary), end = try enclosed(endBoundary)
    return start + (end + (-start)) * .parameterV(parameters.v)
  }

}
