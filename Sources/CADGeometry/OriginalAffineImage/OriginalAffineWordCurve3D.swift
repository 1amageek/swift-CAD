import CADCore

/// Parameter-preserving original curve image under a flat exact spatial word.
public struct OriginalAffineWordCurve3D: Hashable, Sendable {
  public let source: Curve3D
  public let operationWord: OriginalAffineOperationWord
  package let preparedWord: PreparedOriginalAffineOperationWord
  package let sourceTolerance: ModelingTolerance
  package let circularCoefficients: OriginalAffineWordCircularCoefficients?
  private let coefficientProofDepth: ExactScalarDepth

  /// Ordinary numerical convenience creates one independent execution.
  public init(source: Curve3D, operationWord: OriginalAffineOperationWord,
    tolerance: ModelingTolerance) throws {
    var usage = try OriginalQueryExecution.independentGeometry()
    try self.init(source: source, operationWord: operationWord, tolerance: tolerance,
      remainingSourceDepth: usage.limits.remainingSourceDepth,
      maximumSubdivisionDepth: usage.limits.maximumSubdivisionDepth, usage: &usage)
  }

  public init(source: Curve3D,
    operationWord: OriginalAffineOperationWord, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, usage: inout OriginalQueryExecution) throws {
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original affine image requires a remaining source descendant.")
    }
    let calculation = try ExactScalarNumericAccess.withAdmission(&usage) { usage in
      if let maximumAlgebraicDepth {
        guard maximumAlgebraicDepth >= 0 else { throw GeometryConversionError.invalidInput("Original word algebraic depth must be nonnegative.") }
        try operationWord.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
      } else { try operationWord.validateOriginal(tolerance: tolerance, usage: &usage) }
      let prepared = try operationWord.prepared(usage: &usage)
      let coefficients = try OriginalAffineWordCircularCoefficients.prepare(source: source,
        word: prepared, tolerance: tolerance, usage: &usage)
      let local = try coefficients != nil ? tolerance : OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: prepared, tolerance: tolerance, usage: &usage)
      return (prepared, coefficients, local)
    }
    self.source = source; self.operationWord = operationWord
    preparedWord = calculation.value.0; circularCoefficients = calculation.value.1
    sourceTolerance = calculation.value.2; coefficientProofDepth = calculation.depth
    if circularCoefficients == nil {
      try source.validateOriginalSource(tolerance: sourceTolerance,
        remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &usage)
    }
  }

  package func admitCoefficientProof<A: ExactScalarAdmission & ~Copyable>(using usage: inout A) throws {
    try usage.admitDepth(value: coefficientProofDepth.value, coefficient: coefficientProofDepth.coefficient)
  }

  public static func == (a: Self, b: Self) -> Bool { a.source == b.source && a.operationWord == b.operationWord }
  public func hash(into hasher: inout Hasher) { hasher.combine(source); hasher.combine(operationWord) }
  public var parameterDomain: ParameterDomain { source.parameterDomain }
  public func validate(tolerance: ModelingTolerance) throws {
    var usage = try OriginalQueryExecution.independentGeometry()
    try validateOriginalRelation(tolerance: tolerance, remainingSourceDepth: usage.limits.remainingSourceDepth,
      maximumSubdivisionDepth: usage.limits.maximumSubdivisionDepth, using: &usage)
  }

  package func sourceCalculationTolerance<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance,
    using usage: inout A) throws -> ModelingTolerance {
    try admitCoefficientProof(using: &usage)
    if case .some = circularCoefficients { return tolerance }
    return try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
      word: preparedWord, tolerance: tolerance, usage: &usage)
  }

  package func validateOriginalRelation(tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil,
    using usage: inout OriginalQueryExecution) throws {
    try admitCoefficientProof(using: &usage)
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original word descendant exhausted source depth.")
    }
      if let maximumAlgebraicDepth {
        try operationWord.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
      } else {
        try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
      }
      if let _ = try OriginalAffineWordCircularCoefficients.prepare(source: source, word: preparedWord,
          tolerance: tolerance, usage: &usage) { return }
      let local = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      try source.validateOriginalSource(tolerance: local, remainingSourceDepth: remainingSourceDepth - 1,
        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &usage)
  }

  public func point(at parameter: Double,
    tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution) throws -> Point3D {
    try admitCoefficientProof(using: &usage)
    if let circularCoefficients {
      let value = try circularCoefficients.intervalTaylorJet(over: .init(lower: parameter, upper: parameter),
        throughOrder: 0, tolerance: tolerance, using: &usage)
      let bounds = try IntervalVector3DBounds(x: value.x.coefficient(0, 0), y: value.y.coefficient(0, 0), z: value.z.coefficient(0, 0))
      let point = Point3D(x: bounds.x.midpoint, y: bounds.y.midpoint, z: bounds.z.midpoint)
      let radius = IntervalVector3DBounds(x: bounds.x - .exact(point.x), y: bounds.y - .exact(point.y), z: bounds.z - .exact(point.z)).lengthUpperBound
      guard radius <= tolerance.distance else {
        throw GeometryConversionError.resourceLimitExceeded("Original world circular point requires a tighter finite source enclosure.")
      }
      return point
    }
    return try preparedWord.applying(to: source.pointAssumingValid(at: parameter, tolerance: sourceTolerance, using: &usage), usage: &usage)
  }
  public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try point(at: parameter, tolerance: tolerance, using: &usage)
  }
  public func differentialGeometry(at parameter: Double, tolerance: ModelingTolerance)
    throws -> Curve3D.DifferentialGeometry {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try differentialGeometry(at: parameter, tolerance: tolerance, using: &usage)
  }
  public func differentialGeometry(at parameter: Double, tolerance: ModelingTolerance,
    using usage: inout OriginalQueryExecution) throws -> Curve3D.DifferentialGeometry {
    try admitCoefficientProof(using: &usage)
    let p: Point3D, d1: Vector3D, d2: Vector3D
    if let circularCoefficients {
      let value = try circularCoefficients.intervalTaylorJet(over: .init(lower: parameter, upper: parameter),
        throughOrder: 2, tolerance: tolerance, using: &usage)
      func vector(_ order: Int) throws -> Vector3D {
        let factor = OutwardScalarInterval.exact(order == 2 ? 2 : 1)
        return try .init(x: (value.x.coefficient(order, 0) * factor).midpoint,
          y: (value.y.coefficient(order, 0) * factor).midpoint, z: (value.z.coefficient(order, 0) * factor).midpoint)
      }
      let position = try vector(0)
      p = .init(x: position.x, y: position.y, z: position.z); d1 = try vector(1); d2 = try vector(2)
    } else {
      let q = try source.differentialGeometryAssumingValid(at: parameter, tolerance: sourceTolerance, using: &usage)
      p = try preparedWord.applying(to: q.position, usage: &usage)
      d1 = try preparedWord.applying(to: q.firstDerivative, usage: &usage)
      d2 = try preparedWord.applying(to: q.secondDerivative, usage: &usage)
    }
    let speed = d1.length
    guard speed.isFinite, speed > tolerance.distance else {
      throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
        message: "Original affine curve has no admitted numerical tangent at this station.")
    }
    let tangent = d1 / speed
    let curvature = (d2 - tangent * d2.dot(tangent)) / (speed * speed)
    return .init(position: p, firstDerivative: d1, secondDerivative: d2, tangent: tangent,
      curvatureVector: curvature, curvature: curvature.length)
  }
  public func applying(to point: Point3D) throws -> Point3D {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try preparedWord.applying(to: point, usage: &usage)
  }
}
