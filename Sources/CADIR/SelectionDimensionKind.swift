import CADCore

public enum SelectionDimensionKind: String, Codable, Sendable, Hashable {
    case distance
    case angle

    public var quantityKind: QuantityKind {
        switch self {
        case .distance:
            return .length
        case .angle:
            return .angle
        }
    }
}
