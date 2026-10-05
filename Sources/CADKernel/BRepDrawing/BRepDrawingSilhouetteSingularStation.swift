import CADCore
import CADGeometry

/// A retained original singular curve incidence inside the actual source face trim.
public struct BRepDrawingSilhouetteSingularStation: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let source: SurfaceSilhouetteSingularStation
    public let projectedEnclosure: CoordinateEnclosure2D
}
