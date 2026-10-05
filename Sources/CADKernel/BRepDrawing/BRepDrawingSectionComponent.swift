import CADCore
import CADTopology

/// A complete source-face section component, including zero- and two-dimensional contact.
public struct BRepDrawingSectionComponent: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let materialID: MaterialID?
    public let ordinal: Int
    public let geometry: BooleanFaceSplitComponentGeometry
}
