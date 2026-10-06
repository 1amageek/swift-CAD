import CADCore

/// Resource admission for certified free-surface area queries.
public struct FaceAreaIntegrationOptions: Sendable, Equatable {
    public var maximumCellCount: Int
    public var maximumSubdivisionDepth: Int
    public var maximumBoundaryCurveCount: Int
    public var maximumControlPointCount: Int

    public init(maximumCellCount: Int = 262_144, maximumSubdivisionDepth: Int = 32,
                maximumBoundaryCurveCount: Int = 4_096, maximumControlPointCount: Int = 65_536) {
        self.maximumCellCount = maximumCellCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumBoundaryCurveCount = maximumBoundaryCurveCount
        self.maximumControlPointCount = maximumControlPointCount
    }

    func validate(tolerance: ModelingTolerance) throws {
        guard maximumCellCount > 0, maximumCellCount <= 4_194_304,
              maximumSubdivisionDepth > 0, maximumSubdivisionDepth <= 48,
              maximumBoundaryCurveCount > 0, maximumBoundaryCurveCount <= 65_536,
              maximumControlPointCount > 0, maximumControlPointCount <= 1_048_576 else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                              message: "Face area integration options exceed finite admission limits.")
        }
    }
}
