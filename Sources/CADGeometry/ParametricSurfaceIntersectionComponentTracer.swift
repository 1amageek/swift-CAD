import CADCore
import Foundation

/// Traces one regular connected component of a bounded surface intersection.
/// Candidate discovery and completeness proofs are intentionally owned by the
/// representation-specific oracle that supplies the certified seed.
struct ParametricSurfaceIntersectionComponentTracer: Sendable {
  typealias Sample = ParametricSurfaceIntersectionSample

  let first: Surface3D
  let second: Surface3D
  let domains: BoundedSurfaceParameterDomainMap
  let options: SurfaceSurfaceIntersectionOptions
  let tolerance: ModelingTolerance

  func trace(
    from seed: Sample,
    remainingPointCount: inout Int
  ) throws -> [Sample] {
    try traceComponent(
      from: seed,
      remainingPointCount: &remainingPointCount
    ).samples
  }

  func traceComponent(
    from seed: Sample,
    remainingPointCount: inout Int
  ) throws -> ParametricSurfaceIntersectionTracedComponent {
    let tangent = try intersectionTangent(at: seed)
    let forward = try march(
      from: seed,
      initialTangent: tangent,
      remainingPointCount: &remainingPointCount
    )
    if isClosed(forward) {
      return ParametricSurfaceIntersectionTracedComponent(
        samples: try refined(
          forward,
          remainingPointCount: &remainingPointCount
        ),
        isClosed: true
      )
    }
    let reverse = try march(
      from: seed,
      initialTangent: tangent.map { -$0 },
      remainingPointCount: &remainingPointCount
    )
    let combined = Array(reverse.dropFirst().reversed()) + forward
    return ParametricSurfaceIntersectionTracedComponent(
      samples: try refined(
        combined,
        remainingPointCount: &remainingPointCount
      ),
      isClosed: false
    )
  }

  func intersectionTangent(at sample: Sample) throws -> [Double] {
    let firstGeometry = try first.differentialGeometry(
      u: sample.actual[0],
      v: sample.actual[1],
      tolerance: tolerance
    )
    let secondGeometry = try second.differentialGeometry(
      u: sample.actual[2],
      v: sample.actual[3],
      tolerance: tolerance
    )
    let normalSeparation = firstGeometry.normal
      .cross(secondGeometry.normal).length
    guard normalSeparation > tolerance.angle else {
      throw KernelError(
        phase: .geometry,
        code: .singularGeometry,
        residual: normalSeparation,
        tolerance: tolerance,
        message:
          "Regular surface-intersection continuation reached a tangential or branching locus."
      )
    }
    let columns = try rootRefiner.jacobianColumns(at: sample)
    let cofactors = [
      -determinant(columns[1], columns[2], columns[3]),
      determinant(columns[0], columns[2], columns[3]),
      -determinant(columns[0], columns[1], columns[3]),
      determinant(columns[0], columns[1], columns[2]),
    ]
    guard let tangent = normalized(cofactors) else {
      throw KernelError(
        phase: .geometry,
        code: .singularGeometry,
        tolerance: tolerance,
        message: "Regular surface-intersection continuation has no stable parameter-space tangent."
      )
    }
    return tangent
  }

  func correctedSample(
    predictor: [Double],
    tangent: [Double]
  ) throws -> Sample? {
    try pseudoArclengthCorrection(
      predictor: predictor,
      tangent: tangent
    )
  }

  func traceHalf(
    from seed: Sample,
    initialTangent: [Double],
    remainingPointCount: inout Int
  ) throws -> [Sample] {
    try march(
      from: seed,
      initialTangent: initialTangent,
      remainingPointCount: &remainingPointCount
    )
  }

  func refine(
    _ samples: [Sample],
    remainingPointCount: inout Int
  ) throws -> [Sample] {
    try refined(
      samples,
      remainingPointCount: &remainingPointCount
    )
  }

  private var rootRefiner: ParametricSurfaceIntersectionRootRefiner {
    ParametricSurfaceIntersectionRootRefiner(
      first: first,
      second: second,
      domains: domains,
      maximumIterations: options.maximumIterations,
      tolerance: tolerance
    )
  }

