import CADCore

public enum CADAgentCommandAddition: Sendable, Hashable {
    case feature(FeatureID)
    case selectionDimension(SelectionDimensionID)
}
