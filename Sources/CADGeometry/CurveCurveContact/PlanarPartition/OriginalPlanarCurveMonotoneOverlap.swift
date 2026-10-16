/// Complete paired source segments with exact native parameter orientation.
public struct OriginalPlanarCurveMonotoneOverlap: Sendable {
  public let firstSegmentIndex: Int
  public let secondSegmentIndex: Int
  /// +1 for equal native parameter direction, -1 for opposed direction.
  public let direction: Int
  public let firstSpan: OriginalCurveRootSpan3D
  public let secondSpan: OriginalCurveRootSpan3D

  package init(
    firstSegmentIndex: Int, secondSegmentIndex: Int, direction: Int,
    firstSpan: OriginalCurveRootSpan3D, secondSpan: OriginalCurveRootSpan3D
  ) {
    self.firstSegmentIndex = firstSegmentIndex
    self.secondSegmentIndex = secondSegmentIndex
    self.direction = direction
    self.firstSpan = firstSpan
    self.secondSpan = secondSpan
  }
}
