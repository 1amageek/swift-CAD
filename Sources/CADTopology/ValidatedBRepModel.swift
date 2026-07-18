import CADCore

public struct ValidatedBRepModel: Sendable {
    public let model: BRepModel
    public let tolerance: ModelingTolerance
    public let validationLevel: BRepValidationLevel

    public init(
        _ model: BRepModel,
        tolerance: ModelingTolerance,
        validationLevel: BRepValidationLevel = .exact
    ) throws {
        try tolerance.validate()
        try model.validate(level: validationLevel, tolerance: tolerance)
        self.model = model
        self.tolerance = tolerance
        self.validationLevel = validationLevel
    }

    package init(composingValidatedFeatureResults model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try model.validate(level: .exact, tolerance: tolerance)
        self.model = model
        self.tolerance = tolerance
        self.validationLevel = .exact
    }
}
