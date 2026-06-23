import CADCore

public struct CurveTrimFeature: Codable, Hashable, Sendable {
    public var source: CurveOutputReference
    public var domain: ParameterDomain
    public var sampleCount: Int

    public init(
        source: CurveOutputReference,
        domain: ParameterDomain,
        sampleCount: Int = 33
    ) {
        self.source = source
        self.domain = domain
        self.sampleCount = sampleCount
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try source.validate()
        try domain.validate(tolerance: tolerance)
        guard case .closed = domain else {
            throw FeatureEvaluationError.invalidGraph("Curve trim features require a finite closed parameter domain.")
        }
        guard sampleCount >= 2 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
    }
}
