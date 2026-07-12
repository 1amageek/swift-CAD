public struct SubshapeID: Codable, Comparable, Equatable, Hashable, Sendable {
    public let featureID: FeatureID
    public let role: String
    public let ordinal: Int

    public init(featureID: FeatureID, role: String, ordinal: Int) {
        self.featureID = featureID
        self.role = role
        self.ordinal = ordinal
    }

    public var isValid: Bool {
        role.isEmpty == false && ordinal >= 0
    }

    public static func < (lhs: SubshapeID, rhs: SubshapeID) -> Bool {
        if lhs.featureID != rhs.featureID {
            return lhs.featureID < rhs.featureID
        }
        if lhs.role != rhs.role {
            return lhs.role < rhs.role
        }
        return lhs.ordinal < rhs.ordinal
    }
}
