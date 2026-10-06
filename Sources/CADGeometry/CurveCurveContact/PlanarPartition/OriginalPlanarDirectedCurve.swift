import CADCore

/// One original directed native trim in a closed planar contour.
public struct OriginalPlanarDirectedCurve: Sendable {
    public let curve: BSplineCurve3D
    public let parameters: ScalarInterval
    public let isReversed: Bool

    public init(curve: BSplineCurve3D, parameters: ScalarInterval, isReversed: Bool) {
        self.curve = curve; self.parameters = parameters; self.isReversed = isReversed
    }
}
