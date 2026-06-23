import CADCore

public struct SketchDimensionEvaluation: Codable, Sendable, Hashable {
    public var measurements: [SketchDimensionMeasurement]

    public init(measurements: [SketchDimensionMeasurement]) {
        self.measurements = measurements
    }

    public func isSatisfied(tolerance: ModelingTolerance = .standard) throws -> Bool {
        for measurement in measurements {
            guard try measurement.isSatisfied(tolerance: tolerance) else {
                return false
            }
        }
        return true
    }
}
