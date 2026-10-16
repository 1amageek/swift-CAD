import CADCore

/// Original atlas parameters and spatial truth retained independently of geometric images.
public struct OriginalCurveCurveContact: Sendable {
  public let firstSource: OriginalCurveContactSource
  public let secondSource: OriginalCurveContactSource
  public let firstParameters: ScalarInterval
  public let secondParameters: ScalarInterval
  public let position: CoordinateEnclosure3D
  public let tolerance: ModelingTolerance
  public let parameterAuthority: OriginalCurveContactParameterAuthority?
  package let firstNativeSpanIndex: Int?

  /// Evaluates the retained validated law; paid preparation is never replayed here.
  public func firstPoint(using execution: inout OriginalQueryExecution) throws -> Point3D {
    execution.context = .init(
      operation: .curveCurveContact, entry: .membership, stage: .membership,
      first: .init(role: .curve, request: .curveRange(firstParameters)),
      second: .init(role: .curve, request: .curveRange(secondParameters)))
    do {
      try execution.checkpoint()
      let result = try resolveFirstPoint(using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveFirstPoint(using execution: inout OriginalQueryExecution) throws -> Point3D {
    try OriginalCurveContactSourceWork.charge(firstSource.curve, using: &execution)

    return try firstSource.curve.pointAssumingValid(
      at: firstParameters.midpoint, tolerance: tolerance, using: &execution)
  }

  init(
    firstSource: OriginalCurveContactSource, secondSource: OriginalCurveContactSource,
    firstParameters: ScalarInterval, secondParameters: ScalarInterval,
    position: CoordinateEnclosure3D, tolerance: ModelingTolerance,
    parameterAuthority: OriginalCurveContactParameterAuthority? = nil,
    firstNativeSpanIndex: Int? = nil
  ) {
    self.firstSource = firstSource
    self.secondSource = secondSource
    self.firstParameters = firstParameters
    self.secondParameters = secondParameters
    self.position = position
    self.tolerance = tolerance
    self.parameterAuthority = parameterAuthority
    self.firstNativeSpanIndex = firstNativeSpanIndex
  }
}
