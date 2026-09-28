import CADCore
import CADIR
import CADTopology

/// What one Boolean pass knows about its operands' material, shared by every phase: their
/// solidities, the point classifier that honours them, the region-selection rule and the kind
/// of body the pass produces.
public struct BooleanOperandContext: Sendable {
    public let solidities: BooleanOperandSolidities
    public let pointClassifier: any SolidPointClassifying

    public init(targetBodyIDs: [BodyID], toolBodyID: BodyID, solidities: BooleanOperandSolidities) {
        self.solidities = solidities
        self.pointClassifier = BooleanOperandPointClassifier(
            targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, solidities: solidities
        )
    }

    /// A pass whose points are classified by `pointClassifier`, which must honour `solidities`.
    public init(solidities: BooleanOperandSolidities, pointClassifier: any SolidPointClassifying) {
        self.solidities = solidities
        self.pointClassifier = pointClassifier
    }

    /// Two solids taken as their volumes.
    public static func volumes(targetBodyIDs: [BodyID], toolBodyID: BodyID) -> BooleanOperandContext {
        BooleanOperandContext(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, solidities: .volumes)
    }

    /// The pass's region-selection rule.
    public var rule: BooleanRegionSelectionRule {
        BooleanRegionSelectionRule(solidities: solidities)
    }

    /// A pass whose targets have no material yields a sheet; any other, a solid.
    public var resultBodyKind: BodyKind {
        solidities.target == .none ? .sheet : .solid
    }
}
