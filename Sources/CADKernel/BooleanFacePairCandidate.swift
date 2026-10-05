import CADCore

public struct BooleanFacePairCandidate: Hashable, Sendable {
    public let targetFaceID: FaceID
    public let toolFaceID: FaceID

    public init(targetFaceID: FaceID, toolFaceID: FaceID) {
        self.targetFaceID = targetFaceID
        self.toolFaceID = toolFaceID
    }
}

#if !hasFeature(Embedded)
extension BooleanFacePairCandidate: Codable {}
#endif
