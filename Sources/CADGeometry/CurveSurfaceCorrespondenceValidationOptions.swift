import CADCore

public struct CurveSurfaceCorrespondenceValidationOptions: Codable, Hashable, Sendable {
    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int

    public init(
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 64,
              maximumCellCount > 0 else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve-surface correspondence validation options are invalid."
            )
        }
    }
}
