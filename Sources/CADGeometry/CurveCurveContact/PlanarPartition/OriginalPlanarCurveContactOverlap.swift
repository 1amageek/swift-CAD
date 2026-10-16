import CADCore

/// Complete correspondence authority within one original closed owner pair.
public struct OriginalPlanarCurveContactOverlap: Sendable {
  public let firstSpan: OriginalCurveRootSpan3D
  public let secondSpan: OriginalCurveRootSpan3D
  public let factor: ExactBivariatePolynomial
  public let coversAllParameterPairs: Bool
  public let events: [OriginalPlanarCurveContactEvent]
  package let originalProjection: OriginalRationalPlaneCurveProjection?
  package let oppositeAxisProjection: OriginalRationalPlaneCurveProjection?
  package let originalAtlas: OriginalRationalPlaneCurveAtlas?

  package init(
    firstSpan: OriginalCurveRootSpan3D, secondSpan: OriginalCurveRootSpan3D,
    factor: ExactBivariatePolynomial, coversAllParameterPairs: Bool,
    events: [OriginalPlanarCurveContactEvent], projection: OriginalRationalPlaneCurveProjection?,
    atlas: OriginalRationalPlaneCurveAtlas?,
    oppositeAxisProjection: OriginalRationalPlaneCurveProjection?
  ) {
    self.firstSpan = firstSpan
    self.secondSpan = secondSpan
    self.factor = factor
    self.coversAllParameterPairs = coversAllParameterPairs
    self.events = events
    originalProjection = projection
    originalAtlas = atlas
    self.oppositeAxisProjection = oppositeAxisProjection
  }
}
