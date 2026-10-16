import CADCore
import CADGeometry
import CADTopology

public struct FaceKnifeFeature: Hashable, Sendable {
    public var target: FaceKnifeTargetReference
    public var face: StableSubshapeReference
    public var loop: [Point3D]

    public init(
        target: FaceKnifeTargetReference,
        face: StableSubshapeReference,
        loop: [Point3D]
    ) {
        self.target = target
        self.face = face
        self.loop = loop
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate(using: &execution)
        try face.validate(using: &execution)
        guard loop.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph("Face Knife requires at least three loop points.")
        }
        for point in loop {
            try execution.consumeWork(1)
            try execution.consumeWork(1); try point.validate()
        }

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case face
        case loop
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .loop], in: decoder)
        target = try container.decode(FaceKnifeTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        loop = try container.decode([Point3D].self, forKey: .loop)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(loop, forKey: .loop)
    }
#endif
}

public struct FaceKnifeTargetReference: Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case featureID
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
    }
#endif
}

#if !hasFeature(Embedded)
extension FaceKnifeFeature: Codable {}
extension FaceKnifeTargetReference: Codable {}
#endif
