import CADCore
import CADGeometry
import CADTopology

/// An original algebraic contact admitted by the complete trimmed source face.
public struct BRepDrawingSilhouetteAlgebraicContact: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let source: SurfaceSilhouetteAlgebraicContact
    public let projectedEnclosure: CoordinateEnclosure2D
}
