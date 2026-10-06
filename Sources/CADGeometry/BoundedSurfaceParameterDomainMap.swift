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
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws {
    try admission.step()
    let firstBounds = try Self.bounds(of: first, constrainedBy: second, tolerance: tolerance, admission: admission,
      preparedSurface: preparedFirstSurface, preparedPartner: preparedSecondSurface)
    let secondBounds = try Self.bounds(of: second, constrainedBy: first, tolerance: tolerance, admission: admission,
      preparedSurface: preparedSecondSurface, preparedPartner: preparedFirstSurface)
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

  init(first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws {
    try tolerance.validate(); try admission.step()
    func selected(_ interval: ScalarInterval, in domain: ParameterDomain) throws -> (lower: Double, upper: Double) {
      try admission.step()
      guard interval.lower.isFinite, interval.upper.isFinite,
        interval.lower < interval.upper, interval.width.isFinite else {
        throw GeometryConversionError.invalidInput("An original SSI selected box requires finite positive spans.")
      }
      if case .closed(let lower, let upper) = domain {
        guard interval.lower >= lower, interval.upper <= upper else {
          throw GeometryConversionError.invalidInput("An original SSI selected box extends beyond its retained support.")
        }
      }
      return (interval.lower, interval.upper)
    }
    firstU = try selected(firstBox.u, in: first.uDomain)
    firstV = try selected(firstBox.v, in: first.vDomain)
    secondU = try selected(secondBox.u, in: second.uDomain)
    secondV = try selected(secondBox.v, in: second.vDomain)
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

  func actualParameterBox(normalizedBounds: [(lower: Double, upper: Double)],
    admission: SurfaceSurfaceQueryAdmission) throws -> SurfaceIntersectionParameterBox {
    guard normalizedBounds.count == 4 else {
      throw GeometryConversionError.invalidInput("Original SSI domain transport requires four coordinate intervals.")
    }
    func transport(_ index: Int, _ native: (lower: Double, upper: Double)) throws -> ScalarInterval {
      try admission.step()
      let requested = normalizedBounds[index]
      guard requested.lower.isFinite, requested.upper.isFinite,
        requested.lower >= 0, requested.upper <= 1, requested.lower <= requested.upper else {
        throw GeometryConversionError.invalidInput("Original SSI normalized box lies outside its authored domain.")
      }
      let width = OutwardScalarInterval.exact(native.upper) - .exact(native.lower)
      let image = .exact(native.lower)
        + width * OutwardScalarInterval(lower: requested.lower, upper: requested.upper)
      guard let contained = image.intersection(with: .init(lower: native.lower, upper: native.upper)),
        contained.isFinite else {
        throw GeometryConversionError.resourceLimitExceeded("Original SSI native box transport is not finitely enclosed.")
      }
      return try .init(lower: contained.lower, upper: contained.upper)
    }
    return try .init(firstU: transport(0, firstU), firstV: transport(1, firstV),
      secondU: transport(2, secondU), secondV: transport(3, secondV))
  }

  func originalNormalizedBounds(_ interval: OutwardScalarInterval, coordinate: Int,
    admission: SurfaceSurfaceQueryAdmission) throws -> OutwardScalarInterval {
    try admission.step()
    let native: (lower: Double, upper: Double)
    switch coordinate {
    case 0: native = firstU
    case 1: native = firstV
    case 2: native = secondU
    case 3: native = secondV
    default:
      throw GeometryConversionError.invalidInput("Original SSI normalization requires an original chart coordinate.")
    }
    let width = OutwardScalarInterval.exact(native.upper) - .exact(native.lower)
    guard let normalized = (interval - .exact(native.lower)).divided(by: width), normalized.isFinite else {
      throw GeometryConversionError.resourceLimitExceeded("Original SSI normalization has no finite interval quotient.")
    }
    return normalized
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
      lower.isFinite, upper.isFinite, (upper - lower).isFinite,
      upper > lower
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
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission,
    preparedSurface: PreparedSurfaceDifferentialEncloser?, preparedPartner: PreparedSurfaceDifferentialEncloser?
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
    let box = try expandedHull(hull(of: partner, prepared: preparedPartner, tolerance: tolerance,
      admission: admission), by: tolerance.distance)
    let frame = try admission.intervalJet(preparedSurface ?? admission.prepare(surface, tolerance: tolerance),
      over: .init(u: .init(lower: 0, upper: 0), v: .init(lower: 0, upper: 0)), tolerance: tolerance)
    let x = OutwardScalarInterval(lower: box.minimum.x, upper: box.maximum.x) - frame.x.value
    let y = OutwardScalarInterval(lower: box.minimum.y, upper: box.maximum.y) - frame.y.value
    let z = OutwardScalarInterval(lower: box.minimum.z, upper: box.maximum.z) - frame.z.value
    try admission.reserve(count: 6, stride: MemoryLayout<OutwardScalarInterval>.stride)
    let uAxis = [frame.x.derivativeU, frame.y.derivativeU, frame.z.derivativeU]
    let vAxis = [frame.x.derivativeV, frame.y.derivativeV, frame.z.derivativeV]
    func dot(_ a: [OutwardScalarInterval], _ b: [OutwardScalarInterval]) -> OutwardScalarInterval {
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    }
    func projected(_ axis: [OutwardScalarInterval]) -> OutwardScalarInterval {
      x * axis[0] + y * axis[1] + z * axis[2]
    }
    let uu = dot(uAxis, uAxis)
    let uv = dot(uAxis, vAxis)
    let vv = dot(vAxis, vAxis)
    let determinant = uu * vv - uv * uv
    let pu = projected(uAxis)
    let pv = projected(vAxis)
    guard let u = (pu * vv - pv * uv).divided(by: determinant),
          let v = (pv * uu - pu * uv).divided(by: determinant) else {
      throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
        message: "The planar search domain has an uncertifiable parameter frame.")
    }
    return (try closedBounds(.closed(u.lower, u.upper), tolerance: tolerance),
            try closedBounds(.closed(v.lower, v.upper), tolerance: tolerance))
  }

  /// Preparation binds the immutable original source; every hull item is paid.
  private static func hull(of surface: Surface3D, prepared: PreparedSurfaceDifferentialEncloser?,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> BoundingBox3D {
    if case .bSpline(let spline) = surface {
      var minimum: Point3D?, maximum: Point3D?
      for row in spline.controlPoints {
        try admission.step()
        for point in row {
          try admission.step(); try point.validate()
          if let low = minimum, let high = maximum {
            minimum = Point3D(x: min(low.x, point.x), y: min(low.y, point.y), z: min(low.z, point.z))
            maximum = Point3D(x: max(high.x, point.x), y: max(high.y, point.y), z: max(high.z, point.z))
          } else { minimum = point; maximum = point }
        }
      }
      guard let minimum, let maximum else {
        throw GeometryConversionError.invalidInput("An original native surface hull has no control points.")
      }
      return try BoundingBox3D(minimum: minimum, maximum: maximum)
    }
    let u = try closedBounds(surface.uDomain, tolerance: tolerance)
    let v = try closedBounds(surface.vDomain, tolerance: tolerance)
    let source = try prepared ?? admission.prepare(surface, tolerance: tolerance)
    let bounds = try admission.positionBounds(source,
      over: .init(u: .init(lower: u.lower, upper: u.upper),
        v: .init(lower: v.lower, upper: v.upper)), tolerance: tolerance)
    return try BoundingBox3D(minimum: Point3D(x: bounds.x.lower, y: bounds.y.lower, z: bounds.z.lower),
      maximum: Point3D(x: bounds.x.upper, y: bounds.y.upper, z: bounds.z.upper))
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
