import CADCore
import CADGeometry
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("A C math implementation is required.")
#endif

/// Certifies the Green boundary integral `integral Q(u, v) dv` for explicit
/// pcurves on analytic surfaces. Adaptive subdivision is bounded and returns a
/// typed resource failure instead of accepting an enclosure wider than asked.
struct CertifiedAnalyticPcurveFluxIntegrator {
  typealias Integrand = TrimmedAnalyticSurfaceVolumeEvaluator.Integrand
  typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval
  typealias HomogeneousPatch = CertifiedHomogeneousBezierCurvePatch
  typealias ScalarBounds = HomogeneousPatch.ScalarBounds

  struct PolynomialCylinderBounds {
    let flux: Interval
    let parameterArea: SurfaceParameterAreaBounds
  }

  fileprivate struct AnalyticPairCacheKey: Hashable, Sendable {
    let intersection: CertifiedAnalyticAnalyticIntersectionCurve
    let role: SurfaceIntersectionSurfaceRole
    let lowerFraction: Double
    let upperFraction: Double
    let integrand: Integrand
    let requestedWidth: Double
    let tolerance: ModelingTolerance
  }

  fileprivate final class AnalyticPairCacheReceipt: Sendable {
    let bounds: Interval
    let depth: OriginalQueryPreparationDepth

    init(bounds: Interval, depth: OriginalQueryPreparationDepth) {
      self.bounds = bounds
      self.depth = depth
    }

    func read(using execution: inout OriginalQueryExecution) throws -> Interval {
      try execution.consumeWork(1)
      try execution.admitDepth(value: depth.scalar.value, coefficient: depth.scalar.coefficient)
      try execution.admitSourceDepth(depth.sourceDepth)
      try execution.admitGeometricDepth(depth.geometricDepth)
      try execution.admitTransportDepth(depth.transportDepth)
      // The current query retains one immutable authority reference. Historical
      // preparation payload and refinement are owned by this retained receipt.
      try execution.retainStorage(count: 1, stride: MemoryLayout<AnalyticPairCacheReceipt>.stride)
      return bounds
    }
  }

  final class EvaluationCache: Sendable {
    fileprivate struct State: Sendable {
      var version: UInt64 = 0
      var bounds: [AnalyticPairCacheKey: AnalyticPairCacheReceipt] = [:]
    }
    private let state = Mutex(State())

    var entryCount: Int { state.withLock { $0.bounds.count } }

    fileprivate func snapshot() -> State { state.withLock { $0 } }

    fileprivate func publish(_ replacement: State, replacing version: UInt64) -> Bool {
      // A caller-owned snapshot keeps the old COW backing alive until after
      // this short swap. No hashing, allocation, math or admission runs here.
      state.withLock { state in
        guard state.version == version else { return false }
        state = replacement
        return true
      }
    }

    fileprivate func insert(
      _ receipt: AnalyticPairCacheReceipt, for key: AnalyticPairCacheKey,
      using execution: inout OriginalQueryExecution
    ) throws -> AnalyticPairCacheReceipt {
      while true {
        try execution.consumeWork(1)
        let original = snapshot()
        if let winner = original.bounds[key] { return winner }
        let next = original.version.addingReportingOverflow(1)
        let count = original.bounds.count.addingReportingOverflow(1)
        guard !next.overflow, !count.overflow else { throw ExactScalarFailure.countOverflow }
        // Snapshot sharing forces this actual mutation to allocate independent
        // typed dictionary storage. Charge its full requested logical capacity
        // before COW, including failed concurrent publications.
        let capacity = max(original.bounds.capacity, count.partialValue)
        try execution.retainStorage(
          count: capacity,
          stride: MemoryLayout<(AnalyticPairCacheKey, AnalyticPairCacheReceipt)>.stride)
        try execution.consumeWork(original.bounds.count)
        var replacement = original
        replacement.bounds.reserveCapacity(capacity)
        replacement.bounds[key] = receipt
        replacement.version = next.partialValue
        let didPublish = publish(replacement, replacing: original.version)
        withExtendedLifetime(original) {}
        if didPublish { return receipt }
        // Only publication is retried. The original mathematical preparation is
        // immutable and is never re-executed after a publication conflict.
      }
    }
  }

  private let maximumWorkItems: Int
  private let maximumDepth: Int
  private let evaluationCache: EvaluationCache

  private enum LocalProofFailure: Error {
    case intervalSingularity
  }

  private enum PiecewiseRationalEnclosure {
    case enclosed(TensorGaussEnclosure)
    case seamEnclosed(SeamEnclosure)
  }

  private enum SeamSplitLocation {
    case lower
    case upper
    case balanced
  }

  private struct SeamEnclosure {
    let bounds: Interval
    let splitLocation: SeamSplitLocation
  }

  private struct RationalSeamRootCell {
    let differences: [ScalarBounds]
    let weights: [ScalarBounds]
    let lower: Double
    let upper: Double
    let depth: Int
  }

  private struct RigidImageWorkItem {
    let lowerFraction: Double
    let upperFraction: Double
    let requestedWidth: Double
    let depth: Int
  }

  private struct TensorGaussEnclosure {
    let bounds: Interval
    let lambdaError: Double
    let curveError: Double
  }

  private struct ImplicitMidpointEnclosure {
    let bounds: Interval
  }

  /// Owns the immutable Bernstein derivative nets shared by every adaptive
  /// evaluation of one rational pcurve patch. The adaptive proof changes
  /// only the evaluated fraction interval; rebuilding these nets in every
  /// Gauss cell adds no information to the enclosure.
  private struct PreparedRationalPcurvePatch {
    let source: HomogeneousPatch
    let xDerivativeControls: [[Interval]]
    let yDerivativeControls: [[Interval]]
    let weightDerivativeControls: [[Interval]]
  }

  init(
    maximumWorkItems: Int = 65_536,
    maximumDepth: Int = 48,
    evaluationCache: EvaluationCache = EvaluationCache()
  ) {
    self.maximumWorkItems = maximumWorkItems
    self.maximumDepth = maximumDepth
    self.evaluationCache = evaluationCache
  }

  func parameterEnclosures(
    for curve: SurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double = 0.0,
    toNormalizedFraction upperFraction: Double = 1.0,
    maximumWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceParameterCurveEnclosure] {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try parameterEnclosures(
      for: curve, fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction,
      maximumWidth: maximumWidth, tolerance: tolerance, using: &execution)
  }

