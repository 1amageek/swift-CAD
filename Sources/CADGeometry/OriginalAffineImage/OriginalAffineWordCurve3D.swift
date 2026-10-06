import CADCore

/// Parameter-preserving original curve image under a flat exact spatial word.
public struct OriginalAffineWordCurve3D: Hashable, Sendable {
  public let source: Curve3D
  public let operationWord: OriginalAffineOperationWord
  package let preparedWord: PreparedOriginalAffineOperationWord
  package let sourceTolerance: ModelingTolerance
  package let circularCoefficients: OriginalAffineWordCircularCoefficients?

  /// Cancellation-only legacy convenience preserving the complete stored word.
  public init(source: Curve3D, operationWord: OriginalAffineOperationWord,
    tolerance: ModelingTolerance) throws {
    var usage = OriginalAffineImageLegacyUsage()
    try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
    self.source = source; self.operationWord = operationWord
    preparedWord = try operationWord.prepared(usage: &usage)
    circularCoefficients = try OriginalAffineWordCircularCoefficients.prepare(source: source,
      word: preparedWord, tolerance: tolerance, usage: &usage)
    if case .some = circularCoefficients { sourceTolerance = tolerance }
    else {
      sourceTolerance = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      try source.validate(tolerance: sourceTolerance)
    }
  }

  public init<B: RationalAlgebraAdmitting>(source: Curve3D,
    operationWord: OriginalAffineOperationWord, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, usage: inout B) throws {
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original affine image requires a remaining source descendant.")
    }
    if let maximumAlgebraicDepth {
      guard maximumAlgebraicDepth >= 0 else { throw GeometryConversionError.invalidInput("Original word algebraic depth must be nonnegative.") }
      try operationWord.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
    } else {
      try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
    }
    self.source = source; self.operationWord = operationWord
    preparedWord = try operationWord.prepared(usage: &usage)
    circularCoefficients = try OriginalAffineWordCircularCoefficients.prepare(source: source,
      word: preparedWord, tolerance: tolerance, usage: &usage)
    if case .some = circularCoefficients { sourceTolerance = tolerance }
    else {
      sourceTolerance = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      func work(_ depth: Int) throws { try usage.consumeExactWork(1) }
      func bytes(_ count: Int) throws { try RationalAlgebraStorage.retainBytes(count, usage: &usage) }
      try withoutActuallyEscaping(work) { visit in
        try withoutActuallyEscaping(bytes) { storage in
          try source.validateOriginalSource(tolerance: sourceTolerance,
            remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: visit, consumeStorage: storage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
      }
    }
  }

  public static func == (a: Self, b: Self) -> Bool { a.source == b.source && a.operationWord == b.operationWord }
  public func hash(into hasher: inout Hasher) { hasher.combine(source); hasher.combine(operationWord) }
  public var parameterDomain: ParameterDomain { source.parameterDomain }
  public func validate(tolerance: ModelingTolerance) throws {
    var usage = OriginalAffineImageLegacyUsage()
    try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
    if let _ = try OriginalAffineWordCircularCoefficients.prepare(source: source, word: preparedWord,
        tolerance: tolerance, usage: &usage) { return }
    do {
      let local = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      try source.validate(tolerance: local)
    }
  }

  package func sourceCalculationTolerance(tolerance: ModelingTolerance,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> ModelingTolerance {
    if case .some = circularCoefficients { return tolerance }
    return try withoutActuallyEscaping(consumeWork) { work in
      var usage = OriginalGeometryValidationAdmission(consumeWork: { _ in try work() }, consumeStorage: consumeStorage)
      return try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
    }
  }

  package func validateOriginalRelation(tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
    consumeWork: (Int) throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
    maximumAlgebraicDepth: Int? = nil) throws {
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original word descendant exhausted source depth.")
    }
    try withoutActuallyEscaping(consumeWork) { work in
      var usage = OriginalGeometryValidationAdmission(consumeWork: work, consumeStorage: consumeStorage)
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
        maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: work, consumeStorage: consumeStorage,
        maximumAlgebraicDepth: maximumAlgebraicDepth)
    }
  }

  public func point<B: RationalAlgebraAdmitting>(at parameter: Double,
    tolerance: ModelingTolerance, usage: inout B) throws -> Point3D {
    if let circularCoefficients {
      let value = try circularCoefficients.intervalTaylorJet(over: .init(lower: parameter, upper: parameter),
        throughOrder: 0, tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
      let bounds = try IntervalVector3DBounds(x: value.x.coefficient(0, 0), y: value.y.coefficient(0, 0), z: value.z.coefficient(0, 0))
      let point = Point3D(x: bounds.x.midpoint, y: bounds.y.midpoint, z: bounds.z.midpoint)
      let radius = IntervalVector3DBounds(x: bounds.x - .exact(point.x), y: bounds.y - .exact(point.y), z: bounds.z - .exact(point.z)).lengthUpperBound
      guard radius <= tolerance.distance else {
        throw GeometryConversionError.resourceLimitExceeded("Original world circular point requires a tighter finite source enclosure.")
      }
      return point
    }
    return try preparedWord.applying(to: source.pointAssumingValid(at: parameter, tolerance: sourceTolerance), usage: &usage)
  }
  public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var usage = OriginalAffineImageLegacyUsage()
    return try point(at: parameter, tolerance: tolerance, usage: &usage)
  }
  public func differentialGeometry(at parameter: Double, tolerance: ModelingTolerance)
    throws -> Curve3D.DifferentialGeometry {
    var usage = OriginalAffineImageLegacyUsage()
    let p: Point3D, d1: Vector3D, d2: Vector3D
    if let circularCoefficients {
      let value = try circularCoefficients.intervalTaylorJet(over: .init(lower: parameter, upper: parameter),
        throughOrder: 2, tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
      func vector(_ order: Int) throws -> Vector3D {
        let factor = OutwardScalarInterval.exact(order == 2 ? 2 : 1)
        return try .init(x: (value.x.coefficient(order, 0) * factor).midpoint,
          y: (value.y.coefficient(order, 0) * factor).midpoint, z: (value.z.coefficient(order, 0) * factor).midpoint)
      }
      let position = try vector(0)
      p = .init(x: position.x, y: position.y, z: position.z); d1 = try vector(1); d2 = try vector(2)
    } else {
      let q = try source.differentialGeometryAssumingValid(at: parameter, tolerance: sourceTolerance)
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
    var usage = OriginalAffineImageLegacyUsage()
    return try preparedWord.applying(to: point, usage: &usage)
  }
}
