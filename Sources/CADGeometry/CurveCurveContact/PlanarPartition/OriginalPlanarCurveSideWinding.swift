import CADCore

/// Exact adjacent-sector seeds and global original nonzero winding authority.
public struct OriginalPlanarCurveSideWinding: Sendable {
  public struct Seed: Sendable {
    /// Coordinates use the retained cyclic native projection axes.
    public let firstCoordinate: ExactRationalCoefficient
    public let secondCoordinate: ExactRationalCoefficient
    public let winding: Int
  }
  public let span: OriginalCurveRootSpan3D
  public let plane: Plane3D
  public let contours: [[OriginalPlanarDirectedCurve]]
  public let forward: Bool
  public let firstAxis: Int
  public let secondAxis: Int
  public let left: Seed
  public let right: Seed

  package init(
    span: OriginalCurveRootSpan3D, plane: Plane3D,
    contours: [[OriginalPlanarDirectedCurve]], forward: Bool,
    axes: (Int, Int), left: Seed, right: Seed
  ) {
    self.span = span
    self.plane = plane
    self.contours = contours
    self.forward = forward
    firstAxis = axes.0
    secondAxis = axes.1
    self.left = left
    self.right = right
  }
}
