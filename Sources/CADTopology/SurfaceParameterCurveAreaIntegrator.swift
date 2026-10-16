import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

package struct SurfaceParameterCurveAreaIntegrator {
  private struct WorkItem {
    let patch: RationalBezierCurvePatch2D
    let requestedWidth: Double
    let depth: Int
  }

  private struct ImplicitWorkItem {
    let lowerFraction: Double
    let upperFraction: Double
    let requestedWidth: Double
    let depth: Int
  }

  private let maximumSubdivisionDepth: Int
  private let remainingSourceDepth: Int
  private let maximumAlgebraicDepth: Int
  private let maximumImplicitSubdivisionDepthBeforeToleranceFloor = 8
  private let maximumCellCount = 131_072

  package init(maximumSubdivisionDepth: Int = 40,
    remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32) {
    self.maximumSubdivisionDepth = min(40, maximumSubdivisionDepth)
    self.remainingSourceDepth = min(16, remainingSourceDepth)
    self.maximumAlgebraicDepth = maximumAlgebraicDepth
  }

  private func standaloneExecution() throws -> OriginalQueryExecution {
    OriginalQueryExecution(budget: try OriginalQueryBudget(),
      limits: try .init(maximumValueDepth: maximumAlgebraicDepth,
        maximumCoefficientDepth: maximumAlgebraicDepth,
        remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
  }

  package func bounds(for curve: SurfaceParameterCurve, on surface: Surface3D,
    uShift: Double, requestedWidth: Double, tolerance: ModelingTolerance) throws -> SurfaceParameterAreaBounds {
    var execution = try standaloneExecution()
    return try bounds(for: curve, on: surface, uShift: uShift,
      requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  package func bounds(for curve: SurfaceParameterCurve, uShift: Double,
    requestedWidth: Double, tolerance: ModelingTolerance) throws -> SurfaceParameterAreaBounds {
    var execution = try standaloneExecution()
    return try bounds(for: curve, uShift: uShift,
      requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  package func periodicConeBounds(for curve: SurfaceParameterCurve,
    requestedWidth: Double, tolerance: ModelingTolerance) throws -> SurfaceParameterAreaBounds {
    var execution = try standaloneExecution()
    return try periodicConeBounds(for: curve, requestedWidth: requestedWidth,
      tolerance: tolerance, using: &execution)
  }

  package func bounds(for curve: SurfaceParameterCurve, on surface: Surface3D,
    uShift: Double, requestedWidth: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    guard maximumSubdivisionDepth >= 0, remainingSourceDepth > 0, (0...32).contains(maximumAlgebraicDepth), uShift.isFinite, requestedWidth.isFinite, requestedWidth > 0 else {
      throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
        message: "Original bounded UV area requires valid caller depth and finite integral width.")
    }
    try curve.validate(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    if let linear = try OriginalLinearPcurveFluxIntegrator().bounds(for: curve, uShift: uShift,
      requestedWidth: requestedWidth, tolerance: tolerance, using: &execution) { return linear }
    return try originalChartBounds(for: curve, on: surface, uShift: uShift,
      requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  package func bounds(
    for curve: SurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard maximumSubdivisionDepth >= 0, remainingSourceDepth > 0,
      (0...32).contains(maximumAlgebraicDepth), uShift.isFinite,
      requestedWidth.isFinite,
      requestedWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Surface-parameter area integration requires finite positive options."
      )
    }
    switch curve {
    case .originalAffineWord(let image):
      return try originalChartBounds(for: curve, on: .procedural(.originalAffineWord(image.target)),
        uShift: uShift, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
    case .originalImage(let image):
      return try originalChartBounds(for: curve, on: .parameterImage(image.targetImage),
        uShift: uShift, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
    case .originalBSplineContinuation:
      // A numeric UV law needs no physical support metric. The canonical plane
      // binds its two source coordinates for the original chart producer.
      return try originalChartBounds(for: curve, on: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0), normal: .unitZ)),
        uShift: uShift, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
    case .affine(let origin, let direction, let startParameter, let endParameter):
      let start = SurfaceParameter(
        u: origin.x + direction.x * startParameter + uShift,
        v: origin.y + direction.y * startParameter
      )
      let end = SurfaceParameter(
        u: origin.x + direction.x * endParameter + uShift,
        v: origin.y + direction.y * endParameter
      )
      return linearContribution(from: start, to: end)
    case .constantU(let u, let vStart, let vEnd):
      return productBounds(
        u + uShift,
        vEnd - vStart
      )
    case .constantV:
      return .zero
    case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
      return harmonicContribution(
        center: Point2D(x: center.x + uShift, y: center.y),
        cosine: cosine,
        sine: sine,
        startParameter: startParameter,
        endParameter: endParameter
      )
    case .polyline(let points):
      var result = SurfaceParameterAreaBounds.zero
      for index in 1..<points.count {
      try execution.consumeWork(1)
        result = result.adding(
          linearContribution(
            from: SurfaceParameter(
              u: points[index - 1].u + uShift,
              v: points[index - 1].v
            ),
            to: SurfaceParameter(
              u: points[index].u + uShift,
              v: points[index].v
            )
          ))
      }
      return result
    case .bSpline(let spline):
      return try bSplineBounds(
        for: spline,
        uShift: uShift,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .certifiedImplicit(let certified):
      return try certifiedImplicitBounds(
        for: certified,
        uShift: uShift,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .certifiedAnalyticImplicit(let certified):
      return try CertifiedAnalyticImplicitPcurveAreaIntegrator().bounds(
        for: certified,
        uShift: uShift,
        tolerance: tolerance, using: &execution
      )
    case .sphericalGreatCircle(let cosine, let sine, let startParameter, let endParameter):
      return try SphericalGreatCirclePcurveAreaIntegrator().bounds(
        cosine: cosine,
        sine: sine,
        startParameter: startParameter,
        endParameter: endParameter,
        uShift: uShift,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .certifiedAnalyticPair(let certified):
      return try CertifiedAnalyticPairPcurveAreaIntegrator().bounds(
        for: certified,
        uShift: uShift,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .projectedAnalytic(let projected):
      let bounds = try CertifiedAnalyticPcurveFluxIntegrator()
        .projectedParameterAreaBounds(
          for: projected,
          uShift: uShift,
          requestedWidth: requestedWidth,
          tolerance: tolerance, using: &execution
        )
      return SurfaceParameterAreaBounds(
        lower: bounds.lower,
        upper: bounds.upper
      )
    case .rigidImage(let image):
      if let mapping = try image.affineParameterTransform(
        tolerance: tolerance, using: &execution
      ) {
        return try affineRigidImageBounds(
          image: image,
          mapping: mapping,
          uShift: uShift,
          requestedWidth: requestedWidth,
          tolerance: tolerance, using: &execution
        )
      }
      return try sphericalRigidImageBounds(
        image: image,
        uShift: uShift,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .offsetSurfaceImage(let image):
      return try bounds(
        for: image.source,
        uShift: uShift,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, let translatedU, _):
      return try bounds(
        for: base,
        uShift: uShift + translatedU,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    }
  }

  private func originalChartBounds(for curve: SurfaceParameterCurve, on surface: Surface3D,
    uShift: Double, requestedWidth: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterAreaBounds {
    return try execution.withAllocationScope(policy: .none, workLimit: maximumCellCount) { execution in
    try execution.consumeWork(1)
    // FIXME(INCOMPLETE_IMPLEMENTATION): Original numeric/native UV flux now
    // shares bounded preparation and query admission. Implicit/inverse chart
    // root producers still require their complete supported-family direct ports
    // before this production loop-area route can claim all-family closure.
    let chart = try SurfaceAreaParameterChartEncloser(curve: curve, on: surface,
      tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
      using: &execution)
    let first = try chart.endpointBounds(atEnd: false, tolerance: tolerance, using: &execution)
    let last = try chart.endpointBounds(atEnd: true, tolerance: tolerance, using: &execution)
    let correction = OutwardScalarInterval.exact(uShift)
      * (OutwardScalarInterval(lower: last.v.lower, upper: last.v.upper)
        - OutwardScalarInterval(lower: first.v.lower, upper: first.v.upper))
    guard correction.isFinite, correction.width < requestedWidth else {
      throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original UV endpoint uncertainty exceeds the requested integral accuracy.")
    }
    var pending: [(range: ScalarInterval, target: Double, depth: Int)] = []
    try OriginalParameterQueryStorage.reserve(maximumSubdivisionDepth + 1, in: &pending,
      using: &execution)
    try OriginalParameterQueryStorage.append((try ScalarInterval(lower: 0, upper: 1),
      ((requestedWidth-correction.width)/2).nextDown, 0), to: &pending, using: &execution)
    var integral = OutwardScalarInterval.exact(0)
    while let item = pending.popLast() {
      try execution.visitGeometricCell(depth: item.depth)
      var accepted: OutwardScalarInterval?
      do {
        let bounds = try chart.signedFluxIntegrationBounds(over: item.range,
          tolerance: tolerance, using: &execution)
        let span = OutwardScalarInterval.exact(item.range.upper) - .exact(item.range.lower)
        var value = bounds.value * span
        if let midpoint = bounds.midpoint, let second = bounds.secondDerivative {
          let secondMagnitude = max(abs(second.lower), abs(second.upper)).nextUp
          let remainder = OutwardScalarInterval.exact(secondMagnitude) * span * span * span
            * OutwardScalarInterval(1.0/24)
          let taylor = midpoint * span + OutwardScalarInterval(lower: -remainder.upper, upper: remainder.upper)
          guard let combined = value.intersection(with: taylor) else {
            throw KernelError(phase: .topology, code: .classificationFailure, tolerance: tolerance,
              message: "Original UV flux value and Taylor enclosures disagree.")
          }
          value = combined
        }
        guard value.isFinite else {
          throw KernelError(phase: .topology, code: .classificationFailure, tolerance: tolerance,
            message: "Original UV flux has nonfinite integral arithmetic.")
        }
        if value.width <= item.target { accepted = value }
      } catch is SurfaceAreaEnclosureRefinementRequired {}
      if let accepted { integral = integral + accepted; continue }
      let middle = item.range.midpoint
      guard item.depth < maximumSubdivisionDepth, middle > item.range.lower, middle < item.range.upper,
        item.target/2 > 0 else {
        throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original UV flux did not resolve within its original depth and accuracy allowance.")
      }
      try OriginalParameterQueryStorage.append((try ScalarInterval(lower: middle, upper: item.range.upper), item.target/2, item.depth+1), to: &pending, using: &execution)
      try OriginalParameterQueryStorage.append((try ScalarInterval(lower: item.range.lower, upper: middle), item.target/2, item.depth+1), to: &pending, using: &execution)
    }
    let result = integral + correction
    guard result.isFinite, result.width <= requestedWidth else {
      throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original UV flux summation did not achieve the requested complete error width.")
    }
    return SurfaceParameterAreaBounds(lower: result.lower, upper: result.upper)
      }
  }

  /// Integrates the periodic cone area gauge `-v du`.
  ///
  /// The ordinary Green primitive `u dv` differs by the exact differential
  /// `d(uv)`. Analytic-pair curves are certified directly in the periodic
  /// gauge; every other representation reuses its ordinary integral plus
  /// the exact endpoint correction. Keeping this operation here guarantees
  /// that topology validation and volume orientation use the same pcurve
  /// representation rules.
  package func periodicConeBounds(
    for curve: SurfaceParameterCurve,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard requestedWidth.isFinite, requestedWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message:
          "Periodic cone parameter-area integration requires a finite positive enclosure width."
      )
    }
    switch curve {
    case .certifiedAnalyticPair(let certified):
      return try CertifiedAnalyticPairPcurveAreaIntegrator()
        .periodicConeAreaBounds(
          for: certified,
          requestedWidth: requestedWidth,
          tolerance: tolerance, using: &execution
        )
    case .offsetSurfaceImage(let image):
      return try periodicConeBounds(
        for: image.source,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, let uShift, let vShift):
      let period = 2.0 * Double.pi
      let turns = uShift / period
      guard vShift == 0.0,
        uShift.isFinite,
        abs(turns - turns.rounded()) <= tolerance.relative
      else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          residual: max(abs(uShift), abs(vShift)),
          tolerance: tolerance,
          message:
            "A cone pcurve translation must preserve its periodic U chart and non-periodic V coordinate."
        )
      }
      return try periodicConeBounds(
        for: base,
        requestedWidth: requestedWidth,
        tolerance: tolerance, using: &execution
      )
    default:
      let start = try curve.parameter(
        atNormalizedFraction: 0.0,
        tolerance: tolerance, using: &execution
      )
      let end = try curve.parameter(
        atNormalizedFraction: 1.0,
        tolerance: tolerance, using: &execution
      )
      // -v du = u dv - d(uv).
      let correction = productBounds(start.u, start.v).adding(
        productBounds(-end.u, end.v)
      )
      let remainingWidth = (requestedWidth - correction.width).nextDown
      guard remainingWidth.isFinite, remainingWidth > 0.0 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: correction.width,
          tolerance: tolerance,
          message:
            "Periodic cone parameter area exhausted its enclosure width in the exact boundary-gauge correction."
        )
      }
      let primitive = try bounds(
        for: curve,
        uShift: 0.0,
        requestedWidth: remainingWidth,
        tolerance: tolerance, using: &execution
      )
      let result = primitive.adding(correction)
      guard result.width <= requestedWidth.nextUp else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: result.width,
          tolerance: tolerance,
          message: "Periodic cone parameter area exceeded its composed enclosure width."
        )
      }
      return result
    }
  }

  private func certifiedImplicitBounds(
    for curve: CertifiedImplicitSurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    try curve.intersection.validate(tolerance: tolerance, using: &execution)
    let selectedU: SurfaceIntersectionParameterCoordinate =
      curve.role == .first
      ? .firstU
      : .secondU
    let selectedV: SurfaceIntersectionParameterCoordinate =
      curve.role == .first
      ? .firstV
      : .secondV
    guard curve.intersection.cells.isEmpty == false else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified implicit pcurve area requires at least one graph cell."
      )
    }
    let traversalSegments = try curve.canonicalTraversalSegments(
      tolerance: tolerance, using: &execution
    )
    let requestedSpan = abs(curve.endFraction - curve.startFraction)
    let cellCount = curve.intersection.cells.count
    var result = SurfaceParameterAreaBounds.zero
    var remainingCells = maximumCellCount
    for traversal in traversalSegments {
      try execution.consumeWork(1)
      for (index, cell) in curve.intersection.cells.enumerated() {
      try execution.consumeWork(1)
        let cellStart = Double(index) / Double(cellCount)
        let cellEnd = Double(index + 1) / Double(cellCount)
        let overlapStart = max(traversal.canonicalLowerFraction, cellStart)
        let overlapEnd = min(traversal.canonicalUpperFraction, cellEnd)
        guard overlapEnd > overlapStart else { continue }
        let localStart = (overlapStart - cellStart) * Double(cellCount)
        let localEnd = (overlapEnd - cellStart) * Double(cellCount)
        let derivativeBounds = try cell.parameterDerivativeBounds(
          firstSurface: curve.intersection.firstSurface,
          secondSurface: curve.intersection.secondSurface,
          tolerance: tolerance, using: &execution
        )
        try execution.retainStorage(bytes: MemoryLayout<ImplicitWorkItem>.stride)
        var stack = [
          ImplicitWorkItem(
            lowerFraction: localStart,
            upperFraction: localEnd,
            requestedWidth: requestedWidth
              * (overlapEnd - overlapStart) / requestedSpan,
            depth: 0
          )
        ]
        while let item = stack.popLast() {
      try execution.visitGeometricCell(depth: item.depth)
          guard remainingCells > 0 else {
            throw KernelError(
              phase: .topology,
              code: .resourceLimitExceeded,
              tolerance: tolerance,
              message: "Certified implicit pcurve area integration exceeded its cell budget."
            )
          }
          remainingCells -= 1
          let contribution = try implicitContributionBounds(
            in: cell,
            selectedU: selectedU,
            selectedV: selectedV,
            derivativeBounds: derivativeBounds,
            lowerFraction: item.lowerFraction,
            upperFraction: item.upperFraction,
            uShift: uShift,
            firstSurface: curve.intersection.firstSurface,
            secondSurface: curve.intersection.secondSurface,
            tolerance: tolerance, using: &execution
          )
          // Numerical graph anchors carry the modeling-distance uncertainty.
          // Past this depth, further bisection cannot reduce that term; the
          // conservative enclosure remains authoritative for the caller.
          let orientedContribution =
            traversal.direction == .forward
            ? contribution
            : SurfaceParameterAreaBounds(
              lower: (-contribution.upper).nextDown,
              upper: (-contribution.lower).nextUp
            )
          if contribution.width <= item.requestedWidth
            || item.depth == maximumImplicitSubdivisionDepthBeforeToleranceFloor
          {
            result = result.adding(orientedContribution)
            continue
          }
          guard item.depth < maximumSubdivisionDepth else {
            throw KernelError(
              phase: .topology,
              code: .resourceLimitExceeded,
              residual: contribution.width,
              tolerance: tolerance,
              message: "Certified implicit pcurve area integration exceeded its subdivision depth."
            )
          }
          let midpoint =
            item.lowerFraction
            + (item.upperFraction - item.lowerFraction) * 0.5
          guard midpoint > item.lowerFraction,
            midpoint < item.upperFraction
          else {
            throw KernelError(
              phase: .topology,
              code: .resourceLimitExceeded,
              tolerance: tolerance,
              message:
                "Certified implicit pcurve area subdivision reached floating-point resolution."
            )
          }
          let childWidth = item.requestedWidth * 0.5
          try OriginalParameterQueryStorage.append(
            ImplicitWorkItem(
              lowerFraction: midpoint,
              upperFraction: item.upperFraction,
              requestedWidth: childWidth,
              depth: item.depth + 1
            ), to: &stack, using: &execution)
          try OriginalParameterQueryStorage.append(
            ImplicitWorkItem(
              lowerFraction: item.lowerFraction,
              upperFraction: midpoint,
              requestedWidth: childWidth,
              depth: item.depth + 1
            ), to: &stack, using: &execution)
        }
      }
    }
    return result
  }

  private func implicitContributionBounds(
    in cell: CertifiedImplicitIntersectionGraphCell,
    selectedU: SurfaceIntersectionParameterCoordinate,
    selectedV: SurfaceIntersectionParameterCoordinate,
    derivativeBounds: [ScalarInterval],
    lowerFraction: Double,
    upperFraction: Double,
    uShift: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    let start = try cell.parameterPair(
      atNormalizedFraction: lowerFraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance, using: &execution
    )
    let end = try cell.parameterPair(
      atNormalizedFraction: upperFraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance, using: &execution
    )
    let uncertainty = tolerance.distance
    let uInterval = cell.parameterBox.interval(for: selectedU)
    let vInterval = cell.parameterBox.interval(for: selectedV)
    let startU = localizedValueBounds(
      start.values[selectedU.rawValue] + uShift,
      within: try ScalarInterval(
        lower: uInterval.lower + uShift,
        upper: uInterval.upper + uShift
      ),
      uncertainty: uncertainty
    )
    let startV = localizedValueBounds(
      start.values[selectedV.rawValue],
      within: vInterval,
      uncertainty: uncertainty
    )
    let endV = localizedValueBounds(
      end.values[selectedV.rawValue],
      within: vInterval,
      uncertainty: uncertainty
    )
    let deltaV = (
      lower: (endV.lower - startV.upper).nextDown,
      upper: (endV.upper - startV.lower).nextUp
    )
    let base = intervalProductBounds(
      lower: startU.lower,
      upper: startU.upper,
      scalarLower: deltaV.lower,
      scalarUpper: deltaV.upper
    )
    let span = upperFraction - lowerFraction
    let uDerivative = derivativeBounds[selectedU.rawValue]
    let vDerivative = derivativeBounds[selectedV.rawValue]
    let uVariation =
      (max(abs(uDerivative.lower), abs(uDerivative.upper)) * span
      + 2.0 * uncertainty).nextUp
    let vVariation = (max(abs(vDerivative.lower), abs(vDerivative.upper)) * span).nextUp
    let remainder = (uVariation * vVariation).nextUp
    let scale = max(
      abs(base.lower),
      abs(base.upper),
      abs(remainder),
      1.0
    )
    let roundoff = scale * Double.ulpOfOne * 16_384.0
    let error = (remainder + roundoff).nextUp
    return SurfaceParameterAreaBounds(
      lower: (base.lower - error).nextDown,
      upper: (base.upper + error).nextUp
    )
  }

  private func localizedValueBounds(
    _ value: Double,
    within interval: ScalarInterval,
    uncertainty: Double
  ) -> (lower: Double, upper: Double) {
    (
      max(interval.lower, value - uncertainty).nextDown,
      min(interval.upper, value + uncertainty).nextUp
    )
  }

  private func intervalProductBounds(
    lower: Double,
    upper: Double,
    scalarLower: Double,
    scalarUpper: Double
  ) -> SurfaceParameterAreaBounds {
    let products = [
      lower * scalarLower,
      lower * scalarUpper,
      upper * scalarLower,
      upper * scalarUpper,
    ]
    return SurfaceParameterAreaBounds(
      lower: (products.min() ?? -.infinity).nextDown,
      upper: (products.max() ?? .infinity).nextUp
    )
  }

  private func bSplineBounds(
    for curve: BSplineCurve2D,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    let patches = try curve.rationalBezierPatches(tolerance: tolerance, using: &execution)
    guard patches.isEmpty == false else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "B-spline pcurve area integration produced no Bezier spans."
      )
    }
    var polynomial = true
    for patch in patches {
      try execution.consumeWork(1)
      if try !polynomialBezierPatch(patch, using: &execution) { polynomial = false; break }
    }
    if polynomial {
      var result = SurfaceParameterAreaBounds.zero
      for patch in patches {
      try execution.consumeWork(1)
        result = result.adding(try polynomialBezierContributionBounds(patch, uShift: uShift, using: &execution))
      }
      return result
    }
    let patchWidth = requestedWidth / Double(patches.count)
    var stack = try OriginalParameterQueryStorage.map(patches, using: &execution) { patch, execution in
      WorkItem(patch: patch, requestedWidth: patchWidth, depth: 0)
    }
    var result = SurfaceParameterAreaBounds.zero
    var remainingCells = maximumCellCount
    while let item = stack.popLast() {
      try execution.visitGeometricCell(depth: item.depth)
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "B-spline pcurve area integration exceeded its cell budget."
        )
      }
      remainingCells -= 1
      let enclosure = try bezierContributionBounds(
        item.patch,
        uShift: uShift,
        tolerance: tolerance, using: &execution
      )
      if enclosure.width <= item.requestedWidth {
        result = result.adding(enclosure)
        continue
      }
      guard item.depth < maximumSubdivisionDepth else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: enclosure.width,
          tolerance: tolerance,
          message: "B-spline pcurve area integration exceeded its subdivision depth."
        )
      }
      let children = try item.patch.subdivided(tolerance: tolerance, using: &execution)
      let childWidth = item.requestedWidth * 0.5
      for child in children.reversed() {
      try execution.consumeWork(1)
        try OriginalParameterQueryStorage.append(
          WorkItem(
            patch: child,
            requestedWidth: childWidth,
            depth: item.depth + 1
          ), to: &stack, using: &execution)
      }
    }
    return result
  }

  private func polynomialBezierPatch(
    _ patch: RationalBezierCurvePatch2D, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    guard let firstWeight = patch.weights.first else { return false }
    for weight in patch.weights {
      try execution.consumeWork(1)
      if weight != firstWeight { return false }
    }
    return true
  }

  private func polynomialBezierContributionBounds(
    _ patch: RationalBezierCurvePatch2D,
    uShift: Double, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    let degree = patch.degree
    guard degree > 0 else { return .zero }
    var result = SurfaceParameterAreaBounds.zero
    for controlIndex in 0...degree {
      try execution.consumeWork(1)
      let u = patch.controlPoints[controlIndex].x + uShift
      for derivativeIndex in 0..<degree {
      try execution.consumeWork(1)
        let derivative =
          Double(degree)
          * (patch.controlPoints[derivativeIndex + 1].y
            - patch.controlPoints[derivativeIndex].y)
        let productDegree = 2 * degree - 1
        let productIndex = controlIndex + derivativeIndex
        let integralWeight =
          try bernsteinBinomial(degree, controlIndex, using: &execution)
          * bernsteinBinomial(degree - 1, derivativeIndex, using: &execution)
          / bernsteinBinomial(productDegree, productIndex, using: &execution)
          / Double(productDegree + 1)
        result = result.adding(
          productBounds(
            u,
            derivative * integralWeight
          ))
      }
    }
    return result
  }

  private func bernsteinBinomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> Double {
    try execution.consumeWork(1)
    guard k > 0, k < n else { return 1.0 }
    let reduced = min(k, n - k)
    var result = 1.0
    for index in 1...reduced {
      try execution.consumeWork(1)
      result = result * Double(n - reduced + index) / Double(index)
    }
    return result
  }

  private func bezierContributionBounds(
    _ patch: RationalBezierCurvePatch2D,
    uShift: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    guard patch.degree >= 1,
      patch.controlPoints.count == patch.weights.count,
      try weightBounds(patch.weights, using: &execution)?.positive == true,
      let start = patch.controlPoints.first,
      let end = patch.controlPoints.last
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "B-spline pcurve area integration requires a positive-weight Bezier span."
      )
    }
    if patch.degree == 1 {
      return linearContribution(
        from: SurfaceParameter(u: start.x + uShift, v: start.y),
        to: SurfaceParameter(u: end.x + uShift, v: end.y)
      )
    }
    let startParameter = SurfaceParameter(
      u: start.x + uShift,
      v: start.y
    )
    let endParameter = SurfaceParameter(
      u: end.x + uShift,
      v: end.y
    )
    let deviationU = try chordDeviationUpperBound(
      patch,
      coordinate: { $0.x },
      tolerance: tolerance, using: &execution
    )
    let deviationV = try chordDeviationUpperBound(
      patch,
      coordinate: { $0.y },
      tolerance: tolerance, using: &execution
    )
    let variationV = try verticalVariationUpperBound(
      patch,
      tolerance: tolerance, using: &execution
    )
    let deltaU = end.x - start.x
    let deltaV = end.y - start.y
    let central = linearContribution(
      from: startParameter,
      to: endParameter
    )
    let error =
      (deviationU * (2.0 * abs(deltaV) + variationV)
      + abs(deltaU) * deviationV).nextUp
    return SurfaceParameterAreaBounds(
      lower: (central.lower - error).nextDown,
      upper: (central.upper + error).nextUp
    )
  }

  private func chordDeviationUpperBound(
    _ patch: RationalBezierCurvePatch2D,
    coordinate: (Point2D) -> Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    guard let first = patch.controlPoints.first,
      let last = patch.controlPoints.last,
      let minimumWeight = try weightBounds(patch.weights, using: &execution)?.minimum,
      minimumWeight > Double.ulpOfOne
    else {
      throw KernelError(
        phase: .topology,
        code: .singularSystem,
        tolerance: tolerance,
        message: "B-spline chord deviation encountered a singular rational denominator."
      )
    }
    let degree = patch.degree
    let denominator = Double(degree + 1)
    var maximumHomogeneousDeviation = 0.0
    for index in 0...(degree + 1) {
      try execution.consumeWork(1)
      let alpha = Double(index) / denominator
      var coefficient = 0.0
      if index <= degree {
        coefficient +=
          (1.0 - alpha) * patch.weights[index]
          * (coordinate(patch.controlPoints[index])
            - coordinate(first))
      }
      if index > 0 {
        coefficient +=
          alpha * patch.weights[index - 1]
          * (coordinate(patch.controlPoints[index - 1])
            - coordinate(last))
      }
      maximumHomogeneousDeviation = max(
        maximumHomogeneousDeviation,
        abs(coefficient).nextUp
      )
    }
    let result = (maximumHomogeneousDeviation / minimumWeight).nextUp
    guard result.isFinite else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "B-spline chord deviation exceeded finite rational arithmetic."
      )
    }
    return result
  }

  private func verticalVariationUpperBound(
    _ patch: RationalBezierCurvePatch2D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    let degree = Double(patch.degree)
    var homogeneousIndex = 0
    let homogeneousV = try OriginalParameterQueryStorage.map(patch.controlPoints, using: &execution) { point, execution in
      let index = homogeneousIndex
      homogeneousIndex += 1
      return point.y * patch.weights[index]
    }
    var maximumV: Double?
    for value in homogeneousV {
      try execution.consumeWork(1)
      maximumV = max(maximumV ?? 0, abs(value))
    }
    let weights = try weightBounds(patch.weights, using: &execution)
    guard let minimumWeight = weights?.minimum,
      let maximumWeight = weights?.maximum,
      let maximumV,
      minimumWeight > Double.ulpOfOne
    else {
      throw KernelError(
        phase: .topology,
        code: .singularSystem,
        tolerance: tolerance,
        message: "B-spline pcurve area integration encountered a singular rational denominator."
      )
    }
    var maximumVDifference = 0.0
    var maximumWeightDifference = 0.0
    for index in 1..<patch.controlPoints.count {
      try execution.consumeWork(1)
      maximumVDifference = max(
        maximumVDifference,
        abs(homogeneousV[index] - homogeneousV[index - 1])
      )
      maximumWeightDifference = max(
        maximumWeightDifference,
        abs(patch.weights[index] - patch.weights[index - 1])
      )
    }
    let numerator =
      (degree * maximumVDifference * maximumWeight
      + maximumV * degree * maximumWeightDifference).nextUp
    let denominator = (minimumWeight * minimumWeight).nextDown
    guard numerator.isFinite,
      denominator.isFinite,
      denominator > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "B-spline pcurve area bounds exceeded finite rational arithmetic."
      )
    }
    return (numerator / denominator).nextUp
  }

  private func weightBounds(_ weights: [Double], using execution: inout OriginalQueryExecution)
    throws -> (minimum: Double, maximum: Double, positive: Bool)? {
    guard let first = weights.first else { return nil }
    var minimum = first, maximum = first
    var positive = true
    for weight in weights {
      try execution.consumeWork(1)
      minimum = min(minimum, weight); maximum = max(maximum, weight)
      positive = positive && weight.isFinite && weight > Double.ulpOfOne
    }
    return (minimum, maximum, positive)
  }

  private func linearContribution(
    from start: SurfaceParameter,
    to end: SurfaceParameter
  ) -> SurfaceParameterAreaBounds {
    productBounds(
      (start.u + end.u) * 0.5,
      end.v - start.v
    )
  }

  private func harmonicContribution(
    center: Point2D,
    cosine: Point2D,
    sine: Point2D,
    startParameter: Double,
    endParameter: Double
  ) -> SurfaceParameterAreaBounds {
    func areaPrimitive(_ parameter: Double) -> Double {
      (center.x * cosine.y - center.y * cosine.x) * cos(parameter)
        + (center.x * sine.y - center.y * sine.x) * sin(parameter)
        + (cosine.x * sine.y - cosine.y * sine.x) * parameter
    }
    func parameter(_ value: Double) -> SurfaceParameter {
      SurfaceParameter(
        u: center.x + cosine.x * cos(value) + sine.x * sin(value),
        v: center.y + cosine.y * cos(value) + sine.y * sin(value)
      )
    }
    let start = parameter(startParameter)
    let end = parameter(endParameter)
    let orientedArea = 0.5 * (areaPrimitive(endParameter) - areaPrimitive(startParameter))
    let endpointTerm = 0.5 * (end.u * end.v - start.u * start.v)
    let value = orientedArea + endpointTerm
    let scale = max(
      abs(value),
      abs(orientedArea),
      abs(endpointTerm),
      1.0
    )
    let roundoff = scale * Double.ulpOfOne * 1_024.0
    return SurfaceParameterAreaBounds(
      lower: (value - roundoff).nextDown,
      upper: (value + roundoff).nextUp
    )
  }

  private func productBounds(
    _ first: Double,
    _ second: Double
  ) -> SurfaceParameterAreaBounds {
    let value = first * second
    let scale = max(abs(value), Double.leastNormalMagnitude)
    let roundoff = scale * Double.ulpOfOne * 8.0
    return SurfaceParameterAreaBounds(
      lower: (value - roundoff).nextDown,
      upper: (value + roundoff).nextUp
    )
  }

  private func affineRigidImageBounds(
    image: RigidImageSurfaceParameterCurve,
    mapping: SurfaceParameterAffineTransform,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    let sourceCurve = try image.sourceParameterCurve(tolerance: tolerance)
    let determinant = mapping.determinant
    let source = try bounds(
      for: sourceCurve,
      uShift: 0.0,
      requestedWidth: requestedWidth
        / max(abs(determinant), Double.leastNormalMagnitude),
      tolerance: tolerance, using: &execution
    )
    let start = try sourceCurve.startParameter(tolerance: tolerance)
    let end = try sourceCurve.endParameter(tolerance: tolerance)
    let c = mapping.uOffset + uShift
    let correction =
      mapping.uu * mapping.vu * 0.5
      * (end.u * end.u - start.u * start.u)
      + mapping.uv * mapping.vu
      * (end.u * end.v - start.u * start.v)
      + mapping.uv * mapping.vv * 0.5
      * (end.v * end.v - start.v * start.v)
      + c * mapping.vu * (end.u - start.u)
      + c * mapping.vv * (end.v - start.v)
    let scaled: SurfaceParameterAreaBounds
    if determinant >= 0.0 {
      scaled = SurfaceParameterAreaBounds(
        lower: (source.lower * determinant).nextDown,
        upper: (source.upper * determinant).nextUp
      )
    } else {
      scaled = SurfaceParameterAreaBounds(
        lower: (source.upper * determinant).nextDown,
        upper: (source.lower * determinant).nextUp
      )
    }
    let scale = max(
      abs(correction),
      abs(scaled.lower),
      abs(scaled.upper),
      1.0
    )
    let roundoff = (scale * Double.ulpOfOne * 2_048.0).nextUp
    return SurfaceParameterAreaBounds(
      lower: (scaled.lower + correction - roundoff).nextDown,
      upper: (scaled.upper + correction + roundoff).nextUp
    )
  }

  private func sphericalRigidImageBounds(
    image: RigidImageSurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    guard case .analytic(.sphere(let center, let radius)) = image.targetSurface else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A non-affine rigid pcurve area integral requires a spherical target surface."
      )
    }
    var remainingCells = maximumCellCount
    try execution.retainStorage(bytes: MemoryLayout<ImplicitWorkItem>.stride)
    var stack: [ImplicitWorkItem] = [
      ImplicitWorkItem(
        lowerFraction: 0.0,
        upperFraction: 1.0,
        requestedWidth: requestedWidth,
        depth: 0
      )
    ]
    var result = SurfaceParameterAreaBounds.zero
    while let item = stack.popLast() {
      try execution.visitGeometricCell(depth: item.depth)
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Spherical rigid pcurve area integration exceeded its cell budget."
        )
      }
      remainingCells -= 1
      let midpoint =
        item.lowerFraction
        + (item.upperFraction - item.lowerFraction) * 0.5
      let halfSpan = (item.upperFraction - item.lowerFraction) * 0.5
      let geometry = try image.modelSpaceDifferential(
        atNormalizedFraction: midpoint,
        tolerance: tolerance, using: &execution
      )
      guard
        let derivativeBound =
          try image
          .modelSpaceFirstDerivativeMagnitude(
            fromNormalizedFraction: item.lowerFraction,
            toNormalizedFraction: item.upperFraction,
            tolerance: tolerance, using: &execution
          )
      else {
        throw KernelError(
          phase: .topology,
          code: .singularSystem,
          tolerance: tolerance,
          message: "Spherical rigid pcurve area integration requires a certified derivative bound."
        )
      }
      let direction = (geometry.position - center) / radius
      let radialLower =
        (hypot(direction.x, direction.y)
        - derivativeBound / radius * halfSpan).nextDown
      if radialLower > 0.0 {
        let angularDerivative = (derivativeBound / radius / radialLower).nextUp
        let parameter = try image.parameter(
          atNormalizedFraction: midpoint,
          tolerance: tolerance, using: &execution
        )
        let start = try image.parameter(
          atNormalizedFraction: item.lowerFraction,
          tolerance: tolerance, using: &execution
        )
        let end = try image.parameter(
          atNormalizedFraction: item.upperFraction,
          tolerance: tolerance, using: &execution
        )
        let central = (parameter.u + uShift) * (end.v - start.v)
        let uRadius = (angularDerivative * halfSpan).nextUp
        let variation =
          (angularDerivative
          * (item.upperFraction - item.lowerFraction)).nextUp
        let error = (uRadius * variation).nextUp
        let roundoff =
          (max(abs(central), error, 1.0)
          * Double.ulpOfOne * 2_048.0).nextUp
        let totalError = (error + roundoff).nextUp
        if 2.0 * totalError <= item.requestedWidth {
          result = result.adding(
            SurfaceParameterAreaBounds(
              lower: (central - totalError).nextDown,
              upper: (central + totalError).nextUp
            ))
          continue
        }
      }
      guard item.depth < maximumSubdivisionDepth else {
        throw KernelError(
          phase: .topology,
          code: .singularSystem,
          tolerance: tolerance,
          message: "A spherical rigid pcurve reaches a target-chart pole within tolerance."
        )
      }
      try OriginalParameterQueryStorage.append(
        ImplicitWorkItem(
          lowerFraction: midpoint,
          upperFraction: item.upperFraction,
          requestedWidth: item.requestedWidth * 0.5,
          depth: item.depth + 1
        ), to: &stack, using: &execution)
      try OriginalParameterQueryStorage.append(
        ImplicitWorkItem(
          lowerFraction: item.lowerFraction,
          upperFraction: midpoint,
          requestedWidth: item.requestedWidth * 0.5,
          depth: item.depth + 1
        ), to: &stack, using: &execution)
    }
    return result
  }
}
