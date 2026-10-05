import CADCore
import CADGeometry
import CADTopology

/// One isolated original contact admitted by the actual trimmed source face.
public struct BRepDrawingSilhouetteContact: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let source: SurfaceSilhouetteContact
    public let projectedEnclosure: CoordinateEnclosure2D
}
