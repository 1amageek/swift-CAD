import CADCore

/// One exact original parameter pair used to partition both source curves.
public struct OriginalPlanarCurveContactEvent: Sendable {
  public let firstEndpoint: OriginalCurveRootEndpoint
  public let secondEndpoint: OriginalCurveRootEndpoint
  public let firstNativeSpanIndex: Int
  public let secondNativeSpanIndex: Int
  public let belongsToCommonFactor: Bool
  package let originalPair: ExactBivariateSystemRoot?
  package let originalPairAxesExchanged: Bool

  package init(
    firstEndpoint: OriginalCurveRootEndpoint, secondEndpoint: OriginalCurveRootEndpoint,
    firstNativeSpanIndex: Int, secondNativeSpanIndex: Int, belongsToCommonFactor: Bool,
    originalPair: ExactBivariateSystemRoot?, originalPairAxesExchanged: Bool = false
  ) {
    self.firstEndpoint = firstEndpoint
    self.secondEndpoint = secondEndpoint
    self.firstNativeSpanIndex = firstNativeSpanIndex
    self.secondNativeSpanIndex = secondNativeSpanIndex
    self.belongsToCommonFactor = belongsToCommonFactor
    self.originalPair = originalPair
    self.originalPairAxesExchanged = originalPairAxesExchanged
  }
}
