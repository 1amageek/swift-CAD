import CADCore

/// Immutable original length preparation; each direct query borrows one exclusive execution.
public protocol CurveArcLengthParameterization: Sendable {
  var lengthEnclosure: CurveArcLengthEnclosure { get }
  func enclosure(over interval: ScalarInterval) throws -> CurveArcLengthEnclosure
  func enclosure(over interval: ScalarInterval, using execution: inout OriginalQueryExecution)
    throws -> CurveArcLengthEnclosure
  func differentialEnclosure(over interval: ScalarInterval) throws -> CurveDifferentialEnclosure
  func differentialEnclosure(
    over interval: ScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> CurveDifferentialEnclosure
  func hasSmoothNativeInterval(over interval: ScalarInterval) throws -> Bool
  func hasSmoothNativeInterval(
    over interval: ScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> Bool
  func parameterBounds(atFraction fraction: ScalarInterval, maximumParameterWidth: Double) throws
    -> ScalarInterval
  func parameterBounds(
    atFraction fraction: ScalarInterval, maximumParameterWidth: Double,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval
  func parameterEnclosure(atArcLengthFraction fraction: Double) throws
    -> CurveArcLengthParameterEnclosure
  func parameterEnclosure(
    atArcLengthFraction fraction: Double,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthParameterEnclosure
}

public protocol CurveArcLengthResolving: Sendable {
  func parameterization(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance
  ) throws -> any CurveArcLengthParameterization
  func parameterization(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int?,
    using execution: inout OriginalQueryExecution
  ) throws -> any CurveArcLengthParameterization
  func enclosure(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance
  ) throws -> CurveArcLengthEnclosure
  func enclosure(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int?,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthEnclosure
  func parameterEnclosure(
    atArcLengthFraction fraction: Double, of curve: Curve3D,
    over interval: ScalarInterval, options: CurveArcLengthOptions,
    tolerance: ModelingTolerance
  ) throws -> CurveArcLengthParameterEnclosure
  func parameterEnclosure(
    atArcLengthFraction fraction: Double, of curve: Curve3D,
    over interval: ScalarInterval, options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthParameterEnclosure
}

extension CurveArcLengthResolving {
  public func enclosure(
    of curve: Curve3D, over interval: ScalarInterval, tolerance: ModelingTolerance
  ) throws -> CurveArcLengthEnclosure {
    try enclosure(of: curve, over: interval, options: CurveArcLengthOptions(), tolerance: tolerance)
  }
  public func parameterization(
    of curve: Curve3D, over interval: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> any CurveArcLengthParameterization {
    try parameterization(
      of: curve, over: interval, options: CurveArcLengthOptions(), tolerance: tolerance)
  }
  public func parameterEnclosure(
    atArcLengthFraction fraction: Double, of curve: Curve3D,
    over interval: ScalarInterval, tolerance: ModelingTolerance
  ) throws -> CurveArcLengthParameterEnclosure {
    try parameterEnclosure(
      atArcLengthFraction: fraction, of: curve, over: interval,
      options: CurveArcLengthOptions(), tolerance: tolerance)
  }
}
