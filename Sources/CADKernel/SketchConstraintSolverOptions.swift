import CADCore

public struct SketchConstraintSolverOptions: Codable, Hashable, Sendable {
    public let maximumIterations: Int
    public let initialDamping: Double
    public let minimumStep: Double

    public init(
        maximumIterations: Int = 64,
        initialDamping: Double = 1.0e-3,
        minimumStep: Double = 1.0e-12
    ) {
        self.maximumIterations = maximumIterations
        self.initialDamping = initialDamping
        self.minimumStep = minimumStep
    }

    public func validate() throws {
        guard maximumIterations > 0,
              initialDamping.isFinite,
              initialDamping > 0.0,
              minimumStep.isFinite,
              minimumStep > 0.0 else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Sketch constraint solver options are invalid."
            )
        }
    }
}
