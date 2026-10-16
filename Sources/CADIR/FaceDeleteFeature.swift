import CADCore
import CADGeometry
import CADTopology

/// Delete Face: faces taken out of a solid. Healing, the faces around them grow over where they
/// were until they meet and the solid stays closed; otherwise the solid opens into a sheet.
public struct FaceDeleteFeature: Hashable, Sendable {
    public var target: FaceDeleteTargetReference
    public var faces: [StableSubshapeReference]
    public var heals: Bool

    public init(
        target: FaceDeleteTargetReference,
        faces: [StableSubshapeReference],
        heals: Bool = false
    ) {
        self.target = target
        self.faces = faces
        self.heals = heals
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate(using: &execution)
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Delete requires at least one face target.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try execution.consumeWork(1)
            try face.validate(using: &execution)
            try face.chargeStructuralComparison(using: &execution)
            guard (try OriginalParameterQueryStorage.insert(face, in: &seen, using: &execution)) else {
                throw FeatureEvaluationError.invalidGraph("Face Delete targets must be unique.")
            }
        }

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case faces
        case heals
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .faces, .heals], in: decoder)
        target = try container.decode(FaceDeleteTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        heals = try container.decode(Bool.self, forKey: .heals)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(heals, forKey: .heals)
    }
#endif

    /// What the deletion publishes: the healed solid, or the sheet it opens into.
    public var outputRole: FeaturePort { heals ? .body : .sheet }
}

public struct FaceDeleteTargetReference: Hashable, Sendable {
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
extension FaceDeleteFeature: Codable {}
extension FaceDeleteTargetReference: Codable {}
#endif
