import CADCore

public struct FaceKnifeFeature: Codable, Hashable, Sendable {
    public var target: FaceKnifeTargetReference
    public var facePersistentName: PersistentName
    public var loop: [Point3D]

    public init(
        target: FaceKnifeTargetReference,
        facePersistentName: PersistentName,
        loop: [Point3D]
    ) {
        self.target = target
        self.facePersistentName = facePersistentName
        self.loop = loop
    }

    public func validate() throws {
        try target.validate()
        try facePersistentName.validate()
        guard loop.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph("Face Knife requires at least three loop points.")
        }
        for point in loop {
            try point.validate()
        }
    }
}

public struct FaceKnifeTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}
