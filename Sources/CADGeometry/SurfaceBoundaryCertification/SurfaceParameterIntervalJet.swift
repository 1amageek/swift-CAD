import CADCore

/// Shared interval derivatives of numeric surface parameter charts.
struct SurfaceParameterIntervalJet {
  static func enclose(
    _ curve: SurfaceParameterCurve, over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try enclose(curve, over: parameters, tolerance: tolerance, using: &execution)
  }
  static func enclose(
    _ curve: SurfaceParameterCurve, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
    try execution.consumeWork(1)
    let fraction = SurfaceIntervalJet.parameterU(parameters)
    func parameter(_ start: Double, _ end: Double) -> SurfaceIntervalJet {
      .constant(start) + (.constant(end) + .constant(-start)) * fraction
    }
    switch curve {
    case .originalAffineWord(let image): return try image.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
    case .originalImage(let image): return try image.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
    case let .affine(origin, direction, start, end):
      let t = parameter(start, end)
      return (.constant(origin.x) + .constant(direction.x) * t,
              .constant(origin.y) + .constant(direction.y) * t)
    case let .constantU(u, start, end):
      return (.constant(u), parameter(start, end))
    case let .constantV(v, start, end):
      return (parameter(start, end), .constant(v))
    case let .harmonic(center, cosine, sine, start, end):
      let t = parameter(start, end)
      let c = try SurfaceIntervalJet.cosine(of: t, using: &execution)
      let s = try SurfaceIntervalJet.sine(of: t, using: &execution)
      return (.constant(center.x) + .constant(cosine.x) * c + .constant(sine.x) * s,
              .constant(center.y) + .constant(cosine.y) * c + .constant(sine.y) * s)
    case let .originalBSplineContinuation(curve):
      return try curve.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
    case let .bSpline(curve):
      try curve.validate(tolerance: tolerance, using: &execution)
      guard case let .closed(lower, upper) = curve.domain else { return nil }
      let t = parameter(lower, upper)
      let interval = try ScalarInterval(lower: max(lower, t.value.lower), upper: min(upper, t.value.upper))
      let spatial = BSplineCurve3D(degree: curve.degree, knots: curve.knots,
        controlPoints: try OriginalCoefficientAllocation.map(elements: curve.controlPoints, using: &execution) { point, _ in
          Point3D(x: point.x, y: point.y, z: 0)
        }, weights: curve.weights)
      let native = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: .bSpline(spatial), over: interval, tolerance: tolerance, using: &execution)
      let normalized = SurfaceParameterThirdOrderChainRule.intervalJet(
        surface: native, u: t, v: .constant(0))
      return (normalized.x, normalized.y)
    case let .offsetSurfaceImage(image):
      return try Self.enclose(image.source, over: parameters, tolerance: tolerance, using: &execution)
    case let .periodicTranslation(base, uShift, vShift):
      guard let base = try Self.enclose(base, over: parameters, tolerance: tolerance, using: &execution) else { return nil }
      return (base.u + .constant(uShift), base.v + .constant(vShift))
    default: return nil
    }
  }
}
