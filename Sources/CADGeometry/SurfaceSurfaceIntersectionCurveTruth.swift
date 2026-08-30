import CADCore

public indirect enum SurfaceSurfaceIntersectionCurveTruth: Codable, Hashable, Sendable {
  case parametric(Curve3D)
  case implicit(CertifiedImplicitIntersectionCurve)
  case analyticBSpline(CertifiedAnalyticBSplineIntersectionCurve)
  case analyticBSplineTangency(CertifiedAnalyticBSplineTangencyIntersectionCurve)
  case analyticAnalytic(CertifiedAnalyticAnalyticIntersectionCurve)
  case quadraticTangency(CertifiedQuadraticTangencyIntersectionCurve)

  public var curve: Curve3D {
    switch self {
    case .parametric(let curve):
      curve
    case .implicit(let curve):
      .implicit(curve)
    case .analyticBSpline(let curve):
      curve.curve
    case .analyticBSplineTangency(let curve):
      curve.curve
    case .analyticAnalytic(let curve):
      curve.curve
    case .quadraticTangency(let curve):
      curve.curve
    }
  }

  /// Returns component closure only when it is represented by the exact
  /// curve contract. A bounded parameter domain alone does not prove that
  /// its two boundary values denote the same topological point.
  package var certifiedComponentClosure: Bool? {
    if case .implicit(let curve) = self {
      return curve.isClosed
    }
    switch curve.parameterDomain {
    case .periodic:
      return true
    case .unbounded:
      return false
    case .closed:
      return nil
    }
  }

  public func validate(tolerance: ModelingTolerance) throws {
    switch self {
    case .parametric(let curve):
      try curve.validate(tolerance: tolerance)
    case .implicit(let curve):
      try curve.validate(tolerance: tolerance)
    case .analyticBSpline(let curve):
      try curve.validate(tolerance: tolerance)
    case .analyticBSplineTangency(let curve):
      try curve.validate(tolerance: tolerance)
    case .analyticAnalytic(let curve):
      try curve.validate(tolerance: tolerance)
    case .quadraticTangency(let curve):
      try curve.validate(tolerance: tolerance)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case parametric
    case implicit
    case analyticBSpline
    case analyticBSplineTangency
    case analyticAnalytic
    case quadraticTangency
  }

  private enum Kind: String, Codable {
    case parametric
    case implicit
    case analyticBSpline
    case analyticBSplineTangency
    case analyticAnalytic
    case quadraticTangency
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .parametric:
      try container.validateOnlyExpectedKeys([.kind, .parametric], in: decoder)
      self = .parametric(try container.decode(Curve3D.self, forKey: .parametric))
    case .implicit:
      try container.validateOnlyExpectedKeys([.kind, .implicit], in: decoder)
      self = .implicit(
        try container.decode(
          CertifiedImplicitIntersectionCurve.self,
          forKey: .implicit
        ))
    case .analyticBSpline:
      try container.validateOnlyExpectedKeys([.kind, .analyticBSpline], in: decoder)
      self = .analyticBSpline(
        try container.decode(
          CertifiedAnalyticBSplineIntersectionCurve.self,
          forKey: .analyticBSpline
        ))
    case .analyticBSplineTangency:
      try container.validateOnlyExpectedKeys(
        [.kind, .analyticBSplineTangency],
        in: decoder
      )
      self = .analyticBSplineTangency(
        try container.decode(
          CertifiedAnalyticBSplineTangencyIntersectionCurve.self,
          forKey: .analyticBSplineTangency
        ))
    case .analyticAnalytic:
      try container.validateOnlyExpectedKeys([.kind, .analyticAnalytic], in: decoder)
      self = .analyticAnalytic(
        try container.decode(
          CertifiedAnalyticAnalyticIntersectionCurve.self,
          forKey: .analyticAnalytic
        ))
    case .quadraticTangency:
      try container.validateOnlyExpectedKeys([.kind, .quadraticTangency], in: decoder)
      self = .quadraticTangency(
        try container.decode(
          CertifiedQuadraticTangencyIntersectionCurve.self,
          forKey: .quadraticTangency
        ))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .parametric(let curve):
      try container.encode(Kind.parametric, forKey: .kind)
      try container.encode(curve, forKey: .parametric)
    case .implicit(let curve):
      try container.encode(Kind.implicit, forKey: .kind)
      try container.encode(curve, forKey: .implicit)
    case .analyticBSpline(let curve):
      try container.encode(Kind.analyticBSpline, forKey: .kind)
      try container.encode(curve, forKey: .analyticBSpline)
    case .analyticBSplineTangency(let curve):
      try container.encode(Kind.analyticBSplineTangency, forKey: .kind)
      try container.encode(curve, forKey: .analyticBSplineTangency)
    case .analyticAnalytic(let curve):
      try container.encode(Kind.analyticAnalytic, forKey: .kind)
      try container.encode(curve, forKey: .analyticAnalytic)
    case .quadraticTangency(let curve):
      try container.encode(Kind.quadraticTangency, forKey: .kind)
      try container.encode(curve, forKey: .quadraticTangency)
    }
  }
}

