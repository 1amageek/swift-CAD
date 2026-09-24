import CADCore

public enum SectionReference: Codable, Hashable, Sendable {
    case profile(ProfileReference)
    case curve(CurveSectionReference)

    public var featureID: FeatureID {
        switch self {
        case .profile(let profile):
            return profile.featureID
        case .curve(let curve):
            return curve.featureID
        }
    }

    public var profile: ProfileReference? {
        guard case .profile(let profile) = self else {
            return nil
        }
        return profile
    }

    public var isProfile: Bool {
        profile != nil
    }

    public var inputRole: FeaturePort {
        switch self {
        case .profile:
            return .profile
        case .curve:
            return .curve
        }
    }

    public func validate() throws {
        switch self {
        case .profile(let profile):
            try profile.validate()
        case .curve(let curve):
            try curve.validate()
        }
    }

    private enum Kind: String, Codable {
        case profile
        case curve
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case featureID
        case profileIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.kind, .featureID, .profileIndex], in: decoder)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let featureID = try container.decode(FeatureID.self, forKey: .featureID)
        switch kind {
        case .profile:
            let profileIndex = try container.decode(Int.self, forKey: .profileIndex)
            self = .profile(ProfileReference(featureID: featureID, profileIndex: profileIndex))
        case .curve:
            if container.contains(.profileIndex) {
                throw DecodingError.dataCorruptedError(
                    forKey: .profileIndex,
                    in: container,
                    debugDescription: "Curve sections must not contain a profile index."
                )
            }
            self = .curve(CurveSectionReference(featureID: featureID))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profile(let profile):
            try container.encode(Kind.profile, forKey: .kind)
            try container.encode(profile.featureID, forKey: .featureID)
            try container.encode(profile.profileIndex, forKey: .profileIndex)
        case .curve(let curve):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(curve.featureID, forKey: .featureID)
        }
    }
}
