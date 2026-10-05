import CADCore

/// Explicit original conversion caps with optional invocation-wide ceilings.
public struct EdgeOffsetConversionLimits: Hashable, Sendable {
    public let maximumSpanCount: Int
    public let maximumSubdivisionDepth: Int
    public let remainingSourceDepth: Int
    public let maximumAlgebraicDepth: Int
    public let maximumWork: Int?
    public let maximumStorageBytes: Int?

    public init(maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        maximumWork: Int? = nil, maximumStorageBytes: Int? = nil) {
        self.maximumSpanCount = maximumSpanCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.maximumWork = maximumWork
        self.maximumStorageBytes = maximumStorageBytes
    }

    func validate(tolerance: ModelingTolerance) throws {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
              remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
              maximumWork.map({ $0 > 0 }) ?? true,
              maximumStorageBytes.map({ $0 > 0 }) ?? true else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance,
                message: "Original offset conversion requires explicit nonnegative depths, positive spans and optional positive cumulative ceilings.")
        }
    }
}
