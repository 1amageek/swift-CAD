import CADCore

public struct CurveTrimFeature: Codable, Hashable, Sendable {
    public var source: CurveOutputReference
    public var domain: ParameterDomain

    public init(
        source: CurveOutputReference,
        domain: ParameterDomain
    ) {
        self.source = source
        self.domain = domain
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try source.validate()
        try domain.validate(tolerance: tolerance)
        guard case .closed = domain else {
            throw FeatureEvaluationError.invalidGraph("Curve trim features require a finite closed parameter domain.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case domain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .domain], in: decoder)
        source = try container.decode(CurveOutputReference.self, forKey: .source)
        domain = try container.decode(ParameterDomain.self, forKey: .domain)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(domain, forKey: .domain)
    }
}
