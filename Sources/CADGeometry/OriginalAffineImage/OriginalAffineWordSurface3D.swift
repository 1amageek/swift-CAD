import CADCore

/// Original support image retaining its native UV and a flat exact spatial word.
public struct OriginalAffineWordSurface3D: Hashable, Sendable {
  public let source: Surface3D
  public let operationWord: OriginalAffineOperationWord
  package let preparedWord: PreparedOriginalAffineOperationWord
  package let sourceTolerance: ModelingTolerance
  package let harmonicCoefficients: OriginalAffineWordHarmonicSurfaceCoefficients?

  /// Cancellation-only legacy convenience preserving the complete stored word.
  public init(source: Surface3D, operationWord: OriginalAffineOperationWord,
    tolerance: ModelingTolerance) throws {
    var usage = OriginalAffineImageLegacyUsage()
    try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
    self.source = source; self.operationWord = operationWord
    preparedWord = try operationWord.prepared(usage: &usage)
    harmonicCoefficients = try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source,
      word: preparedWord, tolerance: tolerance, usage: &usage)
    if harmonicCoefficients != nil { sourceTolerance = tolerance }
    else {
      sourceTolerance = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      try source.validate(tolerance: sourceTolerance)
    }
  }

  public init<B: RationalAlgebraAdmitting>(source: Surface3D,
    operationWord: OriginalAffineOperationWord, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil, usage: inout B) throws {
    guard remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original affine support requires a remaining source descendant.")
    }
    if let maximumAlgebraicDepth {
      guard maximumAlgebraicDepth >= 0 else { throw GeometryConversionError.invalidInput("Original word algebraic depth must be nonnegative.") }
      try operationWord.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
    } else {
      try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
    }
    self.source = source; self.operationWord = operationWord
    preparedWord = try operationWord.prepared(usage: &usage)
    harmonicCoefficients = try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source,
      word: preparedWord, tolerance: tolerance, usage: &usage)
    if harmonicCoefficients != nil { sourceTolerance = tolerance }
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
  public var uDomain: ParameterDomain { source.uDomain }
  public var vDomain: ParameterDomain { source.vDomain }
  public func validate(tolerance: ModelingTolerance) throws {
    var usage = OriginalAffineImageLegacyUsage()
    try operationWord.validateOriginal(tolerance: tolerance, usage: &usage)
    if try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source,
      word: preparedWord, tolerance: tolerance, usage: &usage) != nil { return }
    let local = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
      word: preparedWord, tolerance: tolerance, usage: &usage)
    try source.validate(tolerance: local)
  }

  package func sourceCalculationTolerance(tolerance: ModelingTolerance,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> ModelingTolerance {
    if harmonicCoefficients != nil { return tolerance }
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
      if try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source,
        word: preparedWord, tolerance: tolerance, usage: &usage) != nil { return }
      let local = try OriginalAffineWordPhysicalAdmission.sourceTolerance(for: source,
        word: preparedWord, tolerance: tolerance, usage: &usage)
      try source.validateOriginalSource(tolerance: local, remainingSourceDepth: remainingSourceDepth - 1,
        maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: work, consumeStorage: consumeStorage,
        maximumAlgebraicDepth: maximumAlgebraicDepth)
    }
  }

  public func point<B: RationalAlgebraAdmitting>(u: Double, v: Double,
    tolerance: ModelingTolerance, usage: inout B) throws -> Point3D {
    if let coefficients = harmonicCoefficients {
      let box = SurfaceParameterBox(u: try .init(lower: u, upper: u), v: try .init(lower: v, upper: v))
      func bytes(_ count: Int) throws { try RationalAlgebraStorage.retainBytes(count, usage: &usage) }
      let jet = try withoutActuallyEscaping(bytes) { storage in
        try coefficients.intervalTaylorJet(over: box, throughOrder: 0, tolerance: tolerance,
          consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
      }
      let position = try IntervalVector3DBounds(x: jet.x.coefficient(0,0), y: jet.y.coefficient(0,0), z: jet.z.coefficient(0,0))
      let point = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
      let residual = (position - .init(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))).lengthUpperBound
      guard residual.isFinite, residual <= tolerance.distance else {
        throw GeometryConversionError.resourceLimitExceeded("Original harmonic image point exceeds its physical rounding allocation.")
      }
      return point
    }
    return try preparedWord.applying(to: source.pointAssumingValid(u: u, v: v, tolerance: sourceTolerance), usage: &usage)
  }
  public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var usage = OriginalAffineImageLegacyUsage()
    return try point(u: u, v: v, tolerance: tolerance, usage: &usage)
  }
  public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
    tolerance: ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
    var usage = OriginalAffineImageLegacyUsage()
    if let coefficients = harmonicCoefficients {
      let jet = try coefficients.intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: 3, tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) }).intervalJet()
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
    let q = try source.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: sourceTolerance)
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
    let q = try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance)
    return .init(position: q.position, tangentU: q.tangentU, tangentV: q.tangentV,
      secondDerivativeUU: q.secondDerivativeUU, secondDerivativeUV: q.secondDerivativeUV,
      secondDerivativeVV: q.secondDerivativeVV)
  }
  func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    if let coefficients = harmonicCoefficients {
      return try coefficients.intervalTaylorJet(over: box, throughOrder: 3, tolerance: tolerance,
        consumeWork: { try Task.checkCancellation() }).intervalJet()
    }
    let original = try PreparedSurfaceDifferentialEncloser(surface: source, tolerance: sourceTolerance)
      .intervalJet(overClosedBox: box, tolerance: sourceTolerance)
    var usage = OriginalAffineImageLegacyUsage()
    return try OriginalAffineWordJetTransport.applying(preparedWord, to: original, usage: &usage)
  }

  func taylorJet(u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
    if let coefficients = harmonicCoefficients {
      let jet = try coefficients.intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: order, tolerance: tolerance, consumeWork: { try Task.checkCancellation() })
      var x = try SurfaceTaylorScalarJet(order: order), y = try SurfaceTaylorScalarJet(order: order), z = try SurfaceTaylorScalarJet(order: order)
      for total in 0...order { for a in 0...total {
        try Task.checkCancellation(); let b = total-a
        try x.setCoefficient(jet.x.coefficient(a,b).midpoint, uOrder: a, vOrder: b)
        try y.setCoefficient(jet.y.coefficient(a,b).midpoint, uOrder: a, vOrder: b)
        try z.setCoefficient(jet.z.coefficient(a,b).midpoint, uOrder: a, vOrder: b)
      } }
      return .init(x: x, y: y, z: z)
    }
    let original = try source.taylorJet(u: u, v: v, throughOrder: order, tolerance: sourceTolerance)
    var usage = OriginalAffineImageLegacyUsage()
    var x = try SurfaceTaylorScalarJet(order: order)
    var y = try SurfaceTaylorScalarJet(order: order)
    var z = try SurfaceTaylorScalarJet(order: order)
    for total in 0...order { for a in 0...total {
      try Task.checkCancellation()
      let b = total - a
      let raw = Vector3D(x: original.x[a,b], y: original.y[a,b], z: original.z[a,b])
      let value: Vector3D
      if total == 0 {
        let point = try preparedWord.applying(to: Point3D(x: raw.x, y: raw.y, z: raw.z), usage: &usage)
        value = Vector3D(x: point.x, y: point.y, z: point.z)
      } else { value = try preparedWord.applying(to: raw, usage: &usage) }
      try x.setCoefficient(value.x, uOrder: a, vOrder: b)
      try y.setCoefficient(value.y, uOrder: a, vOrder: b)
      try z.setCoefficient(value.z, uOrder: a, vOrder: b)
    } }
    return .init(x: x, y: y, z: z)
  }
}
