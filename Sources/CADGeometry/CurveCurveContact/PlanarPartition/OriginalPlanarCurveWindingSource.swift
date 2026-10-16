import CADCore

/// Once-admitted original closed contours and retained exact native laws.
public struct OriginalPlanarCurveWindingSource: Sendable {
  public let contours: [[OriginalPlanarDirectedCurve]]
  public let plane: Plane3D
  public let tolerance: ModelingTolerance
  package let owners: [OriginalPlanarWindingNativeOwner]

  package init(
    contours: [[OriginalPlanarDirectedCurve]], plane: Plane3D,
    tolerance: ModelingTolerance, owners: [OriginalPlanarWindingNativeOwner]
  ) {
    self.contours = contours
    self.plane = plane
    self.tolerance = tolerance
    self.owners = owners
  }
}