  func parameterEnclosures(
    for curve: SurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double = 0.0,
    toNormalizedFraction upperFraction: Double = 1.0,
    maximumWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> [SurfaceParameterCurveEnclosure]
        {

          try execution.consumeWork(1)

          try execution.checkpoint()
          execution.context = execution.context.at(stage: .request)
          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard lowerFraction.isFinite,
            upperFraction.isFinite,
            lowerFraction >= -tolerance.relative,
            upperFraction <= 1.0 + tolerance.relative,
            upperFraction > lowerFraction,
            maximumWidth.isFinite,
            maximumWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: upperFraction - lowerFraction,
              tolerance: tolerance,
              message:
                "Certified analytic pcurve enclosure requires an ordered normalized range and a finite positive width."
            )
          }
          let boundedLower = min(max(lowerFraction, 0.0), 1.0)
          let boundedUpper = min(max(upperFraction, 0.0), 1.0)
          guard boundedUpper > boundedLower else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: boundedUpper - boundedLower,
              tolerance: tolerance,
              message:
                "Certified analytic pcurve enclosure range collapsed at its normalized domain boundary."
            )
          }
          switch curve {
          case .sphericalGreatCircle(
            let
              cosine,
            let
              sine,
            let
              startParameter,
            let
              endParameter
          ):
            try cosine.validateUnitLength(tolerance: tolerance)
            try sine.validateUnitLength(tolerance: tolerance)
            guard abs(cosine.dot(sine)) <= tolerance.angle else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: abs(cosine.dot(sine)),
                tolerance: tolerance,
                message: "A spherical pcurve enclosure requires an orthonormal great-circle frame."
              )
            }
            let parameterSpan = endParameter - startParameter
            let rangeStartParameter =
              startParameter
              + parameterSpan * boundedLower
            let rangeEndParameter =
              startParameter
              + parameterSpan * boundedUpper
            let localEnclosures: [SurfaceParameterCurveEnclosure]
            if let meridian = try meridianParameterEnclosures(
              cosine: cosine,
              sine: sine,
              startParameter: rangeStartParameter,
              endParameter: rangeEndParameter, using: &execution
            ) {
              localEnclosures = meridian
            } else {
              localEnclosures = try adaptiveParameterEnclosures(
                lowerFraction: 0.0,
                upperFraction: 1.0,
                maximumWidth: maximumWidth,
                tolerance: tolerance,
              evaluator: { fraction, execution in
                let parameter =
                  (try Jet.constant(rangeStartParameter, using: &execution).adding(
                    Jet.constant(rangeEndParameter - rangeStartParameter, using: &execution)
                      .multiplied(
                        by: fraction, using: &execution), using: &execution))
                return try greatCircleParameterJets(
                  cosine: cosine,
                  sine: sine,
                  parameter: parameter, using: &execution
                )
              }, using: &execution)
            }
            let aligned = try alignedSphericalEnclosures(
              localEnclosures,
              cosine: cosine,
              sine: sine,
              startParameter: rangeStartParameter,
              endParameter: rangeEndParameter, using: &execution
            )
            let rangeSpan = boundedUpper - boundedLower
            return
              (try OriginalParameterQueryStorage.map(
                aligned, using: &execution,
                transform: { enclosure, execution in
                  SurfaceParameterCurveEnclosure(
                    lowerFraction: boundedLower
                      + rangeSpan * enclosure.lowerFraction,
                    upperFraction: boundedLower
                      + rangeSpan * enclosure.upperFraction,
                    u: enclosure.u,
                    v: enclosure.v
                  )
                }))
          case .projectedAnalytic(let projected):
            return try adaptiveParameterEnclosures(
              lowerFraction: boundedLower,
              upperFraction: boundedUpper,
              maximumWidth: maximumWidth,
              tolerance: tolerance,
              evaluator: { fraction, execution in
              try projectedAnalyticParameterJets(
                projected,
                fraction: fraction,
                tolerance: tolerance, using: &execution
              )
            }, using: &execution)
          case .periodicTranslation(let base, let uShift, let vShift):
            return try OriginalParameterQueryStorage.map(
              parameterEnclosures(
                for: base,
                fromNormalizedFraction: boundedLower,
                toNormalizedFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance, using: &execution
              ), using: &execution,
              transform: { enclosure, execution in
                SurfaceParameterCurveEnclosure(
                  lowerFraction: enclosure.lowerFraction,
                  upperFraction: enclosure.upperFraction,
                  u: try ScalarInterval(
                    lower: (enclosure.u.lower + uShift).nextDown,
                    upper: (enclosure.u.upper + uShift).nextUp
                  ),
                  v: try ScalarInterval(
                    lower: (enclosure.v.lower + vShift).nextDown,
                    upper: (enclosure.v.upper + vShift).nextUp
                  )
                )
              })
          case .offsetSurfaceImage(let image):
            return try parameterEnclosures(
              for: image.source,
              fromNormalizedFraction: boundedLower,
              toNormalizedFraction: boundedUpper,
              maximumWidth: maximumWidth,
              tolerance: tolerance, using: &execution
            )
          case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline,
            .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
            .rigidImage, .originalImage, .originalAffineWord, .originalBSplineContinuation:
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message:
                "This analytic enclosure path received an incompatible pcurve representation."
            )
          }
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func alignedSphericalEnclosures(
    _ enclosures: [SurfaceParameterCurveEnclosure],
    cosine: Vector3D,
    sine: Vector3D,
    startParameter: Double,
    endParameter: Double, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    try execution.consumeWork(1)

    let period = 2.0 * Double.pi
    var referenceLongitude =
      (try sphericalEndpointLongitude(
        cosine: cosine,
        sine: sine,
        parameter: startParameter,
        approachDirection: endParameter > startParameter ? 1.0 : -1.0, using: &execution
      ))
    var result: [SurfaceParameterCurveEnclosure] = []
    for enclosure
      in (try OriginalParameterQueryStorage.ordered(
        enclosures, using: &execution,
        less: {
          $0.lowerFraction < $1.lowerFraction
        }))
    {
      try execution.consumeWork(1)

      let shift =
        round(
          (referenceLongitude - enclosure.u.midpoint) / period
        ) * period
      let shiftedLowerU = enclosure.u.lower + shift
      let shiftedUpperU = enclosure.u.upper + shift
      let parameterSpan = endParameter - startParameter
      let lowerParameter =
        startParameter
        + parameterSpan * enclosure.lowerFraction
      let upperParameter =
        startParameter
        + parameterSpan * enclosure.upperFraction
      let direction = parameterSpan > 0.0 ? 1.0 : -1.0
      let lowerEndpoint =
        (try sphericalParameterEnclosureEndpoint(
          cosine: cosine,
          sine: sine,
          parameter: lowerParameter,
          approachDirection: direction,
          longitudeReference: shiftedLowerU
            + (shiftedUpperU - shiftedLowerU) * 0.5, using: &execution
        ))
      let upperEndpoint =
        (try sphericalParameterEnclosureEndpoint(
          cosine: cosine,
          sine: sine,
          parameter: upperParameter,
          approachDirection: -direction,
          longitudeReference: shiftedLowerU
            + (shiftedUpperU - shiftedLowerU) * 0.5, using: &execution
        ))
      let alignedU = try ScalarInterval(
        lower: min(
          shiftedLowerU,
          lowerEndpoint.u,
          upperEndpoint.u
        ).nextDown,
        upper: max(
          shiftedUpperU,
          lowerEndpoint.u,
          upperEndpoint.u
        ).nextUp
      )
      let alignedV = try ScalarInterval(
        lower: min(
          enclosure.v.lower,
          lowerEndpoint.v,
          upperEndpoint.v
        ).nextDown,
        upper: max(
          enclosure.v.upper,
          lowerEndpoint.v,
          upperEndpoint.v
        ).nextUp
      )
      (try OriginalParameterQueryStorage.append(
        SurfaceParameterCurveEnclosure(
          lowerFraction: enclosure.lowerFraction,
          upperFraction: enclosure.upperFraction,
          u: alignedU,
          v: alignedV
        ), to: &result, using: &execution))
      referenceLongitude = alignedU.midpoint
    }
    return result
  }

  private func sphericalParameterEnclosureEndpoint(
    cosine: Vector3D,
    sine: Vector3D,
    parameter: Double,
    approachDirection: Double,
    longitudeReference: Double, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameter {
    try execution.consumeWork(1)

    let radial = cosine * cos(parameter) + sine * sin(parameter)
    var longitude =
      (try sphericalEndpointLongitude(
        cosine: cosine,
        sine: sine,
        parameter: parameter,
        approachDirection: approachDirection, using: &execution
      ))
    longitude +=
      round(
        (longitudeReference - longitude) / (2.0 * Double.pi)
      ) * (2.0 * Double.pi)
    return SurfaceParameter(
      u: longitude,
      v: asin(min(max(radial.z, -1.0), 1.0))
    )
  }

  private func meridianParameterEnclosures(
    cosine: Vector3D,
    sine: Vector3D,
    startParameter: Double,
    endParameter: Double, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure]? {
    try execution.consumeWork(1)

    let verticalRadius = hypot(cosine.z, sine.z)
    let longitudeNumerator = cosine.x * sine.y - cosine.y * sine.x
    let machineTolerance = Double.ulpOfOne * 16_384.0
    guard abs(verticalRadius - 1.0) <= machineTolerance,
      abs(longitudeNumerator) <= machineTolerance
    else {
      return nil
    }
    let ascendingLower = min(startParameter, endParameter)
    let ascendingUpper = max(startParameter, endParameter)
    let phase = atan2(cosine.z, sine.z)
    var ascendingBreakpoints =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [ascendingLower]
      })
    let firstIndex = Int(
      ceil(
        (ascendingLower + phase - Double.pi * 0.5) / Double.pi
      ))
    let lastIndex = Int(
      floor(
        (ascendingUpper + phase - Double.pi * 0.5) / Double.pi
      ))
    if firstIndex <= lastIndex {
      for index in firstIndex...lastIndex {
        try execution.consumeWork(1)

        let parameter =
          Double.pi * 0.5 - phase
          + Double(index) * Double.pi
        if parameter > ascendingLower, parameter < ascendingUpper {
          (try OriginalParameterQueryStorage.append(
            parameter, to: &ascendingBreakpoints, using: &execution))
        }
      }
    }
    (try OriginalParameterQueryStorage.append(
      ascendingUpper, to: &ascendingBreakpoints, using: &execution))
    try OriginalParameterQueryStorage.sort(&ascendingBreakpoints, using: &execution, less: <)
    let breakpoints =
      startParameter <= endParameter
      ? ascendingBreakpoints
      : (try OriginalParameterQueryStorage.materialize(
        ascendingBreakpoints.reversed(), using: &execution))
    let parameterSpan = endParameter - startParameter
    var referenceLongitude =
      (try sphericalEndpointLongitude(
        cosine: cosine,
        sine: sine,
        parameter: startParameter,
        approachDirection: parameterSpan > 0.0 ? 1.0 : -1.0, using: &execution
      ))
    var result: [SurfaceParameterCurveEnclosure] = []
    for index in 1..<breakpoints.count {
      try execution.consumeWork(1)

      let first = breakpoints[index - 1]
      let second = breakpoints[index]
      let midpoint = first + (second - first) * 0.5
      let radial = cosine * cos(midpoint) + sine * sin(midpoint)
      var longitude = atan2(-radial.x, radial.y)
      if longitude < 0.0 { longitude += 2.0 * Double.pi }
      longitude +=
        round(
          (referenceLongitude - longitude) / (2.0 * Double.pi)
        ) * (2.0 * Double.pi)
      referenceLongitude = longitude
      let firstLatitude = asin(
        min(
          max(
            cosine.z * cos(first) + sine.z * sin(first),
            -1.0
          ), 1.0))
      let secondLatitude = asin(
        min(
          max(
            cosine.z * cos(second) + sine.z * sin(second),
            -1.0
          ), 1.0))
      let firstFraction = (first - startParameter) / parameterSpan
      let secondFraction = (second - startParameter) / parameterSpan
      (try OriginalParameterQueryStorage.append(
        SurfaceParameterCurveEnclosure(
          lowerFraction: min(firstFraction, secondFraction),
          upperFraction: max(firstFraction, secondFraction),
          u: ScalarInterval(
            lower: longitude.nextDown,
            upper: longitude.nextUp
          ),
          v: ScalarInterval(
            lower: min(firstLatitude, secondLatitude).nextDown,
            upper: max(firstLatitude, secondLatitude).nextUp
          )
        ), to: &result, using: &execution))
    }
    return (try OriginalParameterQueryStorage.ordered(result, using: &execution, less: { $0.lowerFraction < $1.lowerFraction }))
  }

  private func sphericalEndpointLongitude(
    cosine: Vector3D,
    sine: Vector3D,
    parameter: Double,
    approachDirection: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    let radial = cosine * cos(parameter) + sine * sin(parameter)
    let horizontalLength = hypot(radial.x, radial.y)
    let direction: Vector3D
    if horizontalLength <= 1.0e-12 {
      let derivative = cosine * -sin(parameter) + sine * cos(parameter)
      direction = derivative * approachDirection
    } else {
      direction = radial
    }
    var longitude = atan2(-direction.x, direction.y)
    if longitude < 0.0 { longitude += 2.0 * Double.pi }
    return longitude
  }

  func bounds(
    for curve: SurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> Interval? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try bounds(
      for: curve, integrand: integrand, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func bounds(
    for curve: SurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval? {

          try execution.consumeWork(1)

          if integrand.usesPeriodicBoundaryGauge {
            return try periodicBoundaryGaugeBounds(
              for: curve,
              integrand: integrand,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          }
          return try greenPrimitiveBounds(
            for: curve,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance, using: &execution
          )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func greenPrimitiveBounds(
    for curve: SurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)
    execution.context = execution.context.at(stage: .request)

    try tolerance.validate()
    execution.context = execution.context.at(stage: .refinement)
    guard requestedWidth.isFinite, requestedWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message: "Certified analytic pcurve flux requires a finite positive enclosure width."
      )
    }
    switch curve {
    case .originalAffineWord, .originalImage, .originalBSplineContinuation:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Specialized analytic Green flux has
      // no original image/continuation jet here. Its volume callers must use
      // the support-bound parametric producer; nil is unsupported, not zero flux.
      return nil
    case .affine(let origin, let direction, let startParameter, let endParameter):
      return try adaptiveJetBounds(
        requestedWidth: requestedWidth,
        tolerance: tolerance,
              evaluator: { fraction, execution in
        let parameterSpan =
          (try Jet.constant(
            Interval.exact(endParameter) - .exact(startParameter), using: &execution
          ))
        let parameter =
          (try Jet.constant(startParameter, using: &execution).adding(
            parameterSpan.multiplied(by: fraction, using: &execution), using: &execution))
        let u =
          (try Jet.constant(origin.x, using: &execution).adding(
            Jet.constant(direction.x, using: &execution).multiplied(
              by: parameter, using: &execution), using: &execution))
        let v =
          (try Jet.constant(origin.y, using: &execution).adding(
            Jet.constant(direction.y, using: &execution).multiplied(
              by: parameter, using: &execution), using: &execution))
        let derivativeV =
          (try Jet.constant(direction.y, using: &execution).multiplied(
            by: parameterSpan, using: &execution))
        return
          (try greenPrimitive(
            integrand: integrand,
            u: u,
            v: v, using: &execution
          ).multiplied(by: derivativeV, using: &execution))
      }, using: &execution)
    case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
      return try adaptiveJetBounds(
        requestedWidth: requestedWidth,
        tolerance: tolerance,
              evaluator: { fraction, execution in
        let parameterSpan =
          (try Jet.constant(
            Interval.exact(endParameter) - .exact(startParameter), using: &execution
          ))
        let parameter =
          (try Jet.constant(startParameter, using: &execution).adding(
            parameterSpan.multiplied(by: fraction, using: &execution), using: &execution))
        let values = (try parameter.sineAndCosine(using: &execution))
        let u =
          (try Jet.constant(center.x, using: &execution).adding(
            Jet.constant(cosine.x, using: &execution).multiplied(
              by: values.cosine, using: &execution), using: &execution
          ).adding(
            Jet.constant(sine.x, using: &execution).multiplied(by: values.sine, using: &execution),
            using: &execution))
        let v =
          (try Jet.constant(center.y, using: &execution).adding(
            Jet.constant(cosine.y, using: &execution).multiplied(
              by: values.cosine, using: &execution), using: &execution
          ).adding(
            Jet.constant(sine.y, using: &execution).multiplied(by: values.sine, using: &execution),
            using: &execution))
        let derivativeV =
          (try Jet.constant(cosine.y, using: &execution).negated(using: &execution).multiplied(
            by: values.sine, using: &execution
          ).adding(
            Jet.constant(sine.y, using: &execution).multiplied(
              by: values.cosine, using: &execution), using: &execution
          ).multiplied(by: parameterSpan, using: &execution))
        return
          (try greenPrimitive(
            integrand: integrand,
            u: u,
            v: v, using: &execution
          ).multiplied(by: derivativeV, using: &execution))
      }, using: &execution)
    case .polyline(let points):
      guard points.count >= 2 else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          residual: Double(points.count),
          tolerance: tolerance,
          message: "Certified analytic polyline flux requires at least two points."
        )
      }
      let segmentWidth = requestedWidth / Double(points.count - 1)
      var result = Interval.exact(0.0)
      for index in 1..<points.count {
        try execution.consumeWork(1)

        let start = points[index - 1]
        let end = points[index]
        let deltaU = Interval.exact(end.u) - .exact(start.u)
        let deltaV = Interval.exact(end.v) - .exact(start.v)
        result =
          result
          + (try adaptiveJetBounds(
            requestedWidth: segmentWidth,
            tolerance: tolerance,
              evaluator: { fraction, execution in
            let u =
              (try Jet.constant(start.u, using: &execution).adding(
                Jet.constant(deltaU, using: &execution).multiplied(by: fraction, using: &execution),
                using: &execution))
            let v =
              (try Jet.constant(start.v, using: &execution).adding(
                Jet.constant(deltaV, using: &execution).multiplied(by: fraction, using: &execution),
                using: &execution))
            return
              (try greenPrimitive(
                integrand: integrand,
                u: u,
                v: v, using: &execution
              ).multiplied(by: Jet.constant(deltaV, using: &execution), using: &execution))
          }, using: &execution))
      }
      return result
    case .sphericalGreatCircle(
      let
        cosine,
      let
        sine,
      let
        startParameter,
      let
        endParameter
    ):
      return try sphericalGreatCircleBounds(
        cosine: cosine,
        sine: sine,
        startParameter: startParameter,
        endParameter: endParameter,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .bSpline(let spline):
      let hasUniformWeights =
        (try OriginalParameterQueryStorage.optionalMap(
          spline.weights.first, using: &execution,
          { firstWeight, execution in
            try firstWeight.isFinite
              && firstWeight > 0.0
              && (try OriginalParameterQueryStorage.allSatisfy(
                spline.weights, using: &execution,
                predicate: { element, execution in element == firstWeight }))
          })) ?? false
      if hasUniformWeights,
        let polynomial = try polynomialCylinderBounds(
          for: spline,
          integrand: integrand,
          requestedWidth: requestedWidth,
          tolerance: tolerance, using: &execution
        )
      {
        return polynomial.flux
      }
      let patches = try CertifiedBSplineCurveBezierExtractor().patches(
        curve: spline,
        tolerance: tolerance, using: &execution
      )
      let preparedPatches = try OriginalParameterQueryStorage.map(
        patches, using: &execution,
        transform: { element, execution in
          try prepareRationalPcurvePatch(element, tolerance: tolerance, using: &execution)
        })
      return try adaptiveJetBoundsShared(
        requestedWidth: requestedWidth,
        tolerance: tolerance,
        evaluators: OriginalParameterQueryStorage.map(
          preparedPatches, using: &execution,
          transform: { patch, execution in
            { fraction, execution in
              try self.rationalFluxJet(
                patch: patch,
                parameter: fraction.coefficients[0],
                integrand: integrand,
                tolerance: tolerance, using: &execution
              )
            }
          }), using: &execution
      )
    case .certifiedAnalyticImplicit(let certified):
      return try certifiedAnalyticImplicitBounds(
        curve: certified,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .certifiedAnalyticPair(let certified):
      return try analyticPairFluxBounds(
        for: certified,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .constantU(let u, let vStart, let vEnd):
      return integrand.verticalBoundaryIntegral(
        u: .exact(u),
        vStart: .exact(vStart),
        vEnd: .exact(vEnd)
      )
    case .constantV:
      return .exact(0.0)
    case .certifiedImplicit:
      // Intersection-backed pcurve flux certification is implemented by
      // the parametric-surface volume path. This analytic caller must
      // treat nil as unsupported and cannot report a successful result.
      return nil
    case .rigidImage(let image):
      return try rigidImageBounds(
        image: image,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .projectedAnalytic(let projected):
      return try adaptiveJetBounds(
        requestedWidth: requestedWidth,
        tolerance: tolerance,
              evaluator: { fraction, execution in
        let parameters = try projectedAnalyticParameterJets(
          projected,
          fraction: fraction,
          tolerance: tolerance, using: &execution
        )
        return
          (try greenPrimitive(
            integrand: integrand,
            u: parameters.u,
            v: parameters.v, using: &execution
          ).multiplied(by: parameters.v.derivative(using: &execution), using: &execution))
      }, using: &execution)
    case .offsetSurfaceImage(let image):
      return try bounds(
        for: image.source,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, let uShift, let vShift):
      let correctionBudget = (requestedWidth * 0.25).nextDown
      guard correctionBudget.isFinite, correctionBudget > 0.0 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: correctionBudget,
          tolerance: tolerance,
          message:
            "Periodic analytic flux could not allocate a finite translation-correction enclosure."
        )
      }
      let baseBounds = try bounds(
        for: base,
        integrand: integrand,
        requestedWidth: (requestedWidth - correctionBudget).nextDown,
        tolerance: tolerance, using: &execution
      )
      guard let baseBounds else { return nil }
      let correction = try periodicTranslationFluxCorrection(
        base: base,
        uShift: uShift,
        vShift: vShift,
        integrand: integrand,
        requestedWidth: correctionBudget,
        tolerance: tolerance, using: &execution
      )
      let result = baseBounds + correction
      guard result.width <= requestedWidth.nextUp else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: result.width,
          tolerance: tolerance,
          message: "Periodic analytic flux exceeded its composed enclosure width."
        )
      }
      return result
    }
  }

  private func analyticPairFluxBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let isReversed = curve.startFraction > curve.endFraction
    let key = AnalyticPairCacheKey(
      intersection: curve.intersection,
      role: curve.role,
      lowerFraction: min(curve.startFraction, curve.endFraction),
      upperFraction: max(curve.startFraction, curve.endFraction),
      integrand: integrand,
      requestedWidth: requestedWidth,
      tolerance: tolerance
    )
    try GeometryStructuralComparisonWork.charge(
      parameterCurve: .certifiedAnalyticPair(curve), using: &execution)
    try execution.consumeWork(1)
    let snapshot = evaluationCache.snapshot()
    if let receipt = snapshot.bounds[key] {
      execution.context = execution.context.at(stage: .request)
      try tolerance.validate()
      execution.context = execution.context.at(stage: .refinement)
      execution.context = execution.context.at(stage: .source)
      try curve.validate(
        on: curve.intersection.surface(for: curve.role), tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .refinement)
      let canonical = try receipt.read(using: &execution)
      return isReversed ? -canonical : canonical
    }
    let prepared = try execution.withPreparationScope { execution in
      try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
        for: curve, integrand: integrand, requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution)
    }
    try execution.retainStorage(
      count: 1,
      stride: MemoryLayout<(Interval, OriginalQueryPreparationDepth)>.stride)
    let receipt = AnalyticPairCacheReceipt(
      bounds: isReversed ? -prepared.result : prepared.result, depth: prepared.depth)
    let published = try evaluationCache.insert(receipt, for: key, using: &execution)
    let canonical = try published.read(using: &execution)
    return isReversed ? -canonical : canonical
  }

  private func periodicBoundaryGaugeBounds(
    for curve: SurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)
    execution.context = execution.context.at(stage: .request)

    try tolerance.validate()
    execution.context = execution.context.at(stage: .refinement)
    guard requestedWidth.isFinite, requestedWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message: "Periodic analytic flux requires a finite positive enclosure width."
      )
    }
    switch curve {
    case .certifiedAnalyticPair(let certified):
      return try analyticPairFluxBounds(
        for: certified,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .offsetSurfaceImage(let image):
      return try periodicBoundaryGaugeBounds(
        for: image.source,
        integrand: integrand,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, let uShift, let vShift):
      let period = 2.0 * Double.pi
      let turns = uShift / period
      guard uShift.isFinite,
        vShift.isFinite,
        abs(turns - turns.rounded()) <= tolerance.relative
      else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          residual: max(abs(uShift), abs(vShift)),
          tolerance: tolerance,
          message: "A periodic analytic pcurve translation must preserve its whole-turn U chart."
        )
      }
      if vShift != 0.0 {
        let vTurns = vShift / period
        guard case .torus = integrand,
          abs(vTurns - vTurns.rounded()) <= tolerance.relative
        else {
          throw KernelError(
            phase: .topology,
            code: .invalidInput,
            residual: vShift,
            tolerance: tolerance,
            message: "Only a torus pcurve can receive a whole-turn V translation."
          )
        }
      }
      let correctionBudget = (requestedWidth * 0.25).nextDown
      let baseBounds = try periodicBoundaryGaugeBounds(
        for: base,
        integrand: integrand,
        requestedWidth: (requestedWidth - correctionBudget).nextDown,
        tolerance: tolerance, using: &execution
      )
      guard let baseBounds else { return nil }
      let correction = try periodicBoundaryTranslationFluxCorrection(
        base: base,
        uShift: uShift,
        vShift: vShift,
        integrand: integrand,
        requestedWidth: correctionBudget,
        tolerance: tolerance, using: &execution
      )
      let result = baseBounds + correction
      guard result.width <= requestedWidth.nextUp else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: result.width,
          tolerance: tolerance,
          message: "Periodic analytic flux exceeded its composed enclosure width."
        )
      }
      return result
    default:
      let correction = try periodicBoundaryGaugeCorrection(
        for: curve,
        integrand: integrand,
        tolerance: tolerance, using: &execution
      )
      let remainingWidth = (requestedWidth - correction.width).nextDown
      guard remainingWidth.isFinite, remainingWidth > 0.0 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: correction.width,
          tolerance: tolerance,
          message:
            "Periodic analytic flux exhausted its enclosure width in the exact boundary-gauge correction."
        )
      }
      guard
        let primitiveBounds = try greenPrimitiveBounds(
          for: curve,
          integrand: integrand,
          requestedWidth: remainingWidth,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      let result = primitiveBounds + correction
      guard result.width <= requestedWidth.nextUp else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: result.width,
          tolerance: tolerance,
          message: "Periodic analytic flux exceeded its composed enclosure width."
        )
      }
      return result
    }
  }

  private func periodicBoundaryGaugeCorrection(
    for curve: SurfaceParameterCurve,
    integrand: Integrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let start = try curve.parameter(
      atNormalizedFraction: 0.0,
      tolerance: tolerance, using: &execution
    )
    let end = try curve.parameter(
      atNormalizedFraction: 1.0,
      tolerance: tolerance, using: &execution
    )
    let startPotential = integrand.periodicBoundaryGaugePotential(
      u: .floating(start.u),
      v: .floating(start.v)
    )
    let endPotential = integrand.periodicBoundaryGaugePotential(
      u: .floating(end.u),
      v: .floating(end.v)
    )
    return endPotential - startPotential
  }

  private func periodicBoundaryTranslationFluxCorrection(
    base: SurfaceParameterCurve,
    uShift: Double,
    vShift: Double,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    if abs(uShift) <= tolerance.relative {
      return .exact(0.0)
    }
    guard requestedWidth.isFinite, requestedWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message: "Periodic analytic flux requires a finite positive translation-correction width."
      )
    }
    var maximumEndpointWidth = min(
      1.0e-3,
      requestedWidth / max(abs(uShift), 1.0)
    )
    for _ in 0..<16 {
      try execution.consumeWork(1)

      let endpoints = try continuousEndpointVEnclosures(
        for: base,
        maximumWidth: maximumEndpointWidth,
        tolerance: tolerance, using: &execution
      )
      let shiftedStartV = Interval(
        lower: (endpoints.start.lower + vShift).nextDown,
        upper: (endpoints.start.upper + vShift).nextUp
      )
      let shiftedEndV = Interval(
        lower: (endpoints.end.lower + vShift).nextDown,
        upper: (endpoints.end.upper + vShift).nextUp
      )
      let correction =
        integrand.periodicBoundaryVerticalIntegral(
          u: .floating(uShift),
          vStart: shiftedStartV,
          vEnd: shiftedEndV
        )
        - integrand.periodicBoundaryVerticalIntegral(
          u: .exact(0.0),
          vStart: shiftedStartV,
          vEnd: shiftedEndV
        )
      if correction.width <= requestedWidth.nextUp {
        return correction
      }
      maximumEndpointWidth *= 0.25
    }
    throw KernelError(
      phase: .topology,
      code: .resourceLimitExceeded,
      residual: maximumEndpointWidth,
      tolerance: tolerance,
      message:
        "Periodic analytic flux could not certify translated endpoint lifts within its correction budget."
    )
  }

  /// Certifies `integral u dv` directly from outward-rounded homogeneous
  /// Bezier patches. This is the proof boundary used by rational revolution
  /// moments; materializing nominal Euclidean control points here would lose
  /// the extraction and Bernstein-product rounding enclosure.
  func parameterAreaBounds(
    for patches: [HomogeneousPatch],
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterAreaBounds {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try parameterAreaBounds(
      for: patches, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  func parameterAreaBounds(
    for patches: [HomogeneousPatch],
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> SurfaceParameterAreaBounds
        {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard patches.isEmpty == false,
            requestedWidth.isFinite,
            requestedWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message:
                "Certified rational parameter-area integration requires patches and a finite positive width."
            )
          }
          let preparedPatches = try OriginalParameterQueryStorage.map(
            patches, using: &execution,
            transform: { element, execution in
              try prepareRationalPcurvePatch(element, tolerance: tolerance, using: &execution)
            })
          let area = try adaptiveJetBoundsShared(
            requestedWidth: requestedWidth,
            tolerance: tolerance,
            evaluators: OriginalParameterQueryStorage.map(
              preparedPatches, using: &execution,
              transform: { patch, execution in
                { fraction, execution in
                  try self.rationalFluxJet(
                    patch: patch,
                    parameter: fraction.coefficients[0],
                    integrand: .plane(volumeScale: .exact(1.0)),
                    tolerance: tolerance, using: &execution
                  )
                }
              }), using: &execution
          )
          return SurfaceParameterAreaBounds(lower: area.lower, upper: area.upper)
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func rigidImageBounds(
    image: RigidImageSurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    var remainingItems = maximumWorkItems
    var stack =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [
          RigidImageWorkItem(
            lowerFraction: 0.0,
            upperFraction: 1.0,
            requestedWidth: requestedWidth,
            depth: 0
          )
        ]
      })
    var result = Interval.exact(0.0)
    while let item = stack.popLast() {
      try execution.visitGeometricCell(depth: item.depth)

      try execution.consumeWork(1)

      guard remainingItems > 0 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Rigid-image analytic flux integration exceeded its work-item budget."
        )
      }
      remainingItems -= 1
      let localImage = try image.subcurve(
        fromNormalizedFraction: item.lowerFraction,
        toNormalizedFraction: item.upperFraction,
        tolerance: tolerance, using: &execution
      )
      let enclosures = try CertifiedSurfaceParameterCurveEncloser()
        .enclosures(
          for: .rigidImage(localImage),
          on: localImage.targetSurface,
          maximumWidth: 0.25,
          tolerance: tolerance, using: &execution
        )
      if enclosures.count != 1 {
        guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth),
          enclosures.isEmpty == false
        else {
          throw KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message:
              "Rigid-image analytic flux subdivision did not converge to one certified chart cell."
          )
        }
        for enclosure in enclosures.reversed() {
          try execution.consumeWork(1)

          let span = item.upperFraction - item.lowerFraction
          let lower =
            item.lowerFraction
            + span * enclosure.lowerFraction
          let upper =
            item.lowerFraction
            + span * enclosure.upperFraction
          (try OriginalParameterQueryStorage.append(
            RigidImageWorkItem(
              lowerFraction: lower,
              upperFraction: upper,
              requestedWidth: item.requestedWidth
                * (enclosure.upperFraction - enclosure.lowerFraction),
              depth: item.depth + 1
            ), to: &stack, using: &execution))
        }
        continue
      }
      let enclosure = enclosures[0]
      let lower = item.lowerFraction
      let upper = item.upperFraction
      let midpoint = lower + (upper - lower) * 0.5
      guard
        let derivativeBound =
          try image
          .modelSpaceFirstDerivativeMagnitude(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            tolerance: tolerance, using: &execution
          ),
        let metricLower =
          (try minimumMetricScale(
            surface: image.targetSurface,
            enclosure: enclosure, using: &execution
          )), metricLower > 0.0
      else {
        throw KernelError(
          phase: .topology,
          code: .singularSystem,
          tolerance: tolerance,
          message: "Rigid-image analytic flux reached a singular target parameter chart."
        )
      }
      let middleParameter = try image.parameter(
        atNormalizedFraction: midpoint,
        tolerance: tolerance, using: &execution
      )
      let startParameter = try image.parameter(
        atNormalizedFraction: lower,
        tolerance: tolerance, using: &execution
      )
      let endParameter = try image.parameter(
        atNormalizedFraction: upper,
        tolerance: tolerance, using: &execution
      )
      let qBounds =
        (try integrand.greenPrimitive(
          u: Interval(
            lower: enclosure.u.lower,
            upper: enclosure.u.upper
          ),
          v: Interval(
            lower: enclosure.v.lower,
            upper: enclosure.v.upper
          )
        ))
      let qMiddle =
        (try integrand.greenPrimitive(
          u: .exact(middleParameter.u),
          v: .exact(middleParameter.v)
        ))
      let deltaV = Interval.floating(
        endParameter.v - startParameter.v
      )
      let central = qMiddle * deltaV
      let qDeviation = max(
        abs(qBounds.lower - qMiddle.upper),
        abs(qBounds.upper - qMiddle.lower)
      ).nextUp
      let parameterVariation = (derivativeBound / metricLower * (upper - lower)).nextUp
      let error = (qDeviation * parameterVariation).nextUp
      let contribution =
        central + Interval(
          lower: (-error).nextDown,
          upper: error.nextUp
        )
      if contribution.width <= item.requestedWidth {
        result = result + contribution
        continue
      }
      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: contribution.width,
          tolerance: tolerance,
          message:
            "Rigid-image analytic flux exceeded its subdivision depth before reaching the requested enclosure width."
        )
      }
      let split = midpoint
      (try OriginalParameterQueryStorage.append(
        RigidImageWorkItem(
          lowerFraction: split,
          upperFraction: upper,
          requestedWidth: item.requestedWidth * 0.5,
          depth: item.depth + 1
        ), to: &stack, using: &execution))
      (try OriginalParameterQueryStorage.append(
        RigidImageWorkItem(
          lowerFraction: lower,
          upperFraction: split,
          requestedWidth: item.requestedWidth * 0.5,
          depth: item.depth + 1
        ), to: &stack, using: &execution))
    }
    return result
  }

  private func minimumMetricScale(
    surface: Surface3D,
    enclosure: SurfaceParameterCurveEnclosure, using execution: inout OriginalQueryExecution
  ) throws -> Double? {
    try execution.consumeWork(1)

    switch surface {
    case .plane, .analytic(.plane):
      return 1.0
    case .cylinder(let cylinder):
      return min(cylinder.radius, 1.0).nextDown
    case .analytic(.cylinder(_, _, let radius)):
      return min(radius, 1.0).nextDown
    case .analytic(.cone(_, _, let halfAngle)):
      let minimumAbsoluteV: Double
      if enclosure.v.lower <= 0.0, enclosure.v.upper >= 0.0 {
        minimumAbsoluteV = 0.0
      } else {
        minimumAbsoluteV = min(
          abs(enclosure.v.lower),
          abs(enclosure.v.upper)
        )
      }
      return min(
        1.0,
        minimumAbsoluteV * abs(sin(halfAngle))
      ).nextDown
    case .analytic(.sphere(_, let radius)):
      let maximumAbsoluteV = max(
        abs(enclosure.v.lower),
        abs(enclosure.v.upper)
      )
      return
        (radius
        * max(
          0.0,
          cos(
            min(
              maximumAbsoluteV,
              Double.pi * 0.5
            )))).nextDown
    case .analytic(.torus(_, _, let majorRadius, let minorRadius)):
      return min(
        minorRadius,
        majorRadius - minorRadius
      ).nextDown
    case .analytic, .bSpline, .procedural:
      return nil
    }
  }

  private func periodicTranslationFluxCorrection(
    base: SurfaceParameterCurve,
    uShift: Double,
    vShift: Double,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let period = 2.0 * Double.pi
    func isWholePeriod(_ shift: Double, using execution: inout OriginalQueryExecution) throws
      -> Bool
    {
      try execution.consumeWork(1)

      guard shift.isFinite else { return false }
      let turns = shift / period
      return abs(turns - turns.rounded()) <= tolerance.relative
    }
    guard try uShift == 0.0 || isWholePeriod(uShift, using: &execution) else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: uShift,
        tolerance: tolerance,
        message: "Analytic flux received a non-periodic U translation."
      )
    }
    if vShift != 0.0 {
      guard case .torus = integrand, try isWholePeriod(vShift, using: &execution) else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          residual: vShift,
          tolerance: tolerance,
          message: "Analytic flux received a non-periodic V translation."
        )
      }
    }
    if uShift == 0.0 { return .exact(0.0) }
    guard case .plane = integrand else {
      guard requestedWidth.isFinite, requestedWidth > 0.0 else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          residual: requestedWidth,
          tolerance: tolerance,
          message: "Periodic analytic flux requires a finite positive correction width."
        )
      }
      var maximumEndpointWidth = min(
        1.0e-3,
        requestedWidth / max(abs(uShift), 1.0)
      )
      for _ in 0..<16 {
        try execution.consumeWork(1)

        let endpoints = try continuousEndpointVEnclosures(
          for: base,
          maximumWidth: maximumEndpointWidth,
          tolerance: tolerance, using: &execution
        )
        let shiftedStartV = Interval(
          lower: (endpoints.start.lower + vShift).nextDown,
          upper: (endpoints.start.upper + vShift).nextUp
        )
        let shiftedEndV = Interval(
          lower: (endpoints.end.lower + vShift).nextDown,
          upper: (endpoints.end.upper + vShift).nextUp
        )
        let correction =
          integrand.verticalBoundaryIntegral(
            u: .exact(uShift),
            vStart: shiftedStartV,
            vEnd: shiftedEndV
          )
          - integrand.verticalBoundaryIntegral(
            u: .exact(0.0),
            vStart: shiftedStartV,
            vEnd: shiftedEndV
          )
        if correction.width <= requestedWidth.nextUp {
          return correction
        }
        maximumEndpointWidth *= 0.25
      }
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: maximumEndpointWidth,
        tolerance: tolerance,
        message:
          "Periodic analytic flux could not certify continuous endpoint lifts within its correction budget."
      )
    }
    throw KernelError(
      phase: .topology,
      code: .invalidInput,
      residual: uShift,
      tolerance: tolerance,
      message: "A planar analytic flux cannot receive a periodic U translation."
    )
  }

  /// Returns endpoint V coordinates in the curve's certified continuous
  /// universal-cover chart. Direct endpoint evaluation is intentionally not
  /// used: periodic analytic pcurves report principal representatives, and
  /// a seam endpoint can therefore differ from the traversed lift by one
  /// whole period. Borrowed endpoint neighborhoods retain the geometric
  /// proof sheet without constructing tolerance-sized topology curves.
  private func continuousEndpointVEnclosures(
    for curve: SurfaceParameterCurve,
    maximumWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (start: ScalarInterval, end: ScalarInterval) {
    try execution.consumeWork(1)

    let minimumSpan = Double.ulpOfOne * 64.0
    let endpointSpan = min(
      1.0e-6,
      max((try maximumEndpointSpan(maximumWidth, using: &execution)), minimumSpan)
    )
    guard endpointSpan < 1.0,
      1.0 - endpointSpan < 1.0
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: endpointSpan,
        tolerance: tolerance,
        message: "Periodic analytic flux reached normalized endpoint resolution."
      )
    }
    let encloser = CertifiedSurfaceParameterCurveEncloser()
    let startEnclosures = try encloser.vEnclosures(
      for: curve,
      fromNormalizedFraction: 0.0,
      toNormalizedFraction: endpointSpan,
      maximumWidth: maximumWidth,
      tolerance: tolerance, using: &execution
    )
    let endEnclosures = try encloser.vEnclosures(
      for: curve,
      fromNormalizedFraction: 1.0 - endpointSpan,
      toNormalizedFraction: 1.0,
      maximumWidth: maximumWidth,
      tolerance: tolerance, using: &execution
    )
    guard let start = startEnclosures.first,
      let end = endEnclosures.last,
      abs(start.lowerFraction) <= tolerance.relative,
      abs(end.upperFraction - 1.0) <= tolerance.relative
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Periodic analytic flux received incomplete endpoint lift certificates."
      )
    }
    return (start.v, end.v)
  }

  private func maximumEndpointSpan(
    _ maximumWidth: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (maximumWidth * 0.01).nextDown
  }

  func projectedParameterAreaBounds(
    for curve: ProjectedAnalyticSurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> Interval {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try projectedParameterAreaBounds(
      for: curve, uShift: uShift, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func projectedParameterAreaBounds(
    for curve: ProjectedAnalyticSurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .source)

          try curve.validate(on: curve.surface, tolerance: tolerance, using: &execution)
          execution.context = execution.context.at(stage: .refinement)
          guard uShift.isFinite,
            requestedWidth.isFinite,
            requestedWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message: "Certified projected pcurve area requires finite positive options."
            )
          }
          return try adaptiveJetBounds(
            requestedWidth: requestedWidth,
            tolerance: tolerance,
              evaluator: { fraction, execution in
            let parameters = try projectedAnalyticParameterJets(
              curve,
              fraction: fraction,
              tolerance: tolerance, using: &execution
            )
            return
              (try parameters.u.adding(.constant(uShift, using: &execution), using: &execution)
              .multiplied(by: parameters.v.derivative(using: &execution), using: &execution))
          }, using: &execution)
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func polynomialBounds(
    for curve: SurfaceParameterCurve,
    primitive: CertifiedPolynomialSurfaceFluxPrimitive,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> Interval? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try polynomialBounds(
      for: curve, primitive: primitive, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func polynomialBounds(
    for curve: SurfaceParameterCurve,
    primitive: CertifiedPolynomialSurfaceFluxPrimitive,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval? {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message:
                "Certified polynomial pcurve flux requires a finite positive enclosure width."
            )
          }
          switch curve {
          case .constantU(let u, let vStart, let vEnd):
            return try adaptiveJetBounds(
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              evaluator: { fraction, execution in
              let v =
                (try Jet.constant(vStart, using: &execution).adding(
                  Jet.constant(Interval.exact(vEnd) - .exact(vStart), using: &execution).multiplied(
                    by: fraction, using: &execution), using: &execution))
              return try polynomialFluxJet(
                primitive: primitive,
                u: .constant(u, using: &execution),
                v: v,
                tolerance: tolerance, using: &execution
              )
            }, using: &execution)
          case .constantV:
            return .exact(0.0)
          case .affine(let origin, let direction, let startParameter, let endParameter):
            return try adaptiveJetBounds(
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              evaluator: { fraction, execution in
              let parameterSpan =
                (try Jet.constant(
                  Interval.exact(endParameter) - .exact(startParameter), using: &execution
                ))
              let parameter =
                (try Jet.constant(startParameter, using: &execution).adding(
                  parameterSpan.multiplied(by: fraction, using: &execution), using: &execution))
              let u =
                (try Jet.constant(origin.x, using: &execution).adding(
                  Jet.constant(direction.x, using: &execution).multiplied(
                    by: parameter, using: &execution), using: &execution))
              let v =
                (try Jet.constant(origin.y, using: &execution).adding(
                  Jet.constant(direction.y, using: &execution).multiplied(
                    by: parameter, using: &execution), using: &execution))
              return try polynomialFluxJet(
                primitive: primitive,
                u: u,
                v: v,
                tolerance: tolerance, using: &execution
              )
            }, using: &execution)
          case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
            return try adaptiveJetBounds(
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              evaluator: { fraction, execution in
              let parameterSpan =
                (try Jet.constant(
                  Interval.exact(endParameter) - .exact(startParameter), using: &execution
                ))
              let parameter =
                (try Jet.constant(startParameter, using: &execution).adding(
                  parameterSpan.multiplied(by: fraction, using: &execution), using: &execution))
              let values = (try parameter.sineAndCosine(using: &execution))
              let u =
                (try Jet.constant(center.x, using: &execution).adding(
                  Jet.constant(cosine.x, using: &execution).multiplied(
                    by: values.cosine, using: &execution), using: &execution
                ).adding(
                  Jet.constant(sine.x, using: &execution).multiplied(
                    by: values.sine, using: &execution),
                  using: &execution))
              let v =
                (try Jet.constant(center.y, using: &execution).adding(
                  Jet.constant(cosine.y, using: &execution).multiplied(
                    by: values.cosine, using: &execution), using: &execution
                ).adding(
                  Jet.constant(sine.y, using: &execution).multiplied(
                    by: values.sine, using: &execution),
                  using: &execution))
              return try polynomialFluxJet(
                primitive: primitive,
                u: u,
                v: v,
                tolerance: tolerance, using: &execution
              )
            }, using: &execution)
          case .polyline(let points):
            guard points.count >= 2 else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: Double(points.count),
                tolerance: tolerance,
                message: "Certified polynomial polyline flux requires at least two points."
              )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
              try execution.consumeWork(1)

              let start = points[index - 1]
              let end = points[index]
              result =
                result
                + (try adaptiveJetBounds(
                  requestedWidth: segmentWidth,
                  tolerance: tolerance,
              evaluator: { fraction, execution in
                  let u =
                    (try Jet.constant(start.u, using: &execution).adding(
                      Jet.constant(Interval.exact(end.u) - .exact(start.u), using: &execution)
                        .multiplied(
                          by: fraction, using: &execution), using: &execution))
                  let v =
                    (try Jet.constant(start.v, using: &execution).adding(
                      Jet.constant(Interval.exact(end.v) - .exact(start.v), using: &execution)
                        .multiplied(
                          by: fraction, using: &execution), using: &execution))
                  return try polynomialFluxJet(
                    primitive: primitive,
                    u: u,
                    v: v,
                    tolerance: tolerance, using: &execution
                  )
                }, using: &execution))
            }
            return result
          case .bSpline(let spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
              curve: spline,
              tolerance: tolerance, using: &execution
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
              try execution.consumeWork(1)

              let preparedPatch = try prepareRationalPcurvePatch(
                patch,
                tolerance: tolerance, using: &execution
              )
              result =
                result
                + (try adaptiveJetBounds(
                  requestedWidth: patchWidth,
                  tolerance: tolerance,
              evaluator: { fraction, execution in
                  let parameters = try rationalPcurveJets(
                    patch: preparedPatch,
                    parameter: fraction.coefficients[0],
                    tolerance: tolerance, using: &execution
                  )
                  return try polynomialFluxJet(
                    primitive: primitive,
                    u: parameters.u,
                    v: parameters.v,
                    tolerance: tolerance, using: &execution
                  )
                }, using: &execution))
            }
            return result
          case .sphericalGreatCircle,
            .certifiedImplicit,
            .certifiedAnalyticImplicit,
            .certifiedAnalyticPair,
            .projectedAnalytic,
            .rigidImage, .originalImage, .originalAffineWord, .originalBSplineContinuation:
            return nil
          case .offsetSurfaceImage(let image):
            return try polynomialBounds(
              for: image.source,
              primitive: primitive,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          case .periodicTranslation(let base, let uShift, let vShift):
            guard uShift == 0.0, vShift == 0.0 else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message:
                  "A polynomial surface flux cannot consume a nonzero periodic parameter translation."
              )
            }
            return try polynomialBounds(
              for: base,
              primitive: primitive,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          }
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func piecewisePolynomialBounds(
    for curve: SurfaceParameterCurve,
    primitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> Interval {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try piecewisePolynomialBounds(
      for: curve, primitive: primitive, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func piecewisePolynomialBounds(
    for curve: SurfaceParameterCurve,
    primitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval {

          try execution.consumeWork(1)

          guard
            let result = try rationalSurfaceBounds(
              for: curve, field: primitive.field,
              uBase: primitive.uBase, requestedWidth: requestedWidth, tolerance: tolerance,
              polynomialPrimitive: primitive, using: &execution)
          else {
            throw KernelError(
              phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
              message: "The original pcurve has no supported piecewise polynomial flux composition."
            )
          }
          return result
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func polynomialSurfaceExplicitBounds(
    primitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive,
    requestedWidth: Double,
    curveBreaks: [Double],
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    struct Cell {
      let lower: Double
      let upper: Double
      let depth: Int
      let width: Double
    }
    let breaks =
      (try sortedUniqueFractions(
        OriginalParameterQueryStorage.concatenated(
          curveBreaks,
          OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in [0, 1] },
          using: &execution),
        using: &execution))
    let intervals =
      (try OriginalParameterQueryStorage.filter(
        (1..<breaks.count), using: &execution,
        predicate: { element, execution in breaks[element] > breaks[element - 1] }))
    guard maximumWorkItems > 0, !intervals.isEmpty else {
      throw resourceFailure(
        residual: nil, tolerance: tolerance,
        message: "Polynomial Green integration requires a positive work allowance and partition.")
    }
    let initialWidth = requestedWidth * 0.5 / Double(intervals.count)
    let roundoffWidth = requestedWidth * 0.5 / Double(maximumWorkItems)
    var pending =
      (try OriginalParameterQueryStorage.map(
        intervals, using: &execution,
        transform: { element, execution in
          Cell(lower: breaks[element - 1], upper: breaks[element], depth: 0, width: initialWidth)
        }))
    var work = 0
    var result = Interval.exact(0)
    while let cell = pending.popLast() {
      try execution.consumeWork(1)

      try CurrentTaskCancellationChecker().checkCancellation()
      work += 1
      guard work <= maximumWorkItems else {
        throw resourceFailure(
          residual: Double(work), tolerance: tolerance,
          message: "Polynomial Green integration exhausted its existing cell allowance.")
      }
      let curve = try parameterEvaluator(
        .variable(Interval(lower: cell.lower, upper: cell.upper), using: &execution), &execution)
      let u = curve.u.coefficients[0]
      let v = curve.v.coefficients[0]
      let enclosure: Interval
      if let uSpan =
        (try OriginalParameterQueryStorage.first(
          primitive.uSpans, using: &execution,
          predicate: { element, execution in u.lower >= element.lower && u.upper <= element.upper })),
        let vSpan =
          (try OriginalParameterQueryStorage.first(
            primitive.vSpans, using: &execution,
            predicate: { element, execution in v.lower >= element.lower && v.upper <= element.upper
            }))
      {
        guard
          let gauss = try gaussEnclosure(
            lower: cell.lower, upper: cell.upper,
            evaluator: { fraction, execution in
              let parameters = try parameterEvaluator(fraction, &execution)
              let green = try primitive.directionalJet(
                u: .series(parameters.u.coefficients, using: &execution),
                v: .series(parameters.v.coefficients, using: &execution),
                uSpan: uSpan, vSpan: vSpan, using: &execution)
              return
                (try Jet(coefficients: green.coefficients).multiplied(
                  by: parameters.v.derivative(using: &execution), using: &execution))
            }, tolerance: tolerance, using: &execution)
        else {
          throw resourceFailure(
            residual: nil, tolerance: tolerance,
            message: "An owning polynomial Green cell lost its original jet proof.")
        }
        enclosure = gauss
      } else {
        // Retain the existing seam-domain enclosure law; no band measure is discarded.
        let uLower = primitive.uSpans[0].lower
        let uUpper = primitive.uSpans[primitive.uSpans.count - 1].upper
        let vLower = primitive.vSpans[0].lower
        let vUpper = primitive.vSpans[primitive.vSpans.count - 1].upper
        let uSlack = Double.ulpOfOne * max(1, abs(uLower), abs(uUpper)) * 4_096
        let vSlack = Double.ulpOfOne * max(1, abs(vLower), abs(vUpper)) * 4_096
        guard u.lower >= uLower - uSlack, u.upper <= uUpper + uSlack,
          v.lower >= vLower - vSlack, v.upper <= vUpper + vSlack
        else {
          throw KernelError(
            phase: .topology, code: .topologyFailure, tolerance: tolerance,
            message: "Polynomial Green seam band left the original surface domain.")
        }
        let green = try primitive.range(
          overClosedUV: Interval(lower: max(uLower, u.lower), upper: min(uUpper, u.upper)),
          v: Interval(lower: max(vLower, v.lower), upper: min(vUpper, v.upper)), using: &execution)
        enclosure =
          green * (try curve.v.derivative(using: &execution)).coefficients[0]
          * .floating(cell.upper - cell.lower)
      }
      guard enclosure.lower.isFinite, enclosure.upper.isFinite else {
        throw resourceFailure(
          residual: enclosure.width, tolerance: tolerance,
          message: "Polynomial Green integration exceeded finite arithmetic.")
      }
      if enclosure.width <= (cell.width + roundoffWidth).nextUp {
        result = result + enclosure
        continue
      }
      let middle = cell.lower + (cell.upper - cell.lower) * 0.5
      guard cell.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth),
        middle > cell.lower, middle < cell.upper
      else {
        throw resourceFailure(
          residual: enclosure.width, tolerance: tolerance,
          message: "Polynomial Green integration exhausted its existing proof depth.")
      }
      (try OriginalParameterQueryStorage.append(
        Cell(lower: middle, upper: cell.upper, depth: cell.depth + 1, width: cell.width * 0.5),
        to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        Cell(lower: cell.lower, upper: middle, depth: cell.depth + 1, width: cell.width * 0.5),
        to: &pending, using: &execution))
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    guard result.width <= requestedWidth else {
      throw resourceFailure(
        residual: result.width, tolerance: tolerance,
        message: "Polynomial Green accumulated enclosure exceeds the requested width.")
    }
    return result
  }

  func rationalSurfaceBounds(
    for curve: SurfaceParameterCurve,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    polynomialPrimitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive? = nil
  ) throws -> Interval? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try rationalSurfaceBounds(
      for: curve, field: field, uBase: uBase, requestedWidth: requestedWidth, tolerance: tolerance,
      polynomialPrimitive: polynomialPrimitive, using: &execution)
  }

  func rationalSurfaceBounds(
    for curve: SurfaceParameterCurve,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    polynomialPrimitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval? {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          try CurrentTaskCancellationChecker().checkCancellation()
          guard uBase.isFinite,
            requestedWidth.isFinite,
            requestedWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message:
                "Certified rational pcurve flux requires a finite base and positive enclosure width."
            )
          }
          switch curve {
          case .constantU(let u, let vStart, let vEnd):
            return try rationalSurfaceExplicitBounds(
              polynomialPrimitive: polynomialPrimitive,
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              curveBreaks: linearSurfaceSpanBreaks(
                uStart: u,
                uEnd: u,
                vStart: vStart,
                vEnd: vEnd,
                field: field, using: &execution
              ),
              parameterEvaluator: { fraction, execution in
              (
                (try .constant(u, using: &execution)),
                (try .constant(vStart, using: &execution).adding(
                  .constant(Interval.exact(vEnd) - .exact(vStart), using: &execution).multiplied(
                    by: fraction, using: &execution), using: &execution))
              )
            }, using: &execution)
          case .constantV:
            return .exact(0.0)
          case .affine(let origin, let direction, let startParameter, let endParameter):
            let uStart = origin.x + direction.x * startParameter
            let uEnd = origin.x + direction.x * endParameter
            let vStart = origin.y + direction.y * startParameter
            let vEnd = origin.y + direction.y * endParameter
            return try rationalSurfaceExplicitBounds(
              polynomialPrimitive: polynomialPrimitive,
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              curveBreaks: linearSurfaceSpanBreaks(
                uStart: uStart,
                uEnd: uEnd,
                vStart: vStart,
                vEnd: vEnd,
                field: field, using: &execution
              ),
              parameterEvaluator: { fraction, execution in
              let span =
                (try Jet.constant(
                  Interval.exact(endParameter) - .exact(startParameter), using: &execution
                ))
              let parameter =
                (try Jet.constant(startParameter, using: &execution).adding(
                  span.multiplied(by: fraction, using: &execution), using: &execution))
              return (
                (try Jet.constant(origin.x, using: &execution).adding(
                  Jet.constant(direction.x, using: &execution).multiplied(
                    by: parameter, using: &execution), using: &execution)),
                (try Jet.constant(origin.y, using: &execution).adding(
                  Jet.constant(direction.y, using: &execution).multiplied(
                    by: parameter, using: &execution), using: &execution))
              )
            }, using: &execution)
          case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
            return try rationalSurfaceExplicitBounds(
              polynomialPrimitive: polynomialPrimitive,
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              curveBreaks: harmonicSurfaceSpanBreaks(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter,
                field: field,
                tolerance: tolerance, using: &execution
              ),
              parameterEvaluator: { fraction, execution in
              let span =
                (try Jet.constant(
                  Interval.exact(endParameter) - .exact(startParameter), using: &execution
                ))
              let parameter =
                (try Jet.constant(startParameter, using: &execution).adding(
                  span.multiplied(by: fraction, using: &execution), using: &execution))
              let values = (try parameter.sineAndCosine(using: &execution))
              return (
                (try Jet.constant(center.x, using: &execution).adding(
                  Jet.constant(cosine.x, using: &execution).multiplied(
                    by: values.cosine, using: &execution), using: &execution
                ).adding(
                  Jet.constant(sine.x, using: &execution).multiplied(
                    by: values.sine, using: &execution),
                  using: &execution)),
                (try Jet.constant(center.y, using: &execution).adding(
                  Jet.constant(cosine.y, using: &execution).multiplied(
                    by: values.cosine, using: &execution), using: &execution
                ).adding(
                  Jet.constant(sine.y, using: &execution).multiplied(
                    by: values.sine, using: &execution),
                  using: &execution))
              )
            }, using: &execution)
          case .polyline(let points):
            guard points.count >= 2 else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: Double(points.count),
                tolerance: tolerance,
                message: "Certified rational polyline flux requires at least two points."
              )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
              try execution.consumeWork(1)

              let start = points[index - 1]
              let end = points[index]
              result =
                result
                + (try rationalSurfaceExplicitBounds(
                  polynomialPrimitive: polynomialPrimitive,
                  field: field,
                  uBase: uBase,
                  requestedWidth: segmentWidth,
                  tolerance: tolerance,
                  curveBreaks: linearSurfaceSpanBreaks(
                    uStart: start.u,
                    uEnd: end.u,
                    vStart: start.v,
                    vEnd: end.v,
                    field: field, using: &execution
                  ),
              parameterEvaluator: { fraction, execution in
                  (
                    (try .constant(start.u, using: &execution).adding(
                      .constant(Interval.exact(end.u) - .exact(start.u), using: &execution)
                        .multiplied(
                          by: fraction, using: &execution), using: &execution)),
                    (try .constant(start.v, using: &execution).adding(
                      .constant(Interval.exact(end.v) - .exact(start.v), using: &execution)
                        .multiplied(
                          by: fraction, using: &execution), using: &execution))
                  )
                }, using: &execution))
            }
            return result
          case .bSpline(let spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
              curve: spline,
              tolerance: tolerance, using: &execution
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
              try execution.consumeWork(1)

              let preparedPatch = try prepareRationalPcurvePatch(
                patch,
                tolerance: tolerance, using: &execution
              )
              result =
                result
                + (try rationalSurfaceExplicitBounds(
                  polynomialPrimitive: polynomialPrimitive,
                  field: field,
                  uBase: uBase,
                  requestedWidth: patchWidth,
                  tolerance: tolerance,
                  curveBreaks: rationalPcurveSurfaceSpanBreaks(
                    patch: patch,
                    field: field,
                    tolerance: tolerance,
                    includeUSurfaceSeams: polynomialPrimitive == nil, using: &execution
                  ),
              parameterEvaluator: { fraction, execution in
                  try rationalPcurveJets(
                    patch: preparedPatch,
                    parameter: fraction.coefficients[0],
                    tolerance: tolerance, using: &execution
                  )
                }, using: &execution))
            }
            return result
          case .certifiedImplicit(let certified):
            return try rationalSurfaceImplicitBounds(
              curve: certified,
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          case .sphericalGreatCircle,
            .certifiedAnalyticImplicit,
            .certifiedAnalyticPair,
            .projectedAnalytic, .originalImage, .originalAffineWord, .originalBSplineContinuation:
            return nil
          case .rigidImage(let image):
            guard
              try image.affineParameterTransform(tolerance: tolerance, using: &execution)
                == .identity
            else {
              return nil
            }
            return try rationalSurfaceBounds(
              for: image.sourceParameterCurve(tolerance: tolerance, using: &execution),
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              polynomialPrimitive: polynomialPrimitive, using: &execution
            )
          case .offsetSurfaceImage(let image):
            return try rationalSurfaceBounds(
              for: image.source,
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              polynomialPrimitive: polynomialPrimitive, using: &execution
            )
          case .periodicTranslation(let base, let uShift, let vShift):
            guard uShift == 0.0, vShift == 0.0 else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message:
                  "A rational surface flux cannot consume a nonzero periodic parameter translation."
              )
            }
            return try rationalSurfaceBounds(
              for: base,
              field: field,
              uBase: uBase,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              polynomialPrimitive: polynomialPrimitive, using: &execution
            )
          }
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func proceduralSurfaceBounds(
    for curve: SurfaceParameterCurve,
    surface: Surface3D,
    reference: Point3D,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> Interval? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try proceduralSurfaceBounds(
      for: curve, surface: surface, reference: reference, uBase: uBase,
      requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  func proceduralSurfaceBounds(
    for curve: SurfaceParameterCurve,
    surface: Surface3D,
    reference: Point3D,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval? {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard case .procedural = surface,
            uBase.isFinite,
            requestedWidth.isFinite,
            requestedWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message:
                "Certified procedural pcurve flux requires a procedural surface, finite base, and positive enclosure width."
            )
          }
          let fluxEncloser = try SurfaceFluxDifferentialEncloser(
            surface: surface,
            tolerance: tolerance, using: &execution
          )
          return try proceduralSurfaceBounds(
            for: curve,
            surface: surface,
            fluxEncloser: fluxEncloser,
            reference: reference,
            uBase: uBase,
            requestedWidth: requestedWidth,
            tolerance: tolerance, using: &execution
          )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func proceduralSurfaceBounds(
    for curve: SurfaceParameterCurve,
    surface: Surface3D,
    fluxEncloser: SurfaceFluxDifferentialEncloser,
    reference: Point3D,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)

    switch curve {
    case .constantU(let u, let vStart, let vEnd):
      return try proceduralSurfaceExplicitBounds(
        surface: surface,
        fluxEncloser: fluxEncloser,
        reference: reference,
        uBase: uBase,
        requestedWidth: requestedWidth,
        tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
        (
          (try .constant(u, using: &execution)),
          (try .constant(vStart, using: &execution).adding(
            .constant(Interval.exact(vEnd) - .exact(vStart), using: &execution).multiplied(
              by: fraction, using: &execution), using: &execution))
        )
      }, using: &execution)
    case .constantV:
      return .exact(0.0)
    case .affine(let origin, let direction, let startParameter, let endParameter):
      return try proceduralSurfaceExplicitBounds(
        surface: surface,
        fluxEncloser: fluxEncloser,
        reference: reference,
        uBase: uBase,
        requestedWidth: requestedWidth,
        tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
        let span =
          (try Jet.constant(
            Interval.exact(endParameter) - .exact(startParameter), using: &execution
          ))
        let parameter =
          (try Jet.constant(startParameter, using: &execution).adding(
            span.multiplied(by: fraction, using: &execution), using: &execution))
        return (
          (try Jet.constant(origin.x, using: &execution).adding(
            Jet.constant(direction.x, using: &execution).multiplied(
              by: parameter, using: &execution), using: &execution)),
          (try Jet.constant(origin.y, using: &execution).adding(
            Jet.constant(direction.y, using: &execution).multiplied(
              by: parameter, using: &execution), using: &execution))
        )
      }, using: &execution)
    case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
      return try proceduralSurfaceExplicitBounds(
        surface: surface,
        fluxEncloser: fluxEncloser,
        reference: reference,
        uBase: uBase,
        requestedWidth: requestedWidth,
        tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
        let span =
          (try Jet.constant(
            Interval.exact(endParameter) - .exact(startParameter), using: &execution
          ))
        let parameter =
          (try Jet.constant(startParameter, using: &execution).adding(
            span.multiplied(by: fraction, using: &execution), using: &execution))
        let values = (try parameter.sineAndCosine(using: &execution))
        return (
          (try Jet.constant(center.x, using: &execution).adding(
            Jet.constant(cosine.x, using: &execution).multiplied(
              by: values.cosine, using: &execution), using: &execution
          ).adding(
            Jet.constant(sine.x, using: &execution).multiplied(by: values.sine, using: &execution),
            using: &execution)),
          (try Jet.constant(center.y, using: &execution).adding(
            Jet.constant(cosine.y, using: &execution).multiplied(
              by: values.cosine, using: &execution), using: &execution
          ).adding(
            Jet.constant(sine.y, using: &execution).multiplied(by: values.sine, using: &execution),
            using: &execution))
        )
      }, using: &execution)
    case .polyline(let points):
      guard points.count >= 2 else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          residual: Double(points.count),
          tolerance: tolerance,
          message: "Certified procedural polyline flux requires at least two points."
        )
      }
      let segmentWidth = requestedWidth / Double(points.count - 1)
      var result = Interval.exact(0.0)
      for index in 1..<points.count {
        try execution.consumeWork(1)

        let start = points[index - 1]
        let end = points[index]
        result =
          result
          + (try proceduralSurfaceExplicitBounds(
            surface: surface,
            fluxEncloser: fluxEncloser,
            reference: reference,
            uBase: uBase,
            requestedWidth: segmentWidth,
            tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
            (
              (try .constant(start.u, using: &execution).adding(
                .constant(Interval.exact(end.u) - .exact(start.u), using: &execution).multiplied(
                  by: fraction, using: &execution), using: &execution)),
              (try .constant(start.v, using: &execution).adding(
                .constant(Interval.exact(end.v) - .exact(start.v), using: &execution).multiplied(
                  by: fraction, using: &execution), using: &execution))
            )
          }, using: &execution))
      }
      return result
    case .bSpline(let spline):
      let patches = try CertifiedBSplineCurveBezierExtractor().patches(
        curve: spline,
        tolerance: tolerance, using: &execution
      )
      guard patches.isEmpty == false else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Certified procedural B-spline flux found no active Bezier span."
        )
      }
      let patchWidth = requestedWidth / Double(patches.count)
      var result = Interval.exact(0.0)
      for patch in patches {
        try execution.consumeWork(1)

        let prepared = try prepareRationalPcurvePatch(
          patch,
          tolerance: tolerance, using: &execution
        )
        result =
          result
          + (try proceduralSurfaceExplicitBounds(
            surface: surface,
            fluxEncloser: fluxEncloser,
            reference: reference,
            uBase: uBase,
            requestedWidth: patchWidth,
            tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
            try rationalPcurveJets(
              patch: prepared,
              parameter: fraction.coefficients[0],
              tolerance: tolerance, using: &execution
            )
          }, using: &execution))
      }
      return result
    case .rigidImage(let image):
      guard
        try image.affineParameterTransform(tolerance: tolerance, using: &execution)
          == .identity
      else {
        return nil
      }
      return try proceduralSurfaceBounds(
        for: image.sourceParameterCurve(tolerance: tolerance, using: &execution),
        surface: surface,
        fluxEncloser: fluxEncloser,
        reference: reference,
        uBase: uBase,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .offsetSurfaceImage(let image):
      return try proceduralSurfaceBounds(
        for: image.source,
        surface: surface,
        fluxEncloser: fluxEncloser,
        reference: reference,
        uBase: uBase,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, let uShift, let vShift):
      let materialized = (try curve.materializingPeriodicTranslation(using: &execution))
      if materialized == curve,
        case .rigidImage(let image) = base,
        try image.affineParameterTransform(tolerance: tolerance, using: &execution) == .identity
      {
        let sourceCurve = try image.sourceParameterCurve(tolerance: tolerance, using: &execution)
        let untranslated = SurfaceParameterCurve.periodicTranslation(
          base: sourceCurve,
          uShift: uShift,
          vShift: vShift
        )
        let translatedSource =
          (try untranslated.materializingPeriodicTranslation(using: &execution))
        guard translatedSource != untranslated else {
          return nil
        }
        return try proceduralSurfaceBounds(
          for: translatedSource,
          surface: surface,
          fluxEncloser: fluxEncloser,
          reference: reference,
          uBase: uBase,
          requestedWidth: requestedWidth,
          tolerance: tolerance, using: &execution
        )
      }
      guard materialized != curve else { return nil }
      return try proceduralSurfaceBounds(
        for: materialized,
        surface: surface,
        fluxEncloser: fluxEncloser,
        reference: reference,
        uBase: uBase,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    // FIXME(INCOMPLETE_IMPLEMENTATION): This procedural flux strategy still
    // returns no enclosure for the retained implicit/image/continuation trims
    // below. Original shell-volume validation reaches this branch through
    // TrimmedParametricSurfaceVolumeEvaluator, including rolling-ball blend
    // neighbour trims, and refuses with "no certified surface-flux strategy".
    // Complete whole original pcurve flux and convergence under unchanged
    // caller error/work/depth are required before full curved solid volume
    // support may be claimed; nil is not a successful integral. The curved
    // source solid path in RollingBallFilletRequestBuilderTests must pass
    // without its known issue before this missing strategy is complete.
    case .sphericalGreatCircle, .certifiedImplicit,
      .certifiedAnalyticImplicit, .certifiedAnalyticPair,
      .projectedAnalytic, .originalImage, .originalAffineWord, .originalBSplineContinuation:
      return nil
    }
  }

  func rationalPlanarAreaBounds(
    for curve: SurfaceParameterCurve,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> Interval? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try rationalPlanarAreaBounds(
      for: curve, field: field, projection: projection, requestedWidth: requestedWidth,
      tolerance: tolerance, using: &execution)
  }

  func rationalPlanarAreaBounds(
    for curve: SurfaceParameterCurve,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval? {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message: "Certified rational planar area requires a positive enclosure width."
            )
          }
          switch curve {
          case .constantU(let u, let vStart, let vEnd):
            return try rationalPlanarExplicitBounds(
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
              (
                (try .constant(u, using: &execution)),
                (try .constant(vStart, using: &execution).adding(
                  .constant(Interval.exact(vEnd) - .exact(vStart), using: &execution).multiplied(
                    by: fraction, using: &execution), using: &execution))
              )
            }, using: &execution)
          case .constantV(let v, let uStart, let uEnd):
            return try rationalPlanarExplicitBounds(
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
              (
                (try .constant(uStart, using: &execution).adding(
                  .constant(Interval.exact(uEnd) - .exact(uStart), using: &execution).multiplied(
                    by: fraction, using: &execution), using: &execution)),
                (try .constant(v, using: &execution))
              )
            }, using: &execution)
          case .affine(let origin, let direction, let startParameter, let endParameter):
            return try rationalPlanarExplicitBounds(
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
              let span =
                (try Jet.constant(
                  Interval.exact(endParameter) - .exact(startParameter), using: &execution
                ))
              let parameter =
                (try Jet.constant(startParameter, using: &execution).adding(
                  span.multiplied(by: fraction, using: &execution), using: &execution))
              return (
                (try Jet.constant(origin.x, using: &execution).adding(
                  Jet.constant(direction.x, using: &execution).multiplied(
                    by: parameter, using: &execution), using: &execution)),
                (try Jet.constant(origin.y, using: &execution).adding(
                  Jet.constant(direction.y, using: &execution).multiplied(
                    by: parameter, using: &execution), using: &execution))
              )
            }, using: &execution)
          case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
            return try rationalPlanarExplicitBounds(
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
              let span =
                (try Jet.constant(
                  Interval.exact(endParameter) - .exact(startParameter), using: &execution
                ))
              let parameter =
                (try Jet.constant(startParameter, using: &execution).adding(
                  span.multiplied(by: fraction, using: &execution), using: &execution))
              let values = (try parameter.sineAndCosine(using: &execution))
              return (
                (try Jet.constant(center.x, using: &execution).adding(
                  Jet.constant(cosine.x, using: &execution).multiplied(
                    by: values.cosine, using: &execution), using: &execution
                ).adding(
                  Jet.constant(sine.x, using: &execution).multiplied(
                    by: values.sine, using: &execution),
                  using: &execution)),
                (try Jet.constant(center.y, using: &execution).adding(
                  Jet.constant(cosine.y, using: &execution).multiplied(
                    by: values.cosine, using: &execution), using: &execution
                ).adding(
                  Jet.constant(sine.y, using: &execution).multiplied(
                    by: values.sine, using: &execution),
                  using: &execution))
              )
            }, using: &execution)
          case .polyline(let points):
            guard points.count >= 2 else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: Double(points.count),
                tolerance: tolerance,
                message: "Certified rational planar polyline requires at least two points."
              )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
              try execution.consumeWork(1)

              let start = points[index - 1]
              let end = points[index]
              result =
                result
                + (try rationalPlanarExplicitBounds(
                  field: field,
                  projection: projection,
                  requestedWidth: segmentWidth,
                  tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
                  (
                    (try .constant(start.u, using: &execution).adding(
                      .constant(Interval.exact(end.u) - .exact(start.u), using: &execution)
                        .multiplied(
                          by: fraction, using: &execution), using: &execution)),
                    (try .constant(start.v, using: &execution).adding(
                      .constant(Interval.exact(end.v) - .exact(start.v), using: &execution)
                        .multiplied(
                          by: fraction, using: &execution), using: &execution))
                  )
                }, using: &execution))
            }
            return result
          case .bSpline(let spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
              curve: spline,
              tolerance: tolerance, using: &execution
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
              try execution.consumeWork(1)

              let preparedPatch = try prepareRationalPcurvePatch(
                patch,
                tolerance: tolerance, using: &execution
              )
              result =
                result
                + (try rationalPlanarExplicitBounds(
                  field: field,
                  projection: projection,
                  requestedWidth: patchWidth,
                  tolerance: tolerance,
              parameterEvaluator: { fraction, execution in
                  try rationalPcurveJets(
                    patch: preparedPatch,
                    parameter: fraction.coefficients[0],
                    tolerance: tolerance, using: &execution
                  )
                }, using: &execution))
            }
            return result
          case .sphericalGreatCircle,
            .certifiedImplicit,
            .certifiedAnalyticImplicit,
            .certifiedAnalyticPair,
            .projectedAnalytic, .originalImage, .originalAffineWord, .originalBSplineContinuation:
            return nil
          case .rigidImage(let image):
            guard
              try image.affineParameterTransform(tolerance: tolerance, using: &execution)
                == .identity
            else {
              return nil
            }
            return try rationalPlanarAreaBounds(
              for: image.sourceParameterCurve(tolerance: tolerance, using: &execution),
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          case .offsetSurfaceImage(let image):
            return try rationalPlanarAreaBounds(
              for: image.source,
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          case .periodicTranslation(let base, let uShift, let vShift):
            guard uShift == 0.0, vShift == 0.0 else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message:
                  "A rational planar area integral cannot consume a nonzero periodic parameter translation."
              )
            }
            return try rationalPlanarAreaBounds(
              for: base,
              field: field,
              projection: projection,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          }
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func rationalPlanarExplicitBounds(
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    struct WorkItem {
      let lower: Double
      let upper: Double
      let widthBudget: Double
      let depth: Int
    }
    var pending =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [
          WorkItem(
            lower: 0.0,
            upper: 1.0,
            widthBudget: requestedWidth,
            depth: 0
          )
        ]
      })
    var result = Interval.exact(0.0)
    var workItemCount = 0
    while let item = pending.popLast() {
      try execution.visitGeometricCell(depth: item.depth)

      try execution.consumeWork(1)

      workItemCount += 1
      guard workItemCount <= maximumWorkItems else {
        throw resourceFailure(
          residual: Double(workItemCount),
          tolerance: tolerance,
          message: "Certified rational planar area exhausted its curve-cell budget."
        )
      }
      let curve = try parameterEvaluator(
        .variable(Interval(lower: item.lower, upper: item.upper), using: &execution), &execution)
      let uSpan = (try field.containingUSpan(curve.u.coefficients[0], using: &execution))
      let vSpan = (try field.containingVSpan(curve.v.coefficients[0], using: &execution))
      let enclosure: Interval?
      if let uSpan, let vSpan {
        enclosure = try rationalPlanarGaussEnclosure(
          field: field,
          projection: projection,
          uSpan: uSpan,
          vSpan: vSpan,
          lower: item.lower,
          upper: item.upper,
          parameterEvaluator: parameterEvaluator,
          tolerance: tolerance, using: &execution
        )
      } else {
        let range = try field.projectedBoundaryAreaRange(
          u: certifiedJet(curve.u, using: &execution),
          v: certifiedJet(curve.v, using: &execution),
          projection: projection, using: &execution
        )
        enclosure =
          Interval(
            lower: range.lower,
            upper: range.upper
          ) * .floating(item.upper - item.lower)
      }
      if let enclosure, enclosure.width <= item.widthBudget {
        result = result + enclosure
        continue
      }
      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw resourceFailure(
          residual: enclosure?.width,
          tolerance: tolerance,
          message: "Certified rational planar area exceeded its proof depth."
        )
      }
      let middle = item.lower + (item.upper - item.lower) * 0.5
      let halfBudget = item.widthBudget * 0.5
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          lower: middle,
          upper: item.upper,
          widthBudget: halfBudget,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          lower: item.lower,
          upper: middle,
          widthBudget: halfBudget,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
    }
    return result
  }

  private func rationalPlanarGaussEnclosure(
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
    uSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
    vSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
    lower: Double,
    upper: Double,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let midpoint = lower + (upper - lower) * 0.5
    let halfSpan = (upper - lower) * 0.5
    let root = sqrt(3.0 / 5.0)
    let nodes =
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [midpoint - halfSpan * root, midpoint, midpoint + halfSpan * root]
      })
    let weights =
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
      })
    var estimate = Interval.exact(0.0)
    for index in nodes.indices {
      try execution.consumeWork(1)

      let curve = try parameterEvaluator(
        .variable(.exact(nodes[index]), using: &execution), &execution)
      let value = try field.projectedBoundaryAreaJet(
        u: certifiedJet(curve.u, using: &execution),
        v: certifiedJet(curve.v, using: &execution),
        projection: projection,
        uSpan: uSpan,
        vSpan: vSpan, using: &execution
      ).coefficients[0]
      estimate = estimate + value * .floating(weights[index])
    }
    estimate = estimate * .floating(halfSpan)

    let curve = try parameterEvaluator(
      .variable(Interval(lower: lower, upper: upper), using: &execution), &execution)
    let integrand = try field.projectedBoundaryAreaJet(
      u: certifiedJet(curve.u, using: &execution),
      v: certifiedJet(curve.v, using: &execution),
      projection: projection,
      uSpan: uSpan,
      vSpan: vSpan, using: &execution
    )
    let sixthCoefficient = integrand.coefficients[6].maximumAbsolute
    let sixthDerivative = (try outwardProduct(sixthCoefficient, 720.0, using: &execution))
    let gaussConstant = 1_296.0 / (7.0 * 720.0 * 720.0 * 720.0)
    var error =
      (try outwardProduct(
        outwardProduct(sixthDerivative, gaussConstant, using: &execution),
        pow(upper - lower, 7.0), using: &execution
      ))
    for _ in 0..<8 {
      try execution.consumeWork(1)
      error = error.nextUp
    }
    guard estimate.lower.isFinite,
      estimate.upper.isFinite,
      error.isFinite
    else {
      throw resourceFailure(
        residual: error,
        tolerance: tolerance,
        message: "Certified rational planar area exceeded finite arithmetic."
      )
    }
    return Interval(
      lower: (estimate.lower - error).nextDown,
      upper: (estimate.upper + error).nextUp
    )
  }

  private func certifiedJet(
    _ jet: Jet, using execution: inout OriginalQueryExecution
  ) throws -> CertifiedUnivariateTaylorJet {
    try execution.consumeWork(1)
    return

      (try CertifiedUnivariateTaylorJet.series(
        OriginalParameterQueryStorage.map(
          jet.coefficients, using: &execution,
          transform: { element, execution in
            CertifiedUnivariateTaylorJet.Interval(
              lower: element.lower,
              upper: element.upper
            )
          }), using: &execution
      ))
  }

  private func proceduralSurfaceExplicitBounds(
    surface: Surface3D,
    fluxEncloser: SurfaceFluxDifferentialEncloser,
    reference: Point3D,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    struct WorkItem {
      let lambdaLower: Double
      let lambdaUpper: Double
      let curveLower: Double
      let curveUpper: Double
      let depth: Int
      let enclosure: Interval
      let lambdaError: Double
      let curveError: Double

      var width: Double { enclosure.width }
    }
    func positiveScalarInterval(
      _ source: Interval,
      domain: ParameterDomain,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> ScalarInterval {
      try execution.consumeWork(1)

      var lower = source.lower
      var upper = source.upper
      if case .closed(let domainLower, let domainUpper) = domain {
        let scale = max(
          abs(domainLower),
          abs(domainUpper),
          abs(lower),
          abs(upper),
          1.0
        )
        let slack = max(
          tolerance.relative * scale,
          Double.ulpOfOne * scale * 4_096.0
        )
        guard lower >= domainLower - slack,
          upper <= domainUpper + slack
        else {
          throw KernelError(
            phase: .topology,
            code: .invalidInput,
            tolerance: tolerance,
            message: "Certified procedural pcurve flux midpoint left the surface parameter domain."
          )
        }
        lower = max(lower, domainLower)
        upper = min(upper, domainUpper)
        if lower == upper {
          if upper < domainUpper {
            upper = min(domainUpper, upper.nextUp)
          } else if lower > domainLower {
            lower = max(domainLower, lower.nextDown)
          }
        }
      } else if lower == upper {
        lower = lower.nextDown
        upper = upper.nextUp
      }
      guard lower.isFinite,
        upper.isFinite,
        upper > lower
      else {
        throw resourceFailure(
          residual: upper - lower,
          tolerance: tolerance,
          message:
            "Certified procedural pcurve flux midpoint requires a positive finite parameter interval."
        )
      }
      return try ScalarInterval(lower: lower, upper: upper)
    }

    func enclosed(
      lambdaLower: Double,
      lambdaUpper: Double,
      curveLower: Double,
      curveUpper: Double,
      depth: Int, using execution: inout OriginalQueryExecution
    ) throws -> WorkItem {
      try execution.consumeWork(1)

      let curve = try parameterEvaluator(
        .variable(
          Interval(
            lower: curveLower,
            upper: curveUpper
          ), using: &execution), &execution)
      let u = curve.u.coefficients[0]
      let v = curve.v.coefficients[0]
      let vDerivative = (try curve.v.derivative(using: &execution)).coefficients[0]
      let deltaU = u - .exact(uBase)
      if deltaU.lower == 0.0, deltaU.upper == 0.0 {
        return WorkItem(
          lambdaLower: lambdaLower,
          lambdaUpper: lambdaUpper,
          curveLower: curveLower,
          curveUpper: curveUpper,
          depth: depth,
          enclosure: .exact(0.0),
          lambdaError: 0.0,
          curveError: 0.0
        )
      }
      if vDerivative.lower == 0.0, vDerivative.upper == 0.0 {
        return WorkItem(
          lambdaLower: lambdaLower,
          lambdaUpper: lambdaUpper,
          curveLower: curveLower,
          curveUpper: curveUpper,
          depth: depth,
          enclosure: .exact(0.0),
          lambdaError: 0.0,
          curveError: 0.0
        )
      }
      let lambda = Interval(
        lower: lambdaLower,
        upper: lambdaUpper
      )
      let mappedU = Interval.exact(uBase) + lambda * deltaU
      guard mappedU.width > 0.0, v.width > 0.0 else {
        throw resourceFailure(
          residual: max(mappedU.width, v.width),
          tolerance: tolerance,
          message: "Certified procedural pcurve flux could not form a positive parameter cell."
        )
      }
      let differential = try fluxEncloser.enclosure(
        over: SurfaceParameterBox(
          u: positiveScalarInterval(
            mappedU,
            domain: surface.uDomain,
            tolerance: tolerance, using: &execution
          ),
          v: positiveScalarInterval(
            v,
            domain: surface.vDomain,
            tolerance: tolerance, using: &execution
          )
        ),
        relativeTo: reference,
        tolerance: tolerance, using: &execution
      )
      let cellArea =
        (lambdaUpper - lambdaLower)
        * (curveUpper - curveLower)
      let flux = Interval(
        lower: differential.value.lower,
        upper: differential.value.upper
      )
      let rangeContribution =
        flux * deltaU * vDerivative
        * .floating(cellArea)
      let firstU = Interval(
        lower: differential.firstDerivativeU.lower,
        upper: differential.firstDerivativeU.upper
      )
      let firstV = Interval(
        lower: differential.firstDerivativeV.lower,
        upper: differential.firstDerivativeV.upper
      )
      let secondUU = Interval(
        lower: differential.secondDerivativeUU.lower,
        upper: differential.secondDerivativeUU.upper
      )
      let secondUV = Interval(
        lower: differential.secondDerivativeUV.lower,
        upper: differential.secondDerivativeUV.upper
      )
      let secondVV = Interval(
        lower: differential.secondDerivativeVV.lower,
        upper: differential.secondDerivativeVV.upper
      )
      let uFirst = (try curve.u.derivative(using: &execution)).coefficients[0]
      let uSecond = (try curve.u.derivative(using: &execution).derivative(using: &execution))
        .coefficients[0]
      let vSecond = (try curve.v.derivative(using: &execution).derivative(using: &execution))
        .coefficients[0]
      let vThird =
        (try curve.v.derivative(using: &execution).derivative(using: &execution).derivative(
          using: &execution))
        .coefficients[0]
      let xFirst = lambda * uFirst
      let xSecond = lambda * uSecond
      let fluxFirst = firstU * xFirst + firstV * vDerivative
      let fluxSecond =
        secondUU * xFirst * xFirst
        + .floating(2.0) * secondUV * xFirst * vDerivative
        + secondVV * vDerivative * vDerivative
        + firstU * xSecond
        + firstV * vSecond
      let boundaryFactor = deltaU * vDerivative
      let boundaryFactorFirst =
        uFirst * vDerivative
        + deltaU * vSecond
      let boundaryFactorSecond =
        uSecond * vDerivative
        + .floating(2.0) * uFirst * vSecond
        + deltaU * vThird
      let secondCurve =
        fluxSecond * boundaryFactor
        + .floating(2.0) * fluxFirst * boundaryFactorFirst
        + flux * boundaryFactorSecond
      let secondLambda =
        secondUU * deltaU * deltaU * deltaU
        * vDerivative
      let lambdaSpan = lambdaUpper - lambdaLower
      let curveSpan = curveUpper - curveLower
      let lambdaError =
        (cellArea * secondLambda.maximumAbsolute
        * lambdaSpan * lambdaSpan / 24.0).nextUp
      let curveError =
        (cellArea * secondCurve.maximumAbsolute
        * curveSpan * curveSpan / 24.0).nextUp
      let totalError = (lambdaError + curveError).nextUp

      let lambdaMidpoint = lambdaLower + lambdaSpan * 0.5
      let curveMidpoint = curveLower + curveSpan * 0.5
      let midpointCurve = try parameterEvaluator(
        .variable(.floating(curveMidpoint), using: &execution), &execution)
      let midpointDeltaU =
        midpointCurve.u.coefficients[0]
        - .exact(uBase)
      let midpointMappedU =
        Interval.exact(uBase)
        + .floating(lambdaMidpoint) * midpointDeltaU
      let midpointV = midpointCurve.v.coefficients[0]
      let midpointFlux = try fluxEncloser.enclosure(
        over: SurfaceParameterBox(
          u: positiveScalarInterval(
            midpointMappedU,
            domain: surface.uDomain,
            tolerance: tolerance, using: &execution
          ),
          v: positiveScalarInterval(
            midpointV,
            domain: surface.vDomain,
            tolerance: tolerance, using: &execution
          )
        ),
        relativeTo: reference,
        tolerance: tolerance, using: &execution
      ).value
      let midpointEstimate =
        Interval(
          lower: midpointFlux.lower,
          upper: midpointFlux.upper
        ) * midpointDeltaU
        * (try midpointCurve.v.derivative(using: &execution)).coefficients[0]
        * .floating(cellArea)
      let midpointContribution =
        midpointEstimate
        + Interval(
          lower: (-totalError).nextDown,
          upper: totalError.nextUp
        )
      let lower = max(
        rangeContribution.lower,
        midpointContribution.lower
      )
      let upper = min(
        rangeContribution.upper,
        midpointContribution.upper
      )
      guard lower <= upper else {
        throw resourceFailure(
          residual: lower - upper,
          tolerance: tolerance,
          message: "Certified procedural pcurve flux produced inconsistent independent enclosures."
        )
      }
      let contribution = Interval(lower: lower, upper: upper)
      guard contribution.lower.isFinite,
        contribution.upper.isFinite
      else {
        throw resourceFailure(
          residual: contribution.width,
          tolerance: tolerance,
          message: "Certified procedural pcurve flux exceeded finite interval arithmetic."
        )
      }
      return WorkItem(
        lambdaLower: lambdaLower,
        lambdaUpper: lambdaUpper,
        curveLower: curveLower,
        curveUpper: curveUpper,
        depth: depth,
        enclosure: contribution,
        lambdaError: lambdaError,
        curveError: curveError
      )
    }

    guard maximumWorkItems > 0 else {
      throw resourceFailure(
        residual: Double(maximumWorkItems),
        tolerance: tolerance,
        message: "Certified procedural pcurve flux has no subdivision budget."
      )
    }
    var heap: [WorkItem] = []
    func push(_ item: WorkItem, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(item, to: &heap, using: &execution))
      var index = heap.count - 1
      while index > 0 {
        try execution.consumeWork(1)

        let parent = (index - 1) / 2
        guard heap[index].width > heap[parent].width else { break }
        heap.swapAt(index, parent)
        index = parent
      }
    }
    func popMaximum(using execution: inout OriginalQueryExecution) throws -> WorkItem? {
      try execution.consumeWork(1)

      guard heap.isEmpty == false else { return nil }
      if heap.count == 1 { return heap.removeLast() }
      let result = heap[0]
      heap[0] = heap.removeLast()
      var index = 0
      while true {
        try execution.consumeWork(1)

        let left = index * 2 + 1
        let right = left + 1
        var largest = index
        if left < heap.count, heap[left].width > heap[largest].width {
          largest = left
        }
        if right < heap.count, heap[right].width > heap[largest].width {
          largest = right
        }
        guard largest != index else { break }
        heap.swapAt(index, largest)
        index = largest
      }
      return result
    }
    func accumulated(using execution: inout OriginalQueryExecution) throws -> Interval {
      try execution.consumeWork(1)
      return

        (try OriginalParameterQueryStorage.reduce(
          heap, initial: .exact(0.0), using: &execution,
          combine: { partial, element, execution in partial + element.enclosure }))
    }

    (try push(
      enclosed(
        lambdaLower: 0.0,
        lambdaUpper: 1.0,
        curveLower: 0.0,
        curveUpper: 1.0,
        depth: 0, using: &execution
      ), using: &execution))
    var evaluatedCellCount = 1
    while (try accumulated(using: &execution)).width > requestedWidth {
      try execution.consumeWork(1)

      guard let item = (try popMaximum(using: &execution)) else {
        throw resourceFailure(
          residual: requestedWidth,
          tolerance: tolerance,
          message: "Certified procedural pcurve flux lost its active subdivision cells."
        )
      }
      try execution.visitGeometricCell(depth: item.depth)

      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth),
        evaluatedCellCount + 2 <= maximumWorkItems
      else {
        throw resourceFailure(
          residual: (try accumulated(using: &execution)).width + item.width,
          tolerance: tolerance,
          message: "Certified procedural pcurve flux exhausted its adaptive subdivision budget."
        )
      }
      let childDepth = item.depth + 1
      if item.curveError >= item.lambdaError {
        let middle =
          item.curveLower
          + (item.curveUpper - item.curveLower) * 0.5
        (try push(
          enclosed(
            lambdaLower: item.lambdaLower,
            lambdaUpper: item.lambdaUpper,
            curveLower: item.curveLower,
            curveUpper: middle,
            depth: childDepth, using: &execution
          ), using: &execution))
        (try push(
          enclosed(
            lambdaLower: item.lambdaLower,
            lambdaUpper: item.lambdaUpper,
            curveLower: middle,
            curveUpper: item.curveUpper,
            depth: childDepth, using: &execution
          ), using: &execution))
      } else {
        let middle =
          item.lambdaLower
          + (item.lambdaUpper - item.lambdaLower) * 0.5
        (try push(
          enclosed(
            lambdaLower: item.lambdaLower,
            lambdaUpper: middle,
            curveLower: item.curveLower,
            curveUpper: item.curveUpper,
            depth: childDepth, using: &execution
          ), using: &execution))
        (try push(
          enclosed(
            lambdaLower: middle,
            lambdaUpper: item.lambdaUpper,
            curveLower: item.curveLower,
            curveUpper: item.curveUpper,
            depth: childDepth, using: &execution
          ), using: &execution))
      }
      evaluatedCellCount += 2
    }
    return (try accumulated(using: &execution))
  }

  private func rationalSurfaceExplicitBounds(
    polynomialPrimitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive? = nil,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    curveBreaks: [Double]? = nil,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)
    let curveBreaks = try curveBreaks ?? OriginalParameterQueryStorage.values(count: 2, using: &execution) { _ in
      [0.0, 1.0]
    }

    if let primitive = polynomialPrimitive {
      return try polynomialSurfaceExplicitBounds(
        primitive: primitive,
        requestedWidth: requestedWidth, curveBreaks: curveBreaks,
        parameterEvaluator: parameterEvaluator, tolerance: tolerance, using: &execution)
    }
    struct WorkItem {
      let lambdaLower: Double
      let lambdaUpper: Double
      let curveLower: Double
      let curveUpper: Double
      let widthBudget: Double
      let depth: Int
    }
    let orderedBreaks =
      (try OriginalParameterQueryStorage.ordered(
        OriginalParameterQueryStorage.filter(
          OriginalParameterQueryStorage.materialize(
            OriginalParameterQueryStorage.set(
              OriginalParameterQueryStorage.concatenated(
                curveBreaks,
                OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
                  [0.0, 1.0]
                }, using: &execution),
              using: &execution), using: &execution), using: &execution,
          predicate: { element, execution in element >= 0.0 && element <= 1.0 }),
        using: &execution, less: <))
    guard orderedBreaks.count >= 2 else {
      throw resourceFailure(
        residual: Double(orderedBreaks.count),
        tolerance: tolerance,
        message: "Certified rational pcurve flux found no bounded curve partition."
      )
    }
    guard maximumWorkItems > 0 else {
      throw resourceFailure(
        residual: Double(maximumWorkItems),
        tolerance: tolerance,
        message: "Certified rational pcurve flux has no two-dimensional cell budget."
      )
    }
    let activeIntervals =
      (try OriginalParameterQueryStorage.compactMap(
        (1..<orderedBreaks.count), using: &execution,
        transform: {
          index, execution
            -> (lower: Double, upper: Double)? in
          let lower = orderedBreaks[index - 1]
          let upper = orderedBreaks[index]
          return upper > lower ? (lower, upper) : nil
        }))
    guard !activeIntervals.isEmpty else {
      throw resourceFailure(
        residual: 0.0,
        tolerance: tolerance,
        message: "Certified rational pcurve flux found no positive curve partition."
      )
    }
    let hierarchicalBudget = requestedWidth * 0.5
    let intervalBudget = hierarchicalBudget / Double(activeIntervals.count)
    let leafRoundoffBudget =
      requestedWidth
      * 0.5
      / Double(maximumWorkItems)
    var pending: [WorkItem] = []
    try OriginalParameterQueryStorage.reserve(
      activeIntervals.count, in: &pending, using: &execution)
    for interval in activeIntervals {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(
        WorkItem(
          lambdaLower: 0.0,
          lambdaUpper: 1.0,
          curveLower: interval.lower,
          curveUpper: interval.upper,
          widthBudget: intervalBudget,
          depth: 0
        ), to: &pending, using: &execution))
    }
    var result = Interval.exact(0.0)
    var workItemCount = 0
    while let item = pending.popLast() {
      try execution.visitGeometricCell(depth: item.depth)

      try execution.consumeWork(1)

      try CurrentTaskCancellationChecker().checkCancellation()
      workItemCount += 1
      guard workItemCount <= maximumWorkItems else {
        throw resourceFailure(
          residual: Double(workItemCount),
          tolerance: tolerance,
          message: "Certified rational pcurve flux exhausted its two-dimensional cell budget."
        )
      }
      // A curve cell whose weight's enclosure reaches zero (a rational pcurve read over too wide
      // a cell) encloses nothing; it is split along the curve like a cell too wide to close.
      let piecewise: PiecewiseRationalEnclosure?
      do {
        piecewise = try piecewiseRationalSurfaceGaussEnclosure(
          field: field,
          uBase: uBase,
          lambdaLower: item.lambdaLower,
          lambdaUpper: item.lambdaUpper,
          curveLower: item.curveLower,
          curveUpper: item.curveUpper,
          parameterEvaluator: parameterEvaluator,
          tolerance: tolerance, using: &execution
        )
      } catch LocalProofFailure.intervalSingularity {
        piecewise = nil
      }
      let enclosure: Interval
      let preferredCurveSplit: Bool
      let seamSplitLocation: SeamSplitLocation?
      let directionalErrors: (lambda: Double, curve: Double)?
      switch piecewise {
      case nil:
        enclosure = Interval(lower: -.infinity, upper: .infinity)
        preferredCurveSplit = true
        seamSplitLocation = nil
        directionalErrors = nil
      case .enclosed(let value):
        enclosure = value.bounds
        preferredCurveSplit = value.curveError >= value.lambdaError
        seamSplitLocation = nil
        directionalErrors = (value.lambdaError, value.curveError)
      case .seamEnclosed(let value):
        enclosure = value.bounds
        preferredCurveSplit = true
        seamSplitLocation = value.splitLocation
        directionalErrors = nil
      }
      if enclosure.width <= (item.widthBudget + leafRoundoffBudget).nextUp {
        result = result + enclosure
        continue
      }
      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw resourceFailure(
          residual: enclosure.width,
          tolerance: tolerance,
          message: (try OriginalParameterQueryStorage.optionalMap(
            directionalErrors, using: &execution,
            { element, execution in
              "Certified rational pcurve flux exceeded its two-dimensional proof depth (lambda remainder: \(element.lambda), curve remainder: \(element.curve))."
            }))
            ?? "Certified rational pcurve flux exceeded its two-dimensional proof depth while isolating a surface-span crossing."
        )
      }
      let halfBudget = item.widthBudget * 0.5
      if preferredCurveSplit {
        let middle =
          item.curveLower
          + (item.curveUpper - item.curveLower) * 0.5
        let lowerBudget: Double
        let upperBudget: Double
        switch seamSplitLocation {
        case .lower:
          lowerBudget = item.widthBudget * 0.75
          upperBudget = item.widthBudget * 0.25
        case .upper:
          lowerBudget = item.widthBudget * 0.25
          upperBudget = item.widthBudget * 0.75
        case .balanced, nil:
          lowerBudget = halfBudget
          upperBudget = halfBudget
        }
        (try OriginalParameterQueryStorage.append(
          WorkItem(
            lambdaLower: item.lambdaLower,
            lambdaUpper: item.lambdaUpper,
            curveLower: middle,
            curveUpper: item.curveUpper,
            widthBudget: upperBudget,
            depth: item.depth + 1
          ), to: &pending, using: &execution))
        (try OriginalParameterQueryStorage.append(
          WorkItem(
            lambdaLower: item.lambdaLower,
            lambdaUpper: item.lambdaUpper,
            curveLower: item.curveLower,
            curveUpper: middle,
            widthBudget: lowerBudget,
            depth: item.depth + 1
          ), to: &pending, using: &execution))
      } else {
        let middle =
          item.lambdaLower
          + (item.lambdaUpper - item.lambdaLower) * 0.5
        (try OriginalParameterQueryStorage.append(
          WorkItem(
            lambdaLower: middle,
            lambdaUpper: item.lambdaUpper,
            curveLower: item.curveLower,
            curveUpper: item.curveUpper,
            widthBudget: halfBudget,
            depth: item.depth + 1
          ), to: &pending, using: &execution))
        (try OriginalParameterQueryStorage.append(
          WorkItem(
            lambdaLower: item.lambdaLower,
            lambdaUpper: middle,
            curveLower: item.curveLower,
            curveUpper: item.curveUpper,
            widthBudget: halfBudget,
            depth: item.depth + 1
          ), to: &pending, using: &execution))
      }
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    return result
  }

  private func linearSurfaceSpanBreaks(
    uStart: Double,
    uEnd: Double,
    vStart: Double,
    vEnd: Double,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    var breaks =
      (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
        [0.0, 1.0]
      })
    (try appendLinearSeamBreaks(
      start: uStart,
      end: uEnd,
      seams: interiorSeams(field.uSpans, using: &execution),
      to: &breaks, using: &execution
    ))
    (try appendLinearSeamBreaks(
      start: vStart,
      end: vEnd,
      seams: interiorSeams(field.vSpans, using: &execution),
      to: &breaks, using: &execution
    ))
    return
      (try OriginalParameterQueryStorage.ordered(
        OriginalParameterQueryStorage.materialize(
          OriginalParameterQueryStorage.set(breaks, using: &execution), using: &execution),
        using: &execution, less: <))
  }

  private func appendLinearSeamBreaks(
    start: Double,
    end: Double,
    seams: [Double],
    to breaks: inout [Double], using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)

    let displacement = end - start
    guard displacement.isFinite, displacement != 0.0 else { return }
    for seam in seams {
      try execution.consumeWork(1)

      let fraction = (seam - start) / displacement
      if fraction > 0.0, fraction < 1.0, fraction.isFinite {
        (try OriginalParameterQueryStorage.append(fraction, to: &breaks, using: &execution))
      }
    }
  }

  private func harmonicSurfaceSpanBreaks(
    center: Point2D,
    cosine: Point2D,
    sine: Point2D,
    startParameter: Double,
    endParameter: Double,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    let values =
      (try OriginalParameterQueryStorage.values(count: 8, using: &execution) { execution in
        [
          center.x, center.y,
          cosine.x, cosine.y,
          sine.x, sine.y,
          startParameter, endParameter,
        ]
      })
    guard
      try OriginalParameterQueryStorage.allSatisfy(
        values, using: &execution, predicate: { element, execution in element.isFinite })
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message:
          "Certified rational harmonic pcurve seam isolation requires finite coefficients and parameters."
      )
    }
    var breaks =
      (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
        [0.0, 1.0]
      })
    try appendHarmonicSeamBreaks(
      center: center.x,
      cosine: cosine.x,
      sine: sine.x,
      startParameter: startParameter,
      endParameter: endParameter,
      seams: interiorSeams(field.uSpans, using: &execution),
      to: &breaks,
      tolerance: tolerance, using: &execution
    )
    try appendHarmonicSeamBreaks(
      center: center.y,
      cosine: cosine.y,
      sine: sine.y,
      startParameter: startParameter,
      endParameter: endParameter,
      seams: interiorSeams(field.vSpans, using: &execution),
      to: &breaks,
      tolerance: tolerance, using: &execution
    )
    return (try sortedUniqueFractions(breaks, using: &execution))
  }

  private func appendHarmonicSeamBreaks(
    center: Double,
    cosine: Double,
    sine: Double,
    startParameter: Double,
    endParameter: Double,
    seams: [Double],
    to breaks: inout [Double],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)

    let parameterSpan = endParameter - startParameter
    guard parameterSpan != 0.0 else { return }
    let amplitude = hypot(cosine, sine)
    guard amplitude > 0.0 else { return }
    let phase = atan2(sine, cosine)
    let parameterLower = min(startParameter, endParameter)
    let parameterUpper = max(startParameter, endParameter)
    let twoPi = 2.0 * Double.pi
    for seam in seams {
      try execution.consumeWork(1)

      let normalized = (seam - center) / amplitude
      let scale = max(1.0, abs(seam), abs(center), amplitude)
      let normalizedSlack = Double.ulpOfOne * scale / amplitude * 512.0
      guard normalized >= -1.0 - normalizedSlack,
        normalized <= 1.0 + normalizedSlack
      else {
        continue
      }
      let angle = acos(min(1.0, max(-1.0, normalized)))
      for base
        in (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
          [phase - angle, phase + angle]
        })
      {
        try execution.consumeWork(1)

        let lowerIndex = ceil((parameterLower - base) / twoPi)
        let upperIndex = floor((parameterUpper - base) / twoPi)
        guard lowerIndex.isFinite, upperIndex.isFinite else {
          throw resourceFailure(
            residual: nil,
            tolerance: tolerance,
            message:
              "Certified rational harmonic pcurve seam isolation exceeded finite turn indexing."
          )
        }
        guard upperIndex >= lowerIndex else { continue }
        let rootCount = upperIndex - lowerIndex + 1.0
        guard breaks.count <= maximumWorkItems else {
          throw resourceFailure(
            residual: Double(breaks.count),
            tolerance: tolerance,
            message: "Certified rational harmonic pcurve seam isolation exhausted its root budget."
          )
        }
        let remainingCapacity = maximumWorkItems - breaks.count
        guard rootCount <= Double(remainingCapacity) else {
          throw resourceFailure(
            residual: rootCount,
            tolerance: tolerance,
            message: "Certified rational harmonic pcurve seam isolation exhausted its root budget."
          )
        }
        var index = lowerIndex
        while index <= upperIndex {
          try execution.consumeWork(1)

          let parameter = base + twoPi * index
          let fraction = (parameter - startParameter) / parameterSpan
          if fraction > 0.0, fraction < 1.0, fraction.isFinite {
            (try OriginalParameterQueryStorage.append(fraction, to: &breaks, using: &execution))
          }
          index += 1.0
        }
      }
    }
  }

  private func rationalPcurveSurfaceSpanBreaks(
    patch: HomogeneousPatch,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    tolerance: ModelingTolerance,
    includeUSurfaceSeams: Bool = true, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    guard patch.degree >= 1,
      try OriginalParameterQueryStorage.allSatisfy(
        patch.controls, using: &execution,
        predicate: { element, execution in element.isFiniteAndPositiveWeight })
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified rational pcurve seam isolation requires valid homogeneous controls."
      )
    }
    var breaks =
      (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
        [0.0, 1.0]
      })
    var workItemCount = 0
    // The original polynomial Green prefix is continuous across U knots. Its
    // adaptive owner retains every unknown closed U band with all incident
    // primitive ranges and the full original pcurve measure. V partitions and
    // the generic rational path retain their existing root-isolation authority.
    if includeUSurfaceSeams {
      for seam in (try interiorSeams(field.uSpans, using: &execution)) {
        try execution.consumeWork(1)

        try appendRationalBezierSeamBreaks(
          coordinateControls: OriginalParameterQueryStorage.map(
            patch.controls, using: &execution, transform: { element, execution in element.x }),
          weightControls: OriginalParameterQueryStorage.map(
            patch.controls, using: &execution, transform: { element, execution in element.weight }),
          seam: seam,
          to: &breaks,
          workItemCount: &workItemCount,
          tolerance: tolerance, using: &execution
        )
      }
    }
    for seam in (try interiorSeams(field.vSpans, using: &execution)) {
      try execution.consumeWork(1)

      try appendRationalBezierSeamBreaks(
        coordinateControls: OriginalParameterQueryStorage.map(
          patch.controls, using: &execution, transform: { element, execution in element.y }),
        weightControls: OriginalParameterQueryStorage.map(
          patch.controls, using: &execution, transform: { element, execution in element.weight }),
        seam: seam,
        to: &breaks,
        workItemCount: &workItemCount,
        tolerance: tolerance, using: &execution
      )
    }
    return (try sortedUniqueFractions(breaks, using: &execution))
  }

  private func appendRationalBezierSeamBreaks(
    coordinateControls: [ScalarBounds],
    weightControls: [ScalarBounds],
    seam: Double,
    to breaks: inout [Double],
    workItemCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)

    let differences =
      (try OriginalParameterQueryStorage.map(
        coordinateControls.indices, using: &execution,
        transform: { index, execution in
          coordinateControls[index]
            - ScalarBounds.exact(seam) * weightControls[index]
        }))
    // A root is located no closer than the controls' own bounds (carried through the piece's
    // extraction) place the coordinate, so the slack is the larger of roundoff and that width.
    let minimumWeight =
      (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          weightControls, using: &execution, transform: { element, execution in element.lower }),
        using: &execution, projection: { element, _ in element }))?.lower ?? 0.0
    let inputUncertainty =
      minimumWeight > 0.0
      ? (try OriginalParameterQueryStorage.optionalMap(
        OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            differences, using: &execution,
            transform: { element, execution in element.upper - element.lower }
          ), using: &execution, projection: { element, _ in element })?.upper, using: &execution,
        { element, execution in element / minimumWeight })) ?? 0.0
      : 0.0
    let coordinateSlack = max(
      Double.ulpOfOne
        * max(1.0, abs(seam))
        * 128.0,
      2.0 * inputUncertainty
    )
    if (try rationalCoordinateResidual(
      differences: differences,
      weights: weightControls, using: &execution
    )) <= coordinateSlack {
      return
    }
    var pending =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [
          RationalSeamRootCell(
            differences: differences,
            weights: weightControls,
            lower: 0.0,
            upper: 1.0,
            depth: 0
          )
        ]
      })
    while let cell = pending.popLast() {
      try execution.consumeWork(1)

      try CurrentTaskCancellationChecker().checkCancellation()
      workItemCount += 1
      guard workItemCount <= maximumWorkItems else {
        throw resourceFailure(
          residual: Double(workItemCount),
          tolerance: tolerance,
          message: "Certified rational pcurve seam isolation exhausted its Bernstein-cell budget."
        )
      }
      let hullLower =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            cell.differences, using: &execution, transform: { element, execution in element.lower }),
          using: &execution, projection: { element, _ in element }))?.lower ?? -.infinity
      let hullUpper =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            cell.differences, using: &execution, transform: { element, execution in element.upper }),
          using: &execution, projection: { element, _ in element }))?.upper ?? .infinity
      if hullLower > 0.0 || hullUpper < 0.0 {
        continue
      }
      // A root at an end of the cell (a pcurve piece starting on the seam itself) leaves its
      // end control on the seam; when every other control keeps one strict side, no root lies
      // inside, and the end is a break already or is recorded as one.
      if let first = cell.differences.first, let last = cell.differences.last,
        cell.differences.count > 2
      {
        func onSeam(
          _ value: ScalarBounds, _ weight: ScalarBounds,
          using execution: inout OriginalQueryExecution
        ) throws -> Bool {
          try execution.consumeWork(1)
          return

            value.lower >= -coordinateSlack * weight.upper
            && value.upper <= coordinateSlack * weight.upper
        }
        let (startOn, endOn) = (
          (try onSeam(first, cell.weights[0], using: &execution)),
          (try onSeam(last, cell.weights[cell.weights.count - 1], using: &execution))
        )
        let rest =
          (try OriginalParameterQueryStorage.map(
            OriginalParameterQueryStorage.filter(
              cell.differences.indices, using: &execution,
              predicate: { index, execution in
                !(index == 0 && startOn) && !(index == cell.differences.count - 1 && endOn)
              }), using: &execution, transform: { element, execution in cell.differences[element] }))
        if startOn || endOn, rest.isEmpty == false,
          try OriginalParameterQueryStorage.allSatisfy(
            rest, using: &execution, predicate: { element, execution in element.lower > 0.0 })
            || OriginalParameterQueryStorage.allSatisfy(
              rest, using: &execution, predicate: { element, execution in element.upper < 0.0 })
        {
          if startOn, cell.lower > 0.0 {
            (try OriginalParameterQueryStorage.append(cell.lower, to: &breaks, using: &execution))
          }
          if endOn, cell.upper < 1.0 {
            (try OriginalParameterQueryStorage.append(cell.upper, to: &breaks, using: &execution))
          }
          continue
        }
      }
      let residual =
        (try rationalCoordinateResidual(
          differences: cell.differences,
          weights: cell.weights, using: &execution
        ))
      if residual <= coordinateSlack {
        if cell.lower > 0.0 {
          (try OriginalParameterQueryStorage.append(cell.lower, to: &breaks, using: &execution))
        }
        if cell.upper < 1.0 {
          (try OriginalParameterQueryStorage.append(cell.upper, to: &breaks, using: &execution))
        }
        continue
      }
      if cell.depth >= min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) {
        // These boundaries preserve the entire unresolved closed band as a partition
        // interval. They certify neither a root nor endpoint equality. Original jets
        // and all owning surface spans must still enclose its complete flux measure
        // under rationalSurfaceExplicitBounds's unchanged requested-width acceptance.
        if cell.lower > 0.0 {
          (try OriginalParameterQueryStorage.append(cell.lower, to: &breaks, using: &execution))
        }
        if cell.upper < 1.0 {
          (try OriginalParameterQueryStorage.append(cell.upper, to: &breaks, using: &execution))
        }
        continue
      }
      let differenceChildren =
        (try subdividedBernsteinControls(cell.differences, using: &execution))
      let weightChildren = (try subdividedBernsteinControls(cell.weights, using: &execution))
      let middle = cell.lower + (cell.upper - cell.lower) * 0.5
      (try OriginalParameterQueryStorage.append(
        RationalSeamRootCell(
          differences: differenceChildren.upper,
          weights: weightChildren.upper,
          lower: middle,
          upper: cell.upper,
          depth: cell.depth + 1
        ), to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        RationalSeamRootCell(
          differences: differenceChildren.lower,
          weights: weightChildren.lower,
          lower: cell.lower,
          upper: middle,
          depth: cell.depth + 1
        ), to: &pending, using: &execution))
    }
  }

  private func rationalCoordinateResidual(
    differences: [ScalarBounds],
    weights: [ScalarBounds], using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    let numerator =
      (try OriginalParameterQueryStorage.reduce(
        differences, initial: 0.0, using: &execution,
        combine: { partial, value, execution in
          max(partial, abs(value.lower), abs(value.upper))
        }))
    let denominator =
      (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          weights, using: &execution, transform: { element, execution in element.lower }),
        using: &execution, projection: { element, _ in element }))?.lower
      ?? 0.0
    guard numerator.isFinite,
      denominator.isFinite,
      denominator > 0.0
    else {
      return .infinity
    }
    return (numerator / denominator).nextUp
  }

  private func subdividedBernsteinControls(
    _ controls: [ScalarBounds], using execution: inout OriginalQueryExecution
  ) throws -> (lower: [ScalarBounds], upper: [ScalarBounds]) {
    try execution.consumeWork(1)

    var levels =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [controls]
      })
    let half = ScalarBounds.exact(0.5)
    while let previous = levels.last, previous.count > 1 {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(
        OriginalParameterQueryStorage.map(
          (0..<(previous.count - 1)), using: &execution,
          transform: { index, execution in
            previous[index] * half + previous[index + 1] * half
          }), to: &levels, using: &execution))
    }
    return (
      (try OriginalParameterQueryStorage.map(
        levels, using: &execution, transform: { element, execution in element[0] })),
      (try OriginalParameterQueryStorage.map(
        levels.reversed(), using: &execution,
        transform: { element, execution in element[element.count - 1] }))
    )
  }

  private func sortedUniqueFractions(
    _ fractions: [Double], using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    let ordered = (try OriginalParameterQueryStorage.ordered(fractions, using: &execution, less: <))
    var result: [Double] = []
    try OriginalParameterQueryStorage.reserve(ordered.count, in: &result, using: &execution)
    for fraction in ordered {
      try execution.consumeWork(1)

      if result.last != fraction {
        (try OriginalParameterQueryStorage.append(fraction, to: &result, using: &execution))
      }
    }
    return result
  }

  private func interiorSeams(
    _ spans: [CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan],
    using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    guard
      let lower =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            spans, using: &execution, transform: { element, execution in element.lower }),
          using: &execution, projection: { element, _ in element }))?.lower,
      let upper =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            spans, using: &execution, transform: { element, execution in element.upper }),
          using: &execution, projection: { element, _ in element }))?.upper
    else {
      return []
    }
    return
      (try OriginalParameterQueryStorage.ordered(
        OriginalParameterQueryStorage.filter(
          OriginalParameterQueryStorage.materialize(
            OriginalParameterQueryStorage.set(
              OriginalParameterQueryStorage.flatMap(
                spans, using: &execution,
                { element, execution in
                  (try OriginalParameterQueryStorage.values(count: 2, using: &execution) {
                    execution in
                    [element.lower, element.upper]
                  })
                }), using: &execution), using: &execution), using: &execution,
          predicate: { element, execution in element > lower && element < upper }),
        using: &execution, less: <))
  }

  private func piecewiseRationalSurfaceGaussEnclosure(
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    lambdaLower: Double,
    lambdaUpper: Double,
    curveLower: Double,
    curveUpper: Double,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> PiecewiseRationalEnclosure {
    try execution.consumeWork(1)

    let curve = try parameterEvaluator(
      .variable(Interval(lower: curveLower, upper: curveUpper), using: &execution), &execution)
    guard
      let vSpan =
        (try field.strictlyContainingVSpan(
          curve.v.coefficients[0], using: &execution
        ))
    else {
      return .seamEnclosed(
        try rationalSurfaceSeamEnclosure(
          field: field,
          uBase: uBase,
          lambdaLower: lambdaLower,
          lambdaUpper: lambdaUpper,
          curveLower: curveLower,
          curveUpper: curveUpper,
          curve: curve,
          parameterEvaluator: parameterEvaluator,
          tolerance: tolerance, using: &execution
        ))
    }
    let uRange = curve.u.coefficients[0]
    var result = Interval.exact(0.0)
    var lambdaError = 0.0
    var curveError = 0.0
    for uSpan in field.uSpans where uSpan.upper > uBase {
      try execution.consumeWork(1)

      let localLower = max(uBase, uSpan.lower)
      guard uSpan.upper > localLower else { continue }
      if uRange.upper <= localLower {
        continue
      }
      let isFull = uRange.lower >= uSpan.upper
      let isPartial =
        uRange.lower >= localLower
        && uRange.upper <= uSpan.upper
      guard isFull || isPartial else {
        return .seamEnclosed(
          try rationalSurfaceSeamEnclosure(
            field: field,
            uBase: uBase,
            lambdaLower: lambdaLower,
            lambdaUpper: lambdaUpper,
            curveLower: curveLower,
            curveUpper: curveUpper,
            curve: curve,
            parameterEvaluator: parameterEvaluator,
            tolerance: tolerance, using: &execution
          ))
      }
      let enclosure = try rationalSurfaceGaussEnclosure(
        field: field,
        uBase: localLower,
        surfaceUSpan: uSpan,
        surfaceVSpan: vSpan,
        lambdaLower: lambdaLower,
        lambdaUpper: lambdaUpper,
        curveLower: curveLower,
        curveUpper: curveUpper,
        parameterEvaluator: { fraction, execution in
          let parameters = try parameterEvaluator(fraction, &execution)
          return (
            isFull ? (try .constant(uSpan.upper, using: &execution)) : parameters.u,
            parameters.v
          )
        },
        tolerance: tolerance, using: &execution
      )
      result = result + enclosure.bounds
      lambdaError = (lambdaError + enclosure.lambdaError).nextUp
      curveError = (curveError + enclosure.curveError).nextUp
    }
    return
      .enclosed(
        TensorGaussEnclosure(
          bounds: result,
          lambdaError: lambdaError,
          curveError: curveError
        ))
  }

  private func rationalSurfaceSeamEnclosure(
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    lambdaLower: Double,
    lambdaUpper: Double,
    curveLower: Double,
    curveUpper: Double,
    curve: (u: Jet, v: Jet),
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SeamEnclosure {
    try execution.consumeWork(1)

    guard
      let uLower =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            field.uSpans, using: &execution, transform: { element, execution in element.lower }),
          using: &execution, projection: { element, _ in element }))?.lower,
      let uUpper =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            field.uSpans, using: &execution, transform: { element, execution in element.upper }),
          using: &execution, projection: { element, _ in element }))?.upper,
      let vLower =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            field.vSpans, using: &execution, transform: { element, execution in element.lower }),
          using: &execution, projection: { element, _ in element }))?.lower,
      let vUpper =
        (try OriginalParameterQueryStorage.extrema(
          OriginalParameterQueryStorage.map(
            field.vSpans, using: &execution, transform: { element, execution in element.upper }),
          using: &execution, projection: { element, _ in element }))?.upper
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Certified rational pcurve seam enclosure found no extracted surface span."
      )
    }
    let rawURange = curve.u.coefficients[0]
    let rawVRange = curve.v.coefficients[0]
    let uScale = max(1.0, abs(uLower), abs(uUpper))
    let vScale = max(1.0, abs(vLower), abs(vUpper))
    let uSlack = Double.ulpOfOne * uScale * 4_096.0
    let vSlack = Double.ulpOfOne * vScale * 4_096.0
    guard rawURange.lower >= uLower - uSlack,
      rawURange.upper <= uUpper + uSlack,
      rawVRange.lower >= vLower - vSlack,
      rawVRange.upper <= vUpper + vSlack,
      uBase >= uLower,
      uBase <= uUpper
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Certified rational pcurve seam enclosure left the extracted surface domain."
      )
    }
    let uRange = Interval(
      lower: max(uLower, rawURange.lower),
      upper: min(uUpper, rawURange.upper)
    )
    let vRange = Interval(
      lower: max(vLower, rawVRange.lower),
      upper: min(vUpper, rawVRange.upper)
    )
    let lambda = Interval(
      lower: lambdaLower,
      upper: lambdaUpper
    )
    let derivativeV = (try curve.v.derivative(using: &execution)).coefficients[0]
    var integrand = Interval.exact(0.0)
    for uSpan in field.uSpans where uSpan.upper > uBase {
      try execution.consumeWork(1)

      let localLower = max(uBase, uSpan.lower)
      guard uSpan.upper > localLower else { continue }
      let endpointLower = min(
        uSpan.upper,
        max(localLower, uRange.lower)
      )
      let endpointUpper = min(
        uSpan.upper,
        max(localLower, uRange.upper)
      )
      let deltaU =
        Interval(
          lower: endpointLower,
          upper: endpointUpper
        ) - .exact(localLower)
      guard deltaU.upper > 0.0 else { continue }
      let mappedU = Interval.exact(localLower) + lambda * deltaU
      let flux = try field.bounds(
        uLower: mappedU.lower,
        uUpper: mappedU.upper,
        vLower: vRange.lower,
        vUpper: vRange.upper, using: &execution
      )
      integrand =
        integrand
        + Interval(lower: flux.lower, upper: flux.upper)
        * deltaU
        * derivativeV
    }
    let measure =
      Interval.floating(lambdaUpper - lambdaLower)
      * .floating(curveUpper - curveLower)
    let result = integrand * measure
    guard result.lower.isFinite, result.upper.isFinite else {
      throw resourceFailure(
        residual: result.width,
        tolerance: tolerance,
        message: "Certified rational pcurve seam enclosure exceeded finite arithmetic."
      )
    }
    return SeamEnclosure(
      bounds: result,
      splitLocation: try seamSplitLocation(
        field: field,
        curveLower: curveLower,
        curveUpper: curveUpper,
        parameterEvaluator: parameterEvaluator, using: &execution
      )
    )
  }

  private func seamSplitLocation(
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    curveLower: Double,
    curveUpper: Double,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    using execution: inout OriginalQueryExecution
  ) throws -> SeamSplitLocation {
    try execution.consumeWork(1)

    let lower = try parameterEvaluator(.variable(.exact(curveLower), using: &execution), &execution)
    let upper = try parameterEvaluator(.variable(.exact(curveUpper), using: &execution), &execution)
    let uSeams = (try interiorSeams(field.uSpans, using: &execution))
    let vSeams = (try interiorSeams(field.vSpans, using: &execution))
    let lowerDistance =
      (try minimumSeamDistance(
        u: lower.u.coefficients[0],
        v: lower.v.coefficients[0],
        uSeams: uSeams,
        vSeams: vSeams, using: &execution
      ))
    let upperDistance =
      (try minimumSeamDistance(
        u: upper.u.coefficients[0],
        v: upper.v.coefficients[0],
        uSeams: uSeams,
        vSeams: vSeams, using: &execution
      ))
    if lowerDistance < upperDistance * 0.5 { return .lower }
    if upperDistance < lowerDistance * 0.5 { return .upper }
    return .balanced
  }

  private func minimumSeamDistance(
    u: Interval,
    v: Interval,
    uSeams: [Double],
    vSeams: [Double], using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    let uDistance =
      (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          uSeams, using: &execution,
          transform: { element, execution in
            (try intervalDistance(u, to: element, using: &execution))
          }), using: &execution, projection: { element, _ in element }))?.lower
      ?? .infinity
    let vDistance =
      (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          vSeams, using: &execution,
          transform: { element, execution in
            (try intervalDistance(v, to: element, using: &execution))
          }), using: &execution, projection: { element, _ in element }))?.lower
      ?? .infinity
    return min(uDistance, vDistance)
  }

  private func intervalDistance(
    _ interval: Interval, to value: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    if interval.lower <= value, interval.upper >= value { return 0.0 }
    return min(abs(interval.lower - value), abs(interval.upper - value))
  }

  private func rationalSurfaceGaussEnclosure(
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    surfaceUSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
    surfaceVSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
    lambdaLower: Double,
    lambdaUpper: Double,
    curveLower: Double,
    curveUpper: Double,
    parameterEvaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> TensorGaussEnclosure {
    try execution.consumeWork(1)

    let lambdaMidpoint = lambdaLower + (lambdaUpper - lambdaLower) * 0.5
    let curveMidpoint = curveLower + (curveUpper - curveLower) * 0.5
    let lambdaHalfSpan = (lambdaUpper - lambdaLower) * 0.5
    let curveHalfSpan = (curveUpper - curveLower) * 0.5
    let root = sqrt(3.0 / 5.0)
    let displacements =
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [-root, 0.0, root]
      })
    let weights =
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
      })
    var estimate = Interval.exact(0.0)
    for lambdaIndex in displacements.indices {
      try execution.consumeWork(1)

      let lambda =
        lambdaMidpoint
        + lambdaHalfSpan * displacements[lambdaIndex]
      for curveIndex in displacements.indices {
        try execution.consumeWork(1)

        let curveParameter =
          curveMidpoint
          + curveHalfSpan * displacements[curveIndex]
        let curve = try parameterEvaluator(
          .variable(.exact(curveParameter), using: &execution), &execution)
        let u = curve.u.coefficients[0]
        let v = curve.v.coefficients[0]
        let deltaU = u - .exact(uBase)
        let mappedU = Interval.exact(uBase) + .floating(lambda) * deltaU
        let flux = try field.bounds(
          u: mappedU,
          v: v,
          uSpan: surfaceUSpan,
          vSpan: surfaceVSpan, using: &execution
        )
        estimate =
          estimate
          + Interval(lower: flux.lower, upper: flux.upper)
          * deltaU
          * (try curve.v.derivative(using: &execution)).coefficients[0]
          * .floating(weights[lambdaIndex] * weights[curveIndex])
      }
    }
    estimate = estimate * .floating(lambdaHalfSpan * curveHalfSpan)

    let curve = try parameterEvaluator(
      .variable(Interval(lower: curveLower, upper: curveUpper), using: &execution), &execution)
    let lambdaSurfaceFlux: CertifiedUnivariateTaylorJet
    let curveSurfaceFlux: CertifiedUnivariateTaylorJet
    let lambdaDeltaU =
      (try CertifiedUnivariateTaylorJet.constant(
        curve.u.coefficients[0] - .exact(uBase), using: &execution
      ))
    let lambdaJet =
      (try CertifiedUnivariateTaylorJet.variable(
        Interval(lower: lambdaLower, upper: lambdaUpper), using: &execution
      ))
    let lambdaMappedU =
      (try CertifiedUnivariateTaylorJet.constant(uBase, using: &execution).adding(
        lambdaJet.multiplied(by: lambdaDeltaU, using: &execution), using: &execution))
    let constantV =
      (try CertifiedUnivariateTaylorJet.constant(curve.v.coefficients[0], using: &execution))
    let curveU = (try CertifiedUnivariateTaylorJet.series(curve.u.coefficients, using: &execution))
    let curveV = (try CertifiedUnivariateTaylorJet.series(curve.v.coefficients, using: &execution))
    let curveDeltaU =
      (try curveU.subtracting(.constant(uBase, using: &execution), using: &execution))
    let curveMappedU =
      (try CertifiedUnivariateTaylorJet.constant(uBase, using: &execution).adding(
        CertifiedUnivariateTaylorJet.constant(
          Interval(lower: lambdaLower, upper: lambdaUpper), using: &execution
        ).multiplied(by: curveDeltaU, using: &execution), using: &execution))
    do {
      let certifiedLambda = try field.directionalFluxJet(
        u: lambdaMappedU,
        v: constantV,
        uSpan: surfaceUSpan,
        vSpan: surfaceVSpan, using: &execution
      )
      let certifiedCurve = try field.directionalFluxJet(
        u: curveMappedU,
        v: curveV,
        uSpan: surfaceUSpan,
        vSpan: surfaceVSpan, using: &execution
      )
      lambdaSurfaceFlux = certifiedLambda
      curveSurfaceFlux = certifiedCurve
    } catch let error as KernelError where error.code == .singularSystem {
      throw error
    }
    let lambdaIntegrand =
      (try lambdaSurfaceFlux.multiplied(by: lambdaDeltaU, using: &execution).multiplied(
        by: .constant(curve.v.derivative(using: &execution).coefficients[0], using: &execution),
        using: &execution))
    let curveIntegrand =
      (try curveSurfaceFlux.multiplied(by: curveDeltaU, using: &execution).multiplied(
        by: curveV.derivative(using: &execution), using: &execution))
    let lambdaSixthCoefficient = lambdaIntegrand.coefficients[6].maximumAbsolute
    let curveSixthCoefficient = curveIntegrand.coefficients[6].maximumAbsolute
    let lambdaSixthDerivative =
      (try outwardProduct(lambdaSixthCoefficient, 720.0, using: &execution))
    let curveSixthDerivative = (try outwardProduct(curveSixthCoefficient, 720.0, using: &execution))
    let gaussConstant = 1_296.0 / (7.0 * 720.0 * 720.0 * 720.0)
    let lambdaSpan = lambdaUpper - lambdaLower
    let curveSpan = curveUpper - curveLower
    let lambdaError =
      (try outwardProduct(
        outwardProduct(lambdaSixthDerivative, gaussConstant, using: &execution),
        pow(lambdaSpan, 7.0) * curveSpan, using: &execution
      ))
    let curveError =
      (try outwardProduct(
        outwardProduct(curveSixthDerivative, gaussConstant, using: &execution),
        pow(curveSpan, 7.0) * lambdaSpan, using: &execution
      ))
    var error = (lambdaError + curveError).nextUp
    for _ in 0..<8 {
      try execution.consumeWork(1)
      error = error.nextUp
    }
    guard estimate.lower.isFinite,
      estimate.upper.isFinite,
      error.isFinite
    else {
      throw resourceFailure(
        residual: error,
        tolerance: tolerance,
        message: "Certified rational pcurve tensor-Gauss enclosure exceeded finite arithmetic."
      )
    }
    return TensorGaussEnclosure(
      bounds: Interval(
        lower: (estimate.lower - error).nextDown,
        upper: (estimate.upper + error).nextUp
      ),
      lambdaError: lambdaError,
      curveError: curveError
    )
  }

  private func rationalSurfaceImplicitBounds(
    curve: CertifiedImplicitSurfaceParameterCurve,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let implicit = curve.intersection
    try implicit.validate(tolerance: tolerance, using: &execution)
    if let planar = try field.exactPlanarAffineFluxTraversal(for: curve, using: &execution) {
      let scale = Interval(
        lower: planar.fluxScale.lower,
        upper: planar.fluxScale.upper
      )
      let scaleMagnitude = scale.maximumAbsolute
      guard scaleMagnitude.isFinite else {
        throw resourceFailure(
          residual: scaleMagnitude,
          tolerance: tolerance,
          message: "Certified planar affine flux lost its finite scale."
        )
      }
      let patches =
        (try OriginalParameterQueryStorage.map(
          planar.patches, using: &execution,
          transform: { patch, execution in
            HomogeneousPatch(
              controls: (try OriginalParameterQueryStorage.map(
                patch.controls, using: &execution,
                transform: { control, execution in
                  HomogeneousPatch.HomogeneousPoint(
                    x: ScalarBounds(
                      lower: control.x.lower,
                      upper: control.x.upper
                    ),
                    y: ScalarBounds(
                      lower: control.y.lower,
                      upper: control.y.upper
                    ),
                    weight: ScalarBounds(
                      lower: control.weight.lower,
                      upper: control.weight.upper
                    )
                  )
                })),
              lower: 0.0,
              upper: 1.0
            )
          }))
      let areaWidth = requestedWidth / max(scaleMagnitude * 4.0, 1.0)
      let area = try parameterAreaBounds(
        for: patches,
        requestedWidth: areaWidth,
        tolerance: tolerance, using: &execution
      )
      let result =
        scale
        * Interval(
          lower: area.lower,
          upper: area.upper
        )
      guard result.width <= requestedWidth else {
        throw resourceFailure(
          residual: result.width,
          tolerance: tolerance,
          message: "Certified planar affine flux exceeded its requested enclosure width."
        )
      }
      return result
    }
    let uCoordinate: SurfaceIntersectionParameterCoordinate =
      curve.role == .first
      ? .firstU
      : .secondU
    let vCoordinate: SurfaceIntersectionParameterCoordinate =
      curve.role == .first
      ? .firstV
      : .secondV
    let traversalSegments = try curve.canonicalTraversalSegments(
      tolerance: tolerance, using: &execution
    )
    let requestedSpan = abs(curve.endFraction - curve.startFraction)
    guard !implicit.cells.isEmpty,
      requestedSpan > tolerance.relative
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified implicit rational pcurve flux requires a nonempty graph traversal."
      )
    }
    let implicitJetEncloser = try ImplicitCurveIntervalJetEncloser(
      intersection: implicit,
      tolerance: tolerance, using: &execution
    )
    struct WorkItem {
      let cell: CertifiedImplicitIntersectionGraphCell
      let cellIndex: Int
      let curveLower: Double
      let curveUpper: Double
      let lambdaLower: Double
      let lambdaUpper: Double
      let orientationMultiplier: Double
      let depth: Int
      let enclosure: Interval
      let rangeWidth: Double
      let midpointWidth: Double?

      var width: Double { enclosure.width }
    }
    let cellCount = implicit.cells.count
    func makeItem(
      cell: CertifiedImplicitIntersectionGraphCell,
      cellIndex: Int,
      curveLower: Double,
      curveUpper: Double,
      lambdaLower: Double,
      lambdaUpper: Double,
      orientationMultiplier: Double,
      depth: Int, using execution: inout OriginalQueryExecution
    ) throws -> WorkItem {
      try execution.consumeWork(1)

      let subcell = try implicitJetEncloser.restrictedBounds(
        of: implicit,
        cellIndex: cellIndex,
        fromNormalizedFraction: curveLower,
        toNormalizedFraction: curveUpper,
        tolerance: tolerance, using: &execution
      )
      let u =
        (try interval(
          subcell.parameterBox.interval(for: uCoordinate), using: &execution))
      let v =
        (try interval(
          subcell.parameterBox.interval(for: vCoordinate), using: &execution))
      let vDerivative =
        (try interval(
          subcell.parameterDerivativeBounds[vCoordinate.rawValue], using: &execution
        ))
      let deltaU = u - .exact(uBase)
      let lambda = Interval(
        lower: lambdaLower,
        upper: lambdaUpper
      )
      let mappedU = Interval.exact(uBase) + lambda * deltaU
      let flux = try field.bounds(
        uLower: mappedU.lower,
        uUpper: mappedU.upper,
        vLower: v.lower,
        vUpper: v.upper, using: &execution
      )
      let rangeEnclosure =
        Interval(lower: flux.lower, upper: flux.upper)
        * deltaU * vDerivative
        * .floating(
          (lambdaUpper - lambdaLower) * orientationMultiplier
        )
      let enclosure: Interval
      let midpointWidth: Double?
      let midpointEnclosure = try implicitRationalMidpointEnclosure(
        intersection: implicit,
        cellIndex: cellIndex,
        curveLower: curveLower,
        curveUpper: curveUpper,
        lambdaLower: lambdaLower,
        lambdaUpper: lambdaUpper,
        orientationMultiplier: orientationMultiplier,
        uCoordinate: uCoordinate,
        vCoordinate: vCoordinate,
        field: field,
        uBase: uBase,
        curveJetEncloser: implicitJetEncloser,
        tolerance: tolerance, using: &execution
      )
      if let midpointEnclosure {
        let lower = max(
          rangeEnclosure.lower,
          midpointEnclosure.bounds.lower
        )
        let upper = min(
          rangeEnclosure.upper,
          midpointEnclosure.bounds.upper
        )
        guard lower <= upper else {
          throw resourceFailure(
            residual: lower - upper,
            tolerance: tolerance,
            message:
              "Certified implicit rational pcurve flux produced inconsistent independent enclosures."
          )
        }
        enclosure = Interval(lower: lower, upper: upper)
        midpointWidth = midpointEnclosure.bounds.width
      } else {
        enclosure = rangeEnclosure
        midpointWidth = nil
      }
      guard enclosure.lower.isFinite, enclosure.upper.isFinite else {
        throw resourceFailure(
          residual: enclosure.width,
          tolerance: tolerance,
          message: "Certified implicit rational pcurve flux exceeded finite interval arithmetic."
        )
      }
      return WorkItem(
        cell: cell,
        cellIndex: cellIndex,
        curveLower: curveLower,
        curveUpper: curveUpper,
        lambdaLower: lambdaLower,
        lambdaUpper: lambdaUpper,
        orientationMultiplier: orientationMultiplier,
        depth: depth,
        enclosure: enclosure,
        rangeWidth: rangeEnclosure.width,
        midpointWidth: midpointWidth
      )
    }

    var heap: [WorkItem] = []
    func push(_ item: WorkItem, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(item, to: &heap, using: &execution))
      var index = heap.count - 1
      while index > 0 {
        try execution.consumeWork(1)

        let parent = (index - 1) / 2
        guard heap[index].width > heap[parent].width else { break }
        heap.swapAt(index, parent)
        index = parent
      }
    }
    func popMaximum(using execution: inout OriginalQueryExecution) throws -> WorkItem? {
      try execution.consumeWork(1)

      guard !heap.isEmpty else { return nil }
      if heap.count == 1 { return heap.removeLast() }
      let result = heap[0]
      heap[0] = heap.removeLast()
      var index = 0
      while true {
        try execution.consumeWork(1)

        let left = index * 2 + 1
        let right = left + 1
        var largest = index
        if left < heap.count, heap[left].width > heap[largest].width {
          largest = left
        }
        if right < heap.count, heap[right].width > heap[largest].width {
          largest = right
        }
        guard largest != index else { break }
        heap.swapAt(index, largest)
        index = largest
      }
      return result
    }
    func accumulatedBounds(using execution: inout OriginalQueryExecution) throws -> Interval {
      try execution.consumeWork(1)
      return

        (try OriginalParameterQueryStorage.reduce(
          heap, initial: Interval.exact(0.0), using: &execution,
          combine: { partial, element, execution in partial + element.enclosure }))
    }

    for traversal in traversalSegments {
      try execution.consumeWork(1)

      for (index, cell) in implicit.cells.enumerated() {
        try execution.consumeWork(1)

        let cellStart = Double(index) / Double(cellCount)
        let cellEnd = Double(index + 1) / Double(cellCount)
        let overlapStart = max(traversal.canonicalLowerFraction, cellStart)
        let overlapEnd = min(traversal.canonicalUpperFraction, cellEnd)
        guard overlapEnd > overlapStart else { continue }
        (try push(
          makeItem(
            cell: cell,
            cellIndex: index,
            curveLower: (overlapStart - cellStart) * Double(cellCount),
            curveUpper: (overlapEnd - cellStart) * Double(cellCount),
            lambdaLower: 0.0,
            lambdaUpper: 1.0,
            orientationMultiplier: traversal.orientationMultiplier,
            depth: 0, using: &execution
          ), using: &execution))
      }
    }
    guard !heap.isEmpty else {
      throw resourceFailure(
        residual: 0.0,
        tolerance: tolerance,
        message: "Certified implicit rational pcurve flux found no active traversal cell."
      )
    }

    var workItemCount = heap.count
    var activeWidth =
      (try OriginalParameterQueryStorage.reduce(
        heap, initial: 0.0, using: &execution,
        combine: { partial, element, execution in
          (partial + element.enclosure.width).nextUp
        }))
    while true {
      try execution.consumeWork(1)

      if activeWidth <= requestedWidth {
        let result = (try accumulatedBounds(using: &execution))
        if result.width <= requestedWidth {
          return result
        }
        activeWidth = result.width
      }
      guard let item = (try popMaximum(using: &execution)) else {
        throw resourceFailure(
          residual: nil,
          tolerance: tolerance,
          message: "Certified implicit rational pcurve flux lost its active proof cells."
        )
      }
      try execution.visitGeometricCell(depth: item.depth)

      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw resourceFailure(
          residual: item.enclosure.width,
          tolerance: tolerance,
          message: "Certified implicit rational pcurve flux exceeded its proof depth."
        )
      }
      workItemCount += 2
      guard workItemCount <= maximumWorkItems else {
        throw resourceFailure(
          residual: activeWidth,
          tolerance: tolerance,
          message:
            "Certified implicit rational pcurve flux exhausted its \(maximumWorkItems)-cell budget; widest cell index \(item.cellIndex), local curve [\(item.curveLower), \(item.curveUpper)], depth \(item.depth), lambda [\(item.lambdaLower), \(item.lambdaUpper)], width \(item.width), range width \(item.rangeWidth), midpoint width \((try analyticFluxOptionalDiagnostic(item.midpointWidth, using: &execution)))."
        )
      }
      let curveSpan = item.curveUpper - item.curveLower
      let lambdaSpan = item.lambdaUpper - item.lambdaLower
      let canSplitCurve =
        curveSpan > tolerance.relative * 2.0
        && item.curveLower + curveSpan * 0.5 > item.curveLower
        && item.curveLower + curveSpan * 0.5 < item.curveUpper
      let canSplitLambda =
        lambdaSpan > tolerance.relative * 2.0
        && item.lambdaLower + lambdaSpan * 0.5 > item.lambdaLower
        && item.lambdaLower + lambdaSpan * 0.5 < item.lambdaUpper
      guard canSplitCurve || canSplitLambda else {
        throw resourceFailure(
          residual: item.enclosure.width,
          tolerance: tolerance,
          message:
            "Certified implicit rational pcurve flux subdivision reached parameter resolution."
        )
      }
      if canSplitCurve,
        item.depth.isMultiple(of: 2) || !canSplitLambda
      {
        let middle = item.curveLower + curveSpan * 0.5
        let upper = try makeItem(
          cell: item.cell,
          cellIndex: item.cellIndex,
          curveLower: middle,
          curveUpper: item.curveUpper,
          lambdaLower: item.lambdaLower,
          lambdaUpper: item.lambdaUpper,
          orientationMultiplier: item.orientationMultiplier,
          depth: item.depth + 1, using: &execution
        )
        let lower = try makeItem(
          cell: item.cell,
          cellIndex: item.cellIndex,
          curveLower: item.curveLower,
          curveUpper: middle,
          lambdaLower: item.lambdaLower,
          lambdaUpper: item.lambdaUpper,
          orientationMultiplier: item.orientationMultiplier,
          depth: item.depth + 1, using: &execution
        )
        (try push(upper, using: &execution))
        (try push(lower, using: &execution))
        activeWidth = max(0.0, activeWidth - item.width)
        activeWidth = (activeWidth + upper.width + lower.width).nextUp
      } else {
        let middle =
          item.lambdaLower
          + lambdaSpan * 0.5
        let upper = try makeItem(
          cell: item.cell,
          cellIndex: item.cellIndex,
          curveLower: item.curveLower,
          curveUpper: item.curveUpper,
          lambdaLower: middle,
          lambdaUpper: item.lambdaUpper,
          orientationMultiplier: item.orientationMultiplier,
          depth: item.depth + 1, using: &execution
        )
        let lower = try makeItem(
          cell: item.cell,
          cellIndex: item.cellIndex,
          curveLower: item.curveLower,
          curveUpper: item.curveUpper,
          lambdaLower: item.lambdaLower,
          lambdaUpper: middle,
          orientationMultiplier: item.orientationMultiplier,
          depth: item.depth + 1, using: &execution
        )
        (try push(upper, using: &execution))
        (try push(lower, using: &execution))
        activeWidth = max(0.0, activeWidth - item.width)
        activeWidth = (activeWidth + upper.width + lower.width).nextUp
      }
    }
  }

  private func implicitRationalMidpointEnclosure(
    intersection: CertifiedImplicitIntersectionCurve,
    cellIndex: Int,
    curveLower: Double,
    curveUpper: Double,
    lambdaLower: Double,
    lambdaUpper: Double,
    orientationMultiplier: Double,
    uCoordinate: SurfaceIntersectionParameterCoordinate,
    vCoordinate: SurfaceIntersectionParameterCoordinate,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    uBase: Double,
    curveJetEncloser: ImplicitCurveIntervalJetEncloser,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ImplicitMidpointEnclosure? {
    try execution.consumeWork(1)

    let cellCount = Double(intersection.cells.count)
    let localSpan = curveUpper - curveLower
    let lambdaSpan = lambdaUpper - lambdaLower
    guard cellCount > 0.0,
      localSpan > tolerance.relative * 4.0,
      localSpan <= 1.0 / 16.0,
      lambdaSpan > 0.0
    else {
      return nil
    }
    let globalLower = (Double(cellIndex) + curveLower) / cellCount
    let globalUpper = (Double(cellIndex) + curveUpper) / cellCount
    let globalSpan = globalUpper - globalLower
    let globalInterval = try ScalarInterval(
      lower: globalLower,
      upper: globalUpper
    )
    let parameterJet = try curveJetEncloser.parameterIntervalJet(
      of: intersection,
      over: globalInterval,
      tolerance: tolerance, using: &execution
    )
    let uCoordinateJet = parameterJet[uCoordinate]
    let vCoordinateJet = parameterJet[vCoordinate]
    let u = (try interval(uCoordinateJet.value, using: &execution))
    let uFirst = (try interval(uCoordinateJet.firstDerivative, using: &execution))
    let uSecond = (try interval(uCoordinateJet.secondDerivative, using: &execution))
    let v = (try interval(vCoordinateJet.value, using: &execution))
    let vFirst = (try interval(vCoordinateJet.firstDerivative, using: &execution))
    let vSecond = (try interval(vCoordinateJet.secondDerivative, using: &execution))
    let vThird = (try interval(vCoordinateJet.thirdDerivative, using: &execution))
    let deltaU = u - .exact(uBase)
    let lambda = Interval(lower: lambdaLower, upper: lambdaUpper)
    let mappedU = Interval.exact(uBase) + lambda * deltaU
    guard let uSpan = (try field.containingUSpan(mappedU, using: &execution)),
      let vSpan = (try field.containingVSpan(v, using: &execution))
    else {
      return nil
    }
    let partials = try field.secondOrderBounds(
      u: mappedU,
      v: v,
      uSpan: uSpan,
      vSpan: vSpan, using: &execution
    )
    let two = Interval.exact(2.0)
    let mappedUFirst = lambda * uFirst
    let mappedUSecond = lambda * uSecond
    let fluxFirst =
      partials.derivativeU * mappedUFirst
      + partials.derivativeV * vFirst
    let fluxSecond =
      partials.secondDerivativeUU
      * mappedUFirst * mappedUFirst
      + two * partials.secondDerivativeUV * mappedUFirst * vFirst
      + partials.secondDerivativeVV * vFirst * vFirst
      + partials.derivativeU * mappedUSecond
      + partials.derivativeV * vSecond
    let curveIntegrandSecond =
      fluxSecond * deltaU * vFirst
      + partials.value * uSecond * vFirst
      + partials.value * deltaU * vThird
      + two * fluxFirst * uFirst * vFirst
      + two * fluxFirst * deltaU * vSecond
      + two * partials.value * uFirst * vSecond
    let lambdaIntegrandSecond =
      partials.secondDerivativeUU
      * deltaU * deltaU * deltaU * vFirst
    let lambdaSecond = lambdaIntegrandSecond.maximumAbsolute
    let curveSecond = curveIntegrandSecond.maximumAbsolute
    let lambdaError =
      (try outwardProduct(
        outwardProduct(lambdaSecond, pow(lambdaSpan, 3.0), using: &execution),
        globalSpan / 24.0, using: &execution
      ))
    let curveError =
      (try outwardProduct(
        outwardProduct(curveSecond, pow(globalSpan, 3.0), using: &execution),
        lambdaSpan / 24.0, using: &execution
      ))
    let error = (lambdaError + curveError).nextUp
    guard error.isFinite else {
      throw resourceFailure(
        residual: error,
        tolerance: tolerance,
        message: "Certified implicit rational pcurve midpoint error exceeded finite arithmetic."
      )
    }

    let localMidpoint = curveLower + localSpan * 0.5
    let minimumHalfWidth = max(
      tolerance.relative * 2.0,
      Double.ulpOfOne * max(1.0, abs(localMidpoint)) * 4_096.0
    )
    let sampleHalfWidth = min(localSpan * 0.25, minimumHalfWidth)
    let sampleGlobalInterval = try ScalarInterval(
      lower: (Double(cellIndex) + localMidpoint - sampleHalfWidth) / cellCount,
      upper: (Double(cellIndex) + localMidpoint + sampleHalfWidth) / cellCount
    )
    let sampleJet = try curveJetEncloser.parameterIntervalJet(
      of: intersection,
      over: sampleGlobalInterval,
      tolerance: tolerance, using: &execution
    )
    let sampleU = (try interval(sampleJet[uCoordinate].value, using: &execution))
    let sampleV = (try interval(sampleJet[vCoordinate].value, using: &execution))
    let derivativeOffset = localSpan * 0.125
    let derivativeOffsetGlobal = derivativeOffset / cellCount
    let lowerDerivativeSample = try curveJetEncloser.parameterIntervalJet(
      of: intersection,
      over: ScalarInterval(
        lower: (Double(cellIndex) + localMidpoint - derivativeOffset
          - sampleHalfWidth) / cellCount,
        upper: (Double(cellIndex) + localMidpoint - derivativeOffset
          + sampleHalfWidth) / cellCount
      ),
      tolerance: tolerance, using: &execution
    )
    let upperDerivativeSample = try curveJetEncloser.parameterIntervalJet(
      of: intersection,
      over: ScalarInterval(
        lower: (Double(cellIndex) + localMidpoint + derivativeOffset
          - sampleHalfWidth) / cellCount,
        upper: (Double(cellIndex) + localMidpoint + derivativeOffset
          + sampleHalfWidth) / cellCount
      ),
      tolerance: tolerance, using: &execution
    )
    let derivativeSecant =
      ((try interval(upperDerivativeSample[vCoordinate].value, using: &execution))
        - (try interval(lowerDerivativeSample[vCoordinate].value, using: &execution)))
      / .floating(2.0 * derivativeOffsetGlobal)
    let derivativeRemainder =
      (try outwardProduct(
        vThird.maximumAbsolute,
        derivativeOffsetGlobal * derivativeOffsetGlobal / 6.0, using: &execution
      ))
    let sampleVDerivative =
      derivativeSecant
      + Interval(
        lower: (-derivativeRemainder).nextDown,
        upper: derivativeRemainder.nextUp
      )
    let sampleDeltaU = sampleU - .exact(uBase)
    let lambdaMidpoint = lambdaLower + lambdaSpan * 0.5
    let sampleMappedU =
      Interval.exact(uBase)
      + .floating(lambdaMidpoint) * sampleDeltaU
    let sampleFlux = try field.bounds(
      uLower: sampleMappedU.lower,
      uUpper: sampleMappedU.upper,
      vLower: sampleV.lower,
      vUpper: sampleV.upper, using: &execution
    )
    let estimate =
      Interval(
        lower: sampleFlux.lower,
        upper: sampleFlux.upper
      ) * sampleDeltaU * sampleVDerivative
      * .floating(lambdaSpan * globalSpan * orientationMultiplier)
    return ImplicitMidpointEnclosure(
      bounds: Interval(
        lower: (estimate.lower - error).nextDown,
        upper: (estimate.upper + error).nextUp
      )
    )
  }

  private func adaptiveJetBounds(
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    evaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> Jet,
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)
    return try adaptiveJetBoundsShared(
      requestedWidth: requestedWidth, tolerance: tolerance,
      evaluators: OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [evaluator]
      },
      using: &execution)
  }

  // Equal per-segment width splits starve segments whose integrand sits on
  // a square-root shoulder while tame segments waste their share, so all
  // segments refine against one shared width budget.
  private func adaptiveJetBoundsShared(
    requestedWidth: Double,
    tolerance: ModelingTolerance,
    evaluators: [(Jet, inout OriginalQueryExecution) throws -> Jet],
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    struct WorkItem {
      let segment: Int
      let lower: Double
      let upper: Double
      let depth: Int
      let enclosure: Interval?

      var width: Double {
        enclosure?.width ?? .infinity
      }
    }
    // Per-cell halving budgets shrink faster than a square-root
    // shoulder can converge, so the proof refines the globally widest
    // cell (singular cells first) until the summed enclosure width
    // meets the request.
    func makeItem(
      segment: Int,
      lower: Double,
      upper: Double,
      depth: Int, using execution: inout OriginalQueryExecution
    ) throws -> WorkItem {
      try execution.consumeWork(1)

      let enclosure = try gaussEnclosure(
        lower: lower,
        upper: upper,
        evaluator: evaluators[segment],
        tolerance: tolerance, using: &execution
      )
      if let enclosure {
        guard enclosure.lower.isFinite, enclosure.upper.isFinite else {
          throw resourceFailure(
            residual: enclosure.width,
            tolerance: tolerance,
            message: "Certified analytic pcurve flux exceeded finite interval arithmetic."
          )
        }
      }
      return WorkItem(
        segment: segment,
        lower: lower,
        upper: upper,
        depth: depth,
        enclosure: enclosure
      )
    }
    var heap: [WorkItem] = []
    func push(_ item: WorkItem, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(item, to: &heap, using: &execution))
      var index = heap.count - 1
      while index > 0 {
        try execution.consumeWork(1)

        let parent = (index - 1) / 2
        guard heap[index].width > heap[parent].width else { break }
        heap.swapAt(index, parent)
        index = parent
      }
    }
    func popMaximum(using execution: inout OriginalQueryExecution) throws -> WorkItem? {
      try execution.consumeWork(1)

      guard heap.isEmpty == false else { return nil }
      if heap.count == 1 { return heap.removeLast() }
      let top = heap[0]
      heap[0] = heap.removeLast()
      var index = 0
      while true {
        try execution.consumeWork(1)

        let left = index * 2 + 1
        let right = left + 1
        var largest = index
        if left < heap.count, heap[left].width > heap[largest].width {
          largest = left
        }
        if right < heap.count, heap[right].width > heap[largest].width {
          largest = right
        }
        guard largest != index else { break }
        heap.swapAt(index, largest)
        index = largest
      }
      return top
    }
    for segment in evaluators.indices {
      try execution.consumeWork(1)

      (try push(
        makeItem(
          segment: segment,
          lower: 0.0,
          upper: 1.0,
          depth: 0, using: &execution
        ), using: &execution))
    }
    var workItemCount = evaluators.count
    func recomputeTotals(using execution: inout OriginalQueryExecution) throws -> (
      finite: Double, singular: Int
    ) {
      try execution.consumeWork(1)

      var total = 0.0
      var singular = 0
      for item in heap {
        try execution.consumeWork(1)

        if let enclosure = item.enclosure {
          total = (total + enclosure.width).nextUp
        } else {
          singular += 1
        }
      }
      return (total, singular)
    }
    var totals = (try recomputeTotals(using: &execution))
    var subdivisionCount = 0
    while totals.singular > 0 || totals.finite > requestedWidth {
      try execution.consumeWork(1)

      guard let item = (try popMaximum(using: &execution)) else {
        throw resourceFailure(
          residual: totals.finite,
          tolerance: tolerance,
          message: "Certified analytic pcurve flux lost its active proof cells."
        )
      }
      try execution.visitGeometricCell(depth: item.depth)

      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw resourceFailure(
          residual: item.enclosure?.width,
          tolerance: tolerance,
          message: "Certified analytic pcurve flux exceeded its maximum proof depth."
        )
      }
      workItemCount += 2
      guard workItemCount <= max(maximumWorkItems, 1_048_576) else {
        let widest = heap.max { lhs, rhs in
          (lhs.enclosure?.width ?? Double.infinity)
            < (rhs.enclosure?.width ?? Double.infinity)
        }
        throw resourceFailure(
          residual: Double(workItemCount),
          tolerance: tolerance,
          message:
            "Certified analytic pcurve flux exhausted its subdivision budget. Finite width \(totals.finite) versus requested \(requestedWidth), singular cells \(totals.singular), widest cell segment \((try analyticFluxOptionalDiagnostic(widest?.segment, using: &execution))) range [\((try analyticFluxOptionalDiagnostic(widest?.lower, using: &execution))), \((try analyticFluxOptionalDiagnostic(widest?.upper, using: &execution)))] depth \((try analyticFluxOptionalDiagnostic(widest?.depth, using: &execution))) enclosure width \((try analyticFluxOptionalDiagnostic(widest?.enclosure?.width, using: &execution))), current item segment \(item.segment) range [\(item.lower), \(item.upper)] depth \(item.depth) enclosure \((try analyticFluxOptionalDiagnostic(item.enclosure?.width, using: &execution)))."
        )
      }
      let middle = item.lower + (item.upper - item.lower) * 0.5
      guard middle > item.lower, middle < item.upper else {
        throw resourceFailure(
          residual: item.enclosure?.width,
          tolerance: tolerance,
          message: "Certified analytic pcurve flux subdivision reached floating-point resolution."
        )
      }
      let left = try makeItem(
        segment: item.segment,
        lower: item.lower,
        upper: middle,
        depth: item.depth + 1, using: &execution
      )
      let right = try makeItem(
        segment: item.segment,
        lower: middle,
        upper: item.upper,
        depth: item.depth + 1, using: &execution
      )
      (try push(left, using: &execution))
      (try push(right, using: &execution))
      subdivisionCount += 1
      if subdivisionCount.isMultiple(of: 128) {
        totals = (try recomputeTotals(using: &execution))
      } else {
        if let popped = item.enclosure {
          totals.finite -= popped.width
        } else {
          totals.singular -= 1
        }
        for child
          in (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
            [left, right]
          })
        {
          try execution.consumeWork(1)

          if let enclosure = child.enclosure {
            totals.finite = (totals.finite + enclosure.width).nextUp
          } else {
            totals.singular += 1
          }
        }
        totals.finite = max(totals.finite, 0.0)
      }
    }
    var result = Interval.exact(0.0)
    for item in heap {
      try execution.consumeWork(1)

      guard let enclosure = item.enclosure else {
        throw resourceFailure(
          residual: nil,
          tolerance: tolerance,
          message: "Certified analytic pcurve flux retained an unresolved singular cell."
        )
      }
      result = result + enclosure
    }
    // Heap refinement order varies with traversal direction, so the
    // bounds are quantized outward onto a shared magnitude grid; this
    // keeps forward and reversed enclosures mutually containing while
    // only ever widening the certified result.
    // The ulp of a binade is a fixed power of two, so the grid is a
    // shared absolute step for every same-magnitude enclosure rather
    // than a magnitude-proportional step that quantization cancels.
    let grid =
      max(
        result.lower.ulp,
        result.upper.ulp,
        Double.leastNormalMagnitude
      ) * 64.0
    return Interval(
      lower: (result.lower / grid).rounded(.down) * grid,
      upper: (result.upper / grid).rounded(.up) * grid
    )
  }

  private func adaptiveParameterEnclosures(
    lowerFraction: Double,
    upperFraction: Double,
    maximumWidth: Double,
    tolerance: ModelingTolerance,
    evaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> (u: Jet, v: Jet),
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    try execution.consumeWork(1)

    struct WorkItem {
      let lower: Double
      let upper: Double
      let depth: Int
    }
    var pending =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [
          WorkItem(
            lower: lowerFraction,
            upper: upperFraction,
            depth: 0
          )
        ]
      })
    var result: [SurfaceParameterCurveEnclosure] = []
    var workItemCount = 0
    while let item = pending.popLast() {
      try execution.consumeWork(1)

      try execution.visitGeometricCell(depth: item.depth)
      workItemCount += 1
      guard workItemCount <= maximumWorkItems else {
        throw resourceFailure(
          residual: Double(workItemCount),
          tolerance: tolerance,
          message: "Certified analytic pcurve enclosure exhausted its cell budget."
        )
      }
      let ranges: (u: Interval, v: Interval)?
      do {
        let parameters = try evaluator(
          .variable(
            Interval(
              lower: item.lower,
              upper: item.upper
            ), using: &execution), &execution)
        ranges = (
          parameters.u.coefficients[0],
          parameters.v.coefficients[0]
        )
      } catch LocalProofFailure.intervalSingularity {
        ranges = nil
      }
      if let ranges,
        ranges.u.lower.isFinite,
        ranges.u.upper.isFinite,
        ranges.v.lower.isFinite,
        ranges.v.upper.isFinite,
        max(ranges.u.width, ranges.v.width) <= maximumWidth
      {
        (try OriginalParameterQueryStorage.append(
          SurfaceParameterCurveEnclosure(
            lowerFraction: item.lower,
            upperFraction: item.upper,
            u: ScalarInterval(
              lower: ranges.u.lower,
              upper: ranges.u.upper
            ),
            v: ScalarInterval(
              lower: ranges.v.lower,
              upper: ranges.v.upper
            )
          ), to: &result, using: &execution))
        continue
      }
      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw resourceFailure(
          residual: (try OriginalParameterQueryStorage.optionalMap(
            ranges, using: &execution,
            { element, execution in max(element.u.width, element.v.width) })),
          tolerance: tolerance,
          message: "Certified analytic pcurve enclosure exceeded its proof depth."
        )
      }
      let middle = item.lower + (item.upper - item.lower) * 0.5
      guard middle > item.lower, middle < item.upper else {
        throw resourceFailure(
          residual: nil,
          tolerance: tolerance,
          message: "Certified analytic pcurve enclosure reached floating-point resolution."
        )
      }
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          lower: middle,
          upper: item.upper,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          lower: item.lower,
          upper: middle,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
    }
    return (try OriginalParameterQueryStorage.ordered(result, using: &execution, less: { $0.lowerFraction < $1.lowerFraction }))
  }

  private func gaussEnclosure(
    lower: Double,
    upper: Double,
    evaluator: @escaping (Jet, inout OriginalQueryExecution) throws -> Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)

    let midpoint = lower + (upper - lower) * 0.5
    let halfSpan = (upper - lower) * 0.5
    let root = sqrt(3.0 / 5.0)
    let nodes =
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [midpoint - halfSpan * root, midpoint, midpoint + halfSpan * root]
      })
    let weights =
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
      })
    var estimate = Interval.exact(0.0)
    for index in nodes.indices {
      try execution.consumeWork(1)

      let evaluated: Jet
      do {
        evaluated = try evaluator(.variable(.exact(nodes[index]), using: &execution), &execution)
      } catch LocalProofFailure.intervalSingularity {
        return nil
      }
      let value = evaluated.coefficients[0]
      estimate = estimate + value * .floating(weights[index])
    }
    estimate = estimate * .floating(halfSpan)

    let domainJet: Jet
    do {
      domainJet = try evaluator(
        .variable(
          Interval(
            lower: lower,
            upper: upper
          ), using: &execution), &execution)
    } catch LocalProofFailure.intervalSingularity {
      return nil
    }
    let sixthCoefficient = domainJet.coefficients[6].maximumAbsolute
    let sixthDerivative = (try outwardProduct(sixthCoefficient, 720.0, using: &execution))
    let gaussConstant = 1_296.0 / (7.0 * 720.0 * 720.0 * 720.0)
    let spanPower = pow(upper - lower, 7.0)
    var error =
      (try outwardProduct(
        outwardProduct(sixthDerivative, gaussConstant, using: &execution),
        spanPower, using: &execution
      ))
    for _ in 0..<8 {
      try execution.consumeWork(1)
      error = error.nextUp
    }
    guard estimate.lower.isFinite,
      estimate.upper.isFinite,
      error.isFinite
    else {
      throw resourceFailure(
        residual: error,
        tolerance: tolerance,
        message: "Certified analytic pcurve Gauss enclosure exceeded finite arithmetic."
      )
    }
    let gauss = Interval(
      lower: (estimate.lower - error).nextDown,
      upper: (estimate.upper + error).nextUp
    )
    // The value-range envelope needs no derivatives, so it stays tame
    // on square-root shoulders where high-order interval jets inflate;
    // both enclosures certify the same integral, so their overlap does
    // too.
    let envelope = domainJet.coefficients[0] * .floating(upper - lower)
    guard envelope.lower.isFinite, envelope.upper.isFinite else {
      return gauss
    }
    let overlapLower = max(gauss.lower, envelope.lower)
    let overlapUpper = min(gauss.upper, envelope.upper)
    guard overlapLower <= overlapUpper else {
      return gauss.width <= envelope.width ? gauss : envelope
    }
    return Interval(lower: overlapLower, upper: overlapUpper)
  }

  private func sphericalGreatCircleBounds(
    cosine: Vector3D,
    sine: Vector3D,
    startParameter: Double,
    endParameter: Double,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    try cosine.validateUnitLength(tolerance: tolerance)
    try sine.validateUnitLength(tolerance: tolerance)
    guard abs(cosine.dot(sine)) <= tolerance.angle,
      startParameter.isFinite,
      endParameter.isFinite,
      abs(endParameter - startParameter) > tolerance.angle,
      abs(endParameter - startParameter) <= 2.0 * Double.pi + tolerance.angle
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified great-circle flux requires one finite nondegenerate turn or less."
      )
    }
    let ascendingLower = min(startParameter, endParameter)
    let ascendingUpper = max(startParameter, endParameter)
    // The curve's longitude where it starts, as its chart lift (and so the loop unwrapper that
    // translates it) reads it; the integration keeps to that branch of the periodic chart.
    let startLongitude =
      (try sphericalEndpointLongitude(
        cosine: cosine,
        sine: sine,
        parameter: startParameter,
        approachDirection: endParameter > startParameter ? 1.0 : -1.0, using: &execution
      ))
    if let meridian =
      (try meridianFluxBounds(
        cosine: cosine,
        sine: sine,
        lower: ascendingLower,
        upper: ascendingUpper,
        startAtLower: startParameter <= endParameter,
        startLongitude: startLongitude,
        integrand: integrand, using: &execution
      ))
    {
      return startParameter <= endParameter ? meridian : -meridian
    }
    let breakpoints =
      (try OriginalParameterQueryStorage.concatenated(
        OriginalParameterQueryStorage.concatenated(
          OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
            [ascendingLower]
          },
          greatCircleSeamParameters(
            cosine: cosine,
            sine: sine,
            lower: ascendingLower,
            upper: ascendingUpper,
            tolerance: tolerance, using: &execution
          ), using: &execution),
        OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
          [ascendingUpper]
        }, using: &execution))
    let totalSpan = ascendingUpper - ascendingLower
    // Each seam-free segment's shift onto the continuous branch running from the start: walked
    // from the start, a segment's entry longitude (read from inside it) meets the running
    // longitude on the nearest branch, and the segment carries it on without wrapping.
    let period = 2.0 * Double.pi
    let forward = startParameter <= endParameter
    var shifts =
      (try OriginalParameterQueryStorage.repeated(0.0, count: breakpoints.count, using: &execution))
    var running = startLongitude
    for index
      in (forward
      ? (try OriginalParameterQueryStorage.materialize(1..<breakpoints.count, using: &execution))
      : (try OriginalParameterQueryStorage.materialize(
        (1..<breakpoints.count).reversed(), using: &execution)))
    {
      try execution.consumeWork(1)

      let (entry, exit) =
        forward
        ? (breakpoints[index - 1], breakpoints[index])
        : (breakpoints[index], breakpoints[index - 1])
      guard entry != exit else { continue }
      let direction = exit > entry ? 1.0 : -1.0
      let entryLongitude =
        (try sphericalEndpointLongitude(
          cosine: cosine, sine: sine, parameter: entry, approachDirection: direction,
          using: &execution))
      let exitLongitude =
        (try sphericalEndpointLongitude(
          cosine: cosine, sine: sine, parameter: exit, approachDirection: -direction,
          using: &execution))
      let shift = ((running - entryLongitude) / period).rounded() * period
      shifts[index] = shift
      running = exitLongitude + shift
    }
    var result = Interval.exact(0.0)
    for index in 1..<breakpoints.count {
      try execution.consumeWork(1)

      let lower = breakpoints[index - 1]
      let upper = breakpoints[index]
      guard upper > lower else { continue }
      let segmentShift = shifts[index]
      let segmentWidth = requestedWidth * (upper - lower) / totalSpan
      result =
        result
        + (try adaptiveJetBounds(
          requestedWidth: segmentWidth,
          tolerance: tolerance,
              evaluator: { fraction, execution in
          let parameter =
            (try Jet.constant(lower, using: &execution).adding(
              Jet.constant(upper - lower, using: &execution).multiplied(
                by: fraction, using: &execution), using: &execution))
          let geometry = try greatCircleParameterJets(
            cosine: cosine,
            sine: sine,
            parameter: parameter, using: &execution
          )
          return
            (try greenPrimitive(
              integrand: integrand,
              u: geometry.u.adding(
                Jet.constant(segmentShift, using: &execution), using: &execution),
              v: geometry.v, using: &execution
            ).multiplied(by: geometry.v.derivative(using: &execution), using: &execution))
        }, using: &execution))
    }
    return startParameter <= endParameter ? result : -result
  }

  private func certifiedAnalyticImplicitBounds(
    curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let intersection = curve.intersection
    try intersection.validate(tolerance: tolerance, using: &execution)
    let implicit = intersection.implicitCurve
    guard !implicit.cells.isEmpty else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified analytic pcurve flux requires at least one graph cell."
      )
    }
    let ascendingStart = min(curve.startFraction, curve.endFraction)
    let ascendingEnd = max(curve.startFraction, curve.endFraction)
    struct WorkItem {
      let cell: CertifiedImplicitIntersectionGraphCell
      let lowerFraction: Double
      let upperFraction: Double
      let widthBudget: Double
      let depth: Int
    }
    let cellCount = implicit.cells.count
    let requestedSpan = ascendingEnd - ascendingStart
    var pending: [WorkItem] = []
    var result = Interval.exact(0.0)
    for (index, cell) in implicit.cells.enumerated() {
      try execution.consumeWork(1)

      let cellStart = Double(index) / Double(cellCount)
      let cellEnd = Double(index + 1) / Double(cellCount)
      let overlapStart = max(ascendingStart, cellStart)
      let overlapEnd = min(ascendingEnd, cellEnd)
      guard overlapEnd - overlapStart > tolerance.relative else { continue }
      let localLower = (overlapStart - cellStart) * Double(cellCount)
      let localUpper = (overlapEnd - cellStart) * Double(cellCount)
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          cell: cell,
          lowerFraction: localLower,
          upperFraction: localUpper,
          widthBudget: requestedWidth * (overlapEnd - overlapStart) / requestedSpan,
          depth: 0
        ), to: &pending, using: &execution))
    }
    var workItemCount = 0
    while let item = pending.popLast() {
      try execution.visitGeometricCell(depth: item.depth)

      try execution.consumeWork(1)

      workItemCount += 1
      guard workItemCount <= maximumWorkItems else {
        throw resourceFailure(
          residual: Double(workItemCount),
          tolerance: tolerance,
          message: "Certified analytic implicit pcurve flux exhausted its subcell budget."
        )
      }
      let subcell = try item.cell.restrictedBounds(
        fromNormalizedFraction: item.lowerFraction,
        toNormalizedFraction: item.upperFraction,
        firstSurface: implicit.firstSurface,
        secondSurface: implicit.secondSurface,
        tolerance: tolerance, using: &execution
      )
      let contribution = try certifiedAnalyticImplicitSubcellBounds(
        curve: curve,
        subcell: subcell,
        integrand: integrand,
        tolerance: tolerance, using: &execution
      )
      if contribution.width <= item.widthBudget {
        result = result + contribution
        continue
      }
      guard item.depth < min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw resourceFailure(
          residual: contribution.width,
          tolerance: tolerance,
          message: "Certified analytic implicit pcurve flux exceeded its proof depth."
        )
      }
      let middle =
        item.lowerFraction
        + (item.upperFraction - item.lowerFraction) * 0.5
      let halfBudget = item.widthBudget * 0.5
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          cell: item.cell,
          lowerFraction: middle,
          upperFraction: item.upperFraction,
          widthBudget: halfBudget,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        WorkItem(
          cell: item.cell,
          lowerFraction: item.lowerFraction,
          upperFraction: middle,
          widthBudget: halfBudget,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
    }
    if curve.startFraction > curve.endFraction { result = -result }
    return result
  }

  private func certifiedAnalyticImplicitSubcellBounds(
    curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
    subcell: CertifiedImplicitIntersectionGraphSubcell,
    integrand: Integrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let enclosure = try curve.parameterEnclosure(
      for: subcell,
      tolerance: tolerance, using: &execution
    )
    return
      integrand.greenPrimitive(
        u: Interval(lower: enclosure.u.lower, upper: enclosure.u.upper),
        v: Interval(lower: enclosure.v.lower, upper: enclosure.v.upper)
      ) * Interval(
        lower: enclosure.vDerivative.lower,
        upper: enclosure.vDerivative.upper
      )
  }

  private func interval(_ bounds: ScalarInterval, using execution: inout OriginalQueryExecution)
    throws -> Interval
  {
    try execution.consumeWork(1)
    return

      Interval(lower: bounds.lower, upper: bounds.upper)
  }

  private func meridianFluxBounds(
    cosine: Vector3D,
    sine: Vector3D,
    lower: Double,
    upper: Double,
    startAtLower: Bool,
    startLongitude: Double,
    integrand: Integrand, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)

    let verticalRadius = hypot(cosine.z, sine.z)
    let longitudeNumerator = cosine.x * sine.y - cosine.y * sine.x
    let machineTolerance = Double.ulpOfOne * 16_384.0
    guard abs(verticalRadius - 1.0) <= machineTolerance,
      abs(longitudeNumerator) <= machineTolerance
    else {
      return nil
    }
    let phase = atan2(cosine.z, sine.z)
    var breakpoints =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in [lower]
      })
    let firstIndex = Int(
      ceil(
        (lower + phase - Double.pi * 0.5) / Double.pi
      ))
    let lastIndex = Int(
      floor(
        (upper + phase - Double.pi * 0.5) / Double.pi
      ))
    if firstIndex <= lastIndex {
      for index in firstIndex...lastIndex {
        try execution.consumeWork(1)

        let parameter = Double.pi * 0.5 - phase + Double(index) * Double.pi
        if parameter > lower, parameter < upper {
          (try OriginalParameterQueryStorage.append(parameter, to: &breakpoints, using: &execution))
        }
      }
    }
    (try OriginalParameterQueryStorage.append(upper, to: &breakpoints, using: &execution))
    try OriginalParameterQueryStorage.sort(&breakpoints, using: &execution, less: <)
    var result = Interval.exact(0.0)
    for index in 1..<breakpoints.count {
      try execution.consumeWork(1)

      let segmentLower = breakpoints[index - 1]
      let segmentUpper = breakpoints[index]
      let midpoint = segmentLower + (segmentUpper - segmentLower) * 0.5
      let radial = cosine * cos(midpoint) + sine * sin(midpoint)
      var longitude = atan2(-radial.x, radial.y)
      if longitude < 0.0 { longitude += 2.0 * Double.pi }
      // The segment the curve starts on keeps the branch its chart lift starts on, which a
      // meridian along the seam may read as either end of the period.
      let startsHere = startAtLower ? index == 1 : index == breakpoints.count - 1
      if startsHere {
        longitude +=
          ((startLongitude - longitude) / (2.0 * Double.pi)).rounded() * (2.0 * Double.pi)
      }
      let lowerLatitude = asin(
        min(
          max(
            cosine.z * cos(segmentLower) + sine.z * sin(segmentLower),
            -1.0
          ), 1.0))
      let upperLatitude = asin(
        min(
          max(
            cosine.z * cos(segmentUpper) + sine.z * sin(segmentUpper),
            -1.0
          ), 1.0))
      result =
        result
        + integrand.verticalBoundaryIntegral(
          u: .floating(longitude),
          vStart: .floating(lowerLatitude),
          vEnd: .floating(upperLatitude)
        )
    }
    return result
  }

  private func greatCircleSeamParameters(
    cosine: Vector3D,
    sine: Vector3D,
    lower: Double,
    upper: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    let horizontalScale = hypot(cosine.x, sine.x)
    guard horizontalScale > tolerance.angle else { return [] }
    let base = atan2(-cosine.x, sine.x)
    let firstIndex = Int(ceil((lower - base) / Double.pi))
    let lastIndex = Int(floor((upper - base) / Double.pi))
    guard firstIndex <= lastIndex else { return [] }
    var result: [Double] = []
    for index in firstIndex...lastIndex {
      try execution.consumeWork(1)

      let parameter = base + Double(index) * Double.pi
      guard parameter > lower + tolerance.angle,
        parameter < upper - tolerance.angle
      else {
        continue
      }
      let y = cosine.y * cos(parameter) + sine.y * sin(parameter)
      if y > tolerance.angle {
        (try OriginalParameterQueryStorage.append(parameter, to: &result, using: &execution))
      }
    }
    return (try OriginalParameterQueryStorage.ordered(result, using: &execution, less: <))
  }

  private func greatCircleParameterJets(
    cosine: Vector3D,
    sine: Vector3D,
    parameter: Jet, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    let values = (try parameter.sineAndCosine(using: &execution))
    let x =
      (try Jet.constant(cosine.x, using: &execution).multiplied(
        by: values.cosine, using: &execution
      ).adding(
        Jet.constant(sine.x, using: &execution).multiplied(by: values.sine, using: &execution),
        using: &execution))
    let y =
      (try Jet.constant(cosine.y, using: &execution).multiplied(
        by: values.cosine, using: &execution
      ).adding(
        Jet.constant(sine.y, using: &execution).multiplied(by: values.sine, using: &execution),
        using: &execution))
    let z =
      (try Jet.constant(cosine.z, using: &execution).multiplied(
        by: values.cosine, using: &execution
      ).adding(
        Jet.constant(sine.z, using: &execution).multiplied(by: values.sine, using: &execution),
        using: &execution))
    let horizontalSquared =
      (try x.multiplied(by: x, using: &execution).adding(
        y.multiplied(by: y, using: &execution), using: &execution))
    let longitudeDerivative = try Jet.constant(
      cosine.x * sine.y - cosine.y * sine.x, using: &execution
    ).divided(by: horizontalSquared, using: &execution)
    let parameterBounds = parameter.coefficients[0]
    let midpoint =
      parameterBounds.lower
      + (parameterBounds.upper - parameterBounds.lower) * 0.5
    let radial = cosine * cos(midpoint) + sine * sin(midpoint)
    var midpointLongitude = atan2(-radial.x, radial.y)
    if midpointLongitude < 0.0 { midpointLongitude += 2.0 * Double.pi }
    let longitudeRadius =
      longitudeDerivative.coefficients[0].maximumAbsolute
      * (parameterBounds.upper - parameterBounds.lower) * 0.5
    let longitude =
      (try Jet.antiderivative(
        constant: Interval(
          lower: (midpointLongitude - longitudeRadius).nextDown,
          upper: (midpointLongitude + longitudeRadius).nextUp
        ),
        derivative: longitudeDerivative, using: &execution
      ))

    let latitudeDenominator = try Jet.constant(1.0, using: &execution).subtracting(
      z.multiplied(by: z, using: &execution), using: &execution
    ).squareRoot(using: &execution)
    let latitudeDerivative = try z.derivative(using: &execution).divided(
      by: latitudeDenominator, using: &execution)
    let zBounds = z.coefficients[0]
    guard zBounds.lower >= -1.0 - Double.ulpOfOne * 4_096.0,
      zBounds.upper <= 1.0 + Double.ulpOfOne * 4_096.0
    else {
      throw LocalProofFailure.intervalSingularity
    }
    let latitude =
      (try Jet.antiderivative(
        constant: Interval(
          lower: asin(min(max(zBounds.lower, -1.0), 1.0)).nextDown,
          upper: asin(min(max(zBounds.upper, -1.0), 1.0)).nextUp
        ),
        derivative: latitudeDerivative, using: &execution
      ))
    return (longitude, latitude)
  }

  private func projectedAnalyticParameterJets(
    _ projected: ProjectedAnalyticSurfaceParameterCurve,
    fraction: Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    try projected.validate(on: projected.surface, tolerance: tolerance, using: &execution)
    let parameter =
      (try Jet.constant(projected.startParameter, using: &execution).adding(
        Jet.constant(projected.endParameter - projected.startParameter, using: &execution)
          .multiplied(by: fraction, using: &execution), using: &execution))
    let point = try projectedAnalyticPointJets(
      projected.curve,
      parameter: parameter,
      tolerance: tolerance, using: &execution
    )
    switch projected.surface {
    case .plane(let plane):
      // A `Plane3D` runs its parameters along its own basis, not the analytic plane's.
      let basis = try plane.parameterBasis(tolerance: tolerance)
      let offset = (
        x:
          (try point.x.subtracting(.constant(plane.origin.x, using: &execution), using: &execution)),
        y:
          (try point.y.subtracting(.constant(plane.origin.y, using: &execution), using: &execution)),
        z:
          (try point.z.subtracting(.constant(plane.origin.z, using: &execution), using: &execution))
      )
      return (
        (try projectedAnalyticDot(offset, basis.u, using: &execution)),
        (try projectedAnalyticDot(offset, basis.v, using: &execution))
      )
    case .analytic(.plane(let origin, let normal)):
      return try planarParameterJets(
        point: point,
        origin: origin,
        normal: normal,
        tolerance: tolerance, using: &execution
      )
    case .analytic(.cone(let apex, let axis, let halfAngle)):
      return try conicalParameterJets(
        point: point,
        apex: apex,
        axis: axis,
        halfAngle: halfAngle,
        projected: projected,
        fraction: fraction,
        tolerance: tolerance, using: &execution
      )
    case .cylinder(let cylinder):
      return try cylindricalParameterJets(
        point: point,
        origin: cylinder.origin,
        axis: cylinder.axis,
        projected: projected,
        fraction: fraction,
        tolerance: tolerance, using: &execution
      )
    case .analytic(.cylinder(let origin, let axis, _)):
      return try cylindricalParameterJets(
        point: point,
        origin: origin,
        axis: axis,
        projected: projected,
        fraction: fraction,
        tolerance: tolerance, using: &execution
      )
    case .analytic, .bSpline, .procedural:
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message:
          "Certified projected pcurve integration requires a plane, cylinder or cone support."
      )
    }
  }

  private func projectedAnalyticPointJets(
    _ curve: Curve3D,
    parameter: Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (x: Jet, y: Jet, z: Jet) {
    try execution.consumeWork(1)

    switch curve {
    case .analytic(.hyperbola(let hyperbola)):
      try hyperbola.validate(tolerance: tolerance)
      let conjugateAxis = try hyperbola.normal
        .cross(hyperbola.transverseAxis)
        .normalized(tolerance: tolerance.distance)
      let values = (try parameter.hyperbolicSineAndCosine(using: &execution))
      return (
        (try .constant(hyperbola.center.x, using: &execution).adding(
          .constant(hyperbola.transverseAxis.x * hyperbola.transverseRadius, using: &execution)
            .multiplied(by: values.cosine, using: &execution), using: &execution
        ).adding(
          .constant(conjugateAxis.x * hyperbola.conjugateRadius, using: &execution).multiplied(
            by: values.sine, using: &execution), using: &execution)),
        (try .constant(hyperbola.center.y, using: &execution).adding(
          .constant(hyperbola.transverseAxis.y * hyperbola.transverseRadius, using: &execution)
            .multiplied(by: values.cosine, using: &execution), using: &execution
        ).adding(
          .constant(conjugateAxis.y * hyperbola.conjugateRadius, using: &execution).multiplied(
            by: values.sine, using: &execution), using: &execution)),
        (try .constant(hyperbola.center.z, using: &execution).adding(
          .constant(hyperbola.transverseAxis.z * hyperbola.transverseRadius, using: &execution)
            .multiplied(by: values.cosine, using: &execution), using: &execution
        ).adding(
          .constant(conjugateAxis.z * hyperbola.conjugateRadius, using: &execution).multiplied(
            by: values.sine, using: &execution), using: &execution))
      )
    case .analytic(.parabola(let parabola)):
      try parabola.validate(tolerance: tolerance)
      let transverseAxis = try parabola.normal
        .cross(parabola.axis)
        .normalized(tolerance: tolerance.distance)
      let squared = (try parameter.multiplied(by: parameter, using: &execution))
      let inverseFourFocalLength = 1.0 / (4.0 * parabola.focalLength)
      return (
        (try .constant(parabola.vertex.x, using: &execution).adding(
          .constant(transverseAxis.x, using: &execution).multiplied(
            by: parameter, using: &execution), using: &execution
        ).adding(
          .constant(parabola.axis.x * inverseFourFocalLength, using: &execution).multiplied(
            by: squared, using: &execution), using: &execution)),
        (try .constant(parabola.vertex.y, using: &execution).adding(
          .constant(transverseAxis.y, using: &execution).multiplied(
            by: parameter, using: &execution), using: &execution
        ).adding(
          .constant(parabola.axis.y * inverseFourFocalLength, using: &execution).multiplied(
            by: squared, using: &execution), using: &execution)),
        (try .constant(parabola.vertex.z, using: &execution).adding(
          .constant(transverseAxis.z, using: &execution).multiplied(
            by: parameter, using: &execution), using: &execution
        ).adding(
          .constant(parabola.axis.z * inverseFourFocalLength, using: &execution).multiplied(
            by: squared, using: &execution), using: &execution))
      )
    case .analytic(
      .ellipse(let center, let normal, let majorAxis, let majorRadius, let minorRadius)):
      let minorAxis = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
      let values = (try parameter.sineAndCosine(using: &execution))
      return (
        (try .constant(center.x, using: &execution).adding(
          .constant(majorAxis.x * majorRadius, using: &execution).multiplied(
            by: values.cosine, using: &execution), using: &execution
        ).adding(
          .constant(minorAxis.x * minorRadius, using: &execution).multiplied(
            by: values.sine, using: &execution), using: &execution)),
        (try .constant(center.y, using: &execution).adding(
          .constant(majorAxis.y * majorRadius, using: &execution).multiplied(
            by: values.cosine, using: &execution), using: &execution
        ).adding(
          .constant(minorAxis.y * minorRadius, using: &execution).multiplied(
            by: values.sine, using: &execution), using: &execution)),
        (try .constant(center.z, using: &execution).adding(
          .constant(majorAxis.z * majorRadius, using: &execution).multiplied(
            by: values.cosine, using: &execution), using: &execution
        ).adding(
          .constant(minorAxis.z * minorRadius, using: &execution).multiplied(
            by: values.sine, using: &execution), using: &execution))
      )
    case .parameterImage, .originalAffineWord, .originalConstructionChart,
      .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain,
      .originalGuideEndpointConnector, .originalPolyline, .originalDrafted,
      .originalAngularTransport:
      // FIXME(INCOMPLETE_IMPLEMENTATION): The specialized projected analytic
      // flux path has no retained original image/chart jet producer. Volume
      // callers must not replace its typed failure with a primitive proxy.
      throw KernelError(
        phase: .topology, code: .unsupportedCapability,
        tolerance: tolerance, message: "Projected analytic flux requires original image/chart jets."
      )
    case .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .rigidImage, .affineImage:
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified projected pcurve integration requires a hyperbola, parabola or ellipse."
      )
    }
  }

  private func planarParameterJets(
    point: (x: Jet, y: Jet, z: Jet),
    origin: Point3D,
    normal: Vector3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    let basis = try projectedAnalyticBasis(normal, tolerance: tolerance, using: &execution)
    let offset = (
      x: (try point.x.subtracting(.constant(origin.x, using: &execution), using: &execution)),
      y: (try point.y.subtracting(.constant(origin.y, using: &execution), using: &execution)),
      z: (try point.z.subtracting(.constant(origin.z, using: &execution), using: &execution))
    )
    return (
      (try projectedAnalyticDot(offset, basis.u, using: &execution)),
      (try projectedAnalyticDot(offset, basis.v, using: &execution))
    )
  }

  private func conicalParameterJets(
    point: (x: Jet, y: Jet, z: Jet),
    apex: Point3D,
    axis: Vector3D,
    halfAngle: Double,
    projected: ProjectedAnalyticSurfaceParameterCurve,
    fraction: Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    let basis = try projectedAnalyticBasis(axis, tolerance: tolerance, using: &execution)
    let offset = (
      x: (try point.x.subtracting(.constant(apex.x, using: &execution), using: &execution)),
      y: (try point.y.subtracting(.constant(apex.y, using: &execution), using: &execution)),
      z: (try point.z.subtracting(.constant(apex.z, using: &execution), using: &execution))
    )
    let axial = (try projectedAnalyticDot(offset, axis, using: &execution))
    let cosine = cos(halfAngle)
    guard cosine.isFinite, abs(cosine) > tolerance.angle else {
      throw KernelError(
        phase: .topology,
        code: .singularGeometry,
        residual: abs(cosine),
        tolerance: tolerance,
        message: "Certified projected cone pcurve has a singular half angle."
      )
    }
    let v =
      (try axial.multiplied(by: .constant(1.0 / cosine, using: &execution), using: &execution))
    let vRange = v.coefficients[0]
    guard vRange.lower > 0.0 || vRange.upper < 0.0 else {
      throw LocalProofFailure.intervalSingularity
    }
    let sign = vRange.lower > 0.0 ? 1.0 : -1.0
    let x =
      (try projectedAnalyticDot(offset, basis.u, using: &execution).multiplied(
        by: .constant(sign, using: &execution), using: &execution))
    let y =
      (try projectedAnalyticDot(offset, basis.v, using: &execution).multiplied(
        by: .constant(sign, using: &execution), using: &execution))
    let denominator =
      (try x.multiplied(by: x, using: &execution).adding(
        y.multiplied(by: y, using: &execution), using: &execution))
    let angleDerivative = try x.multiplied(by: y.derivative(using: &execution), using: &execution)
      .subtracting(
        y.multiplied(by: x.derivative(using: &execution), using: &execution), using: &execution
      ).divided(by: denominator, using: &execution)

    let fractionBounds = fraction.coefficients[0]
    let middleFraction =
      fractionBounds.lower
      + (fractionBounds.upper - fractionBounds.lower) * 0.5
    let reference = try projected.parameter(
      atNormalizedFraction: 0.5,
      tolerance: tolerance, using: &execution
    ).u
    let middle = try projected.parameter(
      atNormalizedFraction: middleFraction,
      tolerance: tolerance, using: &execution
    ).u
    let unwrappedMiddle =
      middle
      + 2.0 * Double.pi * ((reference - middle) / (2.0 * Double.pi)).rounded()
    let angleRadius =
      angleDerivative.coefficients[0].maximumAbsolute
      * (fractionBounds.upper - fractionBounds.lower) * 0.5
    guard angleRadius.isFinite,
      angleRadius < Double.pi - tolerance.angle
    else {
      throw LocalProofFailure.intervalSingularity
    }
    let u =
      (try Jet.antiderivative(
        constant: Interval(
          lower: (unwrappedMiddle - angleRadius).nextDown,
          upper: (unwrappedMiddle + angleRadius).nextUp
        ),
        derivative: angleDerivative, using: &execution
      ))
    return (u, v)
  }

  /// A cylinder's (angle, height) along a projected curve: the height its offset along the axis,
  /// the angle the antiderivative of its turn about the axis from where the curve's own pcurve
  /// puts the interval's middle (already continued along the curve).
  private func cylindricalParameterJets(
    point: (x: Jet, y: Jet, z: Jet),
    origin: Point3D,
    axis: Vector3D,
    projected: ProjectedAnalyticSurfaceParameterCurve,
    fraction: Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    let unit = try axis.normalized(tolerance: tolerance.distance)
    let basis = try projectedAnalyticBasis(unit, tolerance: tolerance, using: &execution)
    let offset = (
      x: (try point.x.subtracting(.constant(origin.x, using: &execution), using: &execution)),
      y: (try point.y.subtracting(.constant(origin.y, using: &execution), using: &execution)),
      z: (try point.z.subtracting(.constant(origin.z, using: &execution), using: &execution))
    )
    let v =
      (try projectedAnalyticDot(offset, axis, using: &execution).multiplied(
        by: .constant(1.0 / axis.dot(axis), using: &execution), using: &execution))
    let x = (try projectedAnalyticDot(offset, basis.u, using: &execution))
    let y = (try projectedAnalyticDot(offset, basis.v, using: &execution))
    let denominator =
      (try x.multiplied(by: x, using: &execution).adding(
        y.multiplied(by: y, using: &execution), using: &execution))
    let angleDerivative = try x.multiplied(by: y.derivative(using: &execution), using: &execution)
      .subtracting(
        y.multiplied(by: x.derivative(using: &execution), using: &execution), using: &execution
      ).divided(by: denominator, using: &execution)
    let fractionBounds = fraction.coefficients[0]
    let middleFraction =
      fractionBounds.lower
      + (fractionBounds.upper - fractionBounds.lower) * 0.5
    let middle = try projected.parameter(
      atNormalizedFraction: middleFraction,
      tolerance: tolerance, using: &execution
    ).u
    let angleRadius =
      angleDerivative.coefficients[0].maximumAbsolute
      * (fractionBounds.upper - fractionBounds.lower) * 0.5
    guard angleRadius.isFinite,
      angleRadius < Double.pi - tolerance.angle
    else {
      throw LocalProofFailure.intervalSingularity
    }
    let u =
      (try Jet.antiderivative(
        constant: Interval(
          lower: (middle - angleRadius).nextDown,
          upper: (middle + angleRadius).nextUp
        ),
        derivative: angleDerivative, using: &execution
      ))
    return (u, v)
  }

  private func projectedAnalyticBasis(
    _ normal: Vector3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Vector3D, v: Vector3D) {
    try execution.consumeWork(1)

    let reference = abs(normal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
    let u = try normal.cross(reference).normalized(tolerance: tolerance.distance)
    let v = try normal.cross(u).normalized(tolerance: tolerance.distance)
    return (u, v)
  }

  private func projectedAnalyticDot(
    _ point: (x: Jet, y: Jet, z: Jet),
    _ vector: Vector3D, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)
    return

      (try point.x.multiplied(by: .constant(vector.x, using: &execution), using: &execution).adding(
        point.y.multiplied(by: .constant(vector.y, using: &execution), using: &execution),
        using: &execution
      ).adding(
        point.z.multiplied(by: .constant(vector.z, using: &execution), using: &execution),
        using: &execution))
  }

  private func rationalFluxJet(
    patch: PreparedRationalPcurvePatch,
    parameter: Interval,
    integrand: Integrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    let parameters = try rationalPcurveJets(
      patch: patch,
      parameter: parameter,
      tolerance: tolerance, using: &execution
    )
    return
      (try greenPrimitive(
        integrand: integrand,
        u: parameters.u,
        v: parameters.v, using: &execution
      ).multiplied(by: parameters.v.derivative(using: &execution), using: &execution))
  }

  func polynomialCylinderBounds(
    for curve: BSplineCurve2D,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> PolynomialCylinderBounds? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumWorkItems, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try polynomialCylinderBounds(
      for: curve, integrand: integrand, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func polynomialCylinderBounds(
    for curve: BSplineCurve2D,
    integrand: Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> PolynomialCylinderBounds? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> PolynomialCylinderBounds?
        {

          try execution.consumeWork(1)

          guard case .cylinder(let radius, let offsetU, let offsetV) = integrand,
            let firstWeight = curve.weights.first,
            firstWeight.isFinite,
            firstWeight > 0.0,
            try OriginalParameterQueryStorage.allSatisfy(
              curve.weights, using: &execution,
              predicate: { element, execution in element == firstWeight })
          else {
            return nil
          }
          let patches = try curve.rationalBezierPatches(tolerance: tolerance, using: &execution)
          guard patches.isEmpty == false else {
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              tolerance: tolerance,
              message: "Polynomial cylinder flux produced no Bezier spans."
            )
          }
          let patchWidth = requestedWidth / Double(patches.count)
          var result = Interval.exact(0.0)
          var parameterArea = Interval.exact(0.0)
          for patch in patches {
            try execution.consumeWork(1)

            guard patch.degree >= 1,
              patch.controlPoints.count == patch.weights.count,
              let firstWeight = patch.weights.first,
              firstWeight.isFinite,
              firstWeight > 0.0,
              try OriginalParameterQueryStorage.allSatisfy(
                patch.weights, using: &execution,
                predicate: { element, execution in element == firstWeight })
            else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Polynomial cylinder flux requires finite certified Bezier controls."
              )
            }
            let uControls =
              (try OriginalParameterQueryStorage.map(
                patch.controlPoints, using: &execution,
                transform: { element, execution in Interval.floating(element.x) }))
            let vControls =
              (try OriginalParameterQueryStorage.map(
                patch.controlPoints, using: &execution,
                transform: { element, execution in Interval.floating(element.y) }))
            let u = (try powerCoefficients(bernsteinControls: uControls, using: &execution))
            let v = (try powerCoefficients(bernsteinControls: vControls, using: &execution))
            let vDerivative = (try derivativeCoefficients(v, using: &execution))
            let uvIntegral = (try integratedProduct(u, vDerivative, using: &execution))
            parameterArea = parameterArea + uvIntegral
            let lowerU =
              (try OriginalParameterQueryStorage.extrema(
                OriginalParameterQueryStorage.map(
                  uControls, using: &execution, transform: { element, execution in element.lower }),
                using: &execution, projection: { element, _ in element }))?.lower
              ?? -.infinity
            let upperU =
              (try OriginalParameterQueryStorage.extrema(
                OriginalParameterQueryStorage.map(
                  uControls, using: &execution, transform: { element, execution in element.upper }),
                using: &execution, projection: { element, _ in element }))?.upper
              ?? .infinity
            let center = lowerU + (upperU - lowerU) * 0.5
            guard center.isFinite else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Polynomial cylinder flux lost a finite angular center."
              )
            }
            let deltaControls =
              (try OriginalParameterQueryStorage.map(
                uControls, using: &execution,
                transform: { element, execution in element - .floating(center) }))
            let delta = (try powerCoefficients(bernsteinControls: deltaControls, using: &execution))
            let maximumDelta = max(abs(lowerU - center), abs(upperU - center)).nextUp
            let maximumVDerivative =
              (try OriginalParameterQueryStorage.extrema(
                OriginalParameterQueryStorage.map(
                  derivativeBernsteinControls(vControls, using: &execution), using: &execution,
                  transform: { element, execution in element.maximumAbsolute }), using: &execution,
                projection: { element, _ in element }))?.upper ?? .infinity
            let trigonometric = try polynomialTrigonometricMoments(
              delta: delta,
              vDerivative: vDerivative,
              center: center,
              maximumDelta: maximumDelta,
              maximumVDerivative: maximumVDerivative,
              tolerance: tolerance, using: &execution
            )
            let contribution =
              radius / .exact(3.0)
              * (offsetU * trigonometric.sine
                - offsetV * trigonometric.cosine
                + radius * uvIntegral)
            guard contribution.width <= patchWidth else {
              throw resourceFailure(
                residual: contribution.width,
                tolerance: tolerance,
                message: "Polynomial cylinder flux exceeded its Bezier-span enclosure budget."
              )
            }
            result = result + contribution
          }
          return PolynomialCylinderBounds(
            flux: result,
            parameterArea: SurfaceParameterAreaBounds(
              lower: parameterArea.lower,
              upper: parameterArea.upper
            )
          )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func polynomialTrigonometricMoments(
    delta: [Interval],
    vDerivative: [Interval],
    center: Double,
    maximumDelta: Double,
    maximumVDerivative: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (sine: Interval, cosine: Interval) {
    try execution.consumeWork(1)

    let maximumOrder = 10
    var deltaPower =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [Interval.exact(1.0)]
      })
    var sine = Interval.exact(0.0)
    var cosine = Interval.exact(0.0)
    var factorial = 1.0
    for order in 0...maximumOrder {
      try execution.consumeWork(1)

      if order > 0 {
        factorial *= Double(order)
        deltaPower = (try convolved(deltaPower, delta, using: &execution))
      }
      let moment = (try integratedProduct(deltaPower, vDerivative, using: &execution))
      let phase = center + Double(order) * Double.pi * 0.5
      sine = sine + .floating(sin(phase) / factorial) * moment
      cosine = cosine + .floating(cos(phase) / factorial) * moment
    }
    let nextFactorial = factorial * Double(maximumOrder + 1)
    var remainder =
      pow(maximumDelta, Double(maximumOrder + 1))
      / nextFactorial * maximumVDerivative
    for _ in 0..<16 {
      try execution.consumeWork(1)
      remainder = remainder.nextUp
    }
    guard remainder.isFinite else {
      throw resourceFailure(
        residual: remainder,
        tolerance: tolerance,
        message: "Polynomial cylinder flux Taylor remainder exceeded finite arithmetic."
      )
    }
    let enclosedSine = Interval(
      lower: (sine.lower - remainder).nextDown,
      upper: (sine.upper + remainder).nextUp
    )
    let enclosedCosine = Interval(
      lower: (cosine.lower - remainder).nextDown,
      upper: (cosine.upper + remainder).nextUp
    )
    return (enclosedSine, enclosedCosine)
  }

  private func powerCoefficients(
    bernsteinControls: [Interval], using execution: inout OriginalQueryExecution
  ) throws -> [Interval] {
    try execution.consumeWork(1)

    let degree = bernsteinControls.count - 1
    return
      (try OriginalParameterQueryStorage.map(
        (0...degree), using: &execution,
        transform: { power, execution in
          var coefficient = Interval.exact(0.0)
          for index in 0...power {
            try execution.consumeWork(1)

            let sign = (power - index).isMultiple(of: 2) ? 1.0 : -1.0
            let scale =
              sign
              * (try binomial(degree, power, using: &execution))
              * (try binomial(power, index, using: &execution))
            coefficient =
              coefficient
              + bernsteinControls[index] * .floating(scale)
          }
          return coefficient
        }))
  }

  private func derivativeCoefficients(
    _ coefficients: [Interval], using execution: inout OriginalQueryExecution
  ) throws -> [Interval] {
    try execution.consumeWork(1)

    guard coefficients.count >= 2 else {
      return
        (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
          [.exact(0.0)]
        })
    }
    return
      (try OriginalParameterQueryStorage.map(
        (1..<coefficients.count), using: &execution,
        transform: { index, execution in
          coefficients[index] * .floating(Double(index))
        }))
  }

  private func derivativeBernsteinControls(
    _ controls: [Interval], using execution: inout OriginalQueryExecution
  ) throws -> [Interval] {
    try execution.consumeWork(1)

    let degree = controls.count - 1
    guard degree > 0 else {
      return
        (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
          [.exact(0.0)]
        })
    }
    return
      (try OriginalParameterQueryStorage.map(
        (0..<degree), using: &execution,
        transform: { index, execution in
          (controls[index + 1] - controls[index]) * .floating(Double(degree))
        }))
  }

  private func convolved(
    _ first: [Interval],
    _ second: [Interval], using execution: inout OriginalQueryExecution
  ) throws -> [Interval] {
    try execution.consumeWork(1)

    var result =
      (try OriginalParameterQueryStorage.repeated(
        Interval.exact(0.0), count: first.count + second.count - 1, using: &execution))
    for firstIndex in first.indices {
      try execution.consumeWork(1)

      for secondIndex in second.indices {
        try execution.consumeWork(1)

        let index = firstIndex + secondIndex
        result[index] =
          result[index]
          + first[firstIndex] * second[secondIndex]
      }
    }
    return result
  }

  private func integratedProduct(
    _ first: [Interval],
    _ second: [Interval], using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let product = (try convolved(first, second, using: &execution))
    return
      (try OriginalParameterQueryStorage.reduce(
        product.indices, initial: Interval.exact(0.0), using: &execution,
        combine: { result, index, execution in
          result + product[index] / .floating(Double(index + 1))
        }))
  }

  private func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws
    -> Double
  {
    try execution.consumeWork(1)

    guard k > 0, k < n else { return 1.0 }
    let reduced = min(k, n - k)
    return
      (try OriginalParameterQueryStorage.reduce(
        (1...reduced), initial: 1.0, using: &execution,
        combine: { result, index, execution in
          result * Double(n - reduced + index) / Double(index)
        }))
  }

  private func rationalPcurveJets(
    patch: PreparedRationalPcurvePatch,
    parameter: Interval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    let x = try bezierVariableJet(
      derivativeControls: patch.xDerivativeControls,
      parameter: parameter,
      tolerance: tolerance, using: &execution
    )
    let y = try bezierVariableJet(
      derivativeControls: patch.yDerivativeControls,
      parameter: parameter,
      tolerance: tolerance, using: &execution
    )
    let weight = try bezierVariableJet(
      derivativeControls: patch.weightDerivativeControls,
      parameter: parameter,
      tolerance: tolerance, using: &execution
    )
    var u = try x.divided(by: weight, using: &execution)
    var v = try y.divided(by: weight, using: &execution)
    let restrictedControls = try patch.source.restrictedControls(
      fractionLower: parameter.lower,
      fractionUpper: parameter.upper,
      tolerance: tolerance, using: &execution
    )
    let uControls =
      (try OriginalParameterQueryStorage.map(
        restrictedControls, using: &execution,
        transform: { element, execution in element.x / element.weight }))
    let vControls =
      (try OriginalParameterQueryStorage.map(
        restrictedControls, using: &execution,
        transform: { element, execution in element.y / element.weight }))
    u.coefficients[0] = Interval(
      lower: (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          uControls, using: &execution, transform: { element, execution in element.lower }),
        using: &execution, projection: { element, _ in element }))?.lower
        ?? -.infinity,
      upper: (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          uControls, using: &execution, transform: { element, execution in element.upper }),
        using: &execution, projection: { element, _ in element }))?.upper
        ?? .infinity
    )
    v.coefficients[0] = Interval(
      lower: (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          vControls, using: &execution, transform: { element, execution in element.lower }),
        using: &execution, projection: { element, _ in element }))?.lower
        ?? -.infinity,
      upper: (try OriginalParameterQueryStorage.extrema(
        OriginalParameterQueryStorage.map(
          vControls, using: &execution, transform: { element, execution in element.upper }),
        using: &execution, projection: { element, _ in element }))?.upper
        ?? .infinity
    )
    return (u, v)
  }

  private func prepareRationalPcurvePatch(
    _ patch: HomogeneousPatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> PreparedRationalPcurvePatch {
    try execution.consumeWork(1)

    guard patch.degree >= 1,
      try OriginalParameterQueryStorage.allSatisfy(
        patch.controls, using: &execution,
        predicate: { element, execution in element.isFiniteAndPositiveWeight })
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified rational pcurve flux requires valid homogeneous controls."
      )
    }
    return PreparedRationalPcurvePatch(
      source: patch,
      xDerivativeControls: (try bezierDerivativeControlLevels(
        OriginalParameterQueryStorage.map(
          patch.controls, using: &execution,
          transform: { element, execution in (try interval(element.x, using: &execution)) }),
        using: &execution
      )),
      yDerivativeControls: (try bezierDerivativeControlLevels(
        OriginalParameterQueryStorage.map(
          patch.controls, using: &execution,
          transform: { element, execution in (try interval(element.y, using: &execution)) }),
        using: &execution
      )),
      weightDerivativeControls: (try bezierDerivativeControlLevels(
        OriginalParameterQueryStorage.map(
          patch.controls, using: &execution,
          transform: { element, execution in (try interval(element.weight, using: &execution)) }),
        using: &execution
      ))
    )
  }

  private func bezierDerivativeControlLevels(
    _ controls: [Interval], using execution: inout OriginalQueryExecution
  ) throws -> [[Interval]] {
    try execution.consumeWork(1)

    var levels =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [controls]
      })
    while let previous = levels.last, previous.count > 1 {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(
        derivativeBernsteinControls(previous, using: &execution), to: &levels, using: &execution))
    }
    return levels
  }

  /// Builds the Taylor jet of a Bernstein polynomial for the independent
  /// variable used by the Gauss proof. Each coefficient is the certified
  /// range of the corresponding derivative divided by its factorial.
  private func bezierVariableJet(
    derivativeControls: [[Interval]],
    parameter: Interval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    var coefficients =
      (try OriginalParameterQueryStorage.repeated(
        Interval.exact(0.0), count: Jet.order + 1, using: &execution))
    var factorial = 1.0
    for derivativeOrder
      in 0..<min(
        derivativeControls.count,
        Jet.order + 1
      )
    {
      try execution.consumeWork(1)

      if derivativeOrder > 1 {
        factorial *= Double(derivativeOrder)
      }
      coefficients[derivativeOrder] =
        try bezierRange(
          controls: derivativeControls[derivativeOrder],
          parameter: parameter,
          tolerance: tolerance, using: &execution
        ) / .exact(factorial)
    }
    return Jet(coefficients: coefficients)
  }

  private func bezierRange(
    controls: [Interval],
    parameter: Interval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    try execution.retainStorage(count: controls.count, stride: MemoryLayout<Interval>.stride)
    var level = controls
    let complement = Interval.exact(1.0) - parameter
    while level.count > 1 {
      try execution.consumeWork(1)

      for index in 0..<(level.count - 1) {
        try execution.consumeWork(1)

        level[index] =
          level[index] * complement
          + level[index + 1] * parameter
      }
      level.removeLast()
    }
    let evaluated = level[0]
    guard parameter.lower.isFinite,
      parameter.upper.isFinite,
      parameter.lower >= 0.0,
      parameter.lower <= parameter.upper,
      parameter.upper <= 1.0
    else {
      return evaluated
    }
    // Every normalized Bernstein basis is nonnegative and sums to one.
    // Intersect the outward evaluation with the complete original same-net
    // coefficient hull, including differentiated nets and their stored scales.
    // This removes interval dependency without asserting any coefficient equality.
    let hullLower =
      (try OriginalParameterQueryStorage.reduce(
        controls, initial: Double.infinity, using: &execution,
        combine: { partial, element, execution in min(partial, element.lower) }))
    let hullUpper =
      (try OriginalParameterQueryStorage.reduce(
        controls, initial: -Double.infinity, using: &execution,
        combine: { partial, element, execution in max(partial, element.upper) }))
    let lower = max(evaluated.lower, hullLower)
    let upper = min(evaluated.upper, hullUpper)
    guard evaluated.lower.isFinite,
      evaluated.upper.isFinite,
      hullLower.isFinite,
      hullUpper.isFinite,
      lower <= upper
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message:
          "Certified rational pcurve Bernstein evaluation could not intersect its finite original coefficient hull."
      )
    }
    return Interval(lower: lower, upper: upper)
  }

  private func polynomialFluxJet(
    primitive: CertifiedPolynomialSurfaceFluxPrimitive,
    u: Jet,
    v: Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    let normalizedU = try normalizedParameterJet(
      u,
      domain: primitive.uDomain,
      tolerance: tolerance, using: &execution
    )
    let normalizedV = try normalizedParameterJet(
      v,
      domain: primitive.vDomain,
      tolerance: tolerance, using: &execution
    )
    let rows =
      (try OriginalParameterQueryStorage.map(
        primitive.coefficients, using: &execution,
        transform: { element, execution in
          (try bernsteinJet(coefficients: element, parameter: normalizedU, using: &execution))
        }))
    let value = (try bernsteinJet(coefficients: rows, parameter: normalizedV, using: &execution))
    return (try value.multiplied(by: normalizedV.derivative(using: &execution), using: &execution))
  }

  private func normalizedParameterJet(
    _ parameter: Jet,
    domain: ParameterDomain,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    guard case .closed(let lower, let upper) = domain,
      lower.isFinite,
      upper.isFinite,
      upper > lower
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified polynomial pcurve flux requires a positive bounded source domain."
      )
    }
    return try parameter.subtracting(.constant(lower, using: &execution), using: &execution)
      .divided(
        by: .constant(Interval.exact(upper) - .exact(lower), using: &execution), using: &execution
      )
  }

  private func bernsteinJet(
    coefficients: [Interval],
    parameter: Jet, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    var level = try OriginalParameterQueryStorage.map(
      coefficients, using: &execution,
      transform: { coefficient, execution in try Jet.constant(coefficient, using: &execution) })
    let complement =
      (try Jet.constant(1.0, using: &execution).subtracting(parameter, using: &execution))
    while level.count > 1 {
      try execution.consumeWork(1)

      level =
        (try OriginalParameterQueryStorage.map(
          (0..<(level.count - 1)), using: &execution,
          transform: { index, execution in
            (try (level[index]).multiplied(by: complement, using: &execution).adding(
              (level[index + 1]).multiplied(by: parameter, using: &execution), using: &execution))
          }))
    }
    return level[0]
  }

  private func bernsteinJet(
    coefficients: [Jet],
    parameter: Jet, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    var level = coefficients
    let complement =
      (try Jet.constant(1.0, using: &execution).subtracting(parameter, using: &execution))
    while level.count > 1 {
      try execution.consumeWork(1)

      level =
        (try OriginalParameterQueryStorage.map(
          (0..<(level.count - 1)), using: &execution,
          transform: { index, execution in
            (try (level[index]).multiplied(by: complement, using: &execution).adding(
              (level[index + 1]).multiplied(by: parameter, using: &execution), using: &execution))
          }))
    }
    return level[0]
  }

  private func interval(_ bounds: ScalarBounds, using execution: inout OriginalQueryExecution)
    throws -> Interval
  {
    try execution.consumeWork(1)
    return

      Interval(lower: bounds.lower, upper: bounds.upper)
  }

  private func outwardProduct(
    _ lhs: Double, _ rhs: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    var result = lhs * rhs
    for _ in 0..<4 {
      try execution.consumeWork(1)
      result = result.nextUp
    }
    return result
  }

  private func greenPrimitive(
    integrand: Integrand,
    u: Jet,
    v: Jet, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    switch integrand {
    case .plane(let volumeScale):
      return (try Jet.constant(volumeScale, using: &execution).multiplied(by: u, using: &execution))
    case .cylinder(let radius, let offsetU, let offsetV):
      return
        (try Jet.constant(radius / .exact(3.0), using: &execution).multiplied(
          by: azimuthPrimitive(u: u, offsetU: offsetU, offsetV: offsetV, using: &execution).adding(
            Jet.constant(radius, using: &execution).multiplied(by: u, using: &execution),
            using: &execution), using: &execution))
    case .cone(
      let
        sine,
      let
        cosine,
      let
        radialOffsetU,
      let
        radialOffsetV,
      let
        axialOffset
    ):
      return
        (try Jet.constant(sine / .exact(3.0), using: &execution).multiplied(
          by: Jet.constant(cosine, using: &execution).multiplied(
            by: azimuthPrimitive(
              u: u,
              offsetU: radialOffsetU,
              offsetV: radialOffsetV, using: &execution
            ), using: &execution
          ).subtracting(
            Jet.constant(sine * axialOffset, using: &execution).multiplied(
              by: u, using: &execution), using: &execution), using: &execution
        ).multiplied(by: v, using: &execution))
    case .sphere(
      let
        radius,
      let
        radialOffsetU,
      let
        radialOffsetV,
      let
        axialOffset
    ):
      let values = (try v.sineAndCosine(using: &execution))
      return
        (try Jet.constant(radius * radius / .exact(3.0), using: &execution).multiplied(
          by: azimuthPrimitive(
            u: u,
            offsetU: radialOffsetU,
            offsetV: radialOffsetV, using: &execution
          ).multiplied(by: values.cosine, using: &execution).multiplied(
            by: values.cosine, using: &execution
          ).adding(
            u.multiplied(
              by: Jet.constant(axialOffset, using: &execution).multiplied(
                by: values.cosine, using: &execution
              ).multiplied(by: values.sine, using: &execution).adding(
                Jet.constant(radius, using: &execution).multiplied(
                  by: values.cosine, using: &execution), using: &execution), using: &execution),
            using: &execution), using: &execution))
    case .torus(
      let
        majorRadius,
      let
        minorRadius,
      let
        radialOffsetU,
      let
        radialOffsetV,
      let
        axialOffset
    ):
      let values = (try v.sineAndCosine(using: &execution))
      let azimuthTerm =
        (try azimuthPrimitive(
          u: u,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV, using: &execution
        ).multiplied(
          by: Jet.constant(majorRadius, using: &execution).multiplied(
            by: values.cosine, using: &execution
          ).adding(
            Jet.constant(minorRadius, using: &execution).multiplied(
              by: values.cosine, using: &execution
            ).multiplied(by: values.cosine, using: &execution), using: &execution),
          using: &execution))
      let axialTerm =
        (try u.multiplied(
          by: Jet.constant(axialOffset * majorRadius, using: &execution).multiplied(
            by: values.sine, using: &execution
          ).adding(
            Jet.constant(axialOffset * minorRadius, using: &execution).multiplied(
              by: values.cosine, using: &execution
            ).multiplied(by: values.sine, using: &execution), using: &execution
          ).adding(
            Jet.constant(majorRadius * majorRadius, using: &execution).multiplied(
              by: values.cosine, using: &execution), using: &execution
          ).adding(
            Jet.constant(majorRadius * minorRadius, using: &execution).multiplied(
              by: values.cosine, using: &execution
            ).multiplied(by: values.cosine, using: &execution), using: &execution
          ).adding(Jet.constant(minorRadius * majorRadius, using: &execution), using: &execution)
            .adding(
              Jet.constant(minorRadius * minorRadius, using: &execution).multiplied(
                by: values.cosine, using: &execution), using: &execution), using: &execution))
      return
        (try Jet.constant(minorRadius / .exact(3.0), using: &execution).multiplied(
          by: azimuthTerm.adding(axialTerm, using: &execution), using: &execution))
    }
  }

  private func azimuthPrimitive(
    u: Jet,
    offsetU: Interval,
    offsetV: Interval, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    let values = (try u.sineAndCosine(using: &execution))
    return
      (try Jet.constant(offsetU, using: &execution).multiplied(by: values.sine, using: &execution)
      .subtracting(
        Jet.constant(offsetV, using: &execution).multiplied(by: values.cosine, using: &execution),
        using: &execution))
  }

  private struct Jet {
    // The sixth derivative of a line integrand containing `v'` depends on
    // the seventh Taylor coefficient of the underlying pcurve.
    static let order = 7
    var coefficients: [Interval]

    static func variable(_ interval: Interval, using execution: inout OriginalQueryExecution) throws
      -> Jet
    {
      try execution.consumeWork(1)

      var coefficients =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: order + 1, using: &execution))
      coefficients[0] = interval
      coefficients[1] = .exact(1.0)
      return Jet(coefficients: coefficients)
    }

    static func constant(_ value: Double, using execution: inout OriginalQueryExecution) throws
      -> Jet
    {
      try execution.consumeWork(1)
      return

        (try constant(.exact(value), using: &execution))
    }

    static func constant(_ value: Interval, using execution: inout OriginalQueryExecution) throws
      -> Jet
    {
      try execution.consumeWork(1)

      var coefficients =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: order + 1, using: &execution))
      coefficients[0] = value
      return Jet(coefficients: coefficients)
    }

    static func antiderivative(
      constant: Interval,
      derivative: Jet, using execution: inout OriginalQueryExecution
    ) throws -> Jet {
      try execution.consumeWork(1)

      var coefficients =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: order + 1, using: &execution))
      coefficients[0] = constant
      for degree in 1...order {
        try execution.consumeWork(1)

        coefficients[degree] =
          derivative.coefficients[degree - 1]
          / .exact(Double(degree))
      }
      return Jet(coefficients: coefficients)
    }

    func negated(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        Jet(
          coefficients: (try OriginalParameterQueryStorage.map(
            coefficients, using: &execution, transform: { element, execution in -element })))
    }
    func adding(_ other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        Jet(
          coefficients: (try OriginalParameterQueryStorage.map(
            zip(coefficients, other.coefficients), using: &execution,
            transform: { pair, execution in
              let element = pair.0
              let secondElement = pair.1
              return element + secondElement
            })))
    }
    func subtracting(_ other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try self.adding(other.negated(using: &execution), using: &execution))
    }
    func multiplied(by other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      for degree in 0...Self.order {
        try execution.consumeWork(1)

        for index in 0...degree {
          try execution.consumeWork(1)

          result[degree] = result[degree] + coefficients[index] * other.coefficients[degree - index]
        }
      }
      return Jet(coefficients: result)
    }

    func divided(by denominator: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try self.multiplied(by: denominator.reciprocal(using: &execution), using: &execution))
    }

    func reciprocal(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      let constant = coefficients[0]
      guard constant.lower > 0.0 || constant.upper < 0.0 else {
        throw LocalProofFailure.intervalSingularity
      }
      let inverse = Interval.exact(1.0) / constant
      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      result[0] = inverse
      for degree in 1...Self.order {
        try execution.consumeWork(1)

        var sum = Interval.exact(0.0)
        for index in 1...degree {
          try execution.consumeWork(1)

          sum = sum + coefficients[index] * result[degree - index]
        }
        result[degree] = -inverse * sum
      }
      return Jet(coefficients: result)
    }

    func derivative(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      for degree in 0..<Self.order {
        try execution.consumeWork(1)

        result[degree] = coefficients[degree + 1] * .exact(Double(degree + 1))
      }
      return Jet(coefficients: result)
    }

    func squareRoot(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      let constant = coefficients[0]
      guard constant.lower > 0.0 else {
        throw LocalProofFailure.intervalSingularity
      }
      let root = Interval(
        lower: sqrt(constant.lower).nextDown,
        upper: sqrt(constant.upper).nextUp
      )
      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      result[0] = root
      let denominator = root * .exact(2.0)
      for degree in 1...Self.order {
        try execution.consumeWork(1)

        var crossTerms = Interval.exact(0.0)
        if degree > 1 {
          for index in 1..<degree {
            try execution.consumeWork(1)

            crossTerms = crossTerms + result[index] * result[degree - index]
          }
        }
        result[degree] = (coefficients[degree] - crossTerms) / denominator
      }
      return Jet(coefficients: result)
    }

    func sineAndCosine(using execution: inout OriginalQueryExecution) throws -> (
      sine: Jet, cosine: Jet
    ) {
      try execution.consumeWork(1)

      var sine =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      var cosine =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      sine[0] = .sine(coefficients[0])
      cosine[0] = .cosine(coefficients[0])
      for degree in 1...Self.order {
        try execution.consumeWork(1)

        var sineSum = Interval.exact(0.0)
        var cosineSum = Interval.exact(0.0)
        for index in 1...degree {
          try execution.consumeWork(1)

          let derivativeCoefficient =
            coefficients[index]
            * .exact(Double(index))
          sineSum =
            sineSum
            + derivativeCoefficient * cosine[degree - index]
          cosineSum =
            cosineSum
            + derivativeCoefficient * sine[degree - index]
        }
        sine[degree] = sineSum / .exact(Double(degree))
        cosine[degree] = -cosineSum / .exact(Double(degree))
      }
      return (
        sine: Jet(coefficients: sine),
        cosine: Jet(coefficients: cosine)
      )
    }

    func hyperbolicSineAndCosine(using execution: inout OriginalQueryExecution) throws -> (
      sine: Jet, cosine: Jet
    ) {
      try execution.consumeWork(1)

      var sine =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      var cosine =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: Self.order + 1, using: &execution))
      sine[0] = (try .hyperbolicSine(coefficients[0], using: &execution))
      cosine[0] = (try .hyperbolicCosine(coefficients[0], using: &execution))
      for degree in 1...Self.order {
        try execution.consumeWork(1)

        var sineSum = Interval.exact(0.0)
        var cosineSum = Interval.exact(0.0)
        for index in 1...degree {
          try execution.consumeWork(1)

          let derivativeCoefficient =
            coefficients[index]
            * .exact(Double(index))
          sineSum =
            sineSum
            + derivativeCoefficient * cosine[degree - index]
          cosineSum =
            cosineSum
            + derivativeCoefficient * sine[degree - index]
        }
        sine[degree] = sineSum / .exact(Double(degree))
        cosine[degree] = cosineSum / .exact(Double(degree))
      }
      return (
        sine: Jet(coefficients: sine),
        cosine: Jet(coefficients: cosine)
      )
    }
  }

  private func resourceFailure(
    residual: Double?,
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .topology,
      code: .resourceLimitExceeded,
      residual: residual,
      tolerance: tolerance,
      message: message
    )
  }
}

