import CADCore
import CADTopology

/// Edges on a target where curves project onto it (Imprint Curve Body): each curve is projected
/// onto the target's faces, which are split along the projection, both sides kept.
public struct ImprintCurvesFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var curves: [CurveOutputReference]
    public var projection: ImprintProjection
    public var completion: ImprintCompletion

    public init(
        target: PatternTargetReference,
        curves: [CurveOutputReference],
        projection: ImprintProjection,
        completion: ImprintCompletion
    ) {
        self.target = target
        self.curves = curves
        self.projection = projection
        self.completion = completion
    }

    public func validate() throws {
        try target.validate()
        guard curves.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Imprint needs at least one curve.")
        }
        for curve in curves { try curve.validate() }
        guard Set(curves).count == curves.count else {
            throw FeatureEvaluationError.invalidGraph("Imprint curves must be distinct.")
        }
        try projection.validate()
    }

    /// The curves' sources as graph inputs, each once.
    public var curveInputs: [FeatureInput] {
        var seen = Set<FeatureID>()
        return curves.compactMap { seen.insert($0.featureID).inserted ? FeatureInput(featureID: $0.featureID, role: .curve) : nil }
    }

    private enum CodingKeys: String, CodingKey {
        case target, curves, projection, completion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .curves, .projection, .completion], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        curves = try container.decode([CurveOutputReference].self, forKey: .curves)
        projection = try container.decode(ImprintProjection.self, forKey: .projection)
        completion = try container.decode(ImprintCompletion.self, forKey: .completion)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(curves, forKey: .curves)
        try container.encode(projection, forKey: .projection)
        try container.encode(completion, forKey: .completion)
    }
}

/// How a curve reaches the target it is imprinted on.
public enum ImprintProjection: Hashable, Sendable {
    /// Each point of the curve goes to the closest point of the target's faces, along their
    /// normal there.
    case normal
    /// The curve is swept along `direction` (both ways when `bidirectional`) and imprinted where
    /// the sweep crosses the target; hiding occlusion keeps only what is seen first from the curve.
    case vector(direction: Vector3D, bidirectional: Bool, hidesOcclusion: Bool)

    public func validate() throws {
        guard case let .vector(direction, _, _) = self else { return }
        guard direction.isFinite, direction.length > 1e-12 else {
            throw FeatureEvaluationError.invalidGraph("An imprint direction must be a finite, nonzero vector.")
        }
    }
}

extension ImprintProjection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, direction, bidirectional, hidesOcclusion
    }

    private enum Kind: String, Codable {
        case normal, vector
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .normal:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .normal
        case .vector:
            try container.validateOnlyExpectedKeys([.kind, .direction, .bidirectional, .hidesOcclusion], in: decoder)
            self = .vector(
                direction: try container.decode(Vector3D.self, forKey: .direction),
                bidirectional: try container.decode(Bool.self, forKey: .bidirectional),
                hidesOcclusion: try container.decode(Bool.self, forKey: .hidesOcclusion)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .normal:
            try container.encode(Kind.normal, forKey: .kind)
        case let .vector(direction, bidirectional, hidesOcclusion):
            try container.encode(Kind.vector, forKey: .kind)
            try container.encode(direction, forKey: .direction)
            try container.encode(bidirectional, forKey: .bidirectional)
            try container.encode(hidesOcclusion, forKey: .hidesOcclusion)
        }
    }
}