// The synthesized equality binds every large certified payload pair in one
// frame, which overflows 512 KB worker stacks in unoptimized builds, so the
// dispatch below binds payloads only inside per-case helpers.
extension SurfaceSurfaceIntersectionCurveTruth {
  public static func == (
    lhs: SurfaceSurfaceIntersectionCurveTruth,
    rhs: SurfaceSurfaceIntersectionCurveTruth
  ) -> Bool {
    switch (lhs, rhs) {
    case (.parametric, .parametric):
      return equalsParametric(lhs, rhs)
    case (.implicit, .implicit):
      return equalsImplicit(lhs, rhs)
    case (.analyticBSpline, .analyticBSpline):
      return equalsAnalyticBSpline(lhs, rhs)
    case (.analyticBSplineTangency, .analyticBSplineTangency):
      return equalsAnalyticBSplineTangency(lhs, rhs)
    case (.analyticAnalytic, .analyticAnalytic):
      return equalsAnalyticAnalytic(lhs, rhs)
    case (.quadraticTangency, .quadraticTangency):
      return equalsQuadraticTangency(lhs, rhs)
    default:
      return false
    }
  }

  @inline(never)
  private static func equalsParametric(_ lhs: Self, _ rhs: Self) -> Bool {
    guard case .parametric(let l) = lhs, case .parametric(let r) = rhs else { return false }
    return l == r
  }

  @inline(never)
  private static func equalsImplicit(_ lhs: Self, _ rhs: Self) -> Bool {
    guard case .implicit(let l) = lhs, case .implicit(let r) = rhs else { return false }
    return l == r
  }

  @inline(never)
  private static func equalsAnalyticBSpline(_ lhs: Self, _ rhs: Self) -> Bool {
    guard case .analyticBSpline(let l) = lhs, case .analyticBSpline(let r) = rhs else {
      return false
    }
    return l == r
  }

  @inline(never)
  private static func equalsAnalyticBSplineTangency(_ lhs: Self, _ rhs: Self) -> Bool {
    guard case .analyticBSplineTangency(let l) = lhs, case .analyticBSplineTangency(let r) = rhs
    else { return false }
    return l == r
  }

  @inline(never)
  private static func equalsAnalyticAnalytic(_ lhs: Self, _ rhs: Self) -> Bool {
    guard case .analyticAnalytic(let l) = lhs, case .analyticAnalytic(let r) = rhs else {
      return false
    }
    return l == r
  }

  @inline(never)
  private static func equalsQuadraticTangency(_ lhs: Self, _ rhs: Self) -> Bool {
    guard case .quadraticTangency(let l) = lhs, case .quadraticTangency(let r) = rhs else {
      return false
    }
    return l == r
  }
}
