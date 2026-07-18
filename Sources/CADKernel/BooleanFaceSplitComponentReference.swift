import CADCore

public struct BooleanFaceSplitComponentReference: Codable, Hashable, Sendable, Comparable {
    public let facePair: BooleanFacePairCandidate
    public let componentID: BooleanFaceSplitComponentID

    public init(
        facePair: BooleanFacePairCandidate,
        componentID: BooleanFaceSplitComponentID
    ) {
        self.facePair = facePair
        self.componentID = componentID
    }

    public static func < (
        lhs: BooleanFaceSplitComponentReference,
        rhs: BooleanFaceSplitComponentReference
    ) -> Bool {
        if lhs.facePair.targetFaceID != rhs.facePair.targetFaceID {
            return lhs.facePair.targetFaceID < rhs.facePair.targetFaceID
        }
        if lhs.facePair.toolFaceID != rhs.facePair.toolFaceID {
            return lhs.facePair.toolFaceID < rhs.facePair.toolFaceID
        }
        return lhs.componentID < rhs.componentID
    }
}
