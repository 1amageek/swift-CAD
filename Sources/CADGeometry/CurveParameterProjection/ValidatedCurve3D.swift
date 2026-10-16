import CADCore

/// An immutable original curve with its retained validation authority.
public struct ValidatedCurve3D: Sendable {
  public let curve: Curve3D
  public let tolerance: ModelingTolerance
  private let receipt: OriginalGeometryPreparationReceipt
  private let limits: OriginalQueryExecutionLimits
  private let contributions: [OriginalQueryContributionHandle]

  public init(_ curve: Curve3D, tolerance: ModelingTolerance) throws {
    var execution = try OriginalQueryExecution.independentGeometry()
    try self.init(curve, tolerance: tolerance, using: &execution)
  }

  public init(
    _ curve: Curve3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    let prepared = try execution.withPreparationScope { execution in
      try curve.validate(tolerance: tolerance, using: &execution)
    }
    receipt = try OriginalGeometryPreparationReceipt(
      tolerance: tolerance,
      depth: prepared.depth, using: &execution)
    limits = execution.effectiveLimits
    contributions = try execution.retainActiveContributionHandles()
    self.curve = curve
    self.tolerance = tolerance
    try execution.checkpoint()
  }

  package func originalExecution() throws -> OriginalQueryExecution {
    try receipt.makeExecution()
  }

  public var parameterDomain: ParameterDomain { curve.parameterDomain }

  package func withRead<Result>(
    using execution: inout OriginalQueryExecution,
    _ body: (inout OriginalQueryExecution) throws -> Result
  ) throws -> Result {
    if execution.budget === receipt.budget {
      return try execution.withContributionScopes(contributions) { execution in
        try receipt.admit(tolerance: tolerance, using: &execution)
        let result = try body(&execution)
        try execution.checkpoint()
        return result
      }
    }
    try receipt.admit(tolerance: tolerance, using: &execution)
    let result = try body(&execution)
    try execution.checkpoint()
    return result
  }

  public func point(at parameter: Double) throws -> Point3D {
    var execution = try OriginalQueryExecution(
      budget: receipt.budget, limits: limits,
      contributions: contributions)
    return try point(at: parameter, using: &execution)
  }

  public func point(at parameter: Double, using execution: inout OriginalQueryExecution) throws
    -> Point3D
  {
    try withRead(using: &execution) { execution in
      guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
        throw GeometryError.invalidDistance(parameter)
      }
      return try curve.pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }
  }

  public func differentialGeometry(at parameter: Double) throws -> Curve3D.DifferentialGeometry {
    var execution = try OriginalQueryExecution(
      budget: receipt.budget, limits: limits,
      contributions: contributions)
    return try differentialGeometry(at: parameter, using: &execution)
  }

  public func differentialGeometry(
    at parameter: Double,
    using execution: inout OriginalQueryExecution
  ) throws -> Curve3D.DifferentialGeometry {
    try withRead(using: &execution) { execution in
      guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
        throw GeometryError.invalidDistance(parameter)
      }
      return try curve.differentialGeometryAssumingValid(
        at: parameter, tolerance: tolerance, using: &execution)
    }
  }

  public func parameterProjection(
    of point: Point3D,
    options: CurveParameterProjectionOptions = .init()
  ) throws -> CurveParameterProjection {
    var execution = try OriginalQueryExecution(
      budget: receipt.budget, limits: limits,
      contributions: contributions)
    return try parameterProjection(of: point, options: options, using: &execution)
  }

  public func parameterProjection(
    of point: Point3D,
    options: CurveParameterProjectionOptions = .init(),
    using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    try withRead(using: &execution) { execution in
      try options.validate(tolerance: tolerance)
      try point.validate()
      return try curve.parameterProjectionAssumingValid(
        of: point, options: options,
        tolerance: tolerance, using: &execution)
    }
  }
}
