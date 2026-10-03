import CADCore
import CADGeometry
import CADTopology

/// Edges on a target where tool solids or sheets cross it (Imprint Body Body): every face of the
/// target a tool's faces cross is split along the crossing, both sides kept, and the tools stay as
/// they are. Each tool crosses the target where its placement puts it. With `completion` `.edge`, a
/// crossing that ends inside a face is carried on along its own direction on the face until it
/// meets an edge or another crossing of the same tool, so one tool's lines cross another's.
public struct ImprintBodyFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var tools: [ImprintBodyTool]
    public var completion: ImprintCompletion

    public init(target: PatternTargetReference, tools: [ImprintBodyTool], completion: ImprintCompletion) {
        self.target = target
        self.tools = tools
        self.completion = completion
    }

    public func validate() throws {
        try target.validate()
        let features = tools.map(\.body.featureID)
        guard features.isEmpty == false, Set(features).count == features.count, features.contains(target.featureID) == false else {
            throw FeatureEvaluationError.invalidGraph("Imprint needs one or more distinct tools other than its target.")
        }
        for tool in tools { try tool.body.validate() }
    }

    private enum CodingKeys: String, CodingKey {
        case target, tools, completion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .tools, .completion], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        tools = try container.decode([ImprintBodyTool].self, forKey: .tools)
        completion = try container.decode(ImprintCompletion.self, forKey: .completion)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(tools, forKey: .tools)
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
