import CADCore
import CADTopology

/// Edges on a target where a tool solid or sheet crosses it (Imprint Body Body): every face of
/// the target the tool's faces cross is split along the crossing, both sides kept, and the tool
/// stays as it is. With `completion` `.edge`, a crossing that ends inside a face is carried on
/// along its own direction on the face until it meets an edge.
public struct ImprintBodyFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var tool: PatternTargetReference
    public var completion: ImprintCompletion

    public init(target: PatternTargetReference, tool: PatternTargetReference, completion: ImprintCompletion) {
        self.target = target
        self.tool = tool
        self.completion = completion
    }

    public func validate() throws {
        try target.validate()
        try tool.validate()
        guard target.featureID != tool.featureID else {
            throw FeatureEvaluationError.invalidGraph("Imprint needs a tool other than its target.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target, tool, completion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .tool, .completion], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        tool = try container.decode(PatternTargetReference.self, forKey: .tool)
        completion = try container.decode(ImprintCompletion.self, forKey: .completion)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(tool, forKey: .tool)
        try container.encode(completion, forKey: .completion)
    }
}

/// How an imprinted curve that ends inside a face is completed.
public enum ImprintCompletion: String, Codable, Hashable, Sendable {
    /// It is not: every curve must reach an edge, another curve, or close on itself.
    case none
    /// Each end inside a face carries on along the curve's direction on the face until it meets
    /// an edge or another imprinted curve.
    case edge
    /// Each end inside a face carries on along the curve's direction on the face until it meets
    /// the face's own boundary, crossing any other imprinted curve on the way.
    case boundary
}
