import CADCore
import CADGeometry

/// True zero/nonzero material transitions, with material to the left of every use.
public struct OriginalPlanarNonzeroBoundary: Sendable {
    public struct Use: Sendable {
        public let span: OriginalCurveRootSpan3D
        public let forward: Bool
        public let sourceSegmentID: UInt64
        public let winding: OriginalPlanarCurveSideWinding
    }
    public struct Loop: Sendable {
        public let uses: [Use]
    }
    public let plane: Plane3D
    public let source: PreparedOriginalPlanarContourContacts
    public let loops: [Loop]
}
