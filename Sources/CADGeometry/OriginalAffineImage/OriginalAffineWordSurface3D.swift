import CADCore

/// Original support image retaining its native UV and a flat exact spatial word.
public struct OriginalAffineWordSurface3D: Hashable, Sendable {
  public let source: Surface3D
  public let operationWord: OriginalAffineOperationWord
  package let preparedWord: PreparedOriginalAffineOperationWord
  package let sourceTolerance: ModelingTolerance
  package let harmonicCoefficients: OriginalAffineWordHarmonicSurfaceCoefficients?
  private let coefficientProofDepth: ExactScalarDepth

  /// Ordinary numerical convenience creates one independent execution.
  public init(source: Surface3D, operationWord: OriginalAffineOperationWord,
    tolerance: ModelingTolerance) throws {
    var usage = try OriginalQueryExecution.independentGeometry()
    try self.init(source: source, operationWord: operationWord, tolerance: tolerance,
      remainingSourceDepth: usage.limits.remainingSourceDepth,
      maximumSubdivisionDepth: usage.limits.maximumSubdivisionDepth, usage: &usage)
  }

  public init(source: Surface3D,
    operationWord: OriginalAffineOperationWord, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, usage: inout OriginalQueryExecution) throws {
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original affine support requires a remaining source descendant.")
    }
    let calculation = try ExactScalarNumericAccess.withAdmission(&usage) { usage in
      if let maximumAlgebraicDepth {
        guard maximumAlgebraicDepth >= 0 else { throw GeometryConversionError.invalidInput("Original word algebraic depth must be nonnegative.") }
        try operationWord.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
      } else { try operationWord.validateOriginal(tolerance: tolerance, usage: &usage) }
      let prepared = try operationWord.prepared(usage: &usage)
      let coefficients = try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source,
        word: prepared, tolerance: tolerance, usage: &usage)
      let local = try coefficients != nil ? tolerance : OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: prepared, tolerance: tolerance, usage: &usage)
      return (prepared, coefficients, local)
    }
    self.source = source; self.operationWord = operationWord
    preparedWord = calculation.value.0; harmonicCoefficients = calculation.value.1
    sourceTolerance = calculation.value.2; coefficientProofDepth = calculation.depth
    if harmonicCoefficients == nil {
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
  public var uDomain: ParameterDomain { source.uDomain }
  public var vDomain: ParameterDomain { source.vDomain }
  public func validate(tolerance: ModelingTolerance) throws {
    var usage = try OriginalQueryExecution.independentGeometry()
    try validateOriginalRelation(tolerance: tolerance, remainingSourceDepth: usage.limits.remainingSourceDepth,
      maximumSubdivisionDepth: usage.limits.maximumSubdivisionDepth, using: &usage)
  }

  package func sourceCalculationTolerance<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance,
    using usage: inout A) throws -> ModelingTolerance {
    try admitCoefficientProof(using: &usage)
    if harmonicCoefficients != nil { return tolerance }
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
      if try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source,
        word: preparedWord, tolerance: tolerance, usage: &usage) != nil { return }
      let local = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      try source.validateOriginalSource(tolerance: local, remainingSourceDepth: remainingSourceDepth - 1,
        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &usage)
  }

  public func point(u: Double, v: Double,
    tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution) throws -> Point3D {
    try admitCoefficientProof(using: &usage)
    if let coefficients = harmonicCoefficients {
      let box = SurfaceParameterBox(u: try .init(lower: u, upper: u), v: try .init(lower: v, upper: v))
      let jet = try coefficients.intervalTaylorJet(over: box, throughOrder: 0, tolerance: tolerance, using: &usage)
      let position = try IntervalVector3DBounds(x: jet.x.coefficient(0,0), y: jet.y.coefficient(0,0), z: jet.z.coefficient(0,0))
      let point = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
      let residual = (position - .init(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))).lengthUpperBound
      guard residual.isFinite, residual <= tolerance.distance else {
        throw GeometryConversionError.resourceLimitExceeded("Original harmonic image point exceeds its physical rounding allocation.")
      }
      return point
    }
    return try preparedWord.applying(to: source.pointAssumingValid(u: u, v: v, tolerance: sourceTolerance, using: &usage), usage: &usage)
  }
  public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try point(u: u, v: v, tolerance: tolerance, using: &usage)
  }
  public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
    tolerance: ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &usage)
  }
  public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
    tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution) throws -> SurfaceParameterThirdOrderDerivatives {
    try admitCoefficientProof(using: &usage)
    if let coefficients = harmonicCoefficients {
      let jet = try coefficients.intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: 3, tolerance: tolerance, using: &usage).intervalJet()
      return .init(position: .init(x: jet.x.value.midpoint, y: jet.y.value.midpoint, z: jet.z.value.midpoint),
        tangentU: .init(x: jet.x.derivativeU.midpoint, y: jet.y.derivativeU.midpoint, z: jet.z.derivativeU.midpoint),
        tangentV: .init(x: jet.x.derivativeV.midpoint, y: jet.y.derivativeV.midpoint, z: jet.z.derivativeV.midpoint),
        secondDerivativeUU: .init(x: jet.x.secondDerivativeUU.midpoint, y: jet.y.secondDerivativeUU.midpoint, z: jet.z.secondDerivativeUU.midpoint),
        secondDerivativeUV: .init(x: jet.x.secondDerivativeUV.midpoint, y: jet.y.secondDerivativeUV.midpoint, z: jet.z.secondDerivativeUV.midpoint),
        secondDerivativeVV: .init(x: jet.x.secondDerivativeVV.midpoint, y: jet.y.secondDerivativeVV.midpoint, z: jet.z.secondDerivativeVV.midpoint),
        thirdDerivativeUUU: .init(x: jet.x.thirdDerivativeUUU.midpoint, y: jet.y.thirdDerivativeUUU.midpoint, z: jet.z.thirdDerivativeUUU.midpoint),
        thirdDerivativeUUV: .init(x: jet.x.thirdDerivativeUUV.midpoint, y: jet.y.thirdDerivativeUUV.midpoint, z: jet.z.thirdDerivativeUUV.midpoint),
        thirdDerivativeUVV: .init(x: jet.x.thirdDerivativeUVV.midpoint, y: jet.y.thirdDerivativeUVV.midpoint, z: jet.z.thirdDerivativeUVV.midpoint),
        thirdDerivativeVVV: .init(x: jet.x.thirdDerivativeVVV.midpoint, y: jet.y.thirdDerivativeVVV.midpoint, z: jet.z.thirdDerivativeVVV.midpoint))
    }
    let q = try source.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: sourceTolerance, using: &usage)
    let p = try preparedWord.applying(to: q.position, usage: &usage)
    let du = try preparedWord.applying(to: q.tangentU, usage: &usage)
    let dv = try preparedWord.applying(to: q.tangentV, usage: &usage)
    let duu = try preparedWord.applying(to: q.secondDerivativeUU, usage: &usage)
    let duv = try preparedWord.applying(to: q.secondDerivativeUV, usage: &usage)
    let dvv = try preparedWord.applying(to: q.secondDerivativeVV, usage: &usage)
    let duuu = try preparedWord.applying(to: q.thirdDerivativeUUU, usage: &usage)
    let duuv = try preparedWord.applying(to: q.thirdDerivativeUUV, usage: &usage)
    let duvv = try preparedWord.applying(to: q.thirdDerivativeUVV, usage: &usage)
    let dvvv = try preparedWord.applying(to: q.thirdDerivativeVVV, usage: &usage)
    return .init(position: p, tangentU: du, tangentV: dv, secondDerivativeUU: duu,
      secondDerivativeUV: duv, secondDerivativeVV: dvv, thirdDerivativeUUU: duuu,
      thirdDerivativeUUV: duuv, thirdDerivativeUVV: duvv, thirdDerivativeVVV: dvvv)
  }
  public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance)
    throws -> SurfaceParameterDerivatives {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &usage)
  }
  public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance,
    using usage: inout OriginalQueryExecution) throws -> SurfaceParameterDerivatives {
    let q = try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &usage)
    return .init(position: q.position, tangentU: q.tangentU, tangentV: q.tangentV,
      secondDerivativeUU: q.secondDerivativeUU, secondDerivativeUV: q.secondDerivativeUV,
      secondDerivativeVV: q.secondDerivativeVV)
  }
  func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try intervalJet(over: box, tolerance: tolerance, using: &usage)
  }
  func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
    using usage: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
    try admitCoefficientProof(using: &usage)
    if let coefficients = harmonicCoefficients {
      return try coefficients.intervalTaylorJet(over: box, throughOrder: 3, tolerance: tolerance,
        using: &usage).intervalJet()
    }
    let original = try PreparedSurfaceDifferentialEncloser(surface: source, tolerance: sourceTolerance, using: &usage)
      .intervalJet(overClosedBox: box, tolerance: sourceTolerance, using: &usage)
    return try OriginalAffineWordJetTransport.applying(preparedWord, to: original, using: &usage)
  }

  func taylorJet(u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
    var usage = try OriginalQueryExecution.independentGeometry()
    return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &usage)
  }
  func taylorJet(u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
    try admitCoefficientProof(using: &usage)
    if let coefficients = harmonicCoefficients {
      let jet = try coefficients.intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: order, tolerance: tolerance, using: &usage)
    var x = try SurfaceTaylorScalarJet(order: order, using: &usage), y = try SurfaceTaylorScalarJet(order: order, using: &usage), z = try SurfaceTaylorScalarJet(order: order, using: &usage)
      for total in 0...order { for a in 0...total {
        try usage.consumeWork(1); let b = total-a
        try x.setCoefficient(jet.x.coefficient(a,b).midpoint, uOrder: a, vOrder: b, using: &usage)
        try y.setCoefficient(jet.y.coefficient(a,b).midpoint, uOrder: a, vOrder: b, using: &usage)
        try z.setCoefficient(jet.z.coefficient(a,b).midpoint, uOrder: a, vOrder: b, using: &usage)
      } }
      return try .init(x: x, y: y, z: z)
    }
    let original = try source.taylorJet(u: u, v: v, throughOrder: order, tolerance: sourceTolerance, using: &usage)
    var x = try SurfaceTaylorScalarJet(order: order, using: &usage)
    var y = try SurfaceTaylorScalarJet(order: order, using: &usage)
    var z = try SurfaceTaylorScalarJet(order: order, using: &usage)
    for total in 0...order { for a in 0...total {
      try usage.consumeWork(1)
      let b = total - a
      let raw = Vector3D(x: original.x[a,b], y: original.y[a,b], z: original.z[a,b])
      let value: Vector3D
      if total == 0 {
        let point = try preparedWord.applying(to: Point3D(x: raw.x, y: raw.y, z: raw.z), usage: &usage)
        value = Vector3D(x: point.x, y: point.y, z: point.z)
      } else { value = try preparedWord.applying(to: raw, usage: &usage) }
      try x.setCoefficient(value.x, uOrder: a, vOrder: b, using: &usage)
      try y.setCoefficient(value.y, uOrder: a, vOrder: b, using: &usage)
      try z.setCoefficient(value.z, uOrder: a, vOrder: b, using: &usage)
    } }
    return try .init(x: x, y: y, z: z)
  }
}
