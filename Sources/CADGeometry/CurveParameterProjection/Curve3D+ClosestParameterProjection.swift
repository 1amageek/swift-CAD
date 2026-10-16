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
  /// Returns a globally certified closest point over a finite curve interval.
  public func closestParameterProjection(
    of point: Point3D, options: CurveParameterProjectionOptions, tolerance: ModelingTolerance
  ) throws -> CurveParameterProjection {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try closestParameterProjection(
      of: point, options: options, tolerance: tolerance, using: &execution)
  }

  public func closestParameterProjection(
    of point: Point3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    let result = try closestParameterProjectionBody(
      of: point, options: options, tolerance: tolerance, using: &execution)
    try execution.checkpoint()
    return result
  }

  private func closestParameterProjectionBody(
    of point: Point3D,
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    try closestParameterProjection(
      of: point,
      options: options,
      positionEncloser: DefaultCurvePositionEncloser(),
      tolerance: tolerance, using: &execution)
  }

  package func closestParameterProjection(
    of point: Point3D, options: CurveParameterProjectionOptions,
    positionEncloser: any CurvePositionEnclosing, tolerance: ModelingTolerance
  ) throws -> CurveParameterProjection {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try closestParameterProjection(
      of: point, options: options, positionEncloser: positionEncloser,
      tolerance: tolerance, using: &execution)
  }

  package func closestParameterProjection(
    of point: Point3D,
    options: CurveParameterProjectionOptions,
    positionEncloser: any CurvePositionEnclosing,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterProjection {
    try options.validate(tolerance: tolerance)
    try validate(tolerance: tolerance, using: &execution)
    try point.validate()

    struct Cell {
      let interval: ScalarInterval
      let depth: Int
    }

    let interval = try closestProjectionInterval(
      options: options,
      tolerance: tolerance
    )
    var best = try closestProjectionWitness(
      initialParameter: interval.midpoint,
      interval: interval,
      point: point,
      maximumIterations: options.maximumIterations,
      tolerance: tolerance, using: &execution)
    for endpointIndex in 0..<2 {
      let endpoint = endpointIndex == 0 ? interval.lower : interval.upper
      try execution.consumeWork(1)
      let candidate = try closestProjectionWitness(
        initialParameter: endpoint,
        interval: interval,
        point: point,
        maximumIterations: options.maximumIterations,
        tolerance: tolerance, using: &execution)
      if candidate.residual < best.residual
        || candidate.residual == best.residual
          && candidate.parameter < best.parameter
      {
        best = candidate
      }
    }

    var remainingCells = options.maximumSubdivisionCells
    try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
    var pending = [Cell(interval: interval, depth: 0)]
    var pendingCapacity = 1
    while let cell = pending.popLast() {
      try execution.visitGeometricCell(depth: cell.depth)
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: best.residual,
          tolerance: tolerance,
          message: "Closest curve projection exceeded its certified cell budget."
        )
      }
      remainingCells -= 1
      let enclosure = try execution.withGeometricDepthOffset(cell.depth) { execution in
        try positionEncloser.enclosure(
          of: self, over: cell.interval, tolerance: tolerance, using: &execution)
      }
      let lowerBound = closestProjectionDistanceLowerBound(
        from: point,
        to: enclosure
      )
      if lowerBound + tolerance.distance >= best.residual {
        continue
      }
      let witness = try closestProjectionWitness(
        initialParameter: cell.interval.midpoint,
        interval: cell.interval,
        point: point,
        maximumIterations: options.maximumIterations,
        tolerance: tolerance, using: &execution)
      if witness.residual < best.residual
        || witness.residual == best.residual
          && witness.parameter < best.parameter
      {
        best = witness
      }
      if lowerBound + tolerance.distance >= best.residual {
        continue
      }
      guard cell.depth < options.maximumSubdivisionDepth else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: max(0.0, best.residual - lowerBound),
          tolerance: tolerance,
          message: "Closest curve projection did not close its global distance bound."
        )
      }
      let middle = cell.interval.midpoint
      guard middle > cell.interval.lower,
        middle < cell.interval.upper
      else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: max(0.0, best.residual - lowerBound),
          tolerance: tolerance,
          message: "Closest curve projection reached floating-point subdivision resolution."
        )
      }
      let depth = cell.depth + 1
      try execution.admitGeometricDepth(depth)
      try OriginalCoefficientAllocation.reserveAppend(
        to: &pending, capacity: &pendingCapacity, using: &execution)
      pending.append(
        Cell(
          interval: try ScalarInterval(
            lower: middle,
            upper: cell.interval.upper
          ),
          depth: depth
        ))
      try OriginalCoefficientAllocation.reserveAppend(
        to: &pending, capacity: &pendingCapacity, using: &execution)
      pending.append(
        Cell(
          interval: try ScalarInterval(
            lower: cell.interval.lower,
            upper: middle
          ),
          depth: depth
        ))
    }

    return try CurveParameterProjection(
      parameter: best.parameter,
      point: best.point,
      residual: best.residual,
      iterations: best.iterations
    )
  }

  private func closestProjectionInterval(
    options: CurveParameterProjectionOptions,
    tolerance: ModelingTolerance
  ) throws -> ScalarInterval {
    let interval: ScalarInterval
    if let requested = options.parameterRange {
      interval = requested
    } else {
      switch parameterDomain {
      case .closed(let lower, let upper):
        interval = try ScalarInterval(lower: lower, upper: upper)
      case .periodic(let period):
        interval = try ScalarInterval(lower: 0.0, upper: period)
      case .unbounded:
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Closest projection on an unbounded curve requires a finite parameter range."
        )
      }
    }
    guard
      try parameterDomain.containsSpan(
        from: interval.lower,
        to: interval.upper,
        tolerance: tolerance
      )
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Closest curve projection range lies outside the curve domain."
      )
    }
    return interval
  }

  private func closestProjectionWitness(
    initialParameter: Double,
    interval: ScalarInterval,
    point: Point3D,
    maximumIterations: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (
    parameter: Double,
    point: Point3D,
    residual: Double,
    iterations: Int
  ) {
    var parameter = min(
      max(
        initialParameter,
        interval.lower
      ), interval.upper)
    var completedIterations = 0
    for iteration in 0..<maximumIterations {
      try execution.consumeWork(1)
      completedIterations = iteration + 1
      let geometry = try differentialGeometryAssumingValid(
        at: parameter,
        tolerance: tolerance, using: &execution)
      let residual = geometry.position - point
      let gradient = residual.dot(geometry.firstDerivative)
      let hessian =
        geometry.firstDerivative.dot(
          geometry.firstDerivative
        ) + residual.dot(geometry.secondDerivative)
      let scale = max(
        1.0,
        geometry.firstDerivative.dot(geometry.firstDerivative),
        abs(residual.dot(geometry.secondDerivative))
      )
      guard hessian.isFinite,
        abs(hessian) > Double.ulpOfOne * scale
      else {
        break
      }
      let delta = gradient / hessian
      guard delta.isFinite else {
        throw GeometryError.invalidDistance(delta)
      }
      let next = min(
        max(
          parameter - delta,
          interval.lower
        ), interval.upper)
      if abs(next - parameter)
        <= max(
          tolerance.relative * max(1.0, abs(parameter)),
          Double.ulpOfOne * max(1.0, abs(parameter)) * 128.0
        )
      {
        parameter = next
        break
      }
      let currentPoint = geometry.position
      let nextPoint = try self.pointAssumingValid(
        at: next,
        tolerance: tolerance, using: &execution)
      if (nextPoint - point).length <= (currentPoint - point).length {
        parameter = next
      } else {
        break
      }
    }
    let projected = try self.pointAssumingValid(
      at: parameter, tolerance: tolerance, using: &execution)
    return (
      parameter: parameter,
      point: projected,
      residual: (projected - point).length.nextUp,
      iterations: completedIterations
    )
  }

  private func closestProjectionDistanceLowerBound(
    from point: Point3D,
    to enclosure: CoordinateEnclosure3D
  ) -> Double {
    func axisDistance(
      _ value: Double,
      interval: ScalarInterval
    ) -> Double {
      if value < interval.lower {
        return max(0.0, (interval.lower - value).nextDown)
      }
      if value > interval.upper {
        return max(0.0, (value - interval.upper).nextDown)
      }
      return 0.0
    }
    let x = axisDistance(point.x, interval: enclosure.x)
    let y = axisDistance(point.y, interval: enclosure.y)
    let z = axisDistance(point.z, interval: enclosure.z)
    return hypot(x, hypot(y, z)).nextDown
  }

}
