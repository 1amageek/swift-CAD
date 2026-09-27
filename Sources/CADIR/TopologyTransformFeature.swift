import CADCore

/// Moves faces, edges and vertices of one body together by one motion: every vertex they bound
/// moves once, so targets that share vertices move consistently.
public struct TopologyTransformFeature: Codable, Hashable, Sendable {
    public let target: TopologyTransformTargetReference
    public let subshapes: [StableSubshapeReference]
    public let motion: TopologyMotion

    public init(
        target: TopologyTransformTargetReference,
        subshapes: [StableSubshapeReference],
        motion: TopologyMotion
    ) {
        self.target = target
        self.subshapes = subshapes
        self.motion = motion
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try target.validate()
        guard !subshapes.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Topology Transform requires at least one face, edge or vertex.")
        }
        guard subshapes.count <= 4_096 else {
            throw FeatureEvaluationError.invalidGraph("Topology Transform exceeds 4096 targets.")
        }
        var seen = Set<StableSubshapeReference>()
        for subshape in subshapes {
            try subshape.validate()
            guard seen.insert(subshape).inserted else {
                throw FeatureEvaluationError.invalidGraph("Topology Transform targets must be unique.")
            }
        }
        try motion.validate(tolerance: tolerance)
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case subshapes
        case motion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .subshapes, .motion], in: decoder)
        target = try container.decode(TopologyTransformTargetReference.self, forKey: .target)
        subshapes = try container.decode([StableSubshapeReference].self, forKey: .subshapes)
        motion = try container.decode(TopologyMotion.self, forKey: .motion)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(subshapes, forKey: .subshapes)
        try container.encode(motion, forKey: .motion)
    }
}
