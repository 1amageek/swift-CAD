import CADCore

/// Immutable depth/tolerance authority issued only after original preparation.
final class OriginalGeometryPreparationReceipt: Sendable {
  let budget: OriginalQueryBudget
  let limits: OriginalQueryExecutionLimits
  let contributions: [OriginalQueryContributionHandle]
  let tolerance: ModelingTolerance
  let depth: OriginalQueryPreparationDepth

  init(
    tolerance: ModelingTolerance, depth: OriginalQueryPreparationDepth,
    using execution: inout OriginalQueryExecution
  ) throws {
    try execution.retainStorage(
      bytes: MemoryLayout<OriginalQueryBudget>.stride
        + MemoryLayout<ModelingTolerance>.stride
        + MemoryLayout<OriginalQueryExecutionLimits>.stride
        + MemoryLayout<[OriginalQueryContributionHandle]>.stride
        + MemoryLayout<OriginalQueryPreparationDepth>.stride
        + 2 * MemoryLayout<UnsafeRawPointer>.stride)
    self.limits = execution.effectiveLimits
    self.contributions = try execution.retainActiveContributionHandles()
    self.budget = execution.budget
    self.tolerance = tolerance
    self.depth = depth
  }

  func makeExecution() throws -> OriginalQueryExecution {
    try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
  }

  func withContributionScopes<Result>(
    using execution: inout OriginalQueryExecution,
    _ body: (inout OriginalQueryExecution) throws -> Result
  ) throws -> Result {
    if execution.budget === budget {
      return try execution.withContributionScopes(contributions, body)
    }
    return try body(&execution)
  }

  func admit(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    guard tolerance == self.tolerance else {
      throw GeometryConversionError.invalidInput(
        "Original preparation requires its retained tolerance.")
    }
    // One fixed receipt check; original numeric decomposition is retained.
    _ = try execution.admitRetainedPreparation(
      owner: self, budget: budget, work: 1, storageBytes: 0,
      depth: depth.scalar, sourceDepth: depth.sourceDepth,
      geometricDepth: depth.geometricDepth, transportDepth: depth.transportDepth)
  }
}
