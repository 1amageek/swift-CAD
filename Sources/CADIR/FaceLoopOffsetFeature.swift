import CADCore

public struct FaceLoopOffsetFeature: Codable, Hashable, Sendable {
    public var target: FaceLoopOffsetTargetReference
    public var facePersistentName: PersistentName
    public var distance: CADExpression
    public var gapFill: FaceLoopOffsetGapFill

    public init(
        target: FaceLoopOffsetTargetReference,
        facePersistentName: PersistentName,
        distance: CADExpression,
        gapFill: FaceLoopOffsetGapFill = .round
    ) {
        self.target = target
        self.facePersistentName = facePersistentName
        self.distance = distance
        self.gapFill = gapFill
    }

    public func validate() throws {
        try target.validate()
        try facePersistentName.validate()
        try distance.validateLiteralQuantities()
    }
}

public struct FaceLoopOffsetTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public enum FaceLoopOffsetGapFill: String, Codable, CaseIterable, Hashable, Sendable {
    case round
    case linear
    case natural
}
