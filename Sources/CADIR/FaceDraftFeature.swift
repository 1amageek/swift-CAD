import CADCore

public struct FaceDraftFeature: Codable, Hashable, Sendable {
    public var target: FaceDraftTargetReference
    public var facePersistentNames: [PersistentName]
    public var neutralFacePersistentName: PersistentName
    public var angle: CADExpression

    public init(
        target: FaceDraftTargetReference,
        facePersistentNames: [PersistentName],
        neutralFacePersistentName: PersistentName,
        angle: CADExpression
    ) {
        self.target = target
        self.facePersistentNames = facePersistentNames
        self.neutralFacePersistentName = neutralFacePersistentName
        self.angle = angle
    }

    public func validate() throws {
        try target.validate()
        guard facePersistentNames.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Draft requires at least one face target.")
        }
        var seen: Set<PersistentName> = []
        for name in facePersistentNames {
            try name.validate()
            guard seen.insert(name).inserted else {
                throw FeatureEvaluationError.invalidGraph("Face Draft targets must be unique.")
            }
        }
        try neutralFacePersistentName.validate()
        guard seen.contains(neutralFacePersistentName) == false else {
            throw FeatureEvaluationError.invalidGraph("Face Draft neutral face must be distinct from target faces.")
        }
        try angle.validateLiteralQuantities()
    }
}

public struct FaceDraftTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}
