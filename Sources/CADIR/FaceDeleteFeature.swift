import CADCore

public struct FaceDeleteFeature: Codable, Hashable, Sendable {
    public var target: FaceDeleteTargetReference
    public var facePersistentNames: [PersistentName]

    public init(
        target: FaceDeleteTargetReference,
        facePersistentNames: [PersistentName]
    ) {
        self.target = target
        self.facePersistentNames = facePersistentNames
    }

    public func validate() throws {
        try target.validate()
        guard facePersistentNames.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Delete requires at least one face target.")
        }
        var seen: Set<PersistentName> = []
        for name in facePersistentNames {
            try name.validate()
            guard seen.insert(name).inserted else {
                throw FeatureEvaluationError.invalidGraph("Face Delete targets must be unique.")
            }
        }
    }
}

public struct FaceDeleteTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}
