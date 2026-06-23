import CADCore
import CADIR

public struct CADAgentCommandResult: Sendable {
    public var document: CADDocument
    public var addition: CADAgentCommandAddition

    public init(document: CADDocument, addedFeatureID: FeatureID) {
        self.document = document
        self.addition = .feature(addedFeatureID)
    }

    public init(document: CADDocument, addedSelectionDimensionID: SelectionDimensionID) {
        self.document = document
        self.addition = .selectionDimension(addedSelectionDimensionID)
    }

    public var addedFeatureID: FeatureID? {
        guard case let .feature(featureID) = addition else {
            return nil
        }
        return featureID
    }

    public var addedSelectionDimensionID: SelectionDimensionID? {
        guard case let .selectionDimension(dimensionID) = addition else {
            return nil
        }
        return dimensionID
    }
}
