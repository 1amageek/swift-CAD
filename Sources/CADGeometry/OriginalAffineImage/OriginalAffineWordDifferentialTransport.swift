import CADCore

/// Invocation-owned quantitative action, separate from persistent point-law admission.
package struct OriginalAffineWordDifferentialTransport: Sendable {
  private enum Source: Sendable {
    case word(OriginalAffineWordSurface3D)
    case identityUVImage(OriginalImageSurface3D)
  }
  private let source: Source
  private let linearNormUpper: Double
  private let cofactorConditionUpper: Double
  private let proofDepth: ExactScalarDepth

  package init<B: ExactScalarAdmission & ~Copyable>(image: OriginalAffineWordSurface3D, usage: inout B) throws {
    source = .word(image)
    let calculation = try ExactScalarNumericAccess.withAdmission(&usage) { usage in
      try image.preparedWord.conditionBounds(usage: &usage)
    }
    proofDepth = calculation.depth
    let q = calculation.value
    guard q.linearNormUpper.isFinite, q.linearNormUpper > 0,
      q.cofactorConditionUpper.isFinite, q.cofactorConditionUpper > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original word has no finite quantitative differential action.")
    }
    linearNormUpper = q.linearNormUpper; cofactorConditionUpper = q.cofactorConditionUpper
  }

  /// The caller retains the same original native owner and unchanged UV box.
  package init<B: ExactScalarAdmission & ~Copyable>(image: OriginalImageSurface3D,
    tolerance: ModelingTolerance, usage: inout B) throws {
    guard image.uParameterGain == .binary(1), image.vParameterGain == .binary(1),
      image.uOffset == 0, image.vOffset == 0, !image.swapAxes else {
      throw GeometryConversionError.invalidInput("Selected native image panels require an exactly unchanged UV chart.")
    }
    source = .identityUVImage(image)
    // This binary affine factor is rational; no coefficient field depth is added.
    let word = try OriginalAffineOperationWord(operation: .forward(image.transform),
      tolerance: tolerance, maximumDepth: 0, usage: &usage)
    let prepared = try word.prepared(usage: &usage)
    let calculation = try ExactScalarNumericAccess.withAdmission(&usage) { usage in
      try prepared.conditionBounds(usage: &usage)
    }
    proofDepth = calculation.depth
    let q = calculation.value
    guard q.linearNormUpper.isFinite, q.linearNormUpper > 0,
      q.cofactorConditionUpper.isFinite, q.cofactorConditionUpper > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original image has no finite quantitative native-panel action.")
    }
    linearNormUpper = q.linearNormUpper; cofactorConditionUpper = q.cofactorConditionUpper
  }

  package func bounds<A: ExactScalarAdmission & ~Copyable>(_ original: SurfaceTessellationDifferentialBounds,
    using execution: inout A) throws -> SurfaceTessellationDifferentialBounds {
    try execution.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
    func scaled(_ value: Double, by scale: Double) throws -> Double {
      try execution.consumeWork(1)
      guard value.isFinite, value >= 0 else {
        throw GeometryConversionError.invalidInput("Original word derivative bound is not finite and nonnegative.")
      }
      let q = OutwardScalarInterval.exact(value) * .exact(scale)
      guard q.isFinite, q.upper >= 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original word derivative bound overflows.")
      }
      return q.upper
    }
    return try .init(
      tangentUMagnitudeUpperBound: scaled(original.tangentUMagnitudeUpperBound, by: linearNormUpper),
      tangentVMagnitudeUpperBound: scaled(original.tangentVMagnitudeUpperBound, by: linearNormUpper),
      secondDerivativeUUMagnitudeUpperBound: scaled(original.secondDerivativeUUMagnitudeUpperBound, by: linearNormUpper),
      secondDerivativeUVMagnitudeUpperBound: scaled(original.secondDerivativeUVMagnitudeUpperBound, by: linearNormUpper),
      secondDerivativeVVMagnitudeUpperBound: scaled(original.secondDerivativeVVMagnitudeUpperBound, by: linearNormUpper),
      unitNormalDerivativeUMagnitudeUpperBound: scaled(original.unitNormalDerivativeUMagnitudeUpperBound, by: cofactorConditionUpper),
      unitNormalDerivativeVMagnitudeUpperBound: scaled(original.unitNormalDerivativeVMagnitudeUpperBound, by: cofactorConditionUpper))
  }
}
