import CADCore

public struct SurfaceSurfaceIntersectionOptions: Hashable, Sendable {
  public var maximumSubdivisionDepth: Int
  public var maximumSubdivisionCells: Int
  public var maximumIterations: Int
  public var maximumSeedCount: Int
  /// Maximum continuation samples across all traced intersection components.
  public var maximumContinuationPointCount: Int
  /// Maximum continuation samples retained by any one intersection component.
  public var maximumContinuationPointCountPerComponent: Int
  public var maximumRootAttempts: Int
  public var maximumBoundarySubdivisionDepth: Int
  public var maximumBoundarySubdivisionCells: Int
  public var maximumPeriodicSeamAttempts: Int
  public var maximumResidualCertificationDepth: Int
  public var maximumResidualCertificationCells: Int

  public init(
    maximumSubdivisionDepth: Int = 12,
    maximumSubdivisionCells: Int = 262_144,
    maximumIterations: Int = 32,
    maximumSeedCount: Int = 1_024,
    maximumContinuationPointCount: Int = 65_536,
    maximumContinuationPointCountPerComponent: Int = 16_384,
    maximumRootAttempts: Int = 65_536,
    maximumBoundarySubdivisionDepth: Int = 16,
    maximumBoundarySubdivisionCells: Int = 1_048_576,
    maximumPeriodicSeamAttempts: Int = 16,
    maximumResidualCertificationDepth: Int = 20,
    maximumResidualCertificationCells: Int = 65_536
  ) {
    self.maximumSubdivisionDepth = maximumSubdivisionDepth
    self.maximumSubdivisionCells = maximumSubdivisionCells
    self.maximumIterations = maximumIterations
    self.maximumSeedCount = maximumSeedCount
    self.maximumContinuationPointCount = maximumContinuationPointCount
    self.maximumContinuationPointCountPerComponent = maximumContinuationPointCountPerComponent
    self.maximumRootAttempts = maximumRootAttempts
    self.maximumBoundarySubdivisionDepth = maximumBoundarySubdivisionDepth
    self.maximumBoundarySubdivisionCells = maximumBoundarySubdivisionCells
    self.maximumPeriodicSeamAttempts = maximumPeriodicSeamAttempts
    self.maximumResidualCertificationDepth = maximumResidualCertificationDepth
    self.maximumResidualCertificationCells = maximumResidualCertificationCells
  }

  public func validate(tolerance: ModelingTolerance) throws {
    try tolerance.validate()
    guard maximumSubdivisionDepth >= 0,
      maximumSubdivisionDepth <= 24,
      maximumSubdivisionCells > 0,
      maximumSubdivisionCells <= 4_194_304,
      maximumIterations > 0,
      maximumIterations <= 256,
      maximumSeedCount > 0,
      maximumSeedCount <= 65_536,
      maximumContinuationPointCount > 0,
      maximumContinuationPointCount <= 4_194_304,
      maximumContinuationPointCountPerComponent > 0,
      maximumContinuationPointCountPerComponent <= maximumContinuationPointCount,
      maximumRootAttempts > 0,
      maximumRootAttempts <= 65_536,
      maximumBoundarySubdivisionDepth >= 0,
      maximumBoundarySubdivisionDepth <= 24,
      maximumBoundarySubdivisionCells > 0,
      maximumBoundarySubdivisionCells <= 1_048_576,
      maximumPeriodicSeamAttempts > 0,
      maximumPeriodicSeamAttempts <= 64,
      maximumResidualCertificationDepth >= 0,
      maximumResidualCertificationDepth <= 32,
      maximumResidualCertificationCells > 0,
      maximumResidualCertificationCells <= 1_048_576
    else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Surface-surface intersection limits are outside the supported resource envelope."
      )
    }
  }
}
