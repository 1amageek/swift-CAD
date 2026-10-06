import CADCore
import CADGeometry

/// Additional caller-selected limits; nil preserves existing per-proof policies.
public struct OffsetFeasibilityLimits: Hashable, Sendable {
    public let maximumCumulativeWork: Int?
    public let maximumCumulativeStorageBytes: Int?
    public let surfaceIntersectionOptions: SurfaceSurfaceIntersectionOptions
    public let remainingSourceDepth: Int
    public let maximumAlgebraicDepth: Int

    public init(maximumCumulativeWork: Int? = nil,
        maximumCumulativeStorageBytes: Int? = nil,
        surfaceIntersectionOptions: SurfaceSurfaceIntersectionOptions = .init(),
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32) {
        self.maximumCumulativeWork = maximumCumulativeWork
        self.maximumCumulativeStorageBytes = maximumCumulativeStorageBytes
        self.surfaceIntersectionOptions = surfaceIntersectionOptions
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try surfaceIntersectionOptions.validate(tolerance: tolerance)
        guard (0...16).contains(remainingSourceDepth), (0...32).contains(maximumAlgebraicDepth),
              maximumCumulativeWork.map({ $0 >= 0 }) ?? true,
              maximumCumulativeStorageBytes.map({ $0 >= 0 }) ?? true else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Offset feasibility cumulative limits must be nonnegative when supplied.")
        }
    }
}

#if !hasFeature(Embedded)
extension OffsetFeasibilityLimits: Codable {}
#endif
