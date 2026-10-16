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
  /// Returns the nearest certified intersection with a directed line over a finite curve interval.
  public func directionalParameterProjection(
    from sourcePoint: Point3D, along direction: Vector3D,
    options: CurveDirectionalParameterProjectionOptions, tolerance: ModelingTolerance
  ) throws -> CurveDirectionalParameterProjection {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try directionalParameterProjection(
      from: sourcePoint, along: direction, options: options, tolerance: tolerance, using: &execution
    )
  }

  public func directionalParameterProjection(
    from sourcePoint: Point3D,
    along direction: Vector3D,
    options: CurveDirectionalParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveDirectionalParameterProjection {
    let result = try directionalParameterProjectionBody(
      from: sourcePoint, along: direction, options: options, tolerance: tolerance, using: &execution
    )
    try execution.checkpoint()
    return result
  }

  private func directionalParameterProjectionBody(
    from sourcePoint: Point3D,
    along direction: Vector3D,
    options: CurveDirectionalParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveDirectionalParameterProjection {
    try options.validate(tolerance: tolerance)
    try validate(tolerance: tolerance, using: &execution)
    try sourcePoint.validate()
    let unitDirection = try direction.normalized(
      tolerance: tolerance.distance
    )
    let curveRange = try directionalProjectionInterval(
      requested: options.parameterRange,
      tolerance: tolerance
    )
    let helper =
      abs(unitDirection.z) < 0.9
      ? Vector3D.unitZ
      : Vector3D.unitY
    let firstNormal = try helper.cross(unitDirection).normalized(
      tolerance: tolerance.distance
    )
    let secondNormal = unitDirection.cross(firstNormal)

    switch try directionalPlaneIntersections(
      planeNormal: firstNormal,
      sourcePoint: sourcePoint,
      curveRange: curveRange,
      options: options,
      tolerance: tolerance, using: &execution)
    {
    case .discrete(let intersections):
      return try selectedDirectionalProjection(
        from: intersections,
        sourcePoint: sourcePoint,
        direction: unitDirection,
        options: options,
        tolerance: tolerance, using: &execution)
    case .coincident:
      switch try directionalPlaneIntersections(
        planeNormal: secondNormal,
        sourcePoint: sourcePoint,
        curveRange: curveRange,
        options: options,
        tolerance: tolerance, using: &execution)
      {
      case .discrete(let intersections):
        return try selectedDirectionalProjection(
          from: intersections,
          sourcePoint: sourcePoint,
          direction: unitDirection,
          options: options,
          tolerance: tolerance, using: &execution)
      case .coincident:
        return try projectionForCurveCoincidentWithLine(
          sourcePoint: sourcePoint,
          direction: unitDirection,
          curveRange: curveRange,
          options: options,
          tolerance: tolerance, using: &execution)
      }
    }
  }

  private func directionalProjectionInterval(
    requested: ScalarInterval?,
    tolerance: ModelingTolerance
  ) throws -> ScalarInterval {
    if let requested {
      guard
        try parameterDomain.containsSpan(
          from: requested.lower,
          to: requested.upper,
          tolerance: tolerance
        )
      else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Directional curve projection range lies outside the curve domain."
        )
      }
      return requested
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
        message: "Directional projection on an unbounded curve requires a finite parameter range."
      )
    }
  }

  private func directionalPlaneIntersections(
    planeNormal: Vector3D,
    sourcePoint: Point3D,
    curveRange: ScalarInterval,
    options: CurveDirectionalParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> DirectionalPlaneIntersectionResult {
    let plane = Plane3D(origin: sourcePoint, normal: planeNormal)
    let ranges = try directionalPlaneParameterRanges(
      plane: plane,
      curveRange: curveRange,
      tolerance: tolerance, using: &execution)
    do {
      return .discrete(
        try DefaultCurveSurfaceIntersector().intersections(
          curve: self,
          surface: .plane(plane),
          options: CurveSurfaceIntersectionOptions(
            curveRange: curveRange,
            surfaceURange: ranges.u,
            surfaceVRange: ranges.v,
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            maximumSubdivisionCells: options.maximumSubdivisionCells,
            maximumIterations: options.maximumIterations,
            maximumCandidateCount: options.maximumCandidateCount
          ),
          tolerance: tolerance, using: &execution))
    } catch let error as KernelError where error.code == .nonDiscreteIntersection {
      return .coincident
    }
  }

  private func directionalPlaneParameterRanges(
    plane: Plane3D,
    curveRange: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: ScalarInterval, v: ScalarInterval) {
    let enclosure = try DefaultCurvePositionEncloser().enclosure(
      of: self,
      over: curveRange,
      tolerance: tolerance, using: &execution)
    let helper =
      abs(plane.normal.z) < 0.9
      ? Vector3D.unitZ
      : Vector3D.unitY
    let basisU = try helper.cross(plane.normal).normalized(
      tolerance: tolerance.distance
    )
    let basisV = plane.normal.cross(basisU)
    let corners = try directionalEnclosureCorners(enclosure, using: &execution)
    return (
      try directionalProjectionRange(
        values: try OriginalCoefficientAllocation.map(elements: corners, using: &execution) {
          point, execution in (point - plane.origin).dot(basisU)
        },
        tolerance: tolerance, using: &execution
      ),
      try directionalProjectionRange(
        values: try OriginalCoefficientAllocation.map(elements: corners, using: &execution) {
          point, execution in (point - plane.origin).dot(basisV)
        },
        tolerance: tolerance, using: &execution
      )
    )
  }

  private func directionalProjectionRange(
    values: [Double],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    var lower: Double?
    var upper: Double?
    for value in values {
      try execution.consumeWork(1)
      lower = lower.map { min($0, value) } ?? value
      upper = upper.map { max($0, value) } ?? value
    }
    guard let rawLower = lower,
      let rawUpper = upper
    else {
      throw KernelError(
        phase: .geometry,
        code: .emptyResult,
        tolerance: tolerance,
        message: "Directional projection could not derive a plane search range."
      )
    }
    let scale = max(abs(rawLower), abs(rawUpper), rawUpper - rawLower, 1.0)
    let padding = max(
      tolerance.distance * 8.0,
      tolerance.relative * scale * 8.0,
      Double.ulpOfOne * scale * 4_096.0
    )
    return try ScalarInterval(
      lower: (rawLower - padding).nextDown,
      upper: (rawUpper + padding).nextUp
    )
  }

  private func directionalEnclosureCorners(
    _ enclosure: CoordinateEnclosure3D, using execution: inout OriginalQueryExecution
  ) throws -> [Point3D] {
    try execution.retainStorage(count: 8, stride: MemoryLayout<Point3D>.stride)
    var result: [Point3D] = []
    result.reserveCapacity(8)
    for x in 0..<2 {
      for y in 0..<2 {
        for z in 0..<2 {
          try execution.consumeWork(1)
          result.append(
            Point3D(
              x: x == 0 ? enclosure.x.lower : enclosure.x.upper,
              y: y == 0 ? enclosure.y.lower : enclosure.y.upper,
              z: z == 0 ? enclosure.z.lower : enclosure.z.upper))
        }
      }
    }
    return result
  }

  private func selectedDirectionalProjection(
    from intersections: [CurveSurfaceIntersection],
    sourcePoint: Point3D,
    direction: Vector3D,
    options: CurveDirectionalParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveDirectionalParameterProjection {
    try execution.retainStorage(
      count: intersections.count, stride: MemoryLayout<CurveDirectionalParameterProjection>.stride)
    var candidates: [CurveDirectionalParameterProjection] = []
    candidates.reserveCapacity(intersections.count)
    for intersection in intersections {
      try execution.consumeWork(1)
      let point = try self.pointAssumingValid(
        at: intersection.curveParameter,
        tolerance: tolerance, using: &execution)
      let signedDistance = (point - sourcePoint).dot(direction)
      guard
        directionalProjectionRange(
          options.range,
          accepts: signedDistance,
          tolerance: tolerance
        )
      else {
        continue
      }
      let linePoint = sourcePoint + direction * signedDistance
      let residual = (point - linePoint).length
      guard residual <= tolerance.distance else {
        continue
      }
      candidates.append(
        try CurveDirectionalParameterProjection(
          parameter: intersection.curveParameter,
          point: point,
          signedDistanceAlongDirection: signedDistance,
          residual: residual,
          iterations: intersection.iterations
        ))
    }
    guard
      let selected = try candidates.min(by: { lhs, rhs in
        try execution.consumeWork(1)
        let lhsMetric = directionalSelectionMetric(
          lhs.signedDistanceAlongDirection,
          range: options.range
        )
        let rhsMetric = directionalSelectionMetric(
          rhs.signedDistanceAlongDirection,
          range: options.range
        )
        if lhsMetric == rhsMetric {
          return lhs.parameter < rhs.parameter
        }
        return lhsMetric < rhsMetric
      })
    else {
      throw KernelError(
        phase: .geometry,
        code: .emptyResult,
        tolerance: tolerance,
        message: "The directed line does not intersect the curve in the requested range."
      )
    }
    return selected
  }

  private func projectionForCurveCoincidentWithLine(
    sourcePoint: Point3D,
    direction: Vector3D,
    curveRange: ScalarInterval,
    options: CurveDirectionalParameterProjectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveDirectionalParameterProjection {
    let closest = try closestParameterProjection(
      of: sourcePoint,
      options: CurveParameterProjectionOptions(
        parameterRange: curveRange,
        maximumIterations: options.maximumIterations,
        seedCount: max(2, min(options.maximumCandidateCount, 64)),
        maximumSubdivisionDepth: options.maximumSubdivisionDepth,
        maximumSubdivisionCells: options.maximumSubdivisionCells,
        maximumCandidateCount: options.maximumCandidateCount
      ),
      tolerance: tolerance, using: &execution)
    let signedDistance = (closest.point - sourcePoint).dot(direction)
    let linePoint = sourcePoint + direction * signedDistance
    let residual = (closest.point - linePoint).length
    guard residual <= tolerance.distance,
      directionalProjectionRange(
        options.range,
        accepts: signedDistance,
        tolerance: tolerance
      )
    else {
      throw KernelError(
        phase: .geometry,
        code: .emptyResult,
        residual: residual,
        tolerance: tolerance,
        message: "The coincident curve does not intersect the requested directional range."
      )
    }
    return try CurveDirectionalParameterProjection(
      parameter: closest.parameter,
      point: closest.point,
      signedDistanceAlongDirection: signedDistance,
      residual: residual,
      iterations: closest.iterations
    )
  }

  private func directionalProjectionRange(
    _ range: DirectionalProjectionRange3D,
    accepts signedDistance: Double,
    tolerance: ModelingTolerance
  ) -> Bool {
    switch range {
    case .line:
      return true
    case .ray:
      return signedDistance >= -tolerance.distance
    }
  }

  private func directionalSelectionMetric(
    _ signedDistance: Double,
    range: DirectionalProjectionRange3D
  ) -> Double {
    switch range {
    case .line:
      return abs(signedDistance)
    case .ray:
      return signedDistance
    }
  }
}

private enum DirectionalPlaneIntersectionResult {
  case discrete([CurveSurfaceIntersection])
  case coincident
}
