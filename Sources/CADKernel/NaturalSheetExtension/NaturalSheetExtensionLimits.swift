import CADCore
import CADIR

/// Original reach-proof limits and an optional caller-selected cumulative allowance.
public struct NaturalSheetExtensionLimits: Hashable, Sendable {
    public let maximumSubdivisionDepth: Int
    public let maximumIntervalCount: Int
    public let maximumWork: Int?
    public let remainingSourceDepth: Int?
    public let maximumAlgebraicDepth: Int?

    public init(maximumSubdivisionDepth: Int = 48, maximumIntervalCount: Int = 131_072,
        maximumWork: Int? = nil, remainingSourceDepth: Int? = nil,
        maximumAlgebraicDepth: Int? = nil) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumIntervalCount = maximumIntervalCount
        self.maximumWork = maximumWork
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    func validate(tolerance: ModelingTolerance) throws {
        guard maximumSubdivisionDepth > 0, maximumSubdivisionDepth <= 48,
              maximumIntervalCount >= 2, maximumIntervalCount <= 131_072,
              maximumWork.map({ $0 > 0 }) ?? true,
              remainingSourceDepth.map({ $0 >= 0 }) ?? true,
              maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true,
              maximumAlgebraicDepth == nil || remainingSourceDepth != nil else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Natural sheet reach limits require the original proof ceilings, a positive optional work allowance and independent selected source/algebra capabilities.")
        }
    }
}
