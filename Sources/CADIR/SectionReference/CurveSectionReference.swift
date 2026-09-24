import CADCore

public struct CurveSectionReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var parameterDomain: ParameterDomain?
    public var isReversed: Bool

    private enum CodingKeys: String, CodingKey {
        case featureID
        case parameterDomain
        case isReversed
    }

    public init(featureID: FeatureID, parameterDomain: ParameterDomain? = nil, isReversed: Bool = false) {
        self.featureID = featureID
        self.parameterDomain = parameterDomain
        self.isReversed = isReversed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .parameterDomain, .isReversed], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        parameterDomain = try container.decodeIfPresent(ParameterDomain.self, forKey: .parameterDomain)
        isReversed = try container.decode(Bool.self, forKey: .isReversed)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
        try container.encodeIfPresent(parameterDomain, forKey: .parameterDomain)
        try container.encode(isReversed, forKey: .isReversed)
    }

    public func validate() throws {
        if let parameterDomain {
            guard case .closed(let lower, let upper) = parameterDomain,
                  lower.isFinite, upper.isFinite, lower < upper else {
                throw FeatureEvaluationError.invalidGraph("Curve section intervals must be finite, increasing and nonempty.")
            }
        }
    }
}
