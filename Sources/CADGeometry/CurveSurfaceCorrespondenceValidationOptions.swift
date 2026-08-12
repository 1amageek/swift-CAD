import CADCore

public struct CurveSurfaceCorrespondenceValidationOptions: Codable, Hashable, Sendable {
    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int
    // Acceptance bound for the lift-versus-curve deviation. The default of
    // nil accepts at the tolerance's distance; callers whose endpoints
    // carry snapped junction offsets widen only this acceptance, keeping
    // the certified machinery (root isolation, projections) at the exact
    // tolerance it was certified for.
    public let maximumDeviation: Double?

    public init(
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        maximumDeviation: Double? = nil
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        self.maximumDeviation = maximumDeviation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 64,
              maximumCellCount > 0,
              maximumDeviation.map({ $0.isFinite && $0 > 0.0 }) ?? true else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve-surface correspondence validation options are invalid."
            )
        }
    }
}
