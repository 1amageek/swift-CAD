import CADCore

public struct SelectionDimensionEvaluation: Codable, Sendable, Hashable {
    public var measurements: [SelectionDimensionMeasurement]

    public init(measurements: [SelectionDimensionMeasurement]) {
        self.measurements = measurements
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        for measurement in measurements {
            _ = try measurement.isSatisfied(tolerance: tolerance)
        }
    }
}
