import CADCore

public struct EdgeOffsetFeature: Codable, Hashable, Sendable {
    public var target: EdgeOffsetTargetReference
    public var edgePersistentName: PersistentName
    public var supportFacePersistentName: PersistentName
    public var distance: CADExpression
    public var isSymmetric: Bool
    public var gapFill: EdgeOffsetGapFill

    public init(
        target: EdgeOffsetTargetReference,
        edgePersistentName: PersistentName,
        supportFacePersistentName: PersistentName,
        distance: CADExpression,
        isSymmetric: Bool = false,
        gapFill: EdgeOffsetGapFill = .round
    ) {
        self.target = target
        self.edgePersistentName = edgePersistentName
        self.supportFacePersistentName = supportFacePersistentName
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.gapFill = gapFill
    }

    public func validate() throws {
        try target.validate()
        try edgePersistentName.validate()
        try supportFacePersistentName.validate()
        try distance.validateLiteralQuantities()
    }
}

public struct EdgeOffsetTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public enum EdgeOffsetGapFill: String, Codable, CaseIterable, Hashable, Sendable {
    case round
    case linear
    case natural
}
