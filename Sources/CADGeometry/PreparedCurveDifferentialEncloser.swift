import CADCore

/// Owns immutable curve representation work for one interval-heavy operation.
package struct PreparedCurveDifferentialEncloser: Sendable {
  private indirect enum Storage: Sendable {
    case direct(Curve3D)
    case callerImplicit(CertifiedImplicitIntersectionCurve, ImplicitCurveIntervalJetEncloser, PreparedSurfaceDifferentialEncloser)
    case callerLift(CallerLift)
    case originalWordLift(OriginalAffineWordSurfaceParameterCurve, PreparedCurveDifferentialEncloser)
    case originalAffineWord(OriginalAffineWordCurve3D, source: PreparedCurveDifferentialEncloser)
    case originalLiftImage(OriginalImageSurfaceParameterCurve, PreparedCurveDifferentialEncloser)
    case periodicNativeBSpline([RationalBezierCurveJetEncloser.NativeSpan])
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
    case parameterImage(ParameterImageCurve3D, source: PreparedCurveDifferentialEncloser)
    case affine(
      AffineTransform3D,
      source: PreparedCurveDifferentialEncloser
    )
  }

  package let curve: Curve3D
  private let storage: Storage
  private let preparationTolerance: ModelingTolerance
  private let preparationMaximumAlgebraicDepth: Int?
  package var certificationTolerance: ModelingTolerance { preparationTolerance }

  package struct ContinuousFirstOrderSource: Sendable {
    package let prepared: PreparedCurveDifferentialEncloser
    package let parameters: ScalarInterval
    fileprivate init(prepared: PreparedCurveDifferentialEncloser, parameters: ScalarInterval) {
      self.prepared = prepared; self.parameters = parameters
    }
  }

  /// Issues positional continuity separately from the one-sided derivative hull.
  package func admittingContinuousFirstOrder<B: RationalAlgebraAdmitting>(
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    usage: inout B) throws -> ContinuousFirstOrderSource? {
    guard tolerance == preparationTolerance, parameters.lower.isFinite,
      parameters.upper.isFinite, parameters.lower <= parameters.upper,
      maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
      throw GeometryConversionError.invalidInput("Original continuity requires its retained preparation and caller domain.")
    }
    if case .direct(.originalPolyline(let original)) = storage {
      guard parameters.lower >= 0, parameters.upper <= 1 else {
        throw GeometryConversionError.invalidInput("Original polyline continuity requires its normalized source domain.")
      }
      try original.validate(tolerance: tolerance); try usage.consumeExactWork(1)
      try RationalAlgebraStorage.retain(1, of: ContinuousFirstOrderSource.self, usage: &usage)
      return .init(prepared: self, parameters: parameters)
    }
    if case .direct(.originalGuideTraversalChain(let original)) = storage {
      guard parameters.lower >= 0, parameters.upper <= 1,
        remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput("Original guide continuity requires its admitted normalized source domain.")
      }
      try original.validate(tolerance: tolerance)
      try usage.consumeExactWork(1)
      try RationalAlgebraStorage.retain(1, of: ContinuousFirstOrderSource.self, usage: &usage)
      return .init(prepared: self, parameters: parameters)
    }
    if case .direct(.originalGuideEndpointConnector(let original)) = storage {
      guard parameters.lower >= 0, parameters.upper <= 1,
        remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput("Original corrected guide continuity requires its admitted normalized source domain.")
      }
      try original.validate(tolerance: tolerance)
      try usage.consumeExactWork(1)
      try RationalAlgebraStorage.retain(1, of: ContinuousFirstOrderSource.self, usage: &usage)
      return .init(prepared: self, parameters: parameters)
    }
    if case .direct(.originalDrafted(let original)) = storage {
      func bytes(_ count: Int) throws {
        let rounded = count.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
        guard count >= 0, !rounded.overflow else {
          throw GeometryConversionError.resourceLimitExceeded("Original draft continuity byte count overflows.")
        }
        try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
      }
      let continuous = try withoutActuallyEscaping(bytes) { bytes in
        try original.hasOriginalFirstOrderContinuity(over: parameters, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: { try usage.consumeExactWork(1) },
          consumeStorage: bytes)
      }
      guard continuous else { return nil }
      try RationalAlgebraStorage.retain(1, of: ContinuousFirstOrderSource.self, usage: &usage)
      return .init(prepared: self, parameters: parameters)
    }
    let first = try ExactRationalCoefficient.originalDouble(parameters.lower, usage: &usage)
    let last = try ExactRationalCoefficient.originalDouble(parameters.upper, usage: &usage)
    // FIXME(INCOMPLETE_IMPLEMENTATION): Selected curve-surface and embedding
    // callers need source-owned implicit/lift join continuity. This issuer
    // reuses exact native/analytic continuity only; a derivative hull cannot
    // grant the missing graph or lifted join authority.
    guard try OriginalCurveTraversalContinuityAdmission().proves(source: curve,
      first: first, last: last, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth,
      maximumAlgebraicDepth: preparationMaximumAlgebraicDepth,
      tolerance: tolerance, usage: &usage) else { return nil }
    try RationalAlgebraStorage.retain(1, of: ContinuousFirstOrderSource.self, usage: &usage)
    return .init(prepared: self, parameters: parameters)
  }

  package init(
    curve: Curve3D,
    tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = {}
  ) throws {
    try CurrentTaskCancellationChecker().checkCancellation()
    try tolerance.validate()
    try consumeWork()
    try curve.validate(tolerance: tolerance)
    self.curve = curve
    preparationTolerance = tolerance
    preparationMaximumAlgebraicDepth = nil
    switch curve {
    case .bSpline(let bSpline):
      if bSpline.isPeriodic {
        storage = .periodicNativeBSpline(try RationalBezierCurveJetEncloser().originalNativeSpans(
          of: bSpline, tolerance: tolerance, consumeWork: consumeWork))
      } else {
        storage = .nativeBSpline(try RationalBezierCurveJetEncloser().originalNativeSpans(
          of: bSpline, tolerance: tolerance, consumeWork: consumeWork))
      }
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
    case .parameterImage(let image):
      storage = .parameterImage(image, source: try PreparedCurveDifferentialEncloser(
        curve: image.source, tolerance: tolerance, consumeWork: consumeWork))
    case .originalAffineWord(let image):
      if case .some = image.circularCoefficients { storage = .direct(curve) }
      else { storage = .originalAffineWord(image, source: try Self(curve: image.source,
        tolerance: try image.sourceCalculationTolerance(tolerance: tolerance, consumeWork: consumeWork, consumeStorage: nil), consumeWork: consumeWork)) }
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
    case .line, .circle, .analytic, .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
      storage = .direct(curve)
    }
  }

  private struct CallerLift: Sendable {
    let lift: SurfaceLiftCurve3D
    let surface: PreparedSurfaceDifferentialEncloser
    let implicit: CertifiedImplicitSurfaceParameterCurve?
    let localizer: ImplicitCurveIntervalJetEncloser?
    let uShift: Double
    let vShift: Double
  }

  /// Invocation-owned preparation for bounded closed queries, including implicit endpoints.
  package init(curve: Curve3D, tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int = Int.max,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
    maximumAlgebraicDepth: Int? = nil) throws {
    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork(); try tolerance.validate()
    guard remainingSourceDepth >= 0 else { throw GeometryConversionError.invalidInput("Original curve preparation needs caller source depth.") }
    try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try consumeWork() },
      consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    self.curve = curve; preparationTolerance = tolerance
    preparationMaximumAlgebraicDepth = maximumAlgebraicDepth
    func childDepth() throws -> Int {
      guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original curve preparation exhausted caller source depth.") }
      return remainingSourceDepth - 1
    }
    switch curve {
    case .bSpline(let original):
      let spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: original,
        tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
      storage = original.isPeriodic ? .periodicNativeBSpline(spans) : .nativeBSpline(spans)
    case .implicit(let original):
      let depth = try childDepth()
      storage = .callerImplicit(original,
        try ImplicitCurveIntervalJetEncloser(localizing: original, tolerance: tolerance,
          maximumSpanCount: Int.max, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
          consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth),
        try PreparedSurfaceDifferentialEncloser(surface: original.firstSurface, tolerance: tolerance,
          remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
    case .rigidImage(let image):
      storage = .rigid(image.transform, source: try Self(curve: image.source, tolerance: tolerance,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
    case .parameterImage(let image):
      storage = .parameterImage(image, source: try Self(curve: image.source, tolerance: tolerance,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
    case .originalAffineWord(let image):
      if case .some = image.circularCoefficients { storage = .direct(curve) }
      else { storage = .originalAffineWord(image, source: try Self(curve: image.source,
        tolerance: try image.sourceCalculationTolerance(tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage), remainingSourceDepth: childDepth(),
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)) }
    case .affineImage(let image):
      storage = .affine(image.transform, source: try Self(curve: image.source, tolerance: tolerance,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
    case .surfaceLift(let lift):
      let depth = try childDepth()
      if case .originalAffineWord(let image) = lift.parameterCurve {
        let depth = try childDepth()
        storage = .originalWordLift(image, try Self(curve: .surfaceLift(image.source),
          tolerance: tolerance, remainingSourceDepth: depth,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
        break
      }
      if case .originalImage(let image) = lift.parameterCurve {
        storage = .originalLiftImage(image, try Self(curve: .surfaceLift(image.source),
          tolerance: tolerance, remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
      } else {
        var chart = lift.parameterCurve
        var uShift = 0.0, vShift = 0.0, wrappers = depth
        unwrap: while true {
          switch chart {
          case .periodicTranslation(let original, let u, let v):
            guard wrappers > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original lifted pcurve exhausted caller source depth.") }
            try consumeWork(); wrappers -= 1; chart = original; uShift += u; vShift += v
          case .offsetSurfaceImage(let image):
            guard wrappers > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original lifted offset chart exhausted caller source depth.") }
            try consumeWork(); wrappers -= 1; chart = image.source
          default: break unwrap
          }
        }
        guard uShift.isFinite, vShift.isFinite else { throw GeometryConversionError.invalidInput("Original lifted chart shift is not finite.") }
        let implicit: CertifiedImplicitSurfaceParameterCurve?
        if case .certifiedImplicit(let source) = chart { implicit = source } else { implicit = nil }
        let localizer = try implicit.map { try ImplicitCurveIntervalJetEncloser(localizing: $0.intersection,
          tolerance: tolerance, maximumSpanCount: Int.max, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: depth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth) }
        storage = .callerLift(.init(lift: lift,
          surface: try PreparedSurfaceDifferentialEncloser(surface: lift.surface, tolerance: tolerance,
            remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth), implicit: implicit,
          localizer: localizer, uShift: uShift, vShift: vShift))
      }
    default:
      storage = .direct(curve)
    }
  }

  func thirdOrderIntervalJet(
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try validate(parameters: parameters, tolerance: tolerance)
    switch storage {
    case .callerImplicit, .callerLift, .originalLiftImage, .originalWordLift:
      throw GeometryConversionError.invalidInput("Invocation-owned closed preparation requires its explicit caller admission overload.")
    case .direct(let curve):
      if case .originalConstructionChart(let image) = curve {
        return try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: image.maximumSpanCount, maximumSubdivisionDepth: image.maximumSubdivisionDepth,
          remainingSourceDepth: image.remainingSourceDepth == Int.max ? Int.max : image.remainingSourceDepth + 1,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      if case .originalPolyline(let original) = curve {
        return try original.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: original.maximumSubdivisionDepth,
          remainingSourceDepth: original.remainingSourceDepth,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      if case .originalGuideTraversalChain(let original) = curve {
        return try original.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: original.maximumSubdivisionDepth,
          remainingSourceDepth: original.remainingSourceDepth,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      if case .originalGuideEndpointConnector(let original) = curve {
        return try original.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: original.maximumSubdivisionDepth,
          remainingSourceDepth: original.remainingSourceDepth,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      if case .originalDrafted(let original) = curve {
        return try original.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: original.maximumSubdivisionDepth,
          remainingSourceDepth: original.remainingSourceDepth,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      if case .originalPlaneDerivative(let original) = curve {
        let receipt = try original.closedNativeJets(over: parameters, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: original.maximumSubdivisionDepth,
          remainingSourceDepth: original.remainingSourceDepth, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
        guard let first = receipt.spans.first else { throw GeometryConversionError.invalidInput("Original plane curve cover is empty.") }
        return receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
      }
      if case .originalEndpointConnector(let connector) = curve {
        let receipt = try connectorJets(connector, over: parameters, tolerance: tolerance,
          maximumSpanCount: connector.maximumSpanCount, maximumSubdivisionDepth: connector.maximumSubdivisionDepth,
          remainingSourceDepth: 0, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
        guard let first = receipt.spans.first else { throw GeometryConversionError.invalidInput("Original connector cover is empty.") }
        return receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
      }
      return try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
        of: curve,
        over: parameters,
        tolerance: tolerance
      )
    case .periodicNativeBSpline(let spans):
      let receipt = try periodicNativeJets(spans: spans, over: parameters,
        tolerance: tolerance, consumeWork: {})
      guard let first = receipt.spans.first else {
        throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "An original periodic curve has no complete lifted span coverage.")
      }
      return receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
    case .nativeBSpline(let spans):
      var result: SurfaceIntervalVectorJet?
      for span in spans {
        let lower = max(parameters.lower, span.lower), upper = min(parameters.upper, span.upper)
        guard lower <= upper else { continue }
        try CurrentTaskCancellationChecker().checkCancellation()
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
    case .parameterImage(let image, let source):
      return try image.mappedJet(try source.thirdOrderIntervalJet(
        over: image.originalInterval(parameters), tolerance: tolerance))
    case .originalAffineWord(let image, let source):
      return try OriginalAffineWordJetTransport.applying(image.preparedWord,
        to: source.thirdOrderIntervalJet(over: parameters, tolerance: source.preparationTolerance),
        consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
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

  package func selectedAffineOwningJet<B: RationalAlgebraAdmitting>(
    owner: ClosedNativeJet.OwnedSpan, normalizedLower: ExactRationalCoefficient,
    normalizedUpper: ExactRationalCoefficient, throughOrder: Int,
    tolerance: ModelingTolerance, remainingSourceDepth: Int,
    usage: inout B) throws -> OriginalRationalCurveIntervalJet {
    guard tolerance == preparationTolerance else {
      throw GeometryConversionError.invalidInput("Selected original polynomial query requires its preparation tolerance.")
    }
    if case .direct(.originalConstructionChart(let image)) = storage {
      return try image.selectedAffineOwningJet(owner: owner, normalizedLower: normalizedLower,
        normalizedUpper: normalizedUpper, throughOrder: throughOrder,
        tolerance: tolerance, remainingSourceDepth: remainingSourceDepth, usage: &usage)
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Original mapped contact consumers
    // require exact polynomial transport across outer spatial or parameter
    // wrappers. This facade binds direct affine chart owners only and cannot
    // promote an outward normalized hull into a selected exact owner domain.
    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This prepared curve has no exact selected affine native query producer.")
  }

  package struct ClosedNativeJet: Sendable {
    package struct OwnedSpan: Sendable {
      package let nativeIndex: Int
      package let nativeDomain: ScalarInterval
      package let parameters: ScalarInterval
      package let jet: SurfaceIntervalVectorJet
      package let originalPeriodicCycle: Double?
      package let originalAffineParameterMap: OriginalCurveAffineParameterMap?
      package let originalGuideTraversal: OriginalCurveRootSpan3D?
      package let originalGuideLowerParameter: ExactRationalCoefficient?
      package let originalGuideUpperParameter: ExactRationalCoefficient?
      package let originalPolylineOwner: OriginalPolylineCurve3D.OwningJet?
      /// Original tensor side and restricted UV law for a native iso lift.
      package let originalSurfaceSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan?
      package let originalSurfaceParameters: SurfaceParameterBox?
      package let originalIsoTraversal: SurfaceLiftCurve3D?
      package init(nativeIndex: Int, nativeDomain: ScalarInterval, parameters: ScalarInterval,
        jet: SurfaceIntervalVectorJet, originalPeriodicCycle: Double? = nil,
        originalSurfaceSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? = nil,
        originalSurfaceParameters: SurfaceParameterBox? = nil, originalIsoTraversal: SurfaceLiftCurve3D? = nil,
        originalAffineParameterMap: OriginalCurveAffineParameterMap? = nil,
        originalGuideTraversal: OriginalCurveRootSpan3D? = nil,
        originalGuideLowerParameter: ExactRationalCoefficient? = nil,
        originalGuideUpperParameter: ExactRationalCoefficient? = nil,
        originalPolylineOwner: OriginalPolylineCurve3D.OwningJet? = nil) {
        self.nativeIndex = nativeIndex; self.nativeDomain = nativeDomain
        self.parameters = parameters; self.jet = jet
        self.originalPeriodicCycle = originalPeriodicCycle
        self.originalAffineParameterMap = originalAffineParameterMap
        self.originalGuideTraversal = originalGuideTraversal
        self.originalGuideLowerParameter = originalGuideLowerParameter
        self.originalGuideUpperParameter = originalGuideUpperParameter
        self.originalPolylineOwner = originalPolylineOwner
        self.originalSurfaceSpan = originalSurfaceSpan
        self.originalSurfaceParameters = originalSurfaceParameters
        self.originalIsoTraversal = originalIsoTraversal
      }
    }
    package let source: Curve3D
    package let parameters: ScalarInterval
    package let tolerance: ModelingTolerance
    /// Separate one-sided smooth jets; their union never establishes join smoothness.
    package let spans: [OwnedSpan]
  }

  package func closedNativeJets(over parameters: ScalarInterval, tolerance: ModelingTolerance,
                        consumeWork: () throws -> Void) throws -> ClosedNativeJet {
    try CurrentTaskCancellationChecker().checkCancellation()
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
        try CurrentTaskCancellationChecker().checkCancellation()
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
      try CurrentTaskCancellationChecker().checkCancellation()
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance, spans: result)
    case .periodicNativeBSpline(let spans):
      return try periodicNativeJets(spans: spans, over: parameters,
        tolerance: tolerance, consumeWork: consumeWork)
    case .direct(let original):
      if case .originalConstructionChart(let image) = original {
        let jet = try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: image.maximumSpanCount, maximumSubdivisionDepth: image.maximumSubdivisionDepth,
          remainingSourceDepth: image.remainingSourceDepth == Int.max ? Int.max : image.remainingSourceDepth + 1,
          consumeWork: consumeWork).intervalJet()
        return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
          spans: [.init(nativeIndex: 0, nativeDomain: parameters, parameters: parameters, jet: jet)])
      }
      if case .originalPolyline(let source) = original {
        return try polylineJets(source, over: parameters, tolerance: tolerance,
          maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
          remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork)
      }
      if case .originalGuideTraversalChain(let source) = original {
        return try guideJets(source, over: parameters, tolerance: tolerance,
          maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
          remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork)
      }
      if case .originalGuideEndpointConnector(let source) = original {
        return try guideJets(source, over: parameters, tolerance: tolerance,
          maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
          remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork)
      }
      if case .originalDrafted(let source) = original {
        let jet = try source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
          remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork).intervalJet()
        return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
          spans: [.init(nativeIndex: 0, nativeDomain: parameters, parameters: parameters, jet: jet)])
      }
      if case .originalPlaneDerivative(let source) = original {
        return try source.closedNativeJets(over: parameters, tolerance: tolerance,
          maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
          remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork)
      }
      if case .originalEndpointConnector(let connector) = original {
        return try connectorJets(connector, over: parameters, tolerance: tolerance,
          maximumSpanCount: connector.maximumSpanCount, maximumSubdivisionDepth: connector.maximumSubdivisionDepth,
          remainingSourceDepth: 0, consumeWork: consumeWork)
      }
      try consumeWork()
      if let jet = try DefaultCurveDifferentialEncloser().directJet(original,
        parameters: parameters, tolerance: tolerance, consumeWork: consumeWork) {
        return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
          spans: [.init(nativeIndex: 0, nativeDomain: parameters, parameters: parameters, jet: jet)])
      }
      if parameters.width > 0 {
        let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: original,
          over: parameters, tolerance: tolerance)
        return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
          spans: [.init(nativeIndex: 0, nativeDomain: parameters, parameters: parameters, jet: jet)])
      }
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "This procedural curve has no original closed-point interval jet authority.")
    case .rigid(let transform, let source):
      let result = try source.closedNativeJets(over: parameters, tolerance: tolerance, consumeWork: consumeWork)
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
        spans: result.spans.map { .init(nativeIndex: $0.nativeIndex, nativeDomain: $0.nativeDomain,
          parameters: $0.parameters, jet: transformed($0.jet, by: transform), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal, originalAffineParameterMap: $0.originalAffineParameterMap) })
    case .parameterImage(let image, let source):
      let native = try image.originalInterval(parameters,consumeWork:consumeWork)
      let result = try source.closedNativeJets(over: native, tolerance: tolerance, consumeWork: consumeWork)
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
        spans: try result.spans.map { span in
          let a = (span.nativeDomain.lower - image.offset) / image.gain
          let b = (span.nativeDomain.upper - image.offset) / image.gain
          return .init(nativeIndex: span.nativeIndex,
            nativeDomain: try ScalarInterval(lower: min(a,b), upper: max(a,b)),
            parameters: parameters, jet: try image.mappedJet(span.jet), originalPeriodicCycle: span.originalPeriodicCycle, originalSurfaceSpan: span.originalSurfaceSpan, originalSurfaceParameters: span.originalSurfaceParameters, originalIsoTraversal: span.originalIsoTraversal)
        })
    case .affine(let transform, let source):
      let result = try source.closedNativeJets(over: parameters, tolerance: tolerance, consumeWork: consumeWork)
      return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance,
        spans: result.spans.map { .init(nativeIndex: $0.nativeIndex, nativeDomain: $0.nativeDomain,
          parameters: $0.parameters, jet: transformed($0.jet, by: transform), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal, originalAffineParameterMap: $0.originalAffineParameterMap) })
    default:
      return try closedNativeJets(over:parameters,tolerance:tolerance,
        maximumSpanCount:Int.max,maximumSubdivisionDepth:32,remainingSourceDepth:Int.max,
        consumeWork:consumeWork)
    }
  }

  /// Separate source-owning sides; no hull establishes continuity at a knot or graph join.
  package func closedNativeJets(over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> ClosedNativeJet {
    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork(); try tolerance.validate()
    guard tolerance == preparationTolerance, maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
      remainingSourceDepth >= 0, parameters.lower.isFinite, parameters.upper.isFinite,
      parameters.lower <= parameters.upper else {
      throw GeometryConversionError.invalidInput("Bounded original closed curves need their preparation tolerance and caller ceilings.")
    }
    func depth() throws -> Int {
      guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original closed curve source exhausted caller depth.") }
      return remainingSourceDepth - 1
    }
    func publish(_ spans: [ClosedNativeJet.OwnedSpan]) throws -> ClosedNativeJet {
      guard !spans.isEmpty, spans.count <= maximumSpanCount else {
        throw GeometryConversionError.resourceLimitExceeded("Original closed curve owning cover is empty or exceeds caller admission.")
      }
      return .init(source: curve, parameters: parameters, tolerance: tolerance, spans: spans)
    }
    func unavailable(_ message: String) throws -> Never {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
    func reserve(_ count: Int) throws {
      try OriginalCoefficientAllocation.reserve(count: count, of: ClosedNativeJet.OwnedSpan.self,
        consumeStorage: consumeStorage)
    }
    func singleton(_ jet: SurfaceIntervalVectorJet) throws -> ClosedNativeJet {
      try reserve(1)
      return try publish([.init(nativeIndex: 0, nativeDomain: parameters, parameters: parameters, jet: jet)])
    }
    switch storage {
    case .nativeBSpline(let spans):
      guard let first = spans.first, let last = spans.last,
        parameters.lower >= first.lower, parameters.upper <= last.upper else {
        throw GeometryConversionError.invalidInput("Original closed curve exceeds its native owning support.")
      }
      var result: [ClosedNativeJet.OwnedSpan] = []
      var capacity = 0
      for span in spans {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        let lo = max(parameters.lower, span.lower), hi = min(parameters.upper, span.upper)
        guard lo <= hi else { continue }
        guard result.count < maximumSpanCount else { throw GeometryConversionError.resourceLimitExceeded("Original closed curve span ceiling exhausted.") }
        let selected = try ScalarInterval(lower: lo, upper: hi)
        let jet = try OriginalNativeCurveHigherTaylor.enclosure(of: span, over: selected,
          order: 3, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
        if result.count == capacity {
          let doubled = capacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw GeometryConversionError.resourceLimitExceeded("Closed native curve result storage overflows.") }
          capacity = min(maximumSpanCount, max(1, doubled.partialValue))
          try reserve(capacity); result.reserveCapacity(capacity)
        }
        result.append(.init(nativeIndex: span.index, nativeDomain: try ScalarInterval(lower: span.lower, upper: span.upper), parameters: selected, jet: jet))
      }
      return try publish(result)
    case .periodicNativeBSpline(let spans):
      return try periodicNativeJets(spans: spans, over: parameters, tolerance: tolerance,
        boundedSpanCount: maximumSpanCount, consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .rigid(let transform, let source):
      let original = try source.closedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
      try reserve(original.spans.count)
      return try publish(try original.spans.map {
        try consumeWork()
        return .init(nativeIndex: $0.nativeIndex,
        nativeDomain: $0.nativeDomain, parameters: $0.parameters, jet: transformed($0.jet, by: transform), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal, originalAffineParameterMap: $0.originalAffineParameterMap) })
    case .originalAffineWord(let image, let source):
      let original = try source.closedNativeJets(over: parameters, tolerance: source.preparationTolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
      try reserve(original.spans.count)
      return try publish(original.spans.map { span in
        try consumeWork()
        return .init(nativeIndex: span.nativeIndex, nativeDomain: span.nativeDomain,
          parameters: span.parameters,
          jet: try OriginalAffineWordJetTransport.applying(image.preparedWord, to: span.jet,
            consumeWork: consumeWork, consumeStorage: consumeStorage),
          originalPeriodicCycle: span.originalPeriodicCycle, originalSurfaceSpan: span.originalSurfaceSpan,
          originalSurfaceParameters: span.originalSurfaceParameters, originalIsoTraversal: span.originalIsoTraversal, originalAffineParameterMap: span.originalAffineParameterMap,
          originalGuideTraversal: span.originalGuideTraversal, originalGuideLowerParameter: span.originalGuideLowerParameter,
          originalGuideUpperParameter: span.originalGuideUpperParameter)
      })
    case .originalWordLift(let image, let source):
      let original = try source.closedNativeJets(over: image.mappedRange(parameters), tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
      let gain = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
      guard gain.excludesZero else { throw GeometryConversionError.invalidInput("Original word lift has no signed traversal gain.") }
      try reserve(original.spans.count)
      return try publish(original.spans.map { span in
        try consumeWork()
        func callerRange(_ range: ScalarInterval) throws -> ScalarInterval {
          guard let fraction = (OutwardScalarInterval(lower: range.lower, upper: range.upper)
            - .exact(image.startFraction)).divided(by: gain),
            let clipped = fraction.intersection(with: .init(lower: parameters.lower, upper: parameters.upper)) else {
            throw GeometryConversionError.resourceLimitExceeded("Original word lift has no source-owning traversal image.")
          }
          return try .init(lower: clipped.lower, upper: clipped.upper)
        }
        let scaled = SurfaceIntervalVectorJet(x: scaledCurveParameter(span.jet.x, by: gain),
          y: scaledCurveParameter(span.jet.y, by: gain), z: scaledCurveParameter(span.jet.z, by: gain))
        return .init(nativeIndex: span.nativeIndex, nativeDomain: try callerRange(span.nativeDomain),
          parameters: try callerRange(span.parameters),
          jet: try OriginalAffineWordJetTransport.applying(image.target.preparedWord, to: scaled,
            consumeWork: consumeWork, consumeStorage: consumeStorage),
          originalPeriodicCycle: span.originalPeriodicCycle, originalSurfaceSpan: span.originalSurfaceSpan,
          originalSurfaceParameters: span.originalSurfaceParameters, originalIsoTraversal: span.originalIsoTraversal)
      })
    case .affine(let transform, let source):
      let original = try source.closedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
      try reserve(original.spans.count)
      return try publish(try original.spans.map {
        try consumeWork()
        return .init(nativeIndex: $0.nativeIndex,
        nativeDomain: $0.nativeDomain, parameters: $0.parameters, jet: transformed($0.jet, by: transform), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal, originalAffineParameterMap: $0.originalAffineParameterMap) })
    case .parameterImage(let image, let source):
      let original = try source.closedNativeJets(over: image.originalInterval(parameters, consumeWork: consumeWork), tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
      func inverse(_ interval: ScalarInterval) throws -> ScalarInterval {
        try OriginalParameterImageMap.inverseInterval(interval, gain: image.parameterGain, offset: image.offset, consumeWork: consumeWork)
      }
      try reserve(original.spans.count)
      return try publish(try original.spans.map {
        try consumeWork()
        return .init(nativeIndex: $0.nativeIndex,
        nativeDomain: try inverse($0.nativeDomain), parameters: try inverse($0.parameters), jet: try image.mappedJet($0.jet), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal) })
    case .originalLiftImage(let image, let source):
      let original = try source.closedNativeJets(over: image.mappedRange(parameters), tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
      let gain = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
      guard gain.excludesZero else { throw GeometryConversionError.invalidInput("Original lifted image has no directed parameter interval.") }
      try reserve(original.spans.count)
      return try publish(original.spans.map { span in
        try consumeWork()
        let mapped = SurfaceIntervalVectorJet(x: scaledCurveParameter(span.jet.x, by: gain),
          y: scaledCurveParameter(span.jet.y, by: gain), z: scaledCurveParameter(span.jet.z, by: gain))
        func callerRange(_ range: ScalarInterval) throws -> ScalarInterval {
          guard let original = (OutwardScalarInterval(lower: range.lower, upper: range.upper)
            - .exact(image.startFraction)).divided(by: gain),
            let clipped = original.intersection(with: .init(lower: parameters.lower, upper: parameters.upper)) else {
            throw GeometryConversionError.resourceLimitExceeded("Original lifted image has no directed owning interval.")
          }
          return try .init(lower: clipped.lower, upper: clipped.upper)
        }
        return .init(nativeIndex: span.nativeIndex, nativeDomain: try callerRange(span.nativeDomain),
          parameters: try callerRange(span.parameters), jet: transformed(mapped, by: image.targetImage.transform), originalPeriodicCycle: span.originalPeriodicCycle, originalSurfaceSpan: span.originalSurfaceSpan, originalSurfaceParameters: span.originalSurfaceParameters, originalIsoTraversal: span.originalIsoTraversal)
      })
    case .callerImplicit(let original, let localizer, let surface):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded original implicit owning
      // queries now forward actual scratch bytes. Complete critical-cell atlases
      // and cross-cell smooth transition authority remain required; these
      // one-sided original jets do not establish a smooth global chain.
      return try publish(implicitSpans(original: original, localizer: localizer, surface: surface,
        over: parameters, outputParameters: parameters, role: 0, gain: .exact(1), parameterOffset: .exact(0), uShift: 0, vShift: 0,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage))
    case .callerLift(let prepared):
      if let chart = prepared.implicit, let localizer = prepared.localizer {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original implicit lifted sides
        // retain per-cell jets and paid scratch; critical transitions still need
        // exact original common-root and requested continuity receipts.
        let gain = OutwardScalarInterval.exact(chart.endFraction) - .exact(chart.startFraction)
        let mapped = OutwardScalarInterval.exact(chart.startFraction) + gain * .init(lower: parameters.lower, upper: parameters.upper)
        guard let restricted = mapped.intersection(with: .init(lower: min(chart.startFraction, chart.endFraction), upper: max(chart.startFraction, chart.endFraction))) else {
          throw GeometryConversionError.invalidInput("Original lifted chart has no retained graph interval.")
        }
        return try publish(implicitSpans(original: chart.intersection, localizer: localizer, surface: prepared.surface,
          over: ScalarInterval(lower: restricted.lower, upper: restricted.upper), outputParameters: parameters,
          role: chart.role == .first ? 0 : 2, gain: gain, parameterOffset: .exact(chart.startFraction), uShift: prepared.uShift, vShift: prepared.vShift,
          tolerance: tolerance, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage))
      }
      if let native = prepared.surface.originalNativePreparation,
        let spans = try nativeIsoSpans(lift: prepared.lift, native: native, over: parameters,
          tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
          consumeWork: consumeWork, consumeStorage: consumeStorage) {
        return try publish(spans)
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Generic lifts now forward query
      // bytes to original UV/support producers. Their unresolved source-family
      // and native join-partition cases remain required before full lift closure;
      // an aggregate derivative hull is not a smoothness receipt.
      let uv = try OriginalParameterCurveHigherTaylor.enclosure(prepared.lift.parameterCurve,
        over: parameters, order: 3, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: depth(), consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth)
      let jet = try liftJet(surface: prepared.surface, u: uv.u, v: uv.v, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return try singleton(jet)
    case .implicit, .implicitLift:
      let prepared = try Self(curve: curve, tolerance: tolerance,
        remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .direct(let original):
      if case .originalAffineWord(let image) = original, let coefficients = image.circularCoefficients {
        let jet = try coefficients.intervalTaylorJet(over: parameters, throughOrder: 3,
          tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
        return try singleton(jet)
      }
      if case .originalConstructionChart(let image) = original {
        if let owners = try image.affineOwningJets(over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage) {
          return try publish(owners)
        }
        let jet = try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
          consumeStorage: consumeStorage).intervalJet()
        return try singleton(jet)
      }
      if case .originalPolyline(let source) = original {
        return try polylineJets(source, over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      if case .originalGuideTraversalChain(let source) = original {
        return try guideJets(source, over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      if case .originalGuideEndpointConnector(let source) = original {
        return try guideJets(source, over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      if case .originalDrafted(let source) = original {
        return try singleton(source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
          consumeStorage: consumeStorage).intervalJet())
      }
      if case .originalPlaneDerivative(let source) = original {
        return try source.closedNativeJets(over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      if case .originalEndpointConnector(let connector) = original {
        return try connectorJets(connector, over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      if case .surfaceLift = original {
        let prepared = try Self(curve: original, tolerance: tolerance,
          remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        return try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      if let jet = try DefaultCurveDifferentialEncloser().directJet(original, parameters: parameters, tolerance: tolerance,
        consumeWork: consumeWork, consumeStorage: consumeStorage) {
        return try singleton(jet)
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Nondirect original higher families
      // delegate byte admission to the actual higher provider. Its remaining
      // periodic/implicit/lift branches refuse unmetered query allocations.
      let jet = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: original, over: parameters,
        tolerance: tolerance, throughOrder: 4, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        consumeWork: consumeWork, consumeStorage: consumeStorage,
        maximumAlgebraicDepth: preparationMaximumAlgebraicDepth).intervalJet()
      return try singleton(jet)
    }
  }

  private func polylineJets(_ original: OriginalPolylineCurve3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> ClosedNativeJet {
    let owners = try original.owningDerivativeJets(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
      maximumAlgebraicDepth: preparationMaximumAlgebraicDepth)
    try OriginalCoefficientAllocation.reserve(count: owners.count, of: ClosedNativeJet.OwnedSpan.self,
      consumeStorage: consumeStorage)
    var spans: [ClosedNativeJet.OwnedSpan] = []; spans.reserveCapacity(owners.count)
    func axis(_ original: IntervalDerivativeJet) throws -> SurfaceIntervalJet {
      try consumeWork()
      return .init(value: original.derivatives[0], derivativeU: original.derivatives[1], derivativeV: .exact(0),
        secondDerivativeUU: original.derivatives[2], secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
        thirdDerivativeUUU: original.derivatives[3], thirdDerivativeUUV: .exact(0),
        thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
    }
    for owner in owners {
      spans.append(try .init(nativeIndex: -1, nativeDomain: owner.parameters, parameters: owner.parameters,
        jet: .init(x: axis(owner.jet.x), y: axis(owner.jet.y), z: axis(owner.jet.z)), originalPolylineOwner: owner))
    }
    return .init(source: curve, parameters: parameters, tolerance: tolerance, spans: spans)
  }

  private func guideJets(_ source: OriginalGuideTraversalChain3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> ClosedNativeJet {
    let owners = try source.owningDerivativeJets(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
      maximumAlgebraicDepth: preparationMaximumAlgebraicDepth)
    return try guideJets(owners: owners, traversals: source.traversals, over: parameters,
      tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
  }

  private func guideJets(_ source: OriginalGuideEndpointConnectorCurve3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> ClosedNativeJet {
    let owners = try source.owningDerivativeJets(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
      maximumAlgebraicDepth: preparationMaximumAlgebraicDepth)
    guard case .originalGuideTraversalChain(let chain) = source.source.source else {
      throw GeometryConversionError.invalidInput("Original corrected guide lost its declared traversal source.")
    }
    return try guideJets(owners: owners, traversals: chain.traversals, over: parameters,
      tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
  }

  private func guideJets(owners: [OriginalGuideTraversalOwningJet], traversals: [OriginalCurveRootSpan3D],
    over parameters: ScalarInterval, tolerance: ModelingTolerance, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)?) throws -> ClosedNativeJet {
    try OriginalCoefficientAllocation.reserve(count: owners.count, of: ClosedNativeJet.OwnedSpan.self,
      consumeStorage: consumeStorage)
    var spans: [ClosedNativeJet.OwnedSpan] = []; spans.reserveCapacity(owners.count)
    func axis(_ original: IntervalDerivativeJet) throws -> SurfaceIntervalJet {
      guard original.derivatives.count == 4 else {
        throw GeometryConversionError.invalidInput("Original guide owner must retain D0 through D3.")
      }
      try consumeWork()
      return .init(value: original.derivatives[0], derivativeU: original.derivatives[1], derivativeV: .exact(0),
        secondDerivativeUU: original.derivatives[2], secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
        thirdDerivativeUUU: original.derivatives[3], thirdDerivativeUUV: .exact(0),
        thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
    }
    for owner in owners {
      try consumeWork()
      guard traversals.indices.contains(owner.traversalIndex) else {
        throw GeometryConversionError.invalidInput("Original guide owner is not a retained declared traversal.")
      }
      let traversal = traversals[owner.traversalIndex]
      let domain: ScalarInterval
      if let index = traversal.nativeSpanIndex, case .bSpline(let native) = traversal.source {
        domain = try .init(lower: native.knots[index], upper: native.knots[index+1])
      } else { domain = owner.parameters }
      spans.append(try .init(nativeIndex: traversal.nativeSpanIndex ?? -1,
        nativeDomain: domain, parameters: owner.parameters,
        jet: .init(x: axis(owner.jet.x), y: axis(owner.jet.y), z: axis(owner.jet.z)),
        originalGuideTraversal: traversal, originalGuideLowerParameter: owner.exactLower,
        originalGuideUpperParameter: owner.exactUpper))
    }
    return .init(source: curve, parameters: parameters, tolerance: tolerance, spans: spans)
  }

  private func connectorJets(_ connector: OriginalEndpointConnectorCurve3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> ClosedNativeJet {
    let original = try connector.constructionTraversal.constructionNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    let corrected = try connector.correctedOwningSpans(from: original, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, consumeWork: consumeWork, consumeStorage: consumeStorage)
    return .init(source: curve, parameters: parameters, tolerance: tolerance, spans: corrected)
  }

  package func positionBounds(over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> IntervalVector3DBounds {
    if case .direct(.originalPolyline(let original)) = storage {
      guard tolerance == preparationTolerance else { throw GeometryConversionError.invalidInput("Original polyline position changed preparation tolerance.") }
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
        maximumAlgebraicDepth: preparationMaximumAlgebraicDepth)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    if case .direct(.originalGuideTraversalChain(let original)) = storage {
      guard tolerance == preparationTolerance else {
        throw GeometryConversionError.invalidInput("Original guide position changed its preparation tolerance.")
      }
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
        maximumAlgebraicDepth: preparationMaximumAlgebraicDepth)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    if case .direct(.originalGuideEndpointConnector(let original)) = storage {
      guard tolerance == preparationTolerance else {
        throw GeometryConversionError.invalidInput("Original corrected guide position changed preparation tolerance.")
      }
      return try original.preparedFirstOrder(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
        maximumAlgebraicDepth: preparationMaximumAlgebraicDepth).position
    }
    if case .direct(.originalDrafted(let original)) = storage {
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    if case .direct(.originalPlaneDerivative(let original)) = storage {
      guard tolerance == preparationTolerance, remainingSourceDepth >= 0 else {
        throw GeometryConversionError.invalidInput("Original plane position query changed preparation binding.")
      }
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    let receipt = try closedNativeJets(over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
    guard let first = receipt.spans.first else { throw GeometryConversionError.invalidInput("Original closed curve cover is empty.") }
    let jet = receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
    return .init(x: jet.x.value, y: jet.y.value, z: jet.z.value)
  }

  package struct OriginalNativeAxisIsoTraversal: Sendable {
    package let originalLift: SurfaceLiftCurve3D
    package let nativeSurfaceSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let surfaceParameters: SurfaceParameterBox
    package let traversal: SurfaceLiftCurve3D
    package let inverse: PreparedOriginalNativeAxisInverse
    package let startStation: PreparedOriginalNativeAxisInverse.Station
    package let endStation: PreparedOriginalNativeAxisInverse.Station
    package let uShift: Double
    package let vShift: Double

    package func station<B: RationalAlgebraAdmitting>(atOriginalSurfaceCoordinate target: ExactRationalCoefficient,
      maximumNormalizedParameterWidth: Double, maximumAlgebraicDepth: Int,
      usage: inout B) throws -> PreparedOriginalNativeAxisInverse.Station? {
      let shift = try ExactRationalCoefficient.originalDouble(inverse.alongU ? uShift : vShift, usage: &usage)
      return try inverse.station(at: target.subtracting(shift, usage: &usage),
        maximumNormalizedParameterWidth: maximumNormalizedParameterWidth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
    }
  }

  /// Owns the physical iso partition separately from a nonlinear native UV clock.
  package func originalNativeAxisIsoCover<B: RationalAlgebraAdmitting>(over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
    maximumNormalizedParameterWidth: Double, usage: inout B) throws -> [OriginalNativeAxisIsoTraversal]? {
    guard tolerance == preparationTolerance, maximumSpanCount > 0,
      maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
      (0...32).contains(maximumAlgebraicDepth) else {
      throw GeometryConversionError.invalidInput("Original native iso cover requires its caller preparation policy.")
    }
    guard parameters.lower == 0, parameters.upper == 1,
      case .callerLift(let retained) = storage,
      let native = retained.surface.originalNativePreparation else { return nil }
    guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original native axis lift requires one source descendant level.") }
    var chartSource = retained.lift.parameterCurve
    var sourceDepth = remainingSourceDepth - 1
    var uShiftQ = ExactRationalCoefficient.zero, vShiftQ = ExactRationalCoefficient.zero
    while true {
      if case .periodicTranslation(let child, let u, let v) = chartSource {
        uShiftQ = try uShiftQ.adding(.originalDouble(u, usage: &usage), usage: &usage)
        vShiftQ = try vShiftQ.adding(.originalDouble(v, usage: &usage), usage: &usage)
        guard sourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original native axis cover exhausted source descent.") }
        try usage.consumeExactWork(1); sourceDepth -= 1; chartSource = child
      } else if case .offsetSurfaceImage(let image) = chartSource {
        guard sourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original native axis cover exhausted source descent.") }
        try usage.consumeExactWork(1); sourceDepth -= 1; chartSource = image.source
      } else { break }
    }
    guard case .bSpline(let original) = chartSource,
      let firstPoint = original.controlPoints.first, let lastPoint = original.controlPoints.last,
      (firstPoint.x == lastPoint.x) != (firstPoint.y == lastPoint.y) else { return nil }
    let alongU = firstPoint.y == lastPoint.y
    let inverse = try PreparedOriginalNativeAxisInverse(source: original, alongU: alongU,
      tolerance: tolerance, remainingSourceDepth: sourceDepth, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
      usage: &usage)
    guard original.knots.prefix(original.degree + 1).allSatisfy({ $0 == original.knots[original.degree] }),
      original.knots.suffix(original.degree + 1).allSatisfy({ $0 == original.knots[original.controlPoints.count] }) else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Whole native axis covers currently
      // retain clamped authored endpoint UV coordinates. Unclamped or partial
      // source clocks need exact endpoint-coordinate carriers before publication.
      return nil
    }
    try usage.consumeExactWork(original.degree * 2 + 2)
    let first = original.controlPoints[0], last = original.controlPoints[original.controlPoints.count-1]
    let shiftBound = try (inverse.alongU ? uShiftQ : vShiftQ).outwardInterval(usage: &usage)
    let fixedShiftBound = try (inverse.alongU ? vShiftQ : uShiftQ).outwardInterval(usage: &usage)
    guard shiftBound.lower == shiftBound.upper, fixedShiftBound.lower == fixedShiftBound.upper,
      shiftBound.isFinite, fixedShiftBound.isFinite else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Complete periodic UV shift sums
      // require retained rational chart coordinates when not exactly binary.
      // Rounded accumulation in numerical lift caches is not source authority.
      throw GeometryConversionError.resourceLimitExceeded("Original native iso shift needs a rational UV carrier.")
    }
    let shift = shiftBound.lower, fixedShift = fixedShiftBound.lower
    func translated(_ value: Double, by shift: Double, usage: inout B) throws -> Double {
      let exact = try ExactRationalCoefficient.originalDouble(value, usage: &usage)
        .adding(.originalDouble(shift, usage: &usage), usage: &usage)
      let bound = try exact.outwardInterval(usage: &usage)
      guard bound.lower == bound.upper, bound.isFinite else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Native physical iso publication
        // needs a rational UV endpoint carrier for nonrepresentable translated
        // source coordinates. Its enclosing box cannot replace the original cut.
        throw GeometryConversionError.resourceLimitExceeded("Original iso coordinate has no exact binary carrier.")
      }
      return bound.lower
    }
    let start = try translated(inverse.alongU ? first.x : first.y, by: shift, usage: &usage)
    let end = try translated(inverse.alongU ? last.x : last.y, by: shift, usage: &usage)
    let fixed = try translated(inverse.alongU ? first.y : first.x, by: fixedShift, usage: &usage)
    let varying = try ScalarInterval(lower: min(start,end), upper: max(start,end))
    let constant = try ScalarInterval(lower: fixed, upper: fixed)
    let box = SurfaceParameterBox(u: inverse.alongU ? varying : constant, v: inverse.alongU ? constant : varying)
    func bytes(_ count: Int) throws {
      let rounded = count.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
      guard count >= 0, !rounded.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original iso cover bytes overflow.") }
      try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
    }
    let owners = try withoutActuallyEscaping(bytes) { bytes in
      try native.originalNativeSpans(over: box, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: bytes)
    }
    try RationalAlgebraStorage.retain(owners.count, of: OriginalNativeAxisIsoTraversal.self, usage: &usage)
    var output: [OriginalNativeAxisIsoTraversal] = []; output.reserveCapacity(owners.count)
    let shiftQ = try ExactRationalCoefficient.originalDouble(shift, usage: &usage)
    for owner in owners {
      try usage.consumeExactWork(1)
      let domain = inverse.alongU ? owner.uBounds : owner.vBounds
      let lower = max(varying.lower, domain.lower), upper = min(varying.upper, domain.upper)
      if lower >= upper { continue }
      let a = inverse.orientation > 0 ? lower : upper
      let b = inverse.orientation > 0 ? upper : lower
      guard let firstStation = try inverse.station(at: ExactRationalCoefficient.originalDouble(a, usage: &usage)
        .subtracting(shiftQ, usage: &usage), maximumNormalizedParameterWidth: maximumNormalizedParameterWidth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage),
        let lastStation = try inverse.station(at: ExactRationalCoefficient.originalDouble(b, usage: &usage)
          .subtracting(shiftQ, usage: &usage), maximumNormalizedParameterWidth: maximumNormalizedParameterWidth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage) else {
        throw GeometryConversionError.invalidInput("Original support iso cut has no source-bound monotone inverse.")
      }
      let part = try ScalarInterval(lower: lower, upper: upper)
      let supportBox = SurfaceParameterBox(u: inverse.alongU ? part : constant, v: inverse.alongU ? constant : part)
      let chart: SurfaceParameterCurve = inverse.alongU ? .constantV(v: fixed, uStart: a, uEnd: b)
        : .constantU(u: fixed, vStart: a, vEnd: b)
      output.append(.init(originalLift: retained.lift, nativeSurfaceSpan: owner, surfaceParameters: supportBox,
        traversal: .init(surface: retained.lift.surface, parameterCurve: chart), inverse: inverse,
        startStation: firstStation, endStation: lastStation, uShift: inverse.alongU ? shift : fixedShift, vShift: inverse.alongU ? fixedShift : shift))
    }
    return output
  }

  private func scaledCurveParameter(_ original: SurfaceIntervalJet,
    by gain: OutwardScalarInterval) -> SurfaceIntervalJet {
    let zero = OutwardScalarInterval.exact(0)
    let squared = gain * gain
    return .init(value: original.value, derivativeU: original.derivativeU * gain,
      derivativeV: zero, secondDerivativeUU: original.secondDerivativeUU * squared,
      secondDerivativeUV: zero, secondDerivativeVV: zero,
      thirdDerivativeUUU: original.thirdDerivativeUUU * squared * gain,
      thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
  }

  private func implicitSpans(original: CertifiedImplicitIntersectionCurve, localizer: ImplicitCurveIntervalJetEncloser,
    surface: PreparedSurfaceDifferentialEncloser, over native: ScalarInterval, outputParameters: ScalarInterval,
    role: Int, gain: OutwardScalarInterval, parameterOffset: OutwardScalarInterval, uShift: Double, vShift: Double, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> [ClosedNativeJet.OwnedSpan] {
    var result: [ClosedNativeJet.OwnedSpan] = []
    var capacity = 0
    for index in original.cells.indices {
      try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
      let count = OutwardScalarInterval.exact(Double(original.cells.count))
      guard let lower = OutwardScalarInterval.exact(Double(index)).divided(by: count),
        let upper = OutwardScalarInterval.exact(Double(index + 1)).divided(by: count) else {
        throw GeometryConversionError.resourceLimitExceeded("Original graph cell normalization exceeds finite arithmetic.")
      }
      let lo = max(native.lower, lower.lower), hi = min(native.upper, upper.upper)
      guard lo <= hi else { continue }
      guard result.count < maximumSpanCount else { throw GeometryConversionError.resourceLimitExceeded("Original implicit owning cover exhausted caller span admission.") }
      let range = try ScalarInterval(lower: lo, upper: hi)
      let q = try OriginalImplicitCurveHigherTaylor.parameterJets(of: original, over: range,
        order: 3, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        selectedOwningCellIndex: index, preparedLocalizer: localizer, consumeWork: consumeWork, consumeStorage: consumeStorage)
      var u = try OriginalCurveTaylorComposition.scaledParameter(q[role], scale: gain, order: 3, consumeWork: consumeWork, consumeStorage: consumeStorage)
      var v = try OriginalCurveTaylorComposition.scaledParameter(q[role + 1], scale: gain, order: 3, consumeWork: consumeWork, consumeStorage: consumeStorage)
      if uShift != 0 { u = try u.adding(.constant(.exact(uShift), order: 3, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage) }
      if vShift != 0 { v = try v.adding(.constant(.exact(vShift), order: 3, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage) }
      let jet = try liftJet(surface: surface, u: u, v: v, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      func callerRange(_ interval: OutwardScalarInterval) throws -> ScalarInterval {
        guard let mapped = (interval - parameterOffset).divided(by: gain),
          let clipped = mapped.intersection(with: .init(lower: outputParameters.lower, upper: outputParameters.upper)) else {
          throw GeometryConversionError.resourceLimitExceeded("Original graph owning interval has no directed caller image.")
        }
        return try .init(lower: clipped.lower, upper: clipped.upper)
      }
      if result.count == capacity {
        let grown = max(1, capacity).multipliedReportingOverflow(by: 2)
        guard !grown.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original graph owning capacity overflows.") }
        capacity = min(maximumSpanCount, grown.partialValue)
        try OriginalCoefficientAllocation.reserve(count: capacity, of: ClosedNativeJet.OwnedSpan.self, consumeStorage: consumeStorage)
        result.reserveCapacity(capacity)
      }
      result.append(.init(nativeIndex: index,
        nativeDomain: try callerRange(.init(lower: lower.lower, upper: upper.upper)),
        parameters: try callerRange(.init(lower: lo, upper: hi)), jet: jet))
    }
    return result
  }

  /// Returns original one-sided tensor owners, never a synthetic smooth join.
  private func nativeIsoSpans(lift: SurfaceLiftCurve3D,
    native: PreparedBSplineSurfaceDifferentialEncloser, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> [ClosedNativeJet.OwnedSpan]? {
    let alongU: Bool, fixed: Double, start: Double, end: Double
    var chartSource = lift.parameterCurve
    var uShift = 0.0, vShift = 0.0
    if case .periodicTranslation(let base, let u, let v) = chartSource {
      guard try OriginalSurfacePeriodShift.proves(on: lift.surface, uShift: u, vShift: v,
        remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
        tolerance: tolerance, consumeWork: consumeWork) else {
        throw GeometryConversionError.invalidInput("Original iso translation is not in its support period lattice.")
      }
      chartSource = base; uShift = u; vShift = v
    }
    func translated(_ coordinate: Double, by shift: Double) throws -> Double {
      if shift == 0 { return coordinate }
      let singleton = try OriginalParameterImageMap.interval(.init(lower: coordinate, upper: coordinate),
        gain: .binary(1), offset: shift, sourceDomain: .unbounded, consumeWork: consumeWork)
      // FIXME(INCOMPLETE_IMPLEMENTATION): Native iso ownership retains exact
      // representable translated UV stations. Nonbinary stations need a
      // persistent rational UV traversal carrier before Mesh may use them.
      guard singleton.width == 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original translated iso station is not representable in its native owner carrier.")
      }
      return singleton.lower
    }
    func affineEndpoint(_ origin: Double, _ direction: Double, _ parameter: Double) throws -> Double {
      try withoutActuallyEscaping(consumeWork) { work in
        var usage = OriginalGeometryValidationAdmission(consumeWork: { _ in try work() }, consumeStorage: consumeStorage)
        let value = try ExactRationalCoefficient.originalDouble(origin, usage: &usage)
          .adding(ExactRationalCoefficient.originalDouble(direction, usage: &usage)
            .multiplied(by: .originalDouble(parameter, usage: &usage), usage: &usage), usage: &usage)
          .outwardInterval(usage: &usage)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Native affine iso consumers retain
        // exact binary stations here. Nonbinary original endpoint expressions
        // need a rational UV traversal carrier before Mesh may publish them.
        guard value.isFinite, value.lower == value.upper else {
          throw GeometryConversionError.resourceLimitExceeded("Original affine iso endpoint is not representable in the retained native UV carrier.")
        }
        return value.lower
      }
    }
    switch chartSource {
    case .affine(let origin, let direction, let first, let last):
      if direction.x == 0, direction.y != 0 {
        alongU = false; fixed = try translated(origin.x, by: uShift)
        start = try translated(affineEndpoint(origin.y, direction.y, first), by: vShift)
        end = try translated(affineEndpoint(origin.y, direction.y, last), by: vShift)
      } else if direction.y == 0, direction.x != 0 {
        alongU = true; fixed = try translated(origin.y, by: vShift)
        start = try translated(affineEndpoint(origin.x, direction.x, first), by: uShift)
        end = try translated(affineEndpoint(origin.x, direction.x, last), by: uShift)
      } else { return nil }
    case .polyline(let points):
      guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
      let variesU: Bool
      if first.u == last.u, first.v != last.v { variesU = false }
      else if first.v == last.v, first.u != last.u { variesU = true }
      else { return nil }
      let firstValue = variesU ? first.u : first.v
      let lastValue = variesU ? last.u : last.v
      let increasing = lastValue > firstValue
      var previous = firstValue
      for point in points {
        try consumeWork()
        guard (variesU ? point.v == first.v : point.u == first.u) else { return nil }
        let value = variesU ? point.u : point.v
        if value != previous, (value > previous) != increasing { return nil }
        previous = value
      }
      // The exact Euclidean lengths are absolute one-axis differences.
      // Their same-direction sum telescopes to the original endpoint difference.
      alongU = variesU
      fixed = try translated(variesU ? first.v : first.u, by: variesU ? vShift : uShift)
      start = try translated(firstValue, by: variesU ? uShift : vShift)
      end = try translated(lastValue, by: variesU ? uShift : vShift)
    case .constantU(let u, let vStart, let vEnd):
      alongU = false; fixed = try translated(u, by: uShift)
      start = try translated(vStart, by: vShift); end = try translated(vEnd, by: vShift)
    case .constantV(let v, let uStart, let uEnd):
      alongU = true; fixed = try translated(v, by: vShift)
      start = try translated(uStart, by: uShift); end = try translated(uEnd, by: uShift)
    default: return nil
    }
    guard parameters.lower >= 0, parameters.upper <= 1 else {
      throw GeometryConversionError.invalidInput("Original normalized iso lift exceeds its authored traversal.")
    }
    let slope = OutwardScalarInterval.exact(end) - .exact(start)
    guard slope.excludesZero else {
      throw GeometryConversionError.invalidInput("Original iso lift has no nonzero directed traversal.")
    }
    let authored = OutwardScalarInterval(lower: min(start, end), upper: max(start, end))
    guard let varying = (OutwardScalarInterval.exact(start)
      + slope * .init(lower: parameters.lower, upper: parameters.upper)).intersection(with: authored) else {
      throw GeometryConversionError.invalidInput("Original iso lift has no closed native query.")
    }
    let varyingRange = try ScalarInterval(lower: varying.lower, upper: varying.upper)
    let fixedRange = try ScalarInterval(lower: fixed, upper: fixed)
    let query = SurfaceParameterBox(u: alongU ? varyingRange : fixedRange,
      v: alongU ? fixedRange : varyingRange)
    let owners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
    if let consumeStorage {
      owners = try native.originalNativeSpans(over: query, tolerance: tolerance,
        maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: consumeWork, consumeStorage: consumeStorage)
    } else {
      owners = try native.originalNativeSpans(over: query, tolerance: tolerance,
        maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: consumeWork)
    }
    try OriginalCoefficientAllocation.reserve(count: owners.count, of: ClosedNativeJet.OwnedSpan.self, consumeStorage: consumeStorage)
    var result: [ClosedNativeJet.OwnedSpan] = []; result.reserveCapacity(owners.count)
    let zero = OutwardScalarInterval.exact(0)
    func chart(_ value: OutwardScalarInterval, derivative: OutwardScalarInterval) -> SurfaceIntervalJet {
      .init(value: value, derivativeU: derivative, derivativeV: zero,
        secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
        thirdDerivativeUUU: zero, thirdDerivativeUUV: zero,
        thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }
    func fraction(_ range: ScalarInterval) throws -> ScalarInterval {
      guard let original = (OutwardScalarInterval(lower: range.lower, upper: range.upper)
        - .exact(start)).divided(by: slope),
        let clipped = original.intersection(with: .init(lower: parameters.lower, upper: parameters.upper)) else {
        throw GeometryConversionError.resourceLimitExceeded("Original iso owner has no finite normalized localization.")
      }
      return try .init(lower: clipped.lower, upper: clipped.upper)
    }
    for (index, owner) in owners.enumerated() {
      try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
      let u = try ScalarInterval(lower: max(query.u.lower, owner.uBounds.lower),
        upper: min(query.u.upper, owner.uBounds.upper))
      let v = try ScalarInterval(lower: max(query.v.lower, owner.vBounds.lower),
        upper: min(query.v.upper, owner.vBounds.upper))
      let box = SurfaceParameterBox(u: u, v: v)
      let original: SurfaceIntervalVectorJet
      if let consumeStorage {
        original = try owner.intervalJet(overClosedBox: box, on: native.surface,
          tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
      } else {
        original = try owner.intervalJet(overClosedBox: box, on: native.surface,
          tolerance: tolerance, consumeWork: consumeWork)
      }
      let jet = SurfaceParameterThirdOrderChainRule.intervalJet(surface: original,
        u: chart(.init(lower: u.lower, upper: u.upper), derivative: alongU ? slope : zero),
        v: chart(.init(lower: v.lower, upper: v.upper), derivative: alongU ? zero : slope))
      let selected = alongU ? u : v
      let owningRange = alongU ? owner.uBounds : owner.vBounds
      let nativeLower = max(min(start, end), owningRange.lower)
      let nativeUpper = min(max(start, end), owningRange.upper)
      let traversal: SurfaceLiftCurve3D?
      if nativeLower < nativeUpper {
        let a = end > start ? nativeLower : nativeUpper
        let b = end > start ? nativeUpper : nativeLower
        let chart: SurfaceParameterCurve = alongU
          ? .constantV(v: fixed, uStart: a, uEnd: b)
          : .constantU(u: fixed, vStart: a, vEnd: b)
        traversal = .init(surface: lift.surface, parameterCurve: chart)
      } else { traversal = nil }
      result.append(.init(nativeIndex: index, nativeDomain: try fraction(owningRange),
        parameters: try fraction(selected), jet: jet, originalSurfaceSpan: owner,
        originalSurfaceParameters: box, originalIsoTraversal: traversal))
    }
    return result
  }

  private func liftJet(surface: PreparedSurfaceDifferentialEncloser,
    u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
    let uv = try SurfaceAreaIntervalTaylorVectorJet(x: u, y: v,
      z: .constant(.exact(0), order: u.order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)).intervalJet()
    let box = SurfaceParameterBox(u: try ScalarInterval(lower: uv.x.value.lower, upper: uv.x.value.upper),
      v: try ScalarInterval(lower: uv.y.value.lower, upper: uv.y.value.upper))
    let original = try surface.intervalJet(overClosedBox: box, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    try consumeWork()
    return SurfaceParameterThirdOrderChainRule.intervalJet(surface: original, u: uv.x, v: uv.y)
  }

  private func periodicNativeJets(spans: [RationalBezierCurveJetEncloser.NativeSpan],
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    boundedSpanCount: Int? = nil, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> ClosedNativeJet {
    guard case .bSpline(let original) = curve, original.isPeriodic,
          let first = spans.first, let last = spans.last else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Periodic span receipts require the original cyclic curve owner.")
    }
    let period = original.knots[original.controlPointCount] - original.knots[original.degree]
    guard period.isFinite, period > 0 else {
      throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "An original cyclic curve has no finite period.")
    }
    var result: [ClosedNativeJet.OwnedSpan] = []
    var capacity = 0
    func reserveAppend() throws {
      guard result.count == capacity else { return }
      let doubled = capacity.multipliedReportingOverflow(by: 2)
      guard !doubled.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original periodic curve result storage overflows.") }
      capacity = min(boundedSpanCount ?? Int.max, max(1, doubled.partialValue))
      try OriginalCoefficientAllocation.reserve(count: capacity, of: ClosedNativeJet.OwnedSpan.self, consumeStorage: consumeStorage)
      result.reserveCapacity(capacity)
    }
    if parameters.width >= period && boundedSpanCount == nil {
      for span in spans {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        let native = try ScalarInterval(lower: span.lower, upper: span.upper)
        if let boundedSpanCount, result.count >= boundedSpanCount { throw GeometryConversionError.resourceLimitExceeded("Original periodic closed cover exhausted caller span admission.") }
        let jet = try boundedSpanCount == nil
          ? RationalBezierCurveJetEncloser().enclosure(of: span, over: native, tolerance: tolerance)
          : OriginalNativeCurveHigherTaylor.enclosure(of: span, over: native, order: 3, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
        try consumeWork()
        try reserveAppend()
        result.append(.init(nativeIndex: span.index, nativeDomain: native, parameters: parameters, jet: jet))
      }
    } else {
      let lowerCycle = ((parameters.lower - last.upper) / period).rounded(.down)
      let upperCycle = ((parameters.upper - first.lower) / period).rounded(.up)
      guard lowerCycle.isFinite, upperCycle.isFinite,
            abs(lowerCycle) <= 9_007_199_254_740_990,
            abs(upperCycle) <= 9_007_199_254_740_990,
            upperCycle - lowerCycle <= Double(boundedSpanCount ?? 4) else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original periodic span lifts exceed finite cycle resolution.")
      }
      var cycle = lowerCycle
      while cycle <= upperCycle {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        let translation = OutwardScalarInterval.exact(cycle) * .exact(period)
        let lifted = OutwardScalarInterval(lower: parameters.lower, upper: parameters.upper) - translation
        guard translation.isFinite, lifted.isFinite else {
          throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original periodic span translation is nonfinite.")
        }
        for span in spans {
          try consumeWork()
          let lower = max(span.lower, lifted.lower), upper = min(span.upper, lifted.upper)
          guard lower <= upper else { continue }
          let native = try ScalarInterval(lower: lower, upper: upper)
          if let boundedSpanCount, result.count >= boundedSpanCount { throw GeometryConversionError.resourceLimitExceeded("Original periodic closed cover exhausted caller span admission.") }
        let jet = try boundedSpanCount == nil
          ? RationalBezierCurveJetEncloser().enclosure(of: span, over: native, tolerance: tolerance)
          : OriginalNativeCurveHigherTaylor.enclosure(of: span, over: native, order: 3, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
          let domain = OutwardScalarInterval(lower: span.lower, upper: span.upper) + translation
          guard domain.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
              message: "Original periodic owning domain is nonfinite.")
          }
          try consumeWork()
          try reserveAppend()
        result.append(.init(nativeIndex: span.index,
            nativeDomain: try ScalarInterval(lower: domain.lower, upper: domain.upper),
            parameters: try ScalarInterval(lower: max(parameters.lower, domain.lower),
              upper: min(parameters.upper, domain.upper)), jet: jet, originalPeriodicCycle: cycle))
        }
        cycle += 1
      }
    }
    guard !result.isEmpty else {
      throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
        message: "An original periodic query has no complete owning native span coverage.")
    }
    return ClosedNativeJet(source: curve, parameters: parameters, tolerance: tolerance, spans: result)
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
