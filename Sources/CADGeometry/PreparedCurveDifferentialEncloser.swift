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

  private struct CallerLift: Sendable {
    let lift: SurfaceLiftCurve3D
    let surface: PreparedSurfaceDifferentialEncloser
    let implicit: CertifiedImplicitSurfaceParameterCurve?
    let localizer: ImplicitCurveIntervalJetEncloser?
    let uShift: Double
    let vShift: Double
  }

  package let curve: Curve3D
  private let storage: Storage
  private let receipt: OriginalGeometryPreparationReceipt
  private let executionLimits: OriginalQueryExecutionLimits
  private let preparationTolerance: ModelingTolerance
  private let preparationMaximumAlgebraicDepth: Int?
  package func makeExecution() throws -> OriginalQueryExecution {
    try receipt.makeExecution()
  }

  package var certificationTolerance: ModelingTolerance { preparationTolerance }

  /// Immutable original nonperiodic coefficient owners for exact source consumers.
  var retainedOriginalNativeSpans: [RationalBezierCurveJetEncloser.NativeSpan]? {
    if case .nativeBSpline(let spans) = storage { return spans }
    return nil
  }

  package struct ContinuousFirstOrderSource: Sendable {
    package let prepared: PreparedCurveDifferentialEncloser
    package let parameters: ScalarInterval
    fileprivate init(prepared: PreparedCurveDifferentialEncloser, parameters: ScalarInterval) {
      self.prepared = prepared; self.parameters = parameters
    }
  }

  /// Issues positional continuity separately from the one-sided derivative hull.
  package func admittingContinuousFirstOrder(
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ContinuousFirstOrderSource? {
    try receipt.admit(tolerance: tolerance, using: &execution)
    guard tolerance == preparationTolerance, parameters.lower.isFinite,
      parameters.upper.isFinite, parameters.lower <= parameters.upper,
      maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
      throw GeometryConversionError.invalidInput("Original continuity requires its retained preparation and caller domain.")
    }
    if case .callerLift(let prepared) = storage,
      case .plane = prepared.lift.surface {
      let endpoints: (SurfaceParameter, SurfaceParameter)?
      switch prepared.lift.parameterCurve {
      case .polyline(let points) where points.count == 2:
        try execution.consumeWork(4)
        endpoints = (points[0], points[1])
      case .constantU(let u, let start, let end):
        try execution.consumeWork(4)
        endpoints = (.init(u: u, v: start), .init(u: u, v: end))
      case .constantV(let v, let start, let end):
        try execution.consumeWork(4)
        endpoints = (.init(u: start, v: v), .init(u: end, v: v))
      default: endpoints = nil
      }
      if let (first, last) = endpoints {
        guard parameters.lower >= 0, parameters.upper <= 1,
          first.u.isFinite, first.v.isFinite, last.u.isFinite, last.v.isFinite,
          first.u != last.u || first.v != last.v else {
          throw GeometryConversionError.invalidInput("Original affine lift continuity requires its finite positive segment and normalized source domain.")
        }
        guard remainingSourceDepth > 0 else {
          throw GeometryConversionError.resourceLimitExceeded("Original affine lift continuity exhausted caller source depth.")
        }
        try execution.admitSourceDepth(1)
        // Each selected original UV law is globally affine; its validated
        // authored plane preserves continuity on every normalized subdomain.
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ContinuousFirstOrderSource.self))
        try execution.checkpoint()
        return .init(prepared: self, parameters: parameters)
      }
    }
    if case .direct(.originalPolyline(let original)) = storage {
      guard parameters.lower >= 0, parameters.upper <= 1 else {
        throw GeometryConversionError.invalidInput("Original polyline continuity requires its normalized source domain.")
      }
      try original.validate(tolerance: tolerance); try execution.consumeWork(1)
      try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ContinuousFirstOrderSource.self))
      return .init(prepared: self, parameters: parameters)
    }
    if case .direct(.originalGuideTraversalChain(let original)) = storage {
      guard parameters.lower >= 0, parameters.upper <= 1,
        remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput("Original guide continuity requires its admitted normalized source domain.")
      }
      try original.validate(tolerance: tolerance)
      try execution.consumeWork(1)
      try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ContinuousFirstOrderSource.self))
      return .init(prepared: self, parameters: parameters)
    }
    if case .direct(.originalGuideEndpointConnector(let original)) = storage {
      guard parameters.lower >= 0, parameters.upper <= 1,
        remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput("Original corrected guide continuity requires its admitted normalized source domain.")
      }
      try original.validate(tolerance: tolerance)
      try execution.consumeWork(1)
      try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ContinuousFirstOrderSource.self))
      return .init(prepared: self, parameters: parameters)
    }
    if case .direct(.originalDrafted(let original)) = storage {

      let continuous = try original.hasOriginalFirstOrderContinuity(over: parameters, tolerance: tolerance,
          maximumSpanCount: original.maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, using: &execution)
      guard continuous else { return nil }
      try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ContinuousFirstOrderSource.self))
      return .init(prepared: self, parameters: parameters)
    }
    let first = try ExactRationalCoefficient.originalDouble(parameters.lower, usage: &execution)
    let last = try ExactRationalCoefficient.originalDouble(parameters.upper, usage: &execution)
    // FIXME(INCOMPLETE_IMPLEMENTATION): Selected curve-surface and embedding
    // callers need source-owned implicit/lift join continuity. This issuer
    // reuses exact native/analytic continuity only; a derivative hull cannot
    // grant the missing graph or lifted join authority.
    guard try OriginalCurveTraversalContinuityAdmission().proves(source: curve,
      first: first, last: last, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth,
      maximumAlgebraicDepth: preparationMaximumAlgebraicDepth,
      tolerance: tolerance, usage: &execution) else { return nil }
    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ContinuousFirstOrderSource.self))
    return .init(prepared: self, parameters: parameters)
  }

  package init(curve: Curve3D, tolerance: ModelingTolerance) throws {
    var execution = try Self.independentExecution()
    try self.init(curve: curve, tolerance: tolerance, using: &execution)
  }

  package init(curve: Curve3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
    try self.init(curve: curve, tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
      maximumAlgebraicDepth: nil, using: &execution)
  }

  private static func independentExecution() throws -> OriginalQueryExecution {
    OriginalQueryExecution(budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
  }

  /// Invocation-owned preparation for bounded closed queries, including implicit endpoints.
  package init(curve: Curve3D, tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int = Int.max,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
    let preparation = try execution.withPreparationScope { execution in
      try Self.makeStorage(curve: curve, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)
    }
    self.curve = curve
    self.preparationTolerance = tolerance
    self.preparationMaximumAlgebraicDepth = maximumAlgebraicDepth
    self.executionLimits = execution.effectiveLimits
    self.storage = preparation.result
    self.receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance, depth: preparation.depth,
      using: &execution)
  }

  @inline(never)
  private static func makeStorage(curve: Curve3D, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int?,
    using execution: inout OriginalQueryExecution) throws -> Storage {
    try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1); try tolerance.validate()
    guard remainingSourceDepth >= 0 else { throw GeometryConversionError.invalidInput("Original curve preparation needs caller source depth.") }
    try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    switch curve {
    case .bSpline(let original):
      return try makeNativeStorage(original, tolerance: tolerance, using: &execution)
    case .surfaceLift(let lift):
      return try makeLiftStorage(lift, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    case .implicit, .rigidImage, .parameterImage, .originalAffineWord, .affineImage:
      return try makePreparedFamilyStorage(curve: curve, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    default:
      return .direct(curve)
    }
  }

  @inline(never)
  private static func makeNativeStorage(_ original: BSplineCurve3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Storage {
      let spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: original,
        tolerance: tolerance, using: &execution)
      return original.isPeriodic ? .periodicNativeBSpline(spans) : .nativeBSpline(spans)
  }

  @inline(never)
  private static func makeLiftStorage(_ lift: SurfaceLiftCurve3D, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int?,
    using execution: inout OriginalQueryExecution) throws -> Storage {
    func childDepth() throws -> Int {
      guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original curve preparation exhausted caller source depth.") }
      return remainingSourceDepth - 1
    }
      let depth = try childDepth()
      if case .originalAffineWord(let image) = lift.parameterCurve {
        let depth = try childDepth()
        return .originalWordLift(image, try Self(curve: .surfaceLift(image.source),
          tolerance: tolerance, remainingSourceDepth: depth,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
      }
      if case .originalImage(let image) = lift.parameterCurve {
        return .originalLiftImage(image, try Self(curve: .surfaceLift(image.source),
          tolerance: tolerance, remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
      } else {
        var chart = lift.parameterCurve
        var uShift = 0.0, vShift = 0.0, wrappers = depth
        unwrap: while true {
          switch chart {
          case .periodicTranslation(let original, let u, let v):
            guard wrappers > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original lifted pcurve exhausted caller source depth.") }
            try execution.consumeWork(1); wrappers -= 1; chart = original; uShift += u; vShift += v
          case .offsetSurfaceImage(let image):
            guard wrappers > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original lifted offset chart exhausted caller source depth.") }
            try execution.consumeWork(1); wrappers -= 1; chart = image.source
          default: break unwrap
          }
        }
        guard uShift.isFinite, vShift.isFinite else { throw GeometryConversionError.invalidInput("Original lifted chart shift is not finite.") }
        let implicit: CertifiedImplicitSurfaceParameterCurve?
        if case .certifiedImplicit(let source) = chart { implicit = source } else { implicit = nil }
        let localizer = try implicit.map { try ImplicitCurveIntervalJetEncloser(localizing: $0.intersection,
          tolerance: tolerance, maximumSpanCount: Int.max, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: depth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) }
        return .callerLift(.init(lift: lift,
          surface: try PreparedSurfaceDifferentialEncloser(surface: lift.surface, tolerance: tolerance,
            remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution), implicit: implicit,
          localizer: localizer, uShift: uShift, vShift: vShift))
      }
  }

  @inline(never)
  private static func makePreparedFamilyStorage(curve: Curve3D, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int?,
    using execution: inout OriginalQueryExecution) throws -> Storage {
    func childDepth() throws -> Int {
      guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original curve preparation exhausted caller source depth.") }
      return remainingSourceDepth - 1
    }
    switch curve {
    case .implicit(let original):
      let depth = try childDepth()
      return .callerImplicit(original,
        try ImplicitCurveIntervalJetEncloser(localizing: original, tolerance: tolerance,
          maximumSpanCount: Int.max, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution),
        try PreparedSurfaceDifferentialEncloser(surface: original.firstSurface, tolerance: tolerance,
          remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
    case .rigidImage(let image):
      return .rigid(image.transform, source: try Self(curve: image.source, tolerance: tolerance,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
    case .parameterImage(let image):
      return .parameterImage(image, source: try Self(curve: image.source, tolerance: tolerance,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
    case .originalAffineWord(let image):
      if case .some = image.circularCoefficients { return .direct(curve) }
      else { return .originalAffineWord(image, source: try Self(curve: image.source,
        tolerance: try image.sourceCalculationTolerance(tolerance: tolerance, using: &execution), remainingSourceDepth: childDepth(),
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)) }
    case .affineImage(let image):
      return .affine(image.transform, source: try Self(curve: image.source, tolerance: tolerance,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
    default:
      throw GeometryConversionError.invalidInput("Original curve preparation family dispatch requires its selected family.")
    }
  }

  func thirdOrderIntervalJet(over parameters: ScalarInterval,
    tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    var execution = try receipt.makeExecution()
    return try thirdOrderIntervalJet(over: parameters, tolerance: tolerance, using: &execution)
  }

  func thirdOrderIntervalJet(over parameters: ScalarInterval, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let receipt = try closedNativeJets(over: parameters, tolerance: tolerance, using: &execution)
    guard let first = receipt.spans.first else {
      throw GeometryConversionError.invalidInput("Original closed source has no owning span.")
    }
    var result = first.jet
    for span in receipt.spans.dropFirst() { try execution.consumeWork(1); result = result.union(span.jet) }
    try execution.checkpoint()
    return result
  }

  package func selectedAffineOwningJet(
    owner: ClosedNativeJet.OwnedSpan, normalizedLower: ExactRationalCoefficient,
    normalizedUpper: ExactRationalCoefficient, throughOrder: Int,
    tolerance: ModelingTolerance, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> OriginalRationalCurveIntervalJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    guard tolerance == preparationTolerance else {
      throw GeometryConversionError.invalidInput("Selected original polynomial query requires its preparation tolerance.")
    }
    if case .direct(.originalConstructionChart(let image)) = storage {
      return try image.selectedAffineOwningJet(owner: owner, normalizedLower: normalizedLower,
        normalizedUpper: normalizedUpper, throughOrder: throughOrder,
        tolerance: tolerance, remainingSourceDepth: remainingSourceDepth, usage: &execution)
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
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: execution.effectiveLimits.maximumSpans,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
  }

  /// Separate source-owning sides; no hull establishes continuity at a knot or graph join.
  @inline(never)
  package func closedNativeJets(over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1); try tolerance.validate()
    guard tolerance == preparationTolerance, maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
      remainingSourceDepth >= 0, parameters.lower.isFinite, parameters.upper.isFinite,
      parameters.lower <= parameters.upper else {
      throw GeometryConversionError.invalidInput("Bounded original closed curves need their preparation tolerance and caller ceilings.")
    }
    switch storage {
    case .nativeBSpline(let spans):
      return try nativeClosedNativeJets(spans, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .periodicNativeBSpline(let spans):
      return try periodicNativeJets(spans: spans, over: parameters, tolerance: tolerance,
        boundedSpanCount: maximumSpanCount, using: &execution)
    case .rigid(let transform, let source):
      return try rigidClosedNativeJets(transform, source: source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .originalAffineWord(let image, let source):
      return try wordClosedNativeJets(image, source: source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .originalWordLift(let image, let source):
      return try wordLiftClosedNativeJets(image, source: source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .affine(let transform, let source):
      return try affineClosedNativeJets(transform, source: source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .parameterImage(let image, let source):
      return try parameterImageClosedNativeJets(image, source: source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .originalLiftImage(let image, let source):
      return try liftImageClosedNativeJets(image, source: source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .callerImplicit(let original, let localizer, let surface):
      return try implicitClosedNativeJets(original, localizer: localizer, surface: surface, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .callerLift(let prepared):
      return try callerLiftClosedNativeJets(prepared, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .implicit, .implicitLift:
      return try repreparedClosedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    case .direct(let original):
      return try directClosedNativeJets(original, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    }
  }

  private func closedNativeSourceDepth(_ remainingSourceDepth: Int) throws -> Int {
    guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original closed curve source exhausted caller depth.") }
    return remainingSourceDepth - 1
  }

  private func publishClosedNativeJets(_ spans: [ClosedNativeJet.OwnedSpan],
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int) throws -> ClosedNativeJet {
    guard !spans.isEmpty, spans.count <= maximumSpanCount else {
      throw GeometryConversionError.resourceLimitExceeded("Original closed curve owning cover is empty or exceeds caller admission.")
    }
    return .init(source: curve, parameters: parameters, tolerance: tolerance, spans: spans)
  }

  @inline(never)
  private func singletonClosedNativeJet(_ jet: SurfaceIntervalVectorJet,
    over parameters: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try OriginalCoefficientAllocation.reserve(count: 1, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets([.init(nativeIndex: 0, nativeDomain: parameters, parameters: parameters, jet: jet)],
      over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func nativeClosedNativeJets(_ spans: [RationalBezierCurveJetEncloser.NativeSpan],
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    guard let first = spans.first, let last = spans.last,
      parameters.lower >= first.lower, parameters.upper <= last.upper else {
      throw GeometryConversionError.invalidInput("Original closed curve exceeds its native owning support.")
    }
    var result: [ClosedNativeJet.OwnedSpan] = []
    var capacity = 0
    for span in spans {
      try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
      let lo = max(parameters.lower, span.lower), hi = min(parameters.upper, span.upper)
      guard lo <= hi else { continue }
      guard result.count < maximumSpanCount else { throw GeometryConversionError.resourceLimitExceeded("Original closed curve span ceiling exhausted.") }
      let selected = try ScalarInterval(lower: lo, upper: hi)
      let jet = try OriginalNativeCurveHigherTaylor.enclosure(of: span, over: selected,
        order: 3, tolerance: tolerance, using: &execution).intervalJet()
      if result.count == capacity {
        let doubled = capacity.multipliedReportingOverflow(by: 2)
        guard !doubled.overflow else { throw GeometryConversionError.resourceLimitExceeded("Closed native curve result storage overflows.") }
        capacity = min(maximumSpanCount, max(1, doubled.partialValue))
        try OriginalCoefficientAllocation.reserve(count: capacity, of: ClosedNativeJet.OwnedSpan.self, using: &execution); result.reserveCapacity(capacity)
      }
      result.append(.init(nativeIndex: span.index, nativeDomain: try ScalarInterval(lower: span.lower, upper: span.upper), parameters: selected, jet: jet))
    }
    return try publishClosedNativeJets(result, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func rigidClosedNativeJets(_ transform: RigidTransform3D, source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let original = try source.closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution)
    try OriginalCoefficientAllocation.reserve(count: original.spans.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets(try original.spans.map {
      try execution.consumeWork(1)
      return .init(nativeIndex: $0.nativeIndex,
      nativeDomain: $0.nativeDomain, parameters: $0.parameters, jet: transformed($0.jet, by: transform), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal, originalAffineParameterMap: $0.originalAffineParameterMap) }, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func wordClosedNativeJets(_ image: OriginalAffineWordCurve3D, source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let original = try source.closedNativeJets(over: parameters, tolerance: source.preparationTolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution)
    try OriginalCoefficientAllocation.reserve(count: original.spans.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets(original.spans.map { span in
      try execution.consumeWork(1)
      return .init(nativeIndex: span.nativeIndex, nativeDomain: span.nativeDomain,
        parameters: span.parameters,
        jet: try OriginalAffineWordJetTransport.applying(image.preparedWord, to: span.jet,
          using: &execution),
        originalPeriodicCycle: span.originalPeriodicCycle, originalSurfaceSpan: span.originalSurfaceSpan,
        originalSurfaceParameters: span.originalSurfaceParameters, originalIsoTraversal: span.originalIsoTraversal, originalAffineParameterMap: span.originalAffineParameterMap,
        originalGuideTraversal: span.originalGuideTraversal, originalGuideLowerParameter: span.originalGuideLowerParameter,
        originalGuideUpperParameter: span.originalGuideUpperParameter)
    }, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func wordLiftClosedNativeJets(_ image: OriginalAffineWordSurfaceParameterCurve, source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let original = try source.closedNativeJets(over: image.mappedRange(parameters), tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution)
    let gain = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
    guard gain.excludesZero else { throw GeometryConversionError.invalidInput("Original word lift has no signed traversal gain.") }
    try OriginalCoefficientAllocation.reserve(count: original.spans.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets(original.spans.map { span in
      try execution.consumeWork(1)
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
          using: &execution),
        originalPeriodicCycle: span.originalPeriodicCycle, originalSurfaceSpan: span.originalSurfaceSpan,
        originalSurfaceParameters: span.originalSurfaceParameters, originalIsoTraversal: span.originalIsoTraversal)
    }, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func affineClosedNativeJets(_ transform: AffineTransform3D, source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let original = try source.closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution)
    try OriginalCoefficientAllocation.reserve(count: original.spans.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets(try original.spans.map {
      try execution.consumeWork(1)
      return .init(nativeIndex: $0.nativeIndex,
      nativeDomain: $0.nativeDomain, parameters: $0.parameters, jet: transformed($0.jet, by: transform), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal, originalAffineParameterMap: $0.originalAffineParameterMap) }, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func parameterImageClosedNativeJets(_ image: ParameterImageCurve3D, source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let original = try source.closedNativeJets(over: image.originalInterval(parameters, using: &execution), tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution)
    func inverse(_ interval: ScalarInterval) throws -> ScalarInterval {
      try OriginalParameterImageMap.inverseInterval(interval, gain: image.parameterGain, offset: image.offset, using: &execution)
    }
    try OriginalCoefficientAllocation.reserve(count: original.spans.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets(try original.spans.map {
      try execution.consumeWork(1)
      return .init(nativeIndex: $0.nativeIndex,
      nativeDomain: try inverse($0.nativeDomain), parameters: try inverse($0.parameters), jet: try image.mappedJet($0.jet), originalPeriodicCycle: $0.originalPeriodicCycle, originalSurfaceSpan: $0.originalSurfaceSpan, originalSurfaceParameters: $0.originalSurfaceParameters, originalIsoTraversal: $0.originalIsoTraversal) }, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func liftImageClosedNativeJets(_ image: OriginalImageSurfaceParameterCurve, source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let original = try source.closedNativeJets(over: image.mappedRange(parameters), tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution)
    let gain = OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)
    guard gain.excludesZero else { throw GeometryConversionError.invalidInput("Original lifted image has no directed parameter interval.") }
    try OriginalCoefficientAllocation.reserve(count: original.spans.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
    return try publishClosedNativeJets(original.spans.map { span in
      try execution.consumeWork(1)
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
    }, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func implicitClosedNativeJets(_ original: CertifiedImplicitIntersectionCurve, localizer: ImplicitCurveIntervalJetEncloser, surface: PreparedSurfaceDifferentialEncloser,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded original implicit owning
    // queries now forward actual scratch bytes. Complete critical-cell atlases
    // and cross-cell smooth transition authority remain required; these
    // one-sided original jets do not establish a smooth global chain.
    return try publishClosedNativeJets(implicitSpans(original: original, localizer: localizer, surface: surface,
      over: parameters, outputParameters: parameters, role: 0, gain: .exact(1), parameterOffset: .exact(0), uShift: 0, vShift: 0,
      tolerance: tolerance, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution), over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
  }

  @inline(never)
  private func callerLiftClosedNativeJets(_ prepared: CallerLift,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    if let chart = prepared.implicit, let localizer = prepared.localizer {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Original implicit lifted sides
      // retain per-cell jets and paid scratch; critical transitions still need
      // exact original common-root and requested continuity receipts.
      let gain = OutwardScalarInterval.exact(chart.endFraction) - .exact(chart.startFraction)
      let mapped = OutwardScalarInterval.exact(chart.startFraction) + gain * .init(lower: parameters.lower, upper: parameters.upper)
      guard let restricted = mapped.intersection(with: .init(lower: min(chart.startFraction, chart.endFraction), upper: max(chart.startFraction, chart.endFraction))) else {
        throw GeometryConversionError.invalidInput("Original lifted chart has no retained graph interval.")
      }
      return try publishClosedNativeJets(implicitSpans(original: chart.intersection, localizer: localizer, surface: prepared.surface,
        over: ScalarInterval(lower: restricted.lower, upper: restricted.upper), outputParameters: parameters,
        role: chart.role == .first ? 0 : 2, gain: gain, parameterOffset: .exact(chart.startFraction), uShift: prepared.uShift, vShift: prepared.vShift,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), using: &execution), over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
    }
    if let native = prepared.surface.originalNativePreparation,
      let spans = try nativeIsoSpans(lift: prepared.lift, native: native, over: parameters,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        using: &execution) {
      return try publishClosedNativeJets(spans, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Generic lifts now forward query
    // bytes to original UV/support producers. Their unresolved source-family
    // and native join-partition cases remain required before full lift closure;
    // an aggregate derivative hull is not a smoothness receipt.
    let uv = try OriginalParameterCurveHigherTaylor.enclosure(prepared.lift.parameterCurve,
      over: parameters, order: 3, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: closedNativeSourceDepth(remainingSourceDepth), maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
    let jet = try liftJet(surface: prepared.surface, u: uv.u, v: uv.v, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
    return try singletonClosedNativeJet(jet, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &execution)
  }

  @inline(never)
  private func repreparedClosedNativeJets(over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let prepared = try Self(curve: curve, tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    return try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
  }

  @inline(never)
  private func higherClosedNativeJets(_ original: Curve3D,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Nondirect original higher families
    // delegate byte admission to the actual higher provider. Its remaining
    // periodic/implicit/lift branches refuse unmetered query allocations.
    let jet = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: original, over: parameters,
      tolerance: tolerance, throughOrder: 4, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution).intervalJet()
    return try singletonClosedNativeJet(jet, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &execution)
  }

  @inline(never)
  private func directClosedNativeJets(_ original: Curve3D,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    switch original {
    case .originalAffineWord(let image):
      return try circularWordClosedNativeJets(image, original: original, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalConstructionChart(let image):
      return try constructionClosedNativeJets(image, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalPolyline(let source):
      return try polylineJets(source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalGuideTraversalChain(let source):
      return try guideJets(source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalGuideEndpointConnector(let source):
      return try guideJets(source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalDrafted(let source):
      return try draftedClosedNativeJets(source, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalPlaneDerivative(let source):
      return try source.closedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .originalEndpointConnector(let connector):
      return try connectorJets(connector, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    case .surfaceLift:
      return try surfaceLiftClosedNativeJets(original, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)

    default:
      return try elementaryClosedNativeJets(original, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
    }
  }

  @inline(never)
  private func circularWordClosedNativeJets(_ image: OriginalAffineWordCurve3D, original: Curve3D,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    if let coefficients = image.circularCoefficients {
      let jet = try coefficients.intervalTaylorJet(over: parameters, throughOrder: 3,
        tolerance: tolerance, using: &execution).intervalJet()
      return try singletonClosedNativeJet(jet, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &execution)

    }
    return try elementaryClosedNativeJets(original, over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
  }

  @inline(never)
  private func constructionClosedNativeJets(_ image: OriginalCurveConstructionChartImage,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    if let owners = try image.affineOwningJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution) {
      return try publishClosedNativeJets(owners, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount)
    }
    let jet = try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution).intervalJet()
    return try singletonClosedNativeJet(jet, over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &execution)
  }

  @inline(never)
  private func draftedClosedNativeJets(_ source: OriginalDraftedCurve3D,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    return try singletonClosedNativeJet(source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution).intervalJet(), over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &execution)
  }

  @inline(never)
  private func surfaceLiftClosedNativeJets(_ original: Curve3D,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    let prepared = try Self(curve: original, tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    return try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
  }

  @inline(never)
  private func elementaryClosedNativeJets(_ original: Curve3D,
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    if let jet = try DefaultCurveDifferentialEncloser().directJet(original, parameters: parameters,
      tolerance: tolerance, using: &execution) {
      return try singletonClosedNativeJet(jet, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, using: &execution)
    }
    return try higherClosedNativeJets(original, over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
  }

  @inline(never)
  private func polylineJets(_ original: OriginalPolylineCurve3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let owners = try original.owningDerivativeJets(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: owners.count, of: ClosedNativeJet.OwnedSpan.self,
      using: &execution)
    var spans: [ClosedNativeJet.OwnedSpan] = []; spans.reserveCapacity(owners.count)
    func axis(_ original: IntervalDerivativeJet) throws -> SurfaceIntervalJet {
      try execution.consumeWork(1)
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

  @inline(never)
  private func guideJets(_ source: OriginalGuideTraversalChain3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let owners = try source.owningDerivativeJets(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
    return try guideJets(owners: owners, traversals: source.traversals, over: parameters,
      tolerance: tolerance, using: &execution)
  }

  @inline(never)
  private func guideJets(_ source: OriginalGuideEndpointConnectorCurve3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let owners = try source.owningDerivativeJets(over: parameters, throughOrder: 3, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
    guard case .originalGuideTraversalChain(let chain) = source.source.source else {
      throw GeometryConversionError.invalidInput("Original corrected guide lost its declared traversal source.")
    }
    return try guideJets(owners: owners, traversals: chain.traversals, over: parameters,
      tolerance: tolerance, using: &execution)
  }

  @inline(never)
  private func guideJets(owners: [OriginalGuideTraversalOwningJet], traversals: [OriginalCurveRootSpan3D],
    over parameters: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: owners.count, of: ClosedNativeJet.OwnedSpan.self,
      using: &execution)
    var spans: [ClosedNativeJet.OwnedSpan] = []; spans.reserveCapacity(owners.count)
    func axis(_ original: IntervalDerivativeJet) throws -> SurfaceIntervalJet {
      guard original.derivatives.count == 4 else {
        throw GeometryConversionError.invalidInput("Original guide owner must retain D0 through D3.")
      }
      try execution.consumeWork(1)
      return .init(value: original.derivatives[0], derivativeU: original.derivatives[1], derivativeV: .exact(0),
        secondDerivativeUU: original.derivatives[2], secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
        thirdDerivativeUUU: original.derivatives[3], thirdDerivativeUUV: .exact(0),
        thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
    }
    for owner in owners {
      try execution.consumeWork(1)
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

  @inline(never)
  private func connectorJets(_ connector: OriginalEndpointConnectorCurve3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let original = try connector.constructionTraversal.constructionNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
    let corrected = try connector.correctedOwningSpans(from: original, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, using: &execution)
    return .init(source: curve, parameters: parameters, tolerance: tolerance, spans: corrected)
  }

  package func positionBounds(over parameters: ScalarInterval, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> IntervalVector3DBounds {
    try receipt.admit(tolerance: tolerance, using: &execution)
    if case .direct(.originalPolyline(let original)) = storage {
      guard tolerance == preparationTolerance else { throw GeometryConversionError.invalidInput("Original polyline position changed preparation tolerance.") }
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    if case .direct(.originalGuideTraversalChain(let original)) = storage {
      guard tolerance == preparationTolerance else {
        throw GeometryConversionError.invalidInput("Original guide position changed its preparation tolerance.")
      }
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    if case .direct(.originalGuideEndpointConnector(let original)) = storage {
      guard tolerance == preparationTolerance else {
        throw GeometryConversionError.invalidInput("Original corrected guide position changed preparation tolerance.")
      }
      return try original.preparedFirstOrder(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth, using: &execution).position
    }
    if case .direct(.originalDrafted(let original)) = storage {
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    if case .direct(.originalPlaneDerivative(let original)) = storage {
      guard tolerance == preparationTolerance, remainingSourceDepth >= 0 else {
        throw GeometryConversionError.invalidInput("Original plane position query changed preparation binding.")
      }
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    }
    let receipt = try closedNativeJets(over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      using: &execution)
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

    package func station(atOriginalSurfaceCoordinate target: ExactRationalCoefficient,
      maximumNormalizedParameterWidth: Double, maximumAlgebraicDepth: Int,
      using execution: inout OriginalQueryExecution) throws -> PreparedOriginalNativeAxisInverse.Station? {
      let shift = try ExactRationalCoefficient.originalDouble(inverse.alongU ? uShift : vShift, usage: &execution)
      return try inverse.station(at: target.subtracting(shift, usage: &execution),
        maximumNormalizedParameterWidth: maximumNormalizedParameterWidth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)
    }
  }

  /// Owns the physical iso partition separately from a nonlinear native UV clock.
  package func originalNativeAxisIsoCover(over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
    maximumNormalizedParameterWidth: Double, using execution: inout OriginalQueryExecution) throws -> [OriginalNativeAxisIsoTraversal]? {
    try receipt.admit(tolerance: tolerance, using: &execution)
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
        uShiftQ = try uShiftQ.adding(.originalDouble(u, usage: &execution), usage: &execution)
        vShiftQ = try vShiftQ.adding(.originalDouble(v, usage: &execution), usage: &execution)
        guard sourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original native axis cover exhausted source descent.") }
        try execution.consumeWork(1); sourceDepth -= 1; chartSource = child
      } else if case .offsetSurfaceImage(let image) = chartSource {
        guard sourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original native axis cover exhausted source descent.") }
        try execution.consumeWork(1); sourceDepth -= 1; chartSource = image.source
      } else { break }
    }
    guard case .bSpline(let original) = chartSource,
      let firstPoint = original.controlPoints.first, let lastPoint = original.controlPoints.last,
      (firstPoint.x == lastPoint.x) != (firstPoint.y == lastPoint.y) else { return nil }
    let alongU = firstPoint.y == lastPoint.y
    let inverse = try PreparedOriginalNativeAxisInverse(source: original, alongU: alongU,
      tolerance: tolerance, remainingSourceDepth: sourceDepth, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
      usage: &execution)
    guard original.knots.prefix(original.degree + 1).allSatisfy({ $0 == original.knots[original.degree] }),
      original.knots.suffix(original.degree + 1).allSatisfy({ $0 == original.knots[original.controlPoints.count] }) else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Whole native axis covers currently
      // retain clamped authored endpoint UV coordinates. Unclamped or partial
      // source clocks need exact endpoint-coordinate carriers before publication.
      return nil
    }
    try execution.consumeWork(original.degree * 2 + 2)
    let first = original.controlPoints[0], last = original.controlPoints[original.controlPoints.count-1]
    let shiftBound = try (inverse.alongU ? uShiftQ : vShiftQ).outwardInterval(usage: &execution)
    let fixedShiftBound = try (inverse.alongU ? vShiftQ : uShiftQ).outwardInterval(usage: &execution)
    guard shiftBound.lower == shiftBound.upper, fixedShiftBound.lower == fixedShiftBound.upper,
      shiftBound.isFinite, fixedShiftBound.isFinite else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Complete periodic UV shift sums
      // require retained rational chart coordinates when not exactly binary.
      // Rounded accumulation in numerical lift caches is not source authority.
      throw GeometryConversionError.resourceLimitExceeded("Original native iso shift needs a rational UV carrier.")
    }
    let shift = shiftBound.lower, fixedShift = fixedShiftBound.lower
    func translated(_ value: Double, by shift: Double, using execution: inout OriginalQueryExecution) throws -> Double {
      let exact = try ExactRationalCoefficient.originalDouble(value, usage: &execution)
        .adding(.originalDouble(shift, usage: &execution), usage: &execution)
      let bound = try exact.outwardInterval(usage: &execution)
      guard bound.lower == bound.upper, bound.isFinite else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Native physical iso publication
        // needs a rational UV endpoint carrier for nonrepresentable translated
        // source coordinates. Its enclosing box cannot replace the original cut.
        throw GeometryConversionError.resourceLimitExceeded("Original iso coordinate has no exact binary carrier.")
      }
      return bound.lower
    }
    let start = try translated(inverse.alongU ? first.x : first.y, by: shift, using: &execution)
    let end = try translated(inverse.alongU ? last.x : last.y, by: shift, using: &execution)
    let fixed = try translated(inverse.alongU ? first.y : first.x, by: fixedShift, using: &execution)
    let varying = try ScalarInterval(lower: min(start,end), upper: max(start,end))
    let constant = try ScalarInterval(lower: fixed, upper: fixed)
    let box = SurfaceParameterBox(u: inverse.alongU ? varying : constant, v: inverse.alongU ? constant : varying)

    let owners = try native.originalNativeSpans(over: box, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, using: &execution)
    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: owners.count, of: OriginalNativeAxisIsoTraversal.self))
    var output: [OriginalNativeAxisIsoTraversal] = []; output.reserveCapacity(owners.count)
    let shiftQ = try ExactRationalCoefficient.originalDouble(shift, usage: &execution)
    for owner in owners {
      try execution.consumeWork(1)
      let domain = inverse.alongU ? owner.uBounds : owner.vBounds
      let lower = max(varying.lower, domain.lower), upper = min(varying.upper, domain.upper)
      if lower >= upper { continue }
      let a = inverse.orientation > 0 ? lower : upper
      let b = inverse.orientation > 0 ? upper : lower
      guard let firstStation = try inverse.station(at: ExactRationalCoefficient.originalDouble(a, usage: &execution)
        .subtracting(shiftQ, usage: &execution), maximumNormalizedParameterWidth: maximumNormalizedParameterWidth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution),
        let lastStation = try inverse.station(at: ExactRationalCoefficient.originalDouble(b, usage: &execution)
          .subtracting(shiftQ, usage: &execution), maximumNormalizedParameterWidth: maximumNormalizedParameterWidth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution) else {
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

  @inline(never)
  private func implicitSpans(original: CertifiedImplicitIntersectionCurve, localizer: ImplicitCurveIntervalJetEncloser,
    surface: PreparedSurfaceDifferentialEncloser, over native: ScalarInterval, outputParameters: ScalarInterval,
    role: Int, gain: OutwardScalarInterval, parameterOffset: OutwardScalarInterval, uShift: Double, vShift: Double, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> [ClosedNativeJet.OwnedSpan] {
    try receipt.admit(tolerance: tolerance, using: &execution)
    var result: [ClosedNativeJet.OwnedSpan] = []
    var capacity = 0
    for index in original.cells.indices {
      try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
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
        selectedOwningCellIndex: index, preparedLocalizer: localizer, using: &execution)
      var u = try OriginalCurveTaylorComposition.scaledParameter(q[role], scale: gain, order: 3, using: &execution)
      var v = try OriginalCurveTaylorComposition.scaledParameter(q[role + 1], scale: gain, order: 3, using: &execution)
      if uShift != 0 { u = try u.adding(.constant(.exact(uShift), order: 3, tolerance: tolerance, using: &execution), using: &execution) }
      if vShift != 0 { v = try v.adding(.constant(.exact(vShift), order: 3, tolerance: tolerance, using: &execution), using: &execution) }
      let jet = try liftJet(surface: surface, u: u, v: v, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
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
        try OriginalCoefficientAllocation.reserve(count: capacity, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
        result.reserveCapacity(capacity)
      }
      result.append(.init(nativeIndex: index,
        nativeDomain: try callerRange(.init(lower: lower.lower, upper: upper.upper)),
        parameters: try callerRange(.init(lower: lo, upper: hi)), jet: jet))
    }
    return result
  }

  /// Returns original one-sided tensor owners, never a synthetic smooth join.
  @inline(never)
  private func nativeIsoSpans(lift: SurfaceLiftCurve3D,
    native: PreparedBSplineSurfaceDifferentialEncloser, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> [ClosedNativeJet.OwnedSpan]? {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let alongU: Bool, fixed: Double, start: Double, end: Double
    var chartSource = lift.parameterCurve
    var uShift = 0.0, vShift = 0.0
    if case .periodicTranslation(let base, let u, let v) = chartSource {
      guard try OriginalSurfacePeriodShift.proves(on: lift.surface, uShift: u, vShift: v,
        remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
        tolerance: tolerance, using: &execution) else {
        throw GeometryConversionError.invalidInput("Original iso translation is not in its support period lattice.")
      }
      chartSource = base; uShift = u; vShift = v
    }
    func translated(_ coordinate: Double, by shift: Double) throws -> Double {
      if shift == 0 { return coordinate }
      let singleton = try OriginalParameterImageMap.interval(.init(lower: coordinate, upper: coordinate),
        gain: .binary(1), offset: shift, sourceDomain: .unbounded, using: &execution)
      // FIXME(INCOMPLETE_IMPLEMENTATION): Native iso ownership retains exact
      // representable translated UV stations. Nonbinary stations need a
      // persistent rational UV traversal carrier before Mesh may use them.
      guard singleton.width == 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original translated iso station is not representable in its native owner carrier.")
      }
      return singleton.lower
    }
    func affineEndpoint(_ origin: Double, _ direction: Double, _ parameter: Double) throws -> Double {
      let value = try ExactRationalCoefficient.originalDouble(origin, usage: &execution)
          .adding(ExactRationalCoefficient.originalDouble(direction, usage: &execution)
            .multiplied(by: .originalDouble(parameter, usage: &execution), usage: &execution), usage: &execution)
          .outwardInterval(usage: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Native affine iso consumers retain
        // exact binary stations here. Nonbinary original endpoint expressions
        // need a rational UV traversal carrier before Mesh may publish them.
        guard value.isFinite, value.lower == value.upper else {
          throw GeometryConversionError.resourceLimitExceeded("Original affine iso endpoint is not representable in the retained native UV carrier.")
        }
        return value.lower
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
        try execution.consumeWork(1)
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

      owners = try native.originalNativeSpans(over: query, tolerance: tolerance,
        maximumSpanCount: min(262_144, maximumSpanCount), using: &execution)

    try OriginalCoefficientAllocation.reserve(count: owners.count, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
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
      try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
      let u = try ScalarInterval(lower: max(query.u.lower, owner.uBounds.lower),
        upper: min(query.u.upper, owner.uBounds.upper))
      let v = try ScalarInterval(lower: max(query.v.lower, owner.vBounds.lower),
        upper: min(query.v.upper, owner.vBounds.upper))
      let box = SurfaceParameterBox(u: u, v: v)
      let original: SurfaceIntervalVectorJet

        original = try owner.intervalJet(overClosedBox: box, on: native.surface,
          tolerance: tolerance, using: &execution)

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

  @inline(never)
  private func liftJet(surface: PreparedSurfaceDifferentialEncloser,
    u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
    let uv = try SurfaceAreaIntervalTaylorVectorJet(x: u, y: v,
      z: .constant(.exact(0), order: u.order, tolerance: tolerance, using: &execution)).intervalJet()
    let box = SurfaceParameterBox(u: try ScalarInterval(lower: uv.x.value.lower, upper: uv.x.value.upper),
      v: try ScalarInterval(lower: uv.y.value.lower, upper: uv.y.value.upper))
    let original = try surface.intervalJet(overClosedBox: box, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
    try execution.consumeWork(1)
    return SurfaceParameterThirdOrderChainRule.intervalJet(surface: original, u: uv.x, v: uv.y)
  }

  @inline(never)
  private func periodicNativeJets(spans: [RationalBezierCurveJetEncloser.NativeSpan],
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    boundedSpanCount: Int? = nil, using execution: inout OriginalQueryExecution) throws -> ClosedNativeJet {
    try receipt.admit(tolerance: tolerance, using: &execution)
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
      try OriginalCoefficientAllocation.reserve(count: capacity, of: ClosedNativeJet.OwnedSpan.self, using: &execution)
      result.reserveCapacity(capacity)
    }
    if parameters.width >= period && boundedSpanCount == nil {
      for span in spans {
        try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
        let native = try ScalarInterval(lower: span.lower, upper: span.upper)
        if let boundedSpanCount, result.count >= boundedSpanCount { throw GeometryConversionError.resourceLimitExceeded("Original periodic closed cover exhausted caller span admission.") }
        let jet = try boundedSpanCount == nil
          ? RationalBezierCurveJetEncloser().enclosure(of: span, over: native, tolerance: tolerance, using: &execution)
          : OriginalNativeCurveHigherTaylor.enclosure(of: span, over: native, order: 3, tolerance: tolerance, using: &execution).intervalJet()
        try execution.consumeWork(1)
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
        try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
        let translation = OutwardScalarInterval.exact(cycle) * .exact(period)
        let lifted = OutwardScalarInterval(lower: parameters.lower, upper: parameters.upper) - translation
        guard translation.isFinite, lifted.isFinite else {
          throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original periodic span translation is nonfinite.")
        }
        for span in spans {
          try execution.consumeWork(1)
          let lower = max(span.lower, lifted.lower), upper = min(span.upper, lifted.upper)
          guard lower <= upper else { continue }
          let native = try ScalarInterval(lower: lower, upper: upper)
          if let boundedSpanCount, result.count >= boundedSpanCount { throw GeometryConversionError.resourceLimitExceeded("Original periodic closed cover exhausted caller span admission.") }
        let jet = try boundedSpanCount == nil
          ? RationalBezierCurveJetEncloser().enclosure(of: span, over: native, tolerance: tolerance, using: &execution)
          : OriginalNativeCurveHigherTaylor.enclosure(of: span, over: native, order: 3, tolerance: tolerance, using: &execution).intervalJet()
          let domain = OutwardScalarInterval(lower: span.lower, upper: span.upper) + translation
          guard domain.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
              message: "Original periodic owning domain is nonfinite.")
          }
          try execution.consumeWork(1)
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
