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
        case parameterDomain
        case isReversed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.kind, .featureID, .profileIndex, .parameterDomain, .isReversed], in: decoder)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let featureID = try container.decode(FeatureID.self, forKey: .featureID)
        switch kind {
        case .profile:
            guard !container.contains(.parameterDomain), !container.contains(.isReversed) else {
                throw DecodingError.dataCorruptedError(forKey: .parameterDomain, in: container,
                    debugDescription: "Profile sections must not contain curve interval or direction fields.")
            }
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
            self = .curve(CurveSectionReference(featureID: featureID,
                parameterDomain: try container.decodeIfPresent(ParameterDomain.self, forKey: .parameterDomain),
                isReversed: try container.decode(Bool.self, forKey: .isReversed)))
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
            try container.encodeIfPresent(curve.parameterDomain, forKey: .parameterDomain)
            try container.encode(curve.isReversed, forKey: .isReversed)
        }
    }
}
