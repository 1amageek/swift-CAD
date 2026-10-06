import CADCore

/// Original UV traversal hosted by an exact flat-word support image.
public struct OriginalAffineWordSurfaceParameterCurve: Hashable, Sendable {
  public let source: SurfaceLiftCurve3D
  public let target: OriginalAffineWordSurface3D
  public let startFraction: Double
  public let endFraction: Double

  /// Legacy numerical/source convenience with cancellation and no new caller ceiling.
  public init(source: SurfaceLiftCurve3D, target: OriginalAffineWordSurface3D,
    startFraction: Double = 0, endFraction: Double = 1, tolerance: ModelingTolerance) throws {
    self.source = source; self.target = target
    self.startFraction = startFraction; self.endFraction = endFraction
    try source.validate(tolerance: tolerance); try target.validate(tolerance: tolerance)
    try binding(on: .procedural(.originalAffineWord(target)), tolerance: tolerance)
  }

  public init<B: RationalAlgebraAdmitting>(source: SurfaceLiftCurve3D,
    target: OriginalAffineWordSurface3D, startFraction: Double = 0, endFraction: Double = 1,
    tolerance: ModelingTolerance, remainingSourceDepth: Int,
    maximumSubdivisionDepth: Int, usage: inout B) throws {
    guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word pcurve needs source admission.") }
    try Curve3D.surfaceLift(source).validateOriginalSource(tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth - 1, maximumSubdivisionDepth: maximumSubdivisionDepth,
      consumeWork: { _ in try usage.consumeExactWork(1) })
    self.source = source; self.target = target
    self.startFraction = startFraction; self.endFraction = endFraction
    try GeometryStructuralComparisonWork.charge(surface: source.surface, using: { try usage.consumeExactWork($0) })
    try GeometryStructuralComparisonWork.charge(surface: target.source, using: { try usage.consumeExactWork($0) })
    try binding(on: .procedural(.originalAffineWord(target)), tolerance: tolerance)
  }
  private func binding(on surface: Surface3D, tolerance: ModelingTolerance) throws {
    guard source.surface == target.source, surface == .procedural(.originalAffineWord(target)),
      startFraction.isFinite, endFraction.isFinite, startFraction >= 0, startFraction <= 1,
      endFraction >= 0, endFraction <= 1, startFraction != endFraction else {
      throw GeometryConversionError.invalidInput("Original word pcurve requires exact support binding and directed fractions.")
    }
  }
  public func validate(on surface: Surface3D, tolerance: ModelingTolerance) throws {
    try source.validate(tolerance: tolerance); try target.validate(tolerance: tolerance)
    try binding(on: surface, tolerance: tolerance)
  }
  private func mappedFraction(_ f: Double) throws -> Double {
    guard f.isFinite, f >= 0, f <= 1 else { throw GeometryConversionError.invalidInput("Original word pcurve fraction exceeds its closed chart.") }
    if f == 0 { return startFraction }; if f == 1 { return endFraction }
    return startFraction + (endFraction - startFraction) * f
  }
  package func mappedRange(_ range: ScalarInterval) throws -> ScalarInterval {
    guard range.lower >= 0, range.upper <= 1 else { throw GeometryConversionError.invalidInput("Original word pcurve range exceeds its closed chart.") }
    if range.lower == range.upper, range.lower == 0 || range.lower == 1 {
      let endpoint = range.lower == 0 ? startFraction : endFraction
      return try .init(lower: endpoint, upper: endpoint)
    }
    let gain = OutwardScalarInterval.exact(endFraction) - .exact(startFraction)
    let value = OutwardScalarInterval.exact(startFraction) + gain * .init(lower: range.lower, upper: range.upper)
    guard let clipped = value.intersection(with: .init(lower: min(startFraction, endFraction), upper: max(startFraction, endFraction))) else {
      throw GeometryConversionError.invalidInput("Original word pcurve has no directed source image.")
    }
    return try .init(lower: clipped.lower, upper: clipped.upper)
  }
  public func parameter(atNormalizedFraction fraction: Double, tolerance: ModelingTolerance) throws -> SurfaceParameter {
    try source.parameterCurve.parameter(atNormalizedFraction: mappedFraction(fraction), tolerance: tolerance)
  }
  public func differential(atNormalizedFraction fraction: Double, tolerance: ModelingTolerance) throws -> SurfaceParameterCurveDifferential {
    let q = try source.parameterCurve.differentialGeometry(atNormalizedFraction: mappedFraction(fraction), tolerance: tolerance)
    let scale = endFraction - startFraction
    return .init(parameter: q.parameter, firstDerivative: q.firstDerivative * scale,
      secondDerivative: q.secondDerivative * (scale * scale))
  }
  func thirdDerivative(atNormalizedFraction fraction: Double, tolerance: ModelingTolerance) throws -> Point2D {
    let q = try source.parameterCurve.thirdOrderDifferential(atNormalizedFraction: mappedFraction(fraction), on: source.surface, tolerance: tolerance)
    let s = endFraction - startFraction
    return q.thirdDerivative * (s * s * s)
  }
  package func parameterBounds(over range: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void) throws -> SurfaceParameterBox {
    let q = try OriginalParameterCurveHigherTaylor.enclosure(source.parameterCurve,
      over: mappedRange(range), order: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork)
    let u = try q.u.coefficient(0, 0), v = try q.v.coefficient(0, 0)
    return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
  }
  package func modelSpaceDifferential(atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance) throws -> SurfaceLiftCurve3D.DifferentialGeometry {
    var usage = OriginalAffineImageLegacyUsage()
    let q = try source.differentialGeometry(atNormalizedFraction: mappedFraction(fraction), tolerance: tolerance)
    let p = try target.preparedWord.applying(to: q.position, usage: &usage)
    let a = try target.preparedWord.applying(to: q.firstDerivative, usage: &usage)
    let b = try target.preparedWord.applying(to: q.secondDerivative, usage: &usage)
    let s = endFraction - startFraction
    return .init(position: p, firstDerivative: a * s, secondDerivative: b * (s * s))
  }
  package func modelSpaceThirdOrder(atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance) throws -> CurveParameterThirdOrderDerivatives {
    var usage = OriginalAffineImageLegacyUsage()
    let q = try Curve3D.surfaceLift(source).parameterDerivativesThroughThirdOrder(at: mappedFraction(fraction), tolerance: tolerance)
    let p = try target.preparedWord.applying(to: q.position, usage: &usage)
    let a = try target.preparedWord.applying(to: q.firstDerivative, usage: &usage)
    let b = try target.preparedWord.applying(to: q.secondDerivative, usage: &usage)
    let c = try target.preparedWord.applying(to: q.thirdDerivative, usage: &usage)
    let s = endFraction - startFraction
    return .init(position: p, firstDerivative: a * s, secondDerivative: b * (s * s), thirdDerivative: c * (s * s * s))
  }
  func intervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
    preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil)
    throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
    guard let original = try DefaultCurveDifferentialEncloser().parameterJets(source.parameterCurve,
      over: mappedRange(range), tolerance: tolerance, preparedImplicit: preparedImplicit) else { return nil }
    let gain = OutwardScalarInterval.exact(endFraction) - .exact(startFraction)
    func scaled(_ q: SurfaceIntervalJet) -> SurfaceIntervalJet {
      .init(value: q.value, derivativeU: q.derivativeU * gain, derivativeV: .exact(0),
        secondDerivativeUU: q.secondDerivativeUU * gain * gain,
        secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
        thirdDerivativeUUU: q.thirdDerivativeUUU * gain * gain * gain,
        thirdDerivativeUUV: .exact(0), thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
    }
    return (scaled(original.u), scaled(original.v))
  }

  func modelSpaceIntervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
    preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil) throws -> SurfaceIntervalVectorJet? {
    guard let original = try DefaultCurveDifferentialEncloser().directJet(.surfaceLift(source),
      parameters: mappedRange(range), tolerance: tolerance, preparedImplicit: preparedImplicit) else { return nil }
    let gain = OutwardScalarInterval.exact(endFraction) - .exact(startFraction)
    func scaled(_ q: SurfaceIntervalJet) -> SurfaceIntervalJet {
      .init(value: q.value, derivativeU: q.derivativeU * gain, derivativeV: .exact(0),
        secondDerivativeUU: q.secondDerivativeUU * gain * gain,
        secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
        thirdDerivativeUUU: q.thirdDerivativeUUU * gain * gain * gain,
        thirdDerivativeUUV: .exact(0), thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
    }
    var usage = OriginalAffineImageLegacyUsage()
    return try OriginalAffineWordJetTransport.applying(target.preparedWord,
      to: .init(x: scaled(original.x), y: scaled(original.y), z: scaled(original.z)), usage: &usage)
  }

  public func reversed(tolerance: ModelingTolerance) throws -> Self {
    .init(retaining: source, target: target, startFraction: endFraction, endFraction: startFraction)
  }
  public func subcurve(fromNormalizedFraction lower: Double, toNormalizedFraction upper: Double,
    tolerance: ModelingTolerance) throws -> Self {
    guard lower.isFinite, upper.isFinite, lower >= 0, upper <= 1, lower < upper else {
      throw GeometryConversionError.invalidInput("Original word subcurve requires an ordered normalized interval.")
    }
    var usage = OriginalAffineImageLegacyUsage()
    func retainedEndpoint(_ fraction: Double) throws -> Double {
      if fraction == 0 { return startFraction }
      if fraction == 1 { return endFraction }
      let start = try ExactRationalCoefficient.originalDouble(startFraction, usage: &usage)
      let end = try ExactRationalCoefficient.originalDouble(endFraction, usage: &usage)
      let value = try end.subtracting(start, usage: &usage)
        .multiplied(by: .originalDouble(fraction, usage: &usage), usage: &usage)
        .adding(start, usage: &usage)
      let bounds = try value.outwardInterval(usage: &usage)
      guard bounds.lower == bounds.upper else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original word pcurve restrictions
        // are used by trimming and continuation consumers. Nonrepresentable
        // composed endpoints need a retained exact fraction carrier before
        // such restrictions may publish a replacement source traversal.
        throw GeometryConversionError.resourceLimitExceeded("Original word pcurve restriction needs an exact fraction endpoint carrier.")
      }
      return bounds.lower
    }
    return try .init(retaining: source, target: target,
      startFraction: retainedEndpoint(lower), endFraction: retainedEndpoint(upper))
  }
  private init(retaining source: SurfaceLiftCurve3D, target: OriginalAffineWordSurface3D,
    startFraction: Double, endFraction: Double) {
    self.source = source; self.target = target; self.startFraction = startFraction; self.endFraction = endFraction
  }
}
