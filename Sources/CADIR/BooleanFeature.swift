import CADCore
import CADGeometry

/// Combines target bodies with tool bodies. The tools act together as one region, their union;
/// the result lives in the frame of the operands without a placement.
public struct BooleanFeature: Hashable, Sendable {
    public var targets: [BooleanTargetReference]
    public var tools: [BooleanToolReference]
    public var operation: BooleanOperation
    /// Keeps every tool body, where it was evaluated, beside the result.
    public var keepTools: Bool

    public init(
        targets: [BooleanTargetReference],
        tools: [BooleanToolReference],
        operation: BooleanOperation,
        keepTools: Bool = false
    ) {
        self.targets = targets
        self.tools = tools
        self.operation = operation
        self.keepTools = keepTools
    }

    public func validate() throws {
        guard targets.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Boolean features require at least one target body.")
        }
        guard tools.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Boolean features require at least one tool body.")
        }
        let targetFeatureIDs = targets.map(\.featureID)
        guard Set(targetFeatureIDs).count == targetFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean target references must be unique.")
        }
        let toolFeatureIDs = tools.map(\.featureID)
        guard Set(toolFeatureIDs).count == toolFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean tool references must be unique.")
        }
        guard Set(targetFeatureIDs).isDisjoint(with: toolFeatureIDs) else {
            throw FeatureEvaluationError.invalidGraph("Boolean tool must be distinct from every target.")
        }
    }
}

extension BooleanFeature: Codable {
    private enum CodingKeys: String, CodingKey {
        case targets, tools, operation, keepTools
        // The single-tool form written before `tools`.
        case tool, toolPlacement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decode([BooleanTargetReference].self, forKey: .targets)
        operation = try container.decode(BooleanOperation.self, forKey: .operation)
        keepTools = try container.decode(Bool.self, forKey: .keepTools)
        if container.contains(.tools) {
            try container.validateOnlyExpectedKeys([.targets, .tools, .operation, .keepTools], in: decoder)
            tools = try container.decode([BooleanToolReference].self, forKey: .tools)
        } else {
            try container.validateOnlyExpectedKeys([.targets, .tool, .toolPlacement, .operation, .keepTools], in: decoder)
            var tool = try container.decode(BooleanToolReference.self, forKey: .tool)
            tool.placement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .toolPlacement)
            tools = [tool]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targets, forKey: .targets)
        try container.encode(tools, forKey: .tools)
        try container.encode(operation, forKey: .operation)
        try container.encode(keepTools, forKey: .keepTools)
    }
}

public struct BooleanTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    /// Where the target body sits in the result's frame: it is moved rigidly there before
    /// combining; `nil` combines it where it was evaluated.
    public var placement: RigidTransform3D?

    public init(featureID: FeatureID, placement: RigidTransform3D? = nil) {
        self.featureID = featureID
        self.placement = placement
    }

    public func validate() throws {}
}

public struct BooleanToolReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    /// Where the tool body sits in the result's frame: a copy moved rigidly there is combined;
    /// `nil` combines the tool where it was evaluated.
    public var placement: RigidTransform3D?

    public init(featureID: FeatureID, placement: RigidTransform3D? = nil) {
        self.featureID = featureID
        self.placement = placement
    }

    public func validate() throws {}
}

public enum BooleanOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case union
    case difference
    case intersect
    case slice
}
