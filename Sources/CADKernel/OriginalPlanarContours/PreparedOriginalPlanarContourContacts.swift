import CADCore
import CADGeometry

/// Global original contact preparation; this value does not assert filled regions.
public struct PreparedOriginalPlanarContourContacts: Sendable {
    public let contours: [OriginalPlanarContour]
    public let segments: [OriginalPlanarContourSegment]
    public let plane: Plane3D
    public let tolerance: ModelingTolerance
    public let pairs: [OriginalPlanarContourPairContact]
    public let sourceEndpointReferences: [[OriginalPlanarContourEndpointReference]]
    public let sourcePartitions: [OriginalPlanarCurveMergedPartition]

    package init(contours: [OriginalPlanarContour], segments: [OriginalPlanarContourSegment],
        plane: Plane3D, tolerance: ModelingTolerance, pairs: [OriginalPlanarContourPairContact],
        sourcePartitions: [OriginalPlanarCurveMergedPartition],
        sourceEndpointReferences: [[OriginalPlanarContourEndpointReference]]) {
        self.contours = contours; self.segments = segments; self.plane = plane
        self.sourceEndpointReferences = sourceEndpointReferences
        self.tolerance = tolerance; self.pairs = pairs; self.sourcePartitions = sourcePartitions
    }
}
