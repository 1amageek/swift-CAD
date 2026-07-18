import CADCore

public struct BooleanFacePairCandidate: Codable, Hashable, Sendable {
    public let targetFaceID: FaceID
    public let toolFaceID: FaceID

    public init(targetFaceID: FaceID, toolFaceID: FaceID) {
        self.targetFaceID = targetFaceID
        self.toolFaceID = toolFaceID
    }
}
