import CADCore
import CADIR

public struct ValidatedBRepModel: Sendable {
    public let model: BRepModel
    public let tolerance: ModelingTolerance

    public init(
        _ model: BRepModel,
        tolerance: ModelingTolerance = .standard
    ) throws {
        try tolerance.validate()
        try model.validate(tolerance: tolerance)
        self.model = model
        self.tolerance = tolerance
    }

    init(composingValidatedFeatureResults model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try model.validate(tolerance: tolerance)
        self.model = model
        self.tolerance = tolerance
    }
}