  private func march(
    from seed: Sample,
    initialTangent: [Double],
    remainingPointCount: inout Int
  ) throws -> [Sample] {
    var result = [seed]
    var current = seed
    var tangent = initialTangent
    let baseStep = max(
      1.0 / pow(2.0, Double(options.maximumSubdivisionDepth + 2)),
      1.0 / 256.0
    )
    while true {
      guard result.count < options.maximumContinuationPointCountPerComponent else {
        throw resourceLimit(
          "Surface intersection continuation exceeded its component length limit."
        )
      }
      guard remainingPointCount > 0 else {
        throw resourceLimit(
          "Surface intersection continuation exceeded its point limit."
        )
      }
      var step = baseStep
      var corrected: Sample?
      var reachesBoundary = false
      for _ in 0..<8 {
        let boundaryScale = scaleToUnitBoundary(
          from: current.normalized,
          direction: tangent,
          requestedStep: step
        )
        reachesBoundary = boundaryScale < step
        let predictor = zip(current.normalized, tangent).map {
          $0.0 + $0.1 * boundaryScale
        }
        corrected = try pseudoArclengthCorrection(
          predictor: predictor,
          tangent: tangent
        )
        if reachesBoundary, let correctedSample = corrected {
          let boundaryParameterIndex = predictor.indices.min {
            min(abs(predictor[$0]), abs(1.0 - predictor[$0]))
              < min(abs(predictor[$1]), abs(1.0 - predictor[$1]))
          }
          if let boundaryParameterIndex {
            let boundaryValue =
              predictor[boundaryParameterIndex] <= 0.5
              ? 0.0
              : 1.0
            var boundarySeed = correctedSample.normalized
            boundarySeed[boundaryParameterIndex] = boundaryValue
            corrected = try rootRefiner.gaugeRoot(
              seed: boundarySeed,
              fixedParameterIndex: boundaryParameterIndex,
              constraints: Array(
                repeating: (lower: 0.0, upper: 1.0),
                count: 4
              )
            )
          }
        }
        if corrected != nil { break }
        step *= 0.5
      }
      guard let next = corrected else {
        if isOnUnitBoundary(current.normalized) { break }
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          tolerance: tolerance,
          message: "Pseudo-arclength correction failed before a component boundary or closure."
        )
      }
      let pointStep = (next.point - current.point).length
      if pointStep <= tolerance.distance * 0.1 {
        if isOnUnitBoundary(next.normalized) { break }
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          residual: pointStep,
          tolerance: tolerance,
          message:
            "Surface intersection continuation stagnated before a component boundary or closure."
        )
      }
      remainingPointCount -= 1
      result.append(next)
      if result.count > 12,
        (next.point - seed.point).length
          <= max(pointStep * 2.0, tolerance.distance * 2.0),
        normalizedDistance(next.normalized, seed.normalized)
          <= max(baseStep * 2.0, tolerance.relative * 16.0)
      {
        result[result.count - 1] = seed
        break
      }
      if reachesBoundary || isOnUnitBoundary(next.normalized) { break }
      var nextTangent = try intersectionTangent(at: next)
      if dot(nextTangent, tangent) < 0.0 {
        nextTangent = nextTangent.map { -$0 }
      }
      tangent = nextTangent
      current = next
    }
    return result
  }

  private func isClosed(_ samples: [Sample]) -> Bool {
    guard samples.count > 12,
      let first = samples.first,
      let last = samples.last
    else {
      return false
    }
    return (first.point - last.point).length <= tolerance.distance
      && normalizedDistance(first.normalized, last.normalized)
        <= tolerance.relative * 16.0
  }

  private func pseudoArclengthCorrection(
    predictor: [Double],
    tangent: [Double]
  ) throws -> Sample? {
    var parameters = predictor.map { min(max($0, 0.0), 1.0) }
    for _ in 0..<options.maximumIterations {
      let sample = try rootRefiner.sample(normalized: parameters)
      let gauge = dot(
        zip(parameters, predictor).map { $0.0 - $0.1 },
        tangent
      )
      if sample.residual <= tolerance.distance * 0.1,
        abs(gauge) <= 1.0e-10
      {
        return sample
      }
      let columns = try rootRefiner.jacobianColumns(at: sample)
      let difference = sample.firstPoint - sample.secondPoint
      let matrix = [
        columns.map(\.x),
        columns.map(\.y),
        columns.map(\.z),
        tangent,
      ]
      let rhs = [-difference.x, -difference.y, -difference.z, -gauge]
      guard
        let delta = SmallLinearSystem4.solve(
          matrix: matrix,
          rightHandSide: rhs
        )
      else {
        return nil
      }
      for index in parameters.indices {
        parameters[index] = min(
          max(parameters[index] + delta[index], 0.0),
          1.0
        )
      }
    }
    let final = try rootRefiner.sample(normalized: parameters)
    return final.residual <= tolerance.distance ? final : nil
  }

  private func refined(
    _ samples: [Sample],
    remainingPointCount: inout Int
  ) throws -> [Sample] {
    guard samples.count >= 2 else { return samples }
    var result = [samples[0]]
    for index in 1..<samples.count {
      try refineSegment(
        firstSample: samples[index - 1],
        secondSample: samples[index],
        depth: 0,
        remainingPointCount: &remainingPointCount,
        result: &result
      )
    }
    return result
  }

  private func refineSegment(
    firstSample: Sample,
    secondSample: Sample,
    depth: Int,
    remainingPointCount: inout Int,
    result: inout [Sample]
  ) throws {
    let residual = try linearSegmentResidual(
      firstSample: firstSample,
      secondSample: secondSample
    )
    if residual <= tolerance.distance * 0.5 {
      result.append(secondSample)
      return
    }
    let difference = zip(
      secondSample.normalized,
      firstSample.normalized
    ).map { $0.0 - $0.1 }
    guard let tangent = normalized(difference) else { return }
    let predictor = zip(
      firstSample.normalized,
      secondSample.normalized
    ).map { ($0.0 + $0.1) * 0.5 }
    guard
      let middle = try pseudoArclengthCorrection(
        predictor: predictor,
        tangent: tangent
      )
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "Surface intersection midpoint correction failed."
      )
    }
    guard depth < 18, remainingPointCount > 0 else {
      throw resourceLimit(
        "Surface intersection residual refinement exceeded its limit."
      )
    }
    remainingPointCount -= 1
    try refineSegment(
      firstSample: firstSample,
      secondSample: middle,
      depth: depth + 1,
      remainingPointCount: &remainingPointCount,
      result: &result
    )
    try refineSegment(
      firstSample: middle,
      secondSample: secondSample,
      depth: depth + 1,
      remainingPointCount: &remainingPointCount,
      result: &result
    )
  }

  private func linearSegmentResidual(
    firstSample: Sample,
    secondSample: Sample
  ) throws -> Double {
    var maximum = 0.0
    for fraction in [0.25, 0.5, 0.75] {
      let normalizedParameters = zip(
        firstSample.normalized,
        secondSample.normalized
      ).map { $0.0 + ($0.1 - $0.0) * fraction }
      let sample = try rootRefiner.sample(
        normalized: normalizedParameters
      )
      let curvePoint = interpolated(
        firstSample.point,
        secondSample.point,
        fraction: fraction
      )
      maximum = max(
        maximum,
        (curvePoint - sample.firstPoint).length,
        (curvePoint - sample.secondPoint).length
      )
    }
    return maximum
  }

  private func scaleToUnitBoundary(
    from point: [Double],
    direction: [Double],
    requestedStep: Double
  ) -> Double {
    zip(point, direction).reduce(requestedStep) { scale, value in
      let (coordinate, velocity) = value
      if velocity > 0.0 {
        return min(scale, max((1.0 - coordinate) / velocity, 0.0))
      }
      if velocity < 0.0 {
        return min(scale, max(-coordinate / velocity, 0.0))
      }
      return scale
    }
  }

  private func isOnUnitBoundary(_ values: [Double]) -> Bool {
    values.contains { abs($0) <= 1.0e-12 || abs(1.0 - $0) <= 1.0e-12 }
  }

  private func normalized(_ values: [Double]) -> [Double]? {
    let length = sqrt(values.reduce(0.0) { $0 + $1 * $1 })
    guard length.isFinite, length > Double.ulpOfOne else { return nil }
    return values.map { $0 / length }
  }

  private func dot(_ first: [Double], _ second: [Double]) -> Double {
    zip(first, second).reduce(0.0) { $0 + $1.0 * $1.1 }
  }

  private func normalizedDistance(_ first: [Double], _ second: [Double]) -> Double {
    sqrt(
      zip(first, second).reduce(0.0) { partial, values in
        let difference = values.0 - values.1
        return partial + difference * difference
      })
  }

  private func determinant(
    _ first: Vector3D,
    _ second: Vector3D,
    _ third: Vector3D
  ) -> Double {
    first.dot(second.cross(third))
  }

  private func interpolated(
    _ first: Point3D,
    _ second: Point3D,
    fraction: Double
  ) -> Point3D {
    Point3D(
      x: first.x + (second.x - first.x) * fraction,
      y: first.y + (second.y - first.y) * fraction,
      z: first.z + (second.z - first.z) * fraction
    )
  }

  private func resourceLimit(_ message: String) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      tolerance: tolerance,
      message: message
    )
  }
}