extension TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
  fileprivate static func hyperbolicSine(
    _ value: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
    using execution: inout OriginalQueryExecution
  ) throws -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
    try execution.consumeWork(1)

    var lower = sinh(value.lower)
    var upper = sinh(value.upper)
    for _ in 0..<16 {
      try execution.consumeWork(1)

      lower = lower.nextDown
      upper = upper.nextUp
    }
    return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
      lower: lower,
      upper: upper
    )
  }

  fileprivate static func hyperbolicCosine(
    _ value: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
    using execution: inout OriginalQueryExecution
  ) throws -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
    try execution.consumeWork(1)

    let lower: Double
    if value.lower <= 0.0, value.upper >= 0.0 {
      lower = 1.0
    } else {
      lower = min(cosh(value.lower), cosh(value.upper))
    }
    var outwardLower = lower
    var outwardUpper = max(cosh(value.lower), cosh(value.upper))
    for _ in 0..<16 {
      try execution.consumeWork(1)

      outwardLower = outwardLower.nextDown
      outwardUpper = outwardUpper.nextUp
    }
    return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
      lower: max(1.0, outwardLower),
      upper: outwardUpper
    )
  }
}

/// Preserves the existing optional numeric diagnostic spelling without reflection.
private func analyticFluxOptionalDiagnostic<Value: CustomStringConvertible>(
  _ value: Value?, using execution: inout OriginalQueryExecution
) throws -> String {
  try execution.consumeWork(1)

  if let value { return "Optional(" + value.description + ")" }
  return "nil"
}

// Actual typed frontier and coefficient allocation operations share the caller execution.
