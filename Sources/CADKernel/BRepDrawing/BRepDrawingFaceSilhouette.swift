import CADCore
import CADGeometry

/// Original source graph provenance; trimmed drawing spans are published separately.
public struct BRepDrawingFaceSilhouette: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let original: SurfaceSilhouetteEnvelope
}
