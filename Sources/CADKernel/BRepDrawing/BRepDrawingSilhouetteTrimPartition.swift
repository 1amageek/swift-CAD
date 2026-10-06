import CADTopology
import CADGeometry

/// Body/face/curve/boundary identity for a complete original lower trim partition.
public struct BRepDrawingSilhouetteTrimPartition: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let curveOrdinal: Int
    public let boundaryOrdinal: Int
    public let original: SurfaceSilhouetteTrimPartition
}
