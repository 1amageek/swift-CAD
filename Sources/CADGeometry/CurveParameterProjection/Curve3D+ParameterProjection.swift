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

extension Curve3D {
  public func parameterProjection(
    of point: Point3D, options: CurveParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance
  ) throws -> CurveParameterProjection {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try parameterProjection(
      of: point, options: options, tolerance: tolerance, using: &execution)
  }

  public func parameterProjection(
    of point: Point3D,
    options: CurveParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    let result = try parameterProjectionBody(
      of: point, options: options, tolerance: tolerance, using: &execution)
    try execution.checkpoint()
    return result
  }

  private func parameterProjectionBody(
    of point: Point3D,
    options: CurveParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    if case .bSpline(let native) = self {
      return try native.parameterProjection(
        of: point, options: options, tolerance: tolerance, using: &execution)
    }
    try options.validate(tolerance: tolerance)
    try validate(tolerance: tolerance, using: &execution)
    try point.validate()

    return try parameterProjectionAssumingValid(
      of: point,
      options: options,
      tolerance: tolerance, using: &execution)
  }

  package func parameterProjectionAssumingValid(
    of point: Point3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {

    let candidate: (parameter: Double, iterations: Int)
    switch self {
    case .line(let line):
      candidate = (try lineParameter(point, line: line, options: options, tolerance: tolerance), 0)
    case .circle(let circle):
      let basis = try directCircleBasis(circle.normal, tolerance: tolerance)
      candidate = (
        try periodicParameter(
          point: point,
          center: circle.center,
          firstAxis: basis.u,
          secondAxis: basis.v,
          firstRadius: circle.radius,
          secondRadius: circle.radius,
          domain: parameterDomain,
          options: options,
          tolerance: tolerance, using: &execution),
        0
      )
    case .analytic(.planeTorus), .surfaceLift, .certifiedIntersection,
      .rigidImage, .affineImage, .originalAffineWord,
      .originalConstructionChart, .originalEndpointConnector,
      .originalPlaneDerivative, .originalGuideTraversalChain,
      .originalPolyline, .originalGuideEndpointConnector,
      .originalDrafted, .originalAngularTransport:
      candidate = try iterativeParameter(
        point,
        options: options,
        tolerance: tolerance, using: &execution)
    case .analytic(let curve):
      candidate = try analyticParameter(
        point,
        curve: curve,
        options: options,
        tolerance: tolerance, using: &execution)
    case .parameterImage(let image):
      var nativeOptions = options
      if let range = options.parameterRange {
        nativeOptions.parameterRange = try image.originalInterval(range, using: &execution)
      }
      let native = try image.source.parameterProjectionAssumingValid(
        of: point,
        options: nativeOptions, tolerance: tolerance, using: &execution)
      candidate = ((native.parameter - image.offset) / image.gain, native.iterations)
    case .bSpline(let curve):
      return try curve.parameterProjection(
        of: point,
        options: options,
        tolerance: tolerance, using: &execution)
    case .implicit:
      candidate = try iterativeParameter(
        point,
        options: options,
        tolerance: tolerance, using: &execution)
    }
    let projectedPoint = try pointAssumingValid(
      at: candidate.parameter,
      tolerance: tolerance, using: &execution)
    let residual = (point - projectedPoint).length
    guard residual <= tolerance.distance else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: residual,
        tolerance: tolerance,
        message: "Point does not lie on the requested curve within tolerance."
      )
    }
    return try CurveParameterProjection(
      parameter: candidate.parameter,
      point: projectedPoint,
      residual: residual,
      iterations: candidate.iterations
    )
  }

  private func analyticParameter(
    _ point: Point3D,
    curve: AnalyticCurve3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (parameter: Double, iterations: Int) {
    switch curve {
    case .line(let origin, let direction):
      return (
        try lineParameter(
          point,
          line: Line3D(origin: origin, direction: direction),
          options: options,
          tolerance: tolerance
        ),
        0
      )
    case .circle(let center, let normal, let radius):
      let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
      return (
        try periodicParameter(
          point: point,
          center: center,
          firstAxis: basis.u,
          secondAxis: basis.v,
          firstRadius: radius,
          secondRadius: radius,
          domain: parameterDomain,
          options: options,
          tolerance: tolerance, using: &execution),
        0
      )
    case .arc(let center, let normal, let radius, _, _):
      let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
      return (
        try periodicParameter(
          point: point,
          center: center,
          firstAxis: basis.u,
          secondAxis: basis.v,
          firstRadius: radius,
          secondRadius: radius,
          domain: parameterDomain,
          options: options,
          tolerance: tolerance, using: &execution),
        0
      )
    case .ellipse(let center, let normal, let majorAxis, let majorRadius, let minorRadius):
      let minorAxis = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
      return (
        try periodicParameter(
          point: point,
          center: center,
          firstAxis: majorAxis,
          secondAxis: minorAxis,
          firstRadius: majorRadius,
          secondRadius: minorRadius,
          domain: parameterDomain,
          options: options,
          tolerance: tolerance, using: &execution),
        0
      )
    case .hyperbola(let curve):
      return (
        try curve.parameter(for: point, tolerance: tolerance),
        0
      )
    case .parabola(let curve):
      return (
        try curve.parameter(for: point, tolerance: tolerance),
        0
      )
    case .planeTorus:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Plane-torus curve projection must use the bounded iterative path."
      )
    }
  }

  private func lineParameter(
    _ point: Point3D,
    line: Line3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance
  ) throws -> Double {
    let denominator = line.direction.dot(line.direction)
    guard denominator > tolerance.distance * tolerance.distance else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Curve projection line direction is degenerate."
      )
    }
    let parameter = (point - line.origin).dot(line.direction) / denominator
    try validate(parameter: parameter, options: options, tolerance: tolerance)
    return parameter
  }

  private func periodicParameter(
    point: Point3D,
    center: Point3D,
    firstAxis: Vector3D,
    secondAxis: Vector3D,
    firstRadius: Double,
    secondRadius: Double,
    domain: ParameterDomain,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    let offset = point - center
    // The angular inverse proposes a label of the same original symbolic
    // phase; the public projection still checks the original spatial law.
    var parameter = CanonicalSphereAngularPhase.candidateLabel(
      ofPhysicalAngle: atan2(
        offset.dot(secondAxis) / secondRadius,
        offset.dot(firstAxis) / firstRadius
      ))
    if parameter < 0.0 {
      parameter += 2.0 * Double.pi
    }
    switch domain {
    case .closed(let lower, let upper):
      while parameter < lower - tolerance.angle {
        try execution.consumeWork(1)
        parameter += 2.0 * Double.pi
      }
      while parameter > upper + tolerance.angle {
        try execution.consumeWork(1)
        parameter -= 2.0 * Double.pi
      }
    case .periodic, .unbounded:
      break
    }
    if let parameterRange = options.parameterRange {
      let period = 2.0 * Double.pi
      parameter += ((parameterRange.midpoint - parameter) / period).rounded() * period
      if parameter < parameterRange.lower - tolerance.angle {
        parameter += period
      } else if parameter > parameterRange.upper + tolerance.angle {
        parameter -= period
      }
    }
    try validate(parameter: parameter, options: options, tolerance: tolerance)
    return parameter
  }

  private func iterativeParameter(
    _ point: Point3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (parameter: Double, iterations: Int) {
    let interval = try resolvedProjectionInterval(options: options, tolerance: tolerance)
    var bestParameter = interval.lower
    var bestSquaredDistance = Double.infinity
    for parameter in try projectionSeedParameters(
      point: point,
      interval: interval,
      options: options,
      tolerance: tolerance, using: &execution)
    {
      let candidate = try pointAssumingValid(
        at: parameter,
        tolerance: tolerance, using: &execution)
      let offset = candidate - point
      let squaredDistance = offset.dot(offset)
      if squaredDistance < bestSquaredDistance {
        bestSquaredDistance = squaredDistance
        bestParameter = parameter
      }
    }

    var parameter = bestParameter
    var completedIterations = 0
    for iteration in 0..<options.maximumIterations {
      try execution.consumeWork(1)
      completedIterations = iteration + 1
      let geometry = try differentialGeometryAssumingValid(
        at: parameter,
        tolerance: tolerance, using: &execution)
      let offset = geometry.position - point
      let numerator = offset.dot(geometry.firstDerivative)
      let denominator =
        geometry.firstDerivative.dot(geometry.firstDerivative)
        + offset.dot(geometry.secondDerivative)
      guard abs(denominator) > tolerance.angle else { break }
      let updated = min(max(parameter - numerator / denominator, interval.lower), interval.upper)
      if abs(updated - parameter) <= max(tolerance.angle, Double.ulpOfOne * 16.0) {
        parameter = updated
        break
      }
      parameter = updated
    }
    try validate(parameter: parameter, options: options, tolerance: tolerance)
    return (parameter, completedIterations)
  }

  private func projectionSeedParameters(
    point: Point3D,
    interval: ScalarInterval,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    guard case .bSpline(let curve) = self else {
      var result = try OriginalCoefficientAllocation.map(
        elements: 0...options.seedCount, using: &execution
      ) { index, execution in
        interval.lower + interval.width * Double(index)
          / Double(options.seedCount)
      }
      var resultCapacity = result.count
      if case .surfaceLift(let lift) = self,
        case .certifiedAnalyticPair(let parameterCurve) = lift.parameterCurve
      {
        let mappingScale =
          parameterCurve.endFraction
          - parameterCurve.startFraction
        let exactFractions: [Double]
        switch parameterCurve.intersection.definition {
        case .generalTorusCylinder(let curve):
          let exactFraction = try curve.normalizedGeneratorAngle(
            for: point,
            tolerance: tolerance, using: &execution
          )
          exactFractions = try OriginalCoefficientAllocation.map(
            elements: -1...1, using: &execution
          ) { shift, execution in
            exactFraction + Double(shift)
          }
        case .generalTorusTorus(let curve):
          let projection = try curve.parameterizedSurface.parameterProjection(
            of: point,
            tolerance: tolerance, using: &execution)
          let period = 2.0 * Double.pi
          let normalizedMajorAngle = projection.u
            .truncatingRemainder(dividingBy: period)
          let majorAngle =
            normalizedMajorAngle >= 0.0
            ? normalizedMajorAngle
            : normalizedMajorAngle + period
          exactFractions = try OriginalCoefficientAllocation.map(
            elements: 0..<curve.majorAngleWindingCount, using: &execution
          ) { winding, execution in
            (majorAngle + period * Double(winding))
              / (period * Double(curve.majorAngleWindingCount))
          }
        default:
          exactFractions = []
        }
        for exactFraction in exactFractions {
          try execution.consumeWork(1)
          let parameter = (exactFraction - parameterCurve.startFraction) / mappingScale
          if parameter >= interval.lower - tolerance.relative,
            parameter <= interval.upper + tolerance.relative
          {
            try OriginalCoefficientAllocation.reserveAppend(
              to: &result, capacity: &resultCapacity, using: &execution)
            result.append(min(max(parameter, interval.lower), interval.upper))
          }
        }
      }
      return result
    }

    let boundaryCapacity = curve.knots.count.addingReportingOverflow(2)
    guard !boundaryCapacity.overflow else { throw ExactScalarFailure.countOverflow }
    try execution.retainStorage(
      count: boundaryCapacity.partialValue, stride: MemoryLayout<Double>.stride)
    var boundaries: [Double] = []
    boundaries.reserveCapacity(boundaryCapacity.partialValue)
    boundaries.append(interval.lower)
    for knot in curve.knots {
      try execution.consumeWork(1)
      guard knot > interval.lower && knot < interval.upper else { continue }
      if knot - (boundaries.last ?? interval.lower) > tolerance.angle {
        boundaries.append(knot)
      }
    }
    if interval.upper - (boundaries.last ?? interval.lower) > tolerance.angle {
      boundaries.append(interval.upper)
    } else {
      boundaries[boundaries.count - 1] = interval.upper
    }
    let spanCount = boundaries.count - 1
    guard spanCount > 0 else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "B-spline curve projection has no non-degenerate knot span."
      )
    }
    let minimumSeedsPerSpan = 8
    let seedsPerSpan = max(
      minimumSeedsPerSpan,
      Int(ceil(Double(options.seedCount) / Double(spanCount)))
    )
    let seedProduct = spanCount.multipliedReportingOverflow(by: seedsPerSpan)
    guard !seedProduct.overflow else { throw ExactScalarFailure.countOverflow }
    let totalSeedIntervals = seedProduct.partialValue
    guard totalSeedIntervals <= 65_536 else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "B-spline curve projection exceeded its knot-span seed limit."
      )
    }

    try execution.retainStorage(count: totalSeedIntervals + 1, stride: MemoryLayout<Double>.stride)
    var result: [Double] = []
    result.reserveCapacity(totalSeedIntervals + 1)
    result.append(interval.lower)
    for index in 1..<boundaries.count {
      try execution.consumeWork(1)
      let lower = boundaries[index - 1]
      let upper = boundaries[index]
      for subdivision in 1...seedsPerSpan {
        try execution.consumeWork(1)
        result.append(
          lower + (upper - lower) * Double(subdivision)
            / Double(seedsPerSpan)
        )
      }
    }
    return result
  }

  private func resolvedProjectionInterval(
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance
  ) throws -> ScalarInterval {
    if let parameterRange = options.parameterRange {
      return parameterRange
    }
    switch parameterDomain {
    case .closed(let lower, let upper):
      return try ScalarInterval(lower: lower, upper: upper)
    case .periodic(let period):
      return try ScalarInterval(lower: 0.0, upper: period)
    case .unbounded:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Unbounded iterative curve projection requires an explicit parameter range."
      )
    }
  }

  private func validate(
    parameter: Double,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance
  ) throws {
    let isInsideRequestedRange: Bool
    if let parameterRange = options.parameterRange {
      let parameterTolerance = max(tolerance.distance, tolerance.angle)
      isInsideRequestedRange =
        parameter >= parameterRange.lower - parameterTolerance
        && parameter <= parameterRange.upper + parameterTolerance
    } else {
      isInsideRequestedRange = true
    }
    guard parameter.isFinite,
      try parameterDomain.contains(parameter, tolerance: tolerance),
      isInsideRequestedRange
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "Curve parameter projection lies outside the requested domain."
      )
    }
  }

  private func directCircleBasis(
    _ normal: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> (u: Vector3D, v: Vector3D) {
    let normalized = try normal.normalized(tolerance: tolerance.distance)
    let helper = abs(normalized.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let u = try helper.cross(normalized).normalized(tolerance: tolerance.distance)
    return (u, normalized.cross(u))
  }
}
