import CADCore

/// Reuses both immutable boundary-curve representations of one ruled surface.
struct PreparedRuledSurfaceDifferentialEncloser: Sendable {
  let surface: RuledSurface3D
  private let startBoundary: PreparedCurveDifferentialEncloser
  private let endBoundary: PreparedCurveDifferentialEncloser

  init(
    surface: RuledSurface3D,
    tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = {}
  ) throws {
    try surface.validate(tolerance: tolerance)
    self.surface = surface
    startBoundary = try PreparedCurveDifferentialEncloser(
      curve: surface.startBoundary,
      tolerance: tolerance, consumeWork: consumeWork
    )
    endBoundary = try PreparedCurveDifferentialEncloser(
      curve: surface.endBoundary,
      tolerance: tolerance, consumeWork: consumeWork
    )
  }

  init(surface: RuledSurface3D, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int = Int.max, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws {
    try consumeWork(); try tolerance.validate()
    guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original ruled preparation exhausts caller source depth.")
    }
    self.surface = surface
    startBoundary = try PreparedCurveDifferentialEncloser(curve: surface.startBoundary,
      tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
    endBoundary = try PreparedCurveDifferentialEncloser(curve: surface.endBoundary,
      tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
    try consumeWork()
    guard case .closed(let lower, let upper) = surface.uDomain,
          lower.isFinite, upper.isFinite,
          upper - lower > max(tolerance.angle, tolerance.distance),
          try surface.startBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance),
          try surface.endBoundary.parameterDomain.containsSpan(from: lower, to: upper, tolerance: tolerance) else {
      throw GeometryConversionError.invalidInput("Original ruled support requires both complete finite rails.")
    }
  }

  func intervalJet(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try parameters.validateAssumingSurfaceValidated(
      for: .procedural(.ruled(surface)),
      tolerance: tolerance
    )
    let startJet = try startBoundary.thirdOrderIntervalJet(
      over: parameters.u,
      tolerance: tolerance
    )
    let endJet = try endBoundary.thirdOrderIntervalJet(
      over: parameters.u,
      tolerance: tolerance
    )
    return startJet + ((endJet + (-startJet)) * .parameterV(parameters.v))
  }

  func intervalJet(overClosedBox parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    func enclosed(_ prepared: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
      let result = try prepared.closedNativeJets(over: parameters.u, tolerance: tolerance, consumeWork: {})
      guard let first = result.spans.first else {
        throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "An original ruled closed query has no owning rail range.")
      }
      return result.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
    }
    let start = try enclosed(startBoundary), end = try enclosed(endBoundary)
    return start + (end + (-start)) * .parameterV(parameters.v)
  }

  func intervalJet(overClosedBox parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
    guard parameters.u.lower <= parameters.u.upper, parameters.v.lower >= 0,
          parameters.v.upper <= 1,
          try surface.uDomain.containsSpan(from: parameters.u.lower, to: parameters.u.upper, tolerance: tolerance) else {
      throw GeometryConversionError.invalidInput("Original ruled query exceeds its complete closed parameter domain.")
    }
    func enclosed(_ prepared: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
      let result = try prepared.closedNativeJets(over: parameters.u, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      guard let first = result.spans.first else {
        throw GeometryConversionError.invalidInput("Original ruled query has no retained owning rail range.")
      }
      var hull = first.jet
      for span in result.spans.dropFirst() { try consumeWork(); hull = hull.union(span.jet) }
      return hull
    }
    let start = try enclosed(startBoundary), end = try enclosed(endBoundary)
    return start + (end + (-start)) * .parameterV(parameters.v)
  }

}
