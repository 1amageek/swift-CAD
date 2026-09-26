import CADCore
import CADGeometry

public struct BooleanFeature: Codable, Hashable, Sendable {
    public var targets: [BooleanTargetReference]
    public var tool: BooleanToolReference
    public var operation: BooleanOperation
    public var keepTools: Bool
    /// Where the tool body sits in the targets' frame. A placed tool is moved rigidly onto the
    /// targets before combining and is consumed by the Boolean; `nil` combines the bodies where
    /// they were evaluated.
    public var toolPlacement: RigidTransform3D?

    public init(
        targets: [BooleanTargetReference],
        tool: BooleanToolReference,
        operation: BooleanOperation,
        keepTools: Bool = false,
        toolPlacement: RigidTransform3D? = nil
    ) {
        self.targets = targets
        self.tool = tool
        self.operation = operation
        self.keepTools = keepTools
        self.toolPlacement = toolPlacement
    }

    public func validate() throws {
        guard targets.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Boolean features require at least one target body.")
        }
        let targetFeatureIDs = targets.map(\.featureID)
        guard Set(targetFeatureIDs).count == targetFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean target references must be unique.")
        }
        try targets.forEach { try $0.validate() }
        try tool.validate()
        guard targetFeatureIDs.contains(tool.featureID) == false else {
            throw FeatureEvaluationError.invalidGraph("Boolean tool must be distinct from every target.")
        }
        guard toolPlacement == nil || keepTools == false else {
            throw FeatureEvaluationError.invalidGraph("A placed Boolean tool is consumed and cannot be kept.")
        }
    }
}

public struct BooleanTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public struct BooleanToolReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public enum BooleanOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case union
    case difference
    case intersect
    case slice
}
