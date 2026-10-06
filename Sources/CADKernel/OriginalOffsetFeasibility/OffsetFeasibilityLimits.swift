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
extension OffsetFeasibilityLimits: Codable {
    private enum CodingKeys: String, CodingKey {
        case maximumCumulativeWork, maximumCumulativeStorageBytes, surfaceIntersectionOptions, remainingSourceDepth, maximumAlgebraicDepth
    }
    private enum OptionKeys: String, CodingKey {
        case maximumSubdivisionDepth, maximumSubdivisionCells, maximumIterations, maximumSeedCount, maximumContinuationPointCount, maximumContinuationPointCountPerComponent, maximumRootAttempts, maximumBoundarySubdivisionDepth, maximumBoundarySubdivisionCells, maximumPeriodicSeamAttempts, maximumResidualCertificationDepth, maximumResidualCertificationCells
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let options = try values.nestedContainer(keyedBy: OptionKeys.self, forKey: .surfaceIntersectionOptions)
        self.init(
            maximumCumulativeWork: try values.decodeIfPresent(Int.self, forKey: .maximumCumulativeWork),
            maximumCumulativeStorageBytes: try values.decodeIfPresent(Int.self, forKey: .maximumCumulativeStorageBytes),
            surfaceIntersectionOptions: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: try options.decode(Int.self, forKey: .maximumSubdivisionDepth),
                maximumSubdivisionCells: try options.decode(Int.self, forKey: .maximumSubdivisionCells),
                maximumIterations: try options.decode(Int.self, forKey: .maximumIterations),
                maximumSeedCount: try options.decode(Int.self, forKey: .maximumSeedCount),
                maximumContinuationPointCount: try options.decode(Int.self, forKey: .maximumContinuationPointCount),
                maximumContinuationPointCountPerComponent: try options.decode(Int.self, forKey: .maximumContinuationPointCountPerComponent),
                maximumRootAttempts: try options.decode(Int.self, forKey: .maximumRootAttempts),
                maximumBoundarySubdivisionDepth: try options.decode(Int.self, forKey: .maximumBoundarySubdivisionDepth),
                maximumBoundarySubdivisionCells: try options.decode(Int.self, forKey: .maximumBoundarySubdivisionCells),
                maximumPeriodicSeamAttempts: try options.decode(Int.self, forKey: .maximumPeriodicSeamAttempts),
                maximumResidualCertificationDepth: try options.decode(Int.self, forKey: .maximumResidualCertificationDepth),
                maximumResidualCertificationCells: try options.decode(Int.self, forKey: .maximumResidualCertificationCells)),
            remainingSourceDepth: try values.decode(Int.self, forKey: .remainingSourceDepth),
            maximumAlgebraicDepth: try values.decode(Int.self, forKey: .maximumAlgebraicDepth))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(maximumCumulativeWork, forKey: .maximumCumulativeWork)
        try values.encodeIfPresent(maximumCumulativeStorageBytes, forKey: .maximumCumulativeStorageBytes)
        try values.encode(remainingSourceDepth, forKey: .remainingSourceDepth)
        try values.encode(maximumAlgebraicDepth, forKey: .maximumAlgebraicDepth)
        var options = values.nestedContainer(keyedBy: OptionKeys.self, forKey: .surfaceIntersectionOptions)
        try options.encode(surfaceIntersectionOptions.maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try options.encode(surfaceIntersectionOptions.maximumSubdivisionCells, forKey: .maximumSubdivisionCells)
        try options.encode(surfaceIntersectionOptions.maximumIterations, forKey: .maximumIterations)
        try options.encode(surfaceIntersectionOptions.maximumSeedCount, forKey: .maximumSeedCount)
        try options.encode(surfaceIntersectionOptions.maximumContinuationPointCount, forKey: .maximumContinuationPointCount)
        try options.encode(surfaceIntersectionOptions.maximumContinuationPointCountPerComponent, forKey: .maximumContinuationPointCountPerComponent)
        try options.encode(surfaceIntersectionOptions.maximumRootAttempts, forKey: .maximumRootAttempts)
        try options.encode(surfaceIntersectionOptions.maximumBoundarySubdivisionDepth, forKey: .maximumBoundarySubdivisionDepth)
        try options.encode(surfaceIntersectionOptions.maximumBoundarySubdivisionCells, forKey: .maximumBoundarySubdivisionCells)
        try options.encode(surfaceIntersectionOptions.maximumPeriodicSeamAttempts, forKey: .maximumPeriodicSeamAttempts)
        try options.encode(surfaceIntersectionOptions.maximumResidualCertificationDepth, forKey: .maximumResidualCertificationDepth)
        try options.encode(surfaceIntersectionOptions.maximumResidualCertificationCells, forKey: .maximumResidualCertificationCells)
    }
}
#endif
