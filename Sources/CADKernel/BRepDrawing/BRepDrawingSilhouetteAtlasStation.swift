import CADCore
import CADGeometry

/// Retains original atlas incidence and the contact used for complete trimmed-face admission.
public struct BRepDrawingSilhouetteAtlasStation: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let atlasOrdinal: Int
    public let stationOrdinal: Int
    public let source: SurfaceSilhouettePlaneAtlas.Station
    public let admittedContact: SurfaceSilhouetteAlgebraicContact
    public let projectedEnclosure: CoordinateEnclosure2D
}
