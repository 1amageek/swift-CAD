import CADCore

/// Owns immutable curve representation work for one interval-heavy operation.
struct PreparedCurveDifferentialEncloser: Sendable {
  private indirect enum Storage: Sendable {
    case direct(Curve3D)
    case bSpline([RationalBezierCurvePatch3D])
    case implicit(
      CertifiedImplicitIntersectionCurve,
      ImplicitCurveIntervalJetEncloser
    )
    case implicitLift(Curve3D, ImplicitCurveIntervalJetEncloser)
    case rigid(
      RigidTransform3D,
      source: PreparedCurveDifferentialEncloser
    )
    case affine(
      AffineTransform3D,
      source: PreparedCurveDifferentialEncloser
    )
  }

  let curve: Curve3D
  private let storage: Storage

  init(
    curve: Curve3D,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    try curve.validate(tolerance: tolerance)
    self.curve = curve
    switch curve {
    case .bSpline(let bSpline):
      storage = .bSpline(
        try BSplineCurveBezierDecomposer().curvePatches(
          curve: bSpline,
          tolerance: tolerance
        ))
    case .implicit(let implicit):
      storage = .implicit(
        implicit,
        try ImplicitCurveIntervalJetEncloser(
          intersection: implicit,
          tolerance: tolerance
        )
      )
    case .rigidImage(let image):
      storage = .rigid(
        image.transform,
        source: try PreparedCurveDifferentialEncloser(
          curve: image.source,
          tolerance: tolerance
        )
      )
    case .affineImage(let image):
      storage = .affine(
        image.transform,
        source: try PreparedCurveDifferentialEncloser(
          curve: image.source,
          tolerance: tolerance
        )
      )
    case .surfaceLift(let lift):
      var parameterCurve = lift.parameterCurve
      unwrap: while true {
        switch parameterCurve {
        case .offsetSurfaceImage(let image): parameterCurve = image.source
        case .periodicTranslation(let base, _, _): parameterCurve = base
        default: break unwrap
        }
      }
      if case .certifiedImplicit(let implicit) = parameterCurve {
        storage = .implicitLift(curve, try ImplicitCurveIntervalJetEncloser(
          intersection: implicit.intersection, tolerance: tolerance))
      } else {
        storage = .direct(curve)
      }
    case .line, .circle, .analytic, .certifiedIntersection:
      storage = .direct(curve)
    }
  }

  func thirdOrderIntervalJet(
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try validate(parameters: parameters, tolerance: tolerance)
    switch storage {
    case .direct(let curve):
      return try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
        of: curve,
        over: parameters,
        tolerance: tolerance
      )
    case .bSpline(let patches):
      return try bSplineJet(
        patches: patches,
        parameters: parameters,
        tolerance: tolerance
      )
    case .implicit(let implicit, let encloser):
      return try encloser.intervalJet(
        of: implicit,
        over: parameters,
        tolerance: tolerance
      )
    case .implicitLift(let curve, let encloser):
      guard let jet = try DefaultCurveDifferentialEncloser().directJet(
        curve, parameters: parameters, tolerance: tolerance, preparedImplicit: encloser
      ) else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message: "A prepared implicit lift lost its direct parameter-jet representation.")
      }
      return jet
    case .rigid(let transform, let source):
      return transformed(
        try source.thirdOrderIntervalJet(
          over: parameters,
          tolerance: tolerance
        ),
        by: transform
      )
    case .affine(let transform, let source):
      return transformed(
        try source.thirdOrderIntervalJet(
          over: parameters,
          tolerance: tolerance
        ),
        by: transform
      )
    }
  }

  func derivativeRange(
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CurveSpatialDerivativeRange {
    let jet = try thirdOrderIntervalJet(
      over: parameters,
      tolerance: tolerance
    )
    return CurveSpatialDerivativeRange(
      x: try scalarInterval(jet.x.derivativeU),
      y: try scalarInterval(jet.y.derivativeU),
      z: try scalarInterval(jet.z.derivativeU)
    )
  }

  func preparedSurfaceLiftDerivativeRange(
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CurveSpatialDerivativeRange? {
    guard case .implicitLift = storage else { return nil }
    return try derivativeRange(over: parameters, tolerance: tolerance)
  }

  func boundingBox(
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    let jet = try thirdOrderIntervalJet(
      over: parameters,
      tolerance: tolerance
    )
    return try BoundingBox3D(
      minimum: Point3D(
        x: jet.x.value.lower,
        y: jet.y.value.lower,
        z: jet.z.value.lower
      ),
      maximum: Point3D(
        x: jet.x.value.upper,
        y: jet.y.value.upper,
        z: jet.z.value.upper
      )
    ).expanded(by: tolerance.distance)
  }

  private func validate(
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    guard parameters.width > 0.0 else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A prepared curve differential enclosure requires a positive parameter span."
      )
    }
    if case .closed(let lower, let upper) = curve.parameterDomain {
      guard parameters.lower >= lower, parameters.upper <= upper else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "The prepared curve parameter interval extends beyond the curve domain."
        )
      }
    }
  }

  private func bSplineJet(
    patches: [RationalBezierCurvePatch3D],
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    let encloser = RationalBezierCurveJetEncloser()
    var result: SurfaceIntervalVectorJet?
    for patch in patches {
      let lower = max(parameters.lower, patch.lower)
      let upper = min(parameters.upper, patch.upper)
      guard upper > lower else { continue }
      let patchJet = try encloser.enclosure(
        of: patch,
        over: try ScalarInterval(lower: lower, upper: upper),
        tolerance: tolerance
      )
      result = result.map { $0.union(patchJet) } ?? patchJet
    }
    guard let result else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "The curve parameter interval did not intersect a prepared B-spline Bezier span."
      )
    }
    return result
  }

  private func scalarInterval(
    _ interval: OutwardScalarInterval
  ) throws -> ScalarInterval {
    try ScalarInterval(
      lower: interval.lower,
      upper: interval.upper
    )
  }

  private func transformed(
    _ jet: SurfaceIntervalVectorJet,
    by transform: RigidTransform3D
  ) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet.constant(
      Point3D(
        x: transform.translation.x,
        y: transform.translation.y,
        z: transform.translation.z
      ))
      + SurfaceIntervalVectorJet.constant(transform.basisX) * jet.x
      + SurfaceIntervalVectorJet.constant(transform.basisY) * jet.y
      + SurfaceIntervalVectorJet.constant(transform.basisZ) * jet.z
  }

  private func transformed(
    _ jet: SurfaceIntervalVectorJet,
    by transform: AffineTransform3D
  ) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet.constant(
      Point3D(
        x: transform.translation.x,
        y: transform.translation.y,
        z: transform.translation.z
      ))
      + SurfaceIntervalVectorJet.constant(transform.basisX) * jet.x
      + SurfaceIntervalVectorJet.constant(transform.basisY) * jet.y
      + SurfaceIntervalVectorJet.constant(transform.basisZ) * jet.z
  }
}
