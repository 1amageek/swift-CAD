import CADIR

struct BooleanRegionSelectionRule {
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
        switch operation {
        case .union:
            return classification == .outside ? .keep : .discard
        case .intersect:
            return classification == .inside ? .keep : .discard
        case .difference:
            if isToolFace {
                return classification == .inside ? .keepReversed : .discard
            }
            return classification == .outside ? .keep : .discard
        case .slice:
            return isToolFace ? .partitionBoundary : .keep
        }
    }
}
