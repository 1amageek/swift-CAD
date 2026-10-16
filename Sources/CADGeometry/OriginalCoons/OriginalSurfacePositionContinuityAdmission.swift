import CADCore

/// Retrieves immutable original C0 authority after the caller's source validation.
package struct OriginalSurfacePositionContinuityAdmission {
  package init() {}
  package func provesAssumingSourceValidated<B: ExactScalarAdmission & ~Copyable>(
    _ surface: Surface3D,
    remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B
  ) throws -> Bool {
    guard remainingSourceDepth >= 0 else {
      throw GeometryConversionError.invalidInput(
        "Original surface continuity source cap is invalid.")
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    try usage.consumeWork(1)
    switch surface {
    case .procedural(.originalCoons(let source)):
      try source.validatePreparationBinding(tolerance: tolerance)
      try source.admitScalarPreparation(using: &usage)
      return source.hasOriginalPositionContinuity
    case .procedural(.originalBoundaryCorrected(let source)):
      try source.validatePreparationBinding(tolerance: tolerance)
      try source.admitScalarPreparation(using: &usage)
      return source.hasOriginalPositionContinuity
    case .procedural(.originalPlaneDerivative(let source)):
      try source.validatePreparationBinding(tolerance: tolerance)
      try source.admitScalarPreparation(using: &usage)
      return source.hasOriginalPositionContinuity
    default: return false
    }
  }
}
