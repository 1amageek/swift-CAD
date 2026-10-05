/// One authored closed directed contour; material composition uses nonzero winding.
public struct OriginalPlanarContour: Sendable {
    public let id: UInt64
    public let segments: [OriginalPlanarContourSegment]

    public init(id: UInt64, segments: [OriginalPlanarContourSegment]) {
        self.id = id; self.segments = segments
    }
}
