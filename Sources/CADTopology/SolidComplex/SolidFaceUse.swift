import CADCore

/// A boundary face in the namespace and ownership of one solid cell.
public struct SolidFaceUse: Equatable, Hashable, Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID

    public init(bodyID: BodyID, faceID: FaceID) {
        self.bodyID = bodyID
        self.faceID = faceID
    }
}
