import CADGeometry

/// One whole authored directed native Bezier law with stable contour incidence.
public struct OriginalPlanarContourSegment: Sendable {
    public let id: UInt64
    public let startVertexID: UInt64
    public let endVertexID: UInt64
    public let curve: BSplineCurve3D
    public let reversed: Bool

    public init(id: UInt64, startVertexID: UInt64, endVertexID: UInt64,
        curve: BSplineCurve3D, reversed: Bool = false) {
        self.id = id; self.startVertexID = startVertexID; self.endVertexID = endVertexID
        self.curve = curve; self.reversed = reversed
    }
}
