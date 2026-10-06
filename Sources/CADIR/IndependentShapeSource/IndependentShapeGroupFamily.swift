/// Original ordering and inverse-membership obligations are separate source meanings.
public enum IndependentShapeGroupFamily: String, Hashable, Sendable {
    case unordered
    case unorderedWithBackPointers
    case ordered
    case orderedWithBackPointers

    public var isOrdered: Bool { self == .ordered || self == .orderedWithBackPointers }
    public var requiresBackPointers: Bool {
        self == .unorderedWithBackPointers || self == .orderedWithBackPointers
    }
}
#if !hasFeature(Embedded)
extension IndependentShapeGroupFamily: Codable {}
#endif
