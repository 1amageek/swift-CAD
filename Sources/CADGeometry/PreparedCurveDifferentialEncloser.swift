import CADCore

/// Owns immutable curve representation work for one interval-heavy operation.
struct PreparedCurveDifferentialEncloser: Sendable {
  private indirect enum Storage: Sendable {
    case direct(Curve3D)
    case nativeBSpline([RationalBezierCurveJetEncloser.NativeSpan])
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
  private let preparationTolerance: ModelingTolerance

  init(
    curve: Curve3D,
    tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = {}
  ) throws {
    try Task.checkCancellation()
    try tolerance.validate()
    try consumeWork()
    try curve.validate(tolerance: tolerance)
    self.curve = curve
    preparationTolerance = tolerance
    switch curve {
    case .bSpline(let bSpline):
      storage = .nativeBSpline(try RationalBezierCurveJetEncloser().originalNativeSpans(
        of: bSpline, tolerance: tolerance, consumeWork: consumeWork))
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
          tolerance: tolerance, consumeWork: consumeWork
        )
      )
    case .affineImage(let image):
      storage = .affine(
        image.transform,
        source: try PreparedCurveDifferentialEncloser(
          curve: image.source,
          tolerance: tolerance, consumeWork: consumeWork
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
    case .nativeBSpline(let spans):
      var result: SurfaceIntervalVectorJet?
      for span in spans {
        let lower = max(parameters.lower, span.lower), upper = min(parameters.upper, span.upper)
        guard lower <= upper else { continue }
        try Task.checkCancellation()
        let jet = try RationalBezierCurveJetEncloser().enclosure(of: span,
          over: ScalarInterval(lower: lower, upper: upper), tolerance: tolerance)
        result = result.map { $0.union(jet) } ?? jet
      }
      guard let result else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                          message: "The curve query has no original owning native span.")
      }
      return result
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

  struct ClosedNativeJet: Sendable {
    struct OwnedSpan: Sendable {
      let nativeIndex: Int
      let nativeDomain: ScalarInterval
      let parameters: ScalarInterval
      let jet: SurfaceIntervalVectorJet
    }
    let source: Curve3D
    let parameters: ScalarInterval
    let tolerance: ModelingTolerance
    /// Separate one-sided smooth jets; their union never establishes join smoothness.
    let spans: [OwnedSpan]
  }

  func closedNativeJets(over parameters: ScalarInterval, tolerance: ModelingTolerance,
                        consumeWork: () throws -> Void) throws -> ClosedNativeJet {
    try Task.checkCancellation()
    try tolerance.validate()
    guard tolerance == preparationTolerance, parameters.lower.isFinite, parameters.upper.isFinite,
          parameters.lower <= parameters.upper else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                        message: "Closed native curve queries require the exact preparation tolerance and finite ordered parameters.")
    }
    switch storage {
    case .nativeBSpline(let nativeSpans):
      guard let first = nativeSpans.first, let last = nativeSpans.last,
            parameters.lower >= first.lower, parameters.upper <= last.upper else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                          message: "The closed curve query extends beyond its original native domain.")
      }
      var result: [ClosedNativeJet.OwnedSpan] = []
      for span in nativeSpans {
        let lower = max(parameters.lower, span.lower), upper = min(parameters.upper, span.upper)
        guard lower <= upper else { continue }
        try Task.checkCancellation()
        try consumeWork()
        let selected = try ScalarInterval(lower: lower, upper: upper)
        let jet = try RationalBezierCurveJetEncloser().enclosure(of: span, over: selected, tolerance: tolerance)
        result.append(.init(nativeIndex: span.index,
          nativeDomain: try ScalarInterval(lower: span.lower, upper: span.upper), parameters: selected, jet: jet))
      }
      guard !result.isEmpty else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                          message: "The closed curve query has no original owning native span.")
      }
      try Task.checkCancellation()
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance, spans: result)
    case .rigid(let transform, let source):
      let result = try source.closedNativeJets(over: parameters, tolerance: tolerance, consumeWork: consumeWork)
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
        spans: result.spans.map { .init(nativeIndex: $0.nativeIndex, nativeDomain: $0.nativeDomain,
          parameters: $0.parameters, jet: transformed($0.jet, by: transform)) })
    case .affine(let transform, let source):
      let result = try source.closedNativeJets(over: parameters, tolerance: tolerance, consumeWork: consumeWork)
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
        spans: result.spans.map { .init(nativeIndex: $0.nativeIndex, nativeDomain: $0.nativeDomain,
          parameters: $0.parameters, jet: transformed($0.jet, by: transform)) })
    // FIXME(INCOMPLETE_IMPLEMENTATION): Closed owning-span curve proofs currently
    // serve original nonperiodic B-splines and their affine images. Q3 rolling and
    // trim consumers must not claim periodic/procedural closed support until their
    // original chart coverage and one-sided derivatives are certified here.
    default:
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "This curve family has no original closed native span receipt.")
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
