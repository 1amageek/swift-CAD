import CADCore

/// One original source partition after all caller-provided contact cuts merge.
public struct OriginalPlanarCurveMergedPartition: Sendable {
  public let source: BSplineCurve3D
  public let parameters: ScalarInterval
  public let tolerance: ModelingTolerance
  public let cuts: [OriginalPlanarCurveMergedCut]
  public let segments: [OriginalPlanarCurveContactSegment]

  package init(
    source: BSplineCurve3D, parameters: ScalarInterval, tolerance: ModelingTolerance,
    cuts: [OriginalPlanarCurveMergedCut], segments: [OriginalPlanarCurveContactSegment]
  ) {
    self.source = source
    self.parameters = parameters
    self.tolerance = tolerance
    self.cuts = cuts
    self.segments = segments
  }
}
