import CADCore

/// Immutable original-law preparation with query-local execution supplied by each reader.
public struct PreparedPolynomialSurfaceContinuationPositionRequest: Sendable {
  public let source: BSplineSurface3D
  public let parameters: SurfaceParameterBox
  public let maximumPositionError: Double
  public let limits: NativeSurfacePositionCertificationLimits
  public let tolerance: ModelingTolerance
  public let admittedScalarCount: Int
  public let admittedWorkUnits: Int
  public let admittedBoxCount: Int

  let originalLaw: PreparedPolynomialSurfaceContinuationLaw?
  private let receipt: OriginalGeometryPreparationReceipt
  private let executionLimits: OriginalQueryExecutionLimits

  init(
    source: BSplineSurface3D, parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits, tolerance: ModelingTolerance,
    originalLaw: PreparedPolynomialSurfaceContinuationLaw?, depth: OriginalQueryPreparationDepth,
    using execution: inout OriginalQueryExecution
  ) throws {
    guard let observed = execution.conversionScopeSnapshot else {
      throw GeometryConversionError.invalidInput(
        "Continuation preparation requires its active execution scope.")
    }
    self.originalLaw = originalLaw
    self.source = source
    self.parameters = parameters
    self.maximumPositionError = maximumPositionError
    self.limits = limits
    self.tolerance = tolerance
    self.admittedScalarCount = observed.scalarSlots
    self.admittedWorkUnits = observed.work
    self.admittedBoxCount = observed.certificationBoxes
    self.executionLimits = execution.effectiveLimits
    self.receipt = try OriginalGeometryPreparationReceipt(
      tolerance: tolerance, depth: depth, using: &execution)
  }

  func independentExecution() throws -> OriginalQueryExecution {
    OriginalQueryExecution(budget: receipt.budget, limits: executionLimits)
  }

  func admit(using execution: inout OriginalQueryExecution) throws {
    try receipt.admit(tolerance: tolerance, using: &execution)
  }
}
