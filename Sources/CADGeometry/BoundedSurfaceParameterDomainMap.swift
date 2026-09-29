import CADCore

struct BoundedSurfaceParameterDomainMap: Sendable {
  let firstU: (lower: Double, upper: Double)
  let firstV: (lower: Double, upper: Double)
  let secondU: (lower: Double, upper: Double)
  let secondV: (lower: Double, upper: Double)

  var spans: [Double] {
    [
      firstU.upper - firstU.lower,
      firstV.upper - firstV.lower,
      secondU.upper - secondU.lower,
      secondV.upper - secondV.lower,
    ]
  }

  var lowerBounds: [Double] {
    [firstU.lower, firstV.lower, secondU.lower, secondV.lower]
  }

  init(
    first: Surface3D,
    second: Surface3D,
    tolerance: ModelingTolerance
  ) throws {
    let firstBounds = try Self.bounds(of: first, constrainedBy: second, tolerance: tolerance)
    let secondBounds = try Self.bounds(of: second, constrainedBy: first, tolerance: tolerance)
    firstU = firstBounds.u
    firstV = firstBounds.v
    secondU = secondBounds.u
    secondV = secondBounds.v
  }

  init(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws {
    try self.init(
      first: .bSpline(first),
      second: .bSpline(second),
      tolerance: tolerance
    )
  }

  func actual(_ normalized: [Double]) -> [Double] {
    [
      interpolate(firstU, normalized[0]),
      interpolate(firstV, normalized[1]),
      interpolate(secondU, normalized[2]),
      interpolate(secondV, normalized[3]),
    ]
  }

  func normalized(_ actual: [Double]) -> [Double] {
    [
      fraction(firstU, actual[0]),
      fraction(firstV, actual[1]),
      fraction(secondU, actual[2]),
      fraction(secondV, actual[3]),
    ]
  }

  private func interpolate(
    _ bounds: (lower: Double, upper: Double),
    _ fraction: Double
  ) -> Double {
    bounds.lower + (bounds.upper - bounds.lower) * fraction
  }

  private func fraction(
    _ bounds: (lower: Double, upper: Double),
    _ value: Double
  ) -> Double {
    (value - bounds.lower) / (bounds.upper - bounds.lower)
  }

  private static func closedBounds(
    _ domain: ParameterDomain,
    tolerance: ModelingTolerance
  ) throws -> (lower: Double, upper: Double) {
    guard case .closed(let lower, let upper) = domain,
      lower.isFinite, upper.isFinite,
      upper - lower > tolerance.distance
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Bounded surface marching requires closed parameter domains."
      )
    }
    return (lower, upper)
  }

  private static func bounds(
    of surface: Surface3D,
    constrainedBy partner: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> (u: (lower: Double, upper: Double), v: (lower: Double, upper: Double)) {
    if case .closed = surface.uDomain, case .closed = surface.vDomain {
      return (try closedBounds(surface.uDomain, tolerance: tolerance),
              try closedBounds(surface.vDomain, tolerance: tolerance))
    }
    guard case .plane = CanonicalAnalyticSurface(surface),
          case .closed = partner.uDomain, case .closed = partner.vDomain else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "Bounded marching requires finite supports or one plane bounded by its finite partner.")
    }
    let box = try expandedHull(hull(of: partner, tolerance: tolerance), by: tolerance.distance)
    let frame = try surface.parameterDerivatives(atU: 0, v: 0, tolerance: tolerance)
    let x = OutwardScalarInterval(lower: box.minimum.x, upper: box.maximum.x) - .exact(frame.position.x)
    let y = OutwardScalarInterval(lower: box.minimum.y, upper: box.maximum.y) - .exact(frame.position.y)
    let z = OutwardScalarInterval(lower: box.minimum.z, upper: box.maximum.z) - .exact(frame.position.z)
    func dot(_ a: Vector3D, _ b: Vector3D) -> OutwardScalarInterval {
      .exact(a.x) * .exact(b.x) + .exact(a.y) * .exact(b.y) + .exact(a.z) * .exact(b.z)
    }
    func projected(_ axis: Vector3D) -> OutwardScalarInterval {
      x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
    }
    let uu = dot(frame.tangentU, frame.tangentU)
    let uv = dot(frame.tangentU, frame.tangentV)
    let vv = dot(frame.tangentV, frame.tangentV)
    let determinant = uu * vv - uv * uv
    let pu = projected(frame.tangentU)
    let pv = projected(frame.tangentV)
    guard let u = (pu * vv - pv * uv).divided(by: determinant),
          let v = (pv * uu - pu * uv).divided(by: determinant) else {
      throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
        message: "The planar search domain has an uncertifiable parameter frame.")
    }
    return (try closedBounds(.closed(u.lower, u.upper), tolerance: tolerance),
            try closedBounds(.closed(v.lower, v.upper), tolerance: tolerance))
  }

  /// The caller validates surfaces before constructing an intersection domain.
  private static func hull(of surface: Surface3D, tolerance: ModelingTolerance) throws -> BoundingBox3D {
    switch surface {
    case .bSpline(let spline):
      // Positive rational weights retain the convex-hull property.
      return try BoundingBox3D(points: spline.controlPoints.joined())
    case .procedural(.offset(let offset)):
      return try expandedHull(hull(of: offset.source, tolerance: tolerance), by: abs(offset.distance))
    default:
      let u = try closedBounds(surface.uDomain, tolerance: tolerance)
      let v = try closedBounds(surface.vDomain, tolerance: tolerance)
      return try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        .boundingBox(over: SurfaceParameterBox(
          u: ScalarInterval(lower: u.lower, upper: u.upper),
          v: ScalarInterval(lower: v.lower, upper: v.upper)), tolerance: tolerance)
    }
  }

  private static func expandedHull(_ box: BoundingBox3D, by distance: Double) throws -> BoundingBox3D {
    try BoundingBox3D(
      minimum: Point3D(x: (box.minimum.x - distance).nextDown,
                       y: (box.minimum.y - distance).nextDown,
                       z: (box.minimum.z - distance).nextDown),
      maximum: Point3D(x: (box.maximum.x + distance).nextUp,
                       y: (box.maximum.y + distance).nextUp,
                       z: (box.maximum.z + distance).nextUp))
  }
}
