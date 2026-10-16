import CADCore

#if !hasFeature(Embedded)
  import Foundation
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("CADGeometry numeric algorithms require the target C math module.")
#endif

extension BSplineCurve3D {
  fileprivate struct ProjectionStorage: Sendable {
    let curve: BSplineCurve3D
    let globalLower: Double
    let globalUpper: Double
    let hasEquivalentEndpoints: Bool
    let patches: [RationalBezierCurvePointProjectionPatch]
  }
  private enum ProjectionPreparation {
    case projected(CurveParameterProjection)
    case retained(ProjectionStorage)
  }
  package struct ParameterProjector: Sendable {
    fileprivate let storage: ProjectionStorage
    fileprivate let options: CurveParameterProjectionOptions
    fileprivate let tolerance: ModelingTolerance
    fileprivate let receipt: OriginalGeometryPreparationReceipt
    fileprivate let limits: OriginalQueryExecutionLimits
    fileprivate let contributions: [OriginalQueryContributionHandle]

    package func project(_ point: Point3D) throws -> CurveParameterProjection {
      var execution = try OriginalQueryExecution(
        budget: receipt.budget, limits: limits,
        contributions: contributions)
      return try project(point, using: &execution)
    }
    package func project(_ point: Point3D, using execution: inout OriginalQueryExecution) throws
      -> CurveParameterProjection
    {
      let currentPolicy = execution.effectiveLimits
      let spanLimit = min(
        currentPolicy.maximumSpans,
        currentPolicy.maximumNativeSpans ?? currentPolicy.maximumSpans)
      guard storage.patches.count <= spanLimit else {
        throw KernelError(
          phase: .geometry, code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Retained B-spline projection exceeds the current native span limit.")
      }
      if execution.budget === receipt.budget {
        return try execution.withContributionScopes(contributions) { execution in
          try receipt.admit(tolerance: tolerance, using: &execution)
          let result = try storage.curve.parameterProjection(
            of: point, prepared: self, using: &execution)
          try execution.checkpoint()
          return result
        }
      }
      try receipt.admit(tolerance: tolerance, using: &execution)
      let result = try storage.curve.parameterProjection(
        of: point, prepared: self, using: &execution)
      try execution.checkpoint()
      return result
    }
  }

  func parameterProjection(
    of point: Point3D, options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance
  ) throws -> CurveParameterProjection {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try parameterProjection(
      of: point, options: options, tolerance: tolerance, using: &execution)
  }

  func parameterProjection(
    of point: Point3D, options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    try options.validate(tolerance: tolerance)
    try point.validate()
    let prepared = try execution.withPreparationScope { execution -> ProjectionPreparation in
      try validate(tolerance: tolerance, using: &execution)
      if let exact = try exactLinearParameterProjection(
        of: point, options: options,
        tolerance: tolerance, using: &execution)
      {
        return .projected(exact)
      }
      return .retained(
        try makeProjectionStorage(options: options, tolerance: tolerance, using: &execution))
    }
    switch prepared.result {
    case .projected(let result):
      try execution.checkpoint()
      return result
    case .retained(let storage):
      let receipt = try OriginalGeometryPreparationReceipt(
        tolerance: tolerance, depth: prepared.depth, using: &execution)
      let projector = ParameterProjector(
        storage: storage, options: options, tolerance: tolerance,
        receipt: receipt, limits: execution.effectiveLimits,
        contributions: try execution.retainActiveContributionHandles())
      return try projector.project(point, using: &execution)
    }
  }

  private func exactLinearParameterProjection(
    of point: Point3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection? {
    guard degree == 1,
      controlPoints.count == 2,
      case .closed(let domainLower, let domainUpper) = domain
    else {
      return nil
    }
    let chord = controlPoints[1] - controlPoints[0]
    let squaredLength = chord.dot(chord)
    guard squaredLength > tolerance.distance * tolerance.distance else {
      return nil
    }
    let length = sqrt(squaredLength)
    let rawFraction = (point - controlPoints[0]).dot(chord) / squaredLength
    let weightScale = max(weights[0], weights[1]) / min(weights[0], weights[1])
    let parameterTolerance = max(
      domain.parameterResolution(tolerance: tolerance),
      tolerance.angle,
      tolerance.distance / length * (domainUpper - domainLower) * weightScale
    )
    guard rawFraction >= -tolerance.distance / length,
      rawFraction <= 1.0 + tolerance.distance / length
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "Point projects outside the exact linear B-spline segment."
      )
    }
    let fraction = min(max(rawFraction, 0.0), 1.0)
    let denominator =
      (1.0 - fraction) * weights[1]
      + fraction * weights[0]
    guard denominator.isFinite,
      denominator > Double.ulpOfOne
    else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        tolerance: tolerance,
        message: "Exact linear B-spline projection produced a singular rational parameter."
      )
    }
    let basisParameter = fraction * weights[0] / denominator
    var parameter =
      domainLower
      + (domainUpper - domainLower) * basisParameter
    let allowedLower = max(domainLower, options.parameterRange?.lower ?? domainLower)
    let allowedUpper = min(domainUpper, options.parameterRange?.upper ?? domainUpper)
    guard allowedUpper >= allowedLower,
      parameter >= allowedLower - parameterTolerance,
      parameter <= allowedUpper + parameterTolerance
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "Exact linear B-spline projection lies outside the requested parameter range."
      )
    }
    parameter = min(max(parameter, allowedLower), allowedUpper)
    let projectedPoint = try pointAssumingValid(
      at: parameter,
      tolerance: tolerance, using: &execution)
    let residual = (point - projectedPoint).length
    guard residual <= tolerance.distance else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: residual,
        tolerance: tolerance,
        message: "Point does not lie on the exact linear B-spline within tolerance."
      )
    }
    return try CurveParameterProjection(
      parameter: parameter,
      point: projectedPoint,
      residual: residual,
      iterations: 0
    )
  }

  package func makeParameterProjector(
    options: CurveParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance
  ) throws -> ParameterProjector {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try makeParameterProjector(options: options, tolerance: tolerance, using: &execution)
  }
  package func makeParameterProjector(
    options: CurveParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ParameterProjector {
    try options.validate(tolerance: tolerance)
    let prepared = try execution.withPreparationScope { execution in
      try validate(tolerance: tolerance, using: &execution)
      return try makeProjectionStorage(options: options, tolerance: tolerance, using: &execution)
    }
    let receipt = try OriginalGeometryPreparationReceipt(
      tolerance: tolerance, depth: prepared.depth, using: &execution)
    let result = ParameterProjector(
      storage: prepared.result, options: options, tolerance: tolerance,
      receipt: receipt, limits: execution.effectiveLimits,
      contributions: try execution.retainActiveContributionHandles())
    try execution.checkpoint()
    return result
  }
  private func makeProjectionStorage(
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ProjectionStorage {
    let searchCurve: BSplineCurve3D
    if isPeriodic, case .closed(let lower, let upper) = fundamentalDomain {
      searchCurve = try trimmed(
        from: options.parameterRange?.lower ?? lower,
        to: options.parameterRange?.upper ?? upper,
        expansionOptions: .init(maximumControlPointCount: options.maximumSubdivisionCells),
        tolerance: tolerance, using: &execution)
    } else if let range = options.parameterRange,
      parameterRange(range, matches: domain, tolerance: tolerance) == false
    {
      searchCurve = try trimmed(
        from: range.lower,
        to: range.upper,
        tolerance: tolerance, using: &execution)
    } else {
      searchCurve = self
    }
    guard case .closed(let globalLower, let globalUpper) = searchCurve.domain else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "B-spline inverse projection requires a bounded parameter domain."
      )
    }
    let hasEquivalentEndpoints = try searchCurve.pointAssumingValid(
      at: globalLower,
      tolerance: tolerance, using: &execution
    ).isApproximatelyEqual(
      to: searchCurve.pointAssumingValid(
        at: globalUpper,
        tolerance: tolerance, using: &execution),
      tolerance: tolerance.distance
    )
    let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
      curve: searchCurve,
      tolerance: tolerance, using: &execution)
    guard sourcePatches.isEmpty == false else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "B-spline inverse projection produced no bounded Bezier spans."
      )
    }
    let currentPolicy = execution.effectiveLimits
    let spanLimit = min(
      currentPolicy.maximumSpans,
      currentPolicy.maximumNativeSpans ?? currentPolicy.maximumSpans)
    guard sourcePatches.count <= spanLimit else {
      throw KernelError(
        phase: .geometry, code: .resourceLimitExceeded,
        tolerance: tolerance, message: "B-spline projection exceeds its native span limit.")
    }
    let patches = try OriginalCoefficientAllocation.map(elements: sourcePatches, using: &execution)
    { patch, execution in
      try RationalBezierCurvePointProjectionPatch(patch: patch, using: &execution)
    }
    return ProjectionStorage(
      curve: searchCurve, globalLower: globalLower,
      globalUpper: globalUpper, hasEquivalentEndpoints: hasEquivalentEndpoints, patches: patches)
  }

  private func parameterProjection(
    of point: Point3D,
    prepared projector: ParameterProjector, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    try point.validate()
    let globalLower = projector.storage.globalLower
    let globalUpper = projector.storage.globalUpper
    let hasEquivalentEndpoints = projector.storage.hasEquivalentEndpoints
    let patches = projector.storage.patches
    let options = projector.options
    let tolerance = projector.tolerance
    var bestWitness = try initialWitness(
      patches: patches,
      point: point,
      tolerance: tolerance, using: &execution)
    var stack = try OriginalCoefficientAllocation.map(
      elements: patches.reversed(), using: &execution
    ) { patch, execution in ProjectionCell(patch: patch, depth: 0) }
    var stackCapacity = stack.count
    var candidateCapacity = 0
    var remainingCells = options.maximumSubdivisionCells
    var remainingCandidates = options.maximumCandidateCount
    var candidates: [RefinedProjection] = []
    var unresolvedResidual: Double?

    while let cell = stack.popLast() {
      try execution.visitGeometricCell(depth: cell.depth)
      guard remainingCells > 0 else {
        throw resourceLimit(
          residual: bestWitness.residual,
          tolerance: tolerance,
          message: "B-spline inverse projection exceeded its subdivision cell budget."
        )
      }
      remainingCells -= 1
      let box = try cell.patch.boundingBox(tolerance: tolerance, using: &execution)
      let lowerBound = boundingBoxDistanceLowerBound(point: point, box: box)
      guard lowerBound <= tolerance.distance else { continue }
      let diameter = boundingBoxDiameterUpperBound(box)
      let parameterScale = max(
        1.0,
        abs(cell.patch.lower),
        abs(cell.patch.upper)
      )
      let parameterResolution = max(
        tolerance.relative * parameterScale,
        Double.ulpOfOne * parameterScale * 128.0
      )
      let requiresSubdivision =
        cell.depth < options.maximumSubdivisionDepth
        && diameter > tolerance.distance * 0.25
        && cell.patch.upper - cell.patch.lower > parameterResolution
      if requiresSubdivision {
        try execution.admitGeometricDepth(cell.depth + 1)
        for child in try cell.patch.subdivided(using: &execution).reversed() {
          try execution.consumeWork(1)
          try OriginalCoefficientAllocation.reserveAppend(
            to: &stack, capacity: &stackCapacity, using: &execution)
          stack.append(ProjectionCell(patch: child, depth: cell.depth + 1))
        }
        continue
      }

      let local = try refine(
        initialParameter: midpoint(cell.patch.lower, cell.patch.upper),
        bounds: (cell.patch.lower, cell.patch.upper),
        point: point,
        options: options,
        tolerance: tolerance, using: &execution)
      if local.residual < bestWitness.residual {
        bestWitness = local
      }
      let mayContainProjection =
        local.residual <= tolerance.distance
        || local.residual - diameter <= tolerance.distance
      if mayContainProjection {
        let canonical = try refine(
          initialParameter: local.parameter,
          bounds: (globalLower, globalUpper),
          point: point,
          options: options,
          tolerance: tolerance, using: &execution)
        if canonical.residual < bestWitness.residual {
          bestWitness = canonical
        }
        if canonical.residual <= tolerance.distance {
          if let index = try duplicateCandidateIndex(
            canonical,
            in: candidates,
            lower: globalLower,
            upper: globalUpper,
            hasEquivalentEndpoints: hasEquivalentEndpoints,
            tolerance: tolerance, using: &execution)
          {
            candidates[index] = preferredCandidate(
              candidates[index],
              canonical,
              lower: globalLower,
              upper: globalUpper,
              hasEquivalentEndpoints: hasEquivalentEndpoints,
              tolerance: tolerance
            )
          } else {
            guard remainingCandidates > 0 else {
              throw resourceLimit(
                residual: canonical.residual,
                tolerance: tolerance,
                message: "B-spline inverse projection exceeded its distinct-candidate budget."
              )
            }
            remainingCandidates -= 1
            try OriginalCoefficientAllocation.reserveAppend(
              to: &candidates, capacity: &candidateCapacity, using: &execution)
            candidates.append(canonical)
          }
          continue
        }
      }
      if local.residual - diameter <= tolerance.distance {
        unresolvedResidual = min(
          unresolvedResidual ?? local.residual,
          local.residual
        )
      }
    }

    if let unresolvedResidual {
      throw resourceLimit(
        residual: unresolvedResidual,
        tolerance: tolerance,
        message:
          "B-spline inverse projection could not certify all remaining control-hull candidates."
      )
    }
    let unique = try deduplicated(
      candidates,
      lower: globalLower,
      upper: globalUpper,
      hasEquivalentEndpoints: hasEquivalentEndpoints,
      tolerance: tolerance, using: &execution)
    guard
      let selected = try unique.min(by: { first, second in
        try execution.consumeWork(1)
        return projectionOrder(first, second)
      })
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: bestWitness.residual,
        tolerance: tolerance,
        message: "Point does not lie on the bounded B-spline curve within tolerance."
      )
    }
    guard unique.count == 1 else {
      throw KernelError(
        phase: .geometry,
        code: .ambiguousSelection,
        residual: selected.residual,
        tolerance: tolerance,
        message: "B-spline inverse projection has multiple distinct parameter solutions."
      )
    }
    return try CurveParameterProjection(
      parameter: selected.parameter,
      point: selected.point,
      residual: selected.residual,
      iterations: selected.iterations
    )
  }

  private func parameterRange(
    _ range: ScalarInterval,
    matches domain: ParameterDomain,
    tolerance: ModelingTolerance
  ) -> Bool {
    guard case .closed(let lower, let upper) = domain else { return false }
    let scale = max(1.0, abs(lower), abs(upper), upper - lower)
    let resolution = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 128.0
    )
    return abs(range.lower - lower) <= resolution
      && abs(range.upper - upper) <= resolution
  }

  private func initialWitness(
    patches: [RationalBezierCurvePointProjectionPatch],
    point: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> RefinedProjection {
    var result: RefinedProjection?
    for patch in patches {
      try execution.consumeWork(1)
      let parameter = midpoint(patch.lower, patch.upper)
      let curvePoint = try self.pointAssumingValid(
        at: parameter, tolerance: tolerance, using: &execution)
      let candidate = RefinedProjection(
        parameter: parameter,
        point: curvePoint,
        residual: outwardLength(curvePoint - point),
        iterations: 0
      )
      if candidate.residual < (result?.residual ?? .infinity) {
        result = candidate
      }
    }
    guard let result else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "B-spline inverse projection could not construct an initial residual witness."
      )
    }
    return result
  }

  private func refine(
    initialParameter: Double,
    bounds: (lower: Double, upper: Double),
    point: Point3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> RefinedProjection {
    var parameter = initialParameter
    var iterations = 0
    var damping = max(tolerance.relative, Double.ulpOfOne.squareRoot())
    let parameterScale = max(1.0, abs(bounds.lower), abs(bounds.upper), bounds.upper - bounds.lower)
    let parameterResolution = max(
      tolerance.relative * parameterScale,
      Double.ulpOfOne * parameterScale * 128.0
    )
    for iteration in 0..<options.maximumIterations {
      try execution.consumeWork(1)
      iterations = iteration + 1
      let geometry = try differentialGeometryAssumingValid(
        at: parameter,
        tolerance: tolerance, using: &execution)
      let offset = geometry.position - point
      let residual = outwardLength(offset)
      let gradient = offset.dot(geometry.firstDerivative)
      let derivativeScale = max(1.0, geometry.firstDerivative.length)
      let stationarityTolerance = max(
        tolerance.distance * tolerance.relative * derivativeScale,
        Double.ulpOfOne * derivativeScale * 128.0
      )
      let hessian =
        geometry.firstDerivative.dot(geometry.firstDerivative)
        + offset.dot(geometry.secondDerivative)
      // World-space stationarity alone leaves distinct numerical copies
      // of the same root on small curves. Resolve the undamped Newton
      // correction within the parameter-space root-identity threshold.
      if residual <= tolerance.distance,
        abs(gradient) <= stationarityTolerance,
        abs(gradient) <= abs(hessian) * parameterResolution * 0.25
      {
        break
      }
      let scale = max(1.0, abs(hessian))
      var accepted = false
      var nextParameter = parameter
      for _ in 0..<12 {
        try execution.consumeWork(1)
        let denominator = hessian + damping * scale
        if denominator.isFinite,
          abs(denominator) > Double.ulpOfOne * scale
        {
          let candidateParameter = min(
            max(parameter - gradient / denominator, bounds.lower),
            bounds.upper
          )
          let candidatePoint = try self.pointAssumingValid(
            at: candidateParameter,
            tolerance: tolerance, using: &execution)
          if outwardLength(candidatePoint - point) < residual {
            accepted = true
            nextParameter = candidateParameter
            damping = max(damping * 0.25, Double.ulpOfOne)
            break
          }
        }
        damping *= 8.0
      }
      guard accepted else { break }
      let change = abs(nextParameter - parameter)
      parameter = nextParameter
      if change <= parameterResolution * 0.25 {
        break
      }
    }
    let curvePoint = try self.pointAssumingValid(
      at: parameter,
      tolerance: tolerance, using: &execution)
    return RefinedProjection(
      parameter: parameter,
      point: curvePoint,
      residual: outwardLength(curvePoint - point),
      iterations: iterations
    )
  }

  private func deduplicated(
    _ candidates: [RefinedProjection],
    lower: Double,
    upper: Double,
    hasEquivalentEndpoints: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [RefinedProjection] {
    let scale = max(1.0, abs(lower), abs(upper), upper - lower)
    let resolution = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 128.0
    )
    let ordered = try orderedProjectionCandidates(candidates, using: &execution)
    try execution.retainStorage(
      count: candidates.count, stride: MemoryLayout<RefinedProjection>.stride)
    var result: [RefinedProjection] = []
    result.reserveCapacity(candidates.count)
    for candidate in ordered {
      try execution.consumeWork(1)
      if let index = try result.firstIndex(where: {
        try execution.consumeWork(1)
        return parametersAreEquivalent(
          $0.parameter,
          candidate.parameter,
          lower: lower,
          upper: upper,
          resolution: resolution,
          hasEquivalentEndpoints: hasEquivalentEndpoints
        )
      }) {
        result[index] = preferredCandidate(
          result[index],
          candidate,
          lower: lower,
          upper: upper,
          hasEquivalentEndpoints: hasEquivalentEndpoints,
          tolerance: tolerance
        )
      } else {
        result.append(candidate)
      }
    }
    return result
  }

  private func orderedProjectionCandidates(
    _ candidates: [RefinedProjection],
    using execution: inout OriginalQueryExecution
  ) throws -> [RefinedProjection] {
    guard candidates.count > 1 else { return candidates }
    try execution.retainStorage(
      count: candidates.count, stride: MemoryLayout<RefinedProjection>.stride)
    try execution.retainStorage(
      count: candidates.count, stride: MemoryLayout<RefinedProjection>.stride)
    var ordered = candidates
    var scratch = candidates
    var width = 1
    while width < candidates.count {
      var base = 0
      while base < candidates.count {
        let middle = min(base + width, candidates.count)
        let end = min(middle + width, candidates.count)
        var first = base
        var second = middle
        for output in base..<end {
          try execution.consumeWork(1)
          if first < middle && (second == end || !projectionOrder(ordered[second], ordered[first]))
          {
            scratch[output] = ordered[first]
            first += 1
          } else {
            scratch[output] = ordered[second]
            second += 1
          }
        }
        base = end
      }
      swap(&ordered, &scratch)
      let next = width.multipliedReportingOverflow(by: 2)
      guard !next.overflow else { throw ExactScalarFailure.countOverflow }
      width = next.partialValue
    }
    return ordered
  }

  private func duplicateCandidateIndex(
    _ candidate: RefinedProjection,
    in candidates: [RefinedProjection],
    lower: Double,
    upper: Double,
    hasEquivalentEndpoints: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Int? {
    let scale = max(1.0, abs(lower), abs(upper), upper - lower)
    let resolution = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 128.0
    )
    return try candidates.firstIndex {
      try execution.consumeWork(1)
      return parametersAreEquivalent(
        $0.parameter,
        candidate.parameter,
        lower: lower,
        upper: upper,
        resolution: resolution,
        hasEquivalentEndpoints: hasEquivalentEndpoints
      )
    }
  }

  private func parametersAreEquivalent(
    _ first: Double,
    _ second: Double,
    lower: Double,
    upper: Double,
    resolution: Double,
    hasEquivalentEndpoints: Bool
  ) -> Bool {
    if abs(first - second) <= resolution {
      return true
    }
    guard hasEquivalentEndpoints else { return false }
    return (abs(first - lower) <= resolution && abs(second - upper) <= resolution)
      || (abs(first - upper) <= resolution && abs(second - lower) <= resolution)
  }

  private func preferredCandidate(
    _ first: RefinedProjection,
    _ second: RefinedProjection,
    lower: Double,
    upper: Double,
    hasEquivalentEndpoints: Bool,
    tolerance: ModelingTolerance
  ) -> RefinedProjection {
    let scale = max(1.0, abs(lower), abs(upper), upper - lower)
    let resolution = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 128.0
    )
    if hasEquivalentEndpoints {
      let firstIsLower = abs(first.parameter - lower) <= resolution
      let secondIsLower = abs(second.parameter - lower) <= resolution
      let firstIsUpper = abs(first.parameter - upper) <= resolution
      let secondIsUpper = abs(second.parameter - upper) <= resolution
      if firstIsLower && secondIsUpper { return first }
      if secondIsLower && firstIsUpper { return second }
    }
    return projectionOrder(first, second) ? first : second
  }

  private func projectionOrder(
    _ first: RefinedProjection,
    _ second: RefinedProjection
  ) -> Bool {
    if first.residual != second.residual {
      return first.residual < second.residual
    }
    return first.parameter < second.parameter
  }

  private func boundingBoxDistanceLowerBound(
    point: Point3D,
    box: BoundingBox3D
  ) -> Double {
    let x = axisDistanceLowerBound(value: point.x, lower: box.minimum.x, upper: box.maximum.x)
    let y = axisDistanceLowerBound(value: point.y, lower: box.minimum.y, upper: box.maximum.y)
    let z = axisDistanceLowerBound(value: point.z, lower: box.minimum.z, upper: box.maximum.z)
    let squared = max(
      0.0,
      ((x * x).nextDown + (y * y).nextDown + (z * z).nextDown).nextDown
    )
    return sqrt(squared).nextDown
  }

  private func axisDistanceLowerBound(
    value: Double,
    lower: Double,
    upper: Double
  ) -> Double {
    if value < lower { return max(0.0, (lower - value).nextDown) }
    if value > upper { return max(0.0, (value - upper).nextDown) }
    return 0.0
  }

  private func boundingBoxDiameterUpperBound(_ box: BoundingBox3D) -> Double {
    let size = box.size
    let x = abs(size.x).nextUp
    let y = abs(size.y).nextUp
    let z = abs(size.z).nextUp
    return sqrt((x * x + y * y + z * z).nextUp).nextUp
  }

  private func midpoint(_ lower: Double, _ upper: Double) -> Double {
    lower + (upper - lower) * 0.5
  }

  private func outwardLength(_ value: Vector3D) -> Double {
    value.length.nextUp
  }

  private func resourceLimit(
    residual: Double?,
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      residual: residual,
      tolerance: tolerance,
      message: message
    )
  }

  private struct ProjectionCell: Sendable {
    let patch: RationalBezierCurvePointProjectionPatch
    let depth: Int
  }

  private struct RefinedProjection: Sendable {
    let parameter: Double
    let point: Point3D
    let residual: Double
    let iterations: Int
  }
}
