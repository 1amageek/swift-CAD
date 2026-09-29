import CADIR

/// Which side of each classified face region a Boolean keeps. The rule is written for operands
/// whose material lies behind their faces' normals; a face of an operand whose material lies in
/// front of them (`isInverted`) bounds the result the other way round, so a kept face turns.
public struct BooleanRegionSelectionRule: Sendable {
    public let solidities: BooleanOperandSolidities

    public init(solidities: BooleanOperandSolidities) {
        self.solidities = solidities
    }

    func action(
        operation: BooleanOperation,
        sample: BooleanClassificationGraph.Sample
    ) -> BooleanRegionSelectionAction {
        action(
            operation: operation,
            classification: sample.classification,
            isToolFace: sample.sourceFaceID == sample.facePair.toolFaceID
        )
    }

    func action(
        operation: BooleanOperation,
        classification: SolidPointClassification,
        isToolFace: Bool
    ) -> BooleanRegionSelectionAction {
        let action: BooleanRegionSelectionAction = switch operation {
        case .union:
            classification == .outside ? .keep : .discard
        case .intersect:
            classification == .inside ? .keep : .discard
        case .difference:
            if isToolFace {
                classification == .inside ? .keepReversed : .discard
            } else {
                classification == .outside ? .keep : .discard
            }
        case .slice:
            isToolFace ? .partitionBoundary : .keep
        case .region:
            // Every face region of every operand bounds some region.
            .keep
        }
        return oriented(action, isToolFace: isToolFace)
    }

    /// `action` for a face of the target or the tool, turned for an inverted operand.
    func oriented(_ action: BooleanRegionSelectionAction, isToolFace: Bool) -> BooleanRegionSelectionAction {
        guard (isToolFace ? solidities.tool : solidities.target).isInverted else { return action }
        switch action {
        case .keep: return .keepReversed
        case .keepReversed: return .keep
        case .discard, .partitionBoundary: return action
        }
    }
}
