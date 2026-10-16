import CADCore

/// Creates an independent ordinary-query owner and observes the active operation scope.
enum NativePositionExecution {
  static func make(limits: NativeSurfacePositionCertificationLimits) throws
    -> OriginalQueryExecution
  {
    try limits.validate()
    return OriginalQueryExecution(
      budget: try OriginalQueryBudget(workLimit: limits.maximumWorkUnits),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumSubdivisionDepth: limits.maximumCertificationBoxes,
        maximumScalarSlots: limits.maximumScalarCount))
  }

  static func certificate(
    parameters: SurfaceParameterBox, bound: Double,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeSurfacePositionCertificate {
    try execution.checkpoint()
    guard let observed = execution.conversionScopeSnapshot else {
      throw GeometryConversionError.invalidInput(
        "Position evidence requires its active execution scope.")
    }
    return NativeSurfacePositionCertificate(
      coveredParameters: parameters, positionErrorUpperBound: bound,
      certifiedBoxCount: observed.certificationBoxes, scalarCount: observed.scalarSlots,
      workUnits: observed.work)
  }
}
