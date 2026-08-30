import CADCore

/// Internal proof record used while a regular intersection component is being
/// traced and covered. It stores exact chart anchors and constructs one
/// validated public graph cell that the completed atlas retains.
struct ParametricSurfaceIntersectionGraphCellRecord: Sendable {
  let parameterBox: SurfaceIntersectionParameterBox
  let freeParameter: SurfaceIntersectionParameterCoordinate
  let lowerAnchor: SurfaceIntersectionParameterPair
  let midpointAnchor: SurfaceIntersectionParameterPair
  let upperAnchor: SurfaceIntersectionParameterPair

  func cell(
    direction: CertifiedImplicitIntersectionDirection,
    first: Surface3D,
    second: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionGraphCell {
    try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox,
      freeParameter: freeParameter,
      direction: direction,
      lowerAnchor: lowerAnchor,
      midpointAnchor: midpointAnchor,
      upperAnchor: upperAnchor,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
  }

  func cell(
    direction: CertifiedImplicitIntersectionDirection,
    first: PreparedSurfaceDifferentialEncloser,
    second: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionGraphCell {
    try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox,
      freeParameter: freeParameter,
      direction: direction,
      lowerAnchor: lowerAnchor,
      midpointAnchor: midpointAnchor,
      upperAnchor: upperAnchor,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
  }
}
