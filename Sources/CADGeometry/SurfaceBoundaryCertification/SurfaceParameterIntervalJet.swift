import CADCore

/// Shared interval derivatives of numeric surface parameter charts.
struct SurfaceParameterIntervalJet {
  static func enclose(
    _ curve: SurfaceParameterCurve, over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
    let fraction = SurfaceIntervalJet.parameterU(parameters)
    func parameter(_ start: Double, _ end: Double) -> SurfaceIntervalJet {
      .constant(start) + (.constant(end) + .constant(-start)) * fraction
    }
    switch curve {
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
      let c = SurfaceIntervalJet.cosine(of: t)
      let s = SurfaceIntervalJet.sine(of: t)
      return (.constant(center.x) + .constant(cosine.x) * c + .constant(sine.x) * s,
              .constant(center.y) + .constant(cosine.y) * c + .constant(sine.y) * s)
    case let .bSpline(curve):
      try curve.validate(tolerance: tolerance)
      guard case let .closed(lower, upper) = curve.domain else { return nil }
      let t = parameter(lower, upper)
      let interval = try ScalarInterval(lower: max(lower, t.value.lower), upper: min(upper, t.value.upper))
      let spatial = BSplineCurve3D(degree: curve.degree, knots: curve.knots,
        controlPoints: curve.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }, weights: curve.weights)
      let native = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: .bSpline(spatial), over: interval, tolerance: tolerance)
      let normalized = SurfaceParameterThirdOrderChainRule.intervalJet(
        surface: native, u: t, v: .constant(0))
      return (normalized.x, normalized.y)
    case let .offsetSurfaceImage(image):
      return try Self.enclose(image.source, over: parameters, tolerance: tolerance)
    case let .periodicTranslation(base, uShift, vShift):
      guard let base = try Self.enclose(base, over: parameters, tolerance: tolerance) else { return nil }
      return (base.u + .constant(uShift), base.v + .constant(vShift))
    default: return nil
    }
  }
}
