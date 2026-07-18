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
}
