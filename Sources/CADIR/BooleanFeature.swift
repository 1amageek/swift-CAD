import CADCore
import CADGeometry

/// Combines target bodies with tool bodies, solids or sheets. The tools act together as one
/// region, their union; the result lives in the frame of the operands without a placement.
public struct BooleanFeature: Hashable, Sendable {
    public var targets: [BooleanTargetReference]
    public var tools: [BooleanToolReference]
    public var operation: BooleanOperation
    /// Keeps every tool body, where it was evaluated, beside the result.
    public var keepTools: Bool
    /// How the targets' material is taken.
    public var targetMaterial: BooleanMaterial
    /// How the tools' material is taken.
    public var toolMaterial: BooleanMaterial

    public init(
        targets: [BooleanTargetReference],
        tools: [BooleanToolReference],
        operation: BooleanOperation,
        keepTools: Bool = false,
        targetMaterial: BooleanMaterial = .default,
        toolMaterial: BooleanMaterial = .default
    ) {
        self.targets = targets
        self.tools = tools
        self.operation = operation
        self.keepTools = keepTools
        self.targetMaterial = targetMaterial
        self.toolMaterial = toolMaterial
    }

    /// The output the Boolean publishes, from what its targets are: a sheet when the targets'
    /// material is empty (Empty, or Default on sheets), otherwise a body. Targets are all solids
    /// or all sheets.
    public func resultPort(targetPorts: [FeaturePort]) throws -> FeaturePort {
        guard let first = targetPorts.first, targetPorts.allSatisfy({ $0 == first }),
              first == .body || first == .sheet else {
            throw FeatureEvaluationError.invalidGraph("Boolean targets must all be solids or all be sheets.")
        }
        switch targetMaterial {
        case .empty:
            return .sheet
        case .default:
            return first
        case .inside, .outside:
            return .body
        }
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
        case targets, tools, operation, keepTools, targetMaterial, toolMaterial
        // The single-tool form written before `tools`.
        case tool, toolPlacement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decode([BooleanTargetReference].self, forKey: .targets)
        operation = try container.decode(BooleanOperation.self, forKey: .operation)
        keepTools = try container.decode(Bool.self, forKey: .keepTools)
        // Booleans written before materials took every operand as it is.
        targetMaterial = try container.decodeIfPresent(BooleanMaterial.self, forKey: .targetMaterial) ?? .default
        toolMaterial = try container.decodeIfPresent(BooleanMaterial.self, forKey: .toolMaterial) ?? .default
        if container.contains(.tools) {
            try container.validateOnlyExpectedKeys(
                [.targets, .tools, .operation, .keepTools, .targetMaterial, .toolMaterial], in: decoder
            )
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
        try container.encode(targetMaterial, forKey: .targetMaterial)
        try container.encode(toolMaterial, forKey: .toolMaterial)
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

/// How a Boolean takes an operand's material.
public enum BooleanMaterial: String, Codable, CaseIterable, Hashable, Sendable {
    /// A solid's volume; a sheet tool facing solid targets takes the side behind its normals
    /// (as `inside`); any other sheet is an empty shell.
    case `default`
    /// An empty shell: no material, only its faces.
    case empty
    /// Solid behind its faces' normals: a solid's volume, the side behind a sheet.
    case inside
    /// Solid in front of its faces' normals: everything outside a solid, the side a sheet faces.
    case outside
}

/// The Materials of one Boolean pass.
public struct BooleanMaterials: Hashable, Sendable {
    public var target: BooleanMaterial
    public var tool: BooleanMaterial

    public init(target: BooleanMaterial = .default, tool: BooleanMaterial = .default) {
        self.target = target
        self.tool = tool
    }

    public static let `default` = BooleanMaterials()
}

public enum BooleanOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case union
    case difference
    case intersect
    case slice
}
