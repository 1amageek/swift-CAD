import CADCore
import CADGeometry
import CADTopology

/// Match Face: faces of one body take the surface of a reference face, and the faces around them
/// are re-solved to meet them. The reference face may lie on the target itself or on another
/// body, `sourcePlacement` putting that body in the target's frame (where it is, when nil). With
/// `front`, each matched face faces out the way the reference face does; otherwise it keeps the
/// side it faced.
public struct FaceMatchFeature: Hashable, Sendable {
    public var target: PatternTargetReference
    public var faces: [StableSubshapeReference]
    public var source: PatternTargetReference
    public var referenceFace: StableSubshapeReference
    public var sourcePlacement: RigidTransform3D?
    public var front: Bool
    public var grow: FaceEditGrow

    public init(
        target: PatternTargetReference,
        faces: [StableSubshapeReference],
        source: PatternTargetReference,
        referenceFace: StableSubshapeReference,
        sourcePlacement: RigidTransform3D? = nil,
        front: Bool = false,
        grow: FaceEditGrow = .moving
    ) {
        self.target = target
        self.faces = faces
        self.source = source
        self.referenceFace = referenceFace
        self.sourcePlacement = sourcePlacement
        self.front = front
        self.grow = grow
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try source.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Match Face requires at least one face.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try execution.consumeWork(1)
            try face.validate(using: &execution)
            try face.chargeStructuralComparison(using: &execution)
            guard (try OriginalParameterQueryStorage.insert(face, in: &seen, using: &execution)) else {
                throw FeatureEvaluationError.invalidGraph("Match Face faces must be unique.")
            }
        }
        try referenceFace.validate(using: &execution)
        try referenceFace.chargeStructuralComparison(using: &execution)
        try execution.consumeWork(1)
        guard seen.contains(referenceFace) == false else {
            throw FeatureEvaluationError.invalidGraph("Match Face cannot match a face to itself.")
        }
        guard source.featureID != target.featureID || sourcePlacement == nil else {
            throw FeatureEvaluationError.invalidGraph("Match Face places only a reference face of another body.")
        }

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target, faces, source, referenceFace, sourcePlacement, front, grow
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .faces, .source, .referenceFace, .sourcePlacement, .front, .grow], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        source = try container.decode(PatternTargetReference.self, forKey: .source)
        referenceFace = try container.decode(StableSubshapeReference.self, forKey: .referenceFace)
        sourcePlacement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .sourcePlacement)
        front = try container.decode(Bool.self, forKey: .front)
        grow = try container.decode(FaceEditGrow.self, forKey: .grow)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(source, forKey: .source)
        try container.encode(referenceFace, forKey: .referenceFace)
        try container.encodeIfPresent(sourcePlacement, forKey: .sourcePlacement)
        try container.encode(front, forKey: .front)
        try container.encode(grow, forKey: .grow)
    }
#endif

    func validationInputs(using execution: inout OriginalQueryExecution) throws -> [FeatureInput] {
        try execution.consumeWork(1)
        var inputs: [FeatureInput] = []
        try OriginalParameterQueryStorage.append(FeatureInput(featureID: target.featureID, role: .target),
            to: &inputs, using: &execution)
        if source.featureID != target.featureID {
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: source.featureID, role: .body),
                to: &inputs, using: &execution)
        }
        try execution.checkpoint()
        return inputs
    }

    /// The inputs the feature reads: its target, and the reference face's body when that is
    /// another.
    public var inputs: [FeatureInput] {
        var inputs = [FeatureInput(featureID: target.featureID, role: .target)]
        if source.featureID != target.featureID { inputs.append(FeatureInput(featureID: source.featureID, role: .body)) }
        return inputs
    }
}

#if !hasFeature(Embedded)
extension FaceMatchFeature: Codable {}
#endif
