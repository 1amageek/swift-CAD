import CADCore

public struct ValidatedBRepModel: Sendable {
    public let model: BRepModel
    public let tolerance: ModelingTolerance
    public let validationLevel: BRepValidationLevel
    public let volume: Double?

    public init(
        _ model: BRepModel,
        tolerance: ModelingTolerance,
        validationLevel: BRepValidationLevel = .exact
    ) throws {
        try tolerance.validate()
        let prerequisiteLevel: BRepValidationLevel = validationLevel == .volumetric
            ? .exact
            : validationLevel
        try model.validate(level: prerequisiteLevel, tolerance: tolerance)
        let certifiedVolume: Double?
        if validationLevel == .volumetric {
            certifiedVolume = try model.volumeAfterBaseValidation(tolerance: tolerance)
        } else {
            certifiedVolume = nil
        }
        self.model = model
        self.tolerance = tolerance
        self.validationLevel = validationLevel
        self.volume = certifiedVolume
    }

    package init(composingValidatedFeatureResults model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try model.validate(level: .exact, tolerance: tolerance)
        self.model = model
        self.tolerance = tolerance
        self.validationLevel = .exact
        self.volume = nil
    }
}
