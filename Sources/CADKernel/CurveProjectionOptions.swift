import CADCore

public struct CurveProjectionOptions: Sendable, Hashable {
    public var sampleCount: Int
    public var maximumIterations: Int

    public init(sampleCount: Int = 9, maximumIterations: Int = 32) {
        self.sampleCount = sampleCount
        self.maximumIterations = maximumIterations
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Curve projection sample count must be at least two.")
        }
        guard maximumIterations >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve projection iteration count must not be negative.")
        }
    }
}
