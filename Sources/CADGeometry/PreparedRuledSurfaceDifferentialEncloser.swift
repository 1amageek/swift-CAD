import CADCore

/// Reuses both immutable boundary-curve representations of one ruled surface.
struct PreparedRuledSurfaceDifferentialEncloser: Sendable {
  let surface: RuledSurface3D
  private let startBoundary: PreparedCurveDifferentialEncloser
  private let endBoundary: PreparedCurveDifferentialEncloser

  init(
    surface: RuledSurface3D,
    tolerance: ModelingTolerance
  ) throws {
    try surface.validate(tolerance: tolerance)
    self.surface = surface
    startBoundary = try PreparedCurveDifferentialEncloser(
      curve: surface.startBoundary,
      tolerance: tolerance
    )
    endBoundary = try PreparedCurveDifferentialEncloser(
      curve: surface.endBoundary,
      tolerance: tolerance
    )
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
}
