/// A positive original source interval between two consecutive exact cuts.
public struct OriginalPlanarCurveContactSegment: Sendable {
    public let lowerCutIndex: Int
    public let upperCutIndex: Int
    public let originalSpan: OriginalCurveRootSpan3D

    package init(lowerCutIndex: Int, upperCutIndex: Int, originalSpan: OriginalCurveRootSpan3D) {
        self.lowerCutIndex = lowerCutIndex; self.upperCutIndex = upperCutIndex
        self.originalSpan = originalSpan
    }
}
