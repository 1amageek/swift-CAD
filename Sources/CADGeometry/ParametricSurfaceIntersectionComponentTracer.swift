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
  let admission: SurfaceSurfaceQueryAdmission
  let preparedFirstSurface: PreparedSurfaceDifferentialEncloser?
  let preparedSecondSurface: PreparedSurfaceDifferentialEncloser?

  init(first: Surface3D, second: Surface3D, domains: BoundedSurfaceParameterDomainMap, options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil) {
    self.first = first
    self.second = second
    self.domains = domains
    self.options = options
    self.tolerance = tolerance
    self.admission = admission
    self.preparedFirstSurface = preparedFirstSurface
    self.preparedSecondSurface = preparedSecondSurface
  }

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
    try admission.reserve(count: tangent.count, stride: MemoryLayout<Double>.stride)
    let reverse = try march(
      from: seed,
      initialTangent: tangent.map { -$0 },
      remainingPointCount: &remainingPointCount
    )
    let combinedCount = reverse.count.addingReportingOverflow(forward.count)
    guard !combinedCount.overflow else { throw resourceLimit("Original continuation retained count overflowed.") }
    try admission.reserve(count: combinedCount.partialValue, stride: MemoryLayout<Sample>.stride)
    var combined: [Sample] = []
    combined.reserveCapacity(combinedCount.partialValue)
    for sample in reverse.dropFirst().reversed() { try admission.step(); combined.append(sample) }
    for sample in forward { try admission.step(); combined.append(sample) }
    return ParametricSurfaceIntersectionTracedComponent(
      samples: try refined(
        combined,
        remainingPointCount: &remainingPointCount
      ),
      isClosed: false
    )
  }

  func intersectionTangent(at sample: Sample) throws -> [Double] {
    let columns = try rootRefiner.jacobianColumns(at: sample)
    let firstNormal = columns[0].cross(columns[1])
    let secondNormal = columns[2].cross(columns[3])
    let firstLength = firstNormal.length, secondLength = secondNormal.length
    guard firstLength.isFinite, secondLength.isFinite, firstLength > 0, secondLength > 0 else {
      throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
        message: "Regular surface continuation has no finite nonzero original normal candidate.")
    }
    let normalSeparation = (firstNormal / firstLength).cross(secondNormal / secondLength).length
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
    try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
    let cofactors = [
      -determinant(columns[1], columns[2], columns[3]),
      determinant(columns[0], columns[2], columns[3]),
      -determinant(columns[0], columns[1], columns[3]),
      determinant(columns[0], columns[1], columns[2]),
    ]
    guard let tangent = try normalized(cofactors) else {
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
      tolerance: tolerance, admission: admission,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
    )
  }

  private func march(
    from seed: Sample,
    initialTangent: [Double],
    remainingPointCount: inout Int
  ) throws -> [Sample] {
    try admission.reserve(count: 1, stride: MemoryLayout<Sample>.stride)
    var result = [seed]
    var current = seed
    var tangent = initialTangent
    let baseStep = max(
      1.0 / pow(2.0, Double(options.maximumSubdivisionDepth + 2)),
      1.0 / 256.0
    )
    while true {
      try admission.step()
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
        try admission.step()
        let boundaryScale = scaleToUnitBoundary(
          from: current.normalized,
          direction: tangent,
          requestedStep: step
        )
        reachesBoundary = boundaryScale < step
        try admission.reserve(count: current.normalized.count, stride: MemoryLayout<Double>.stride)
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
            try admission.reserve(count: correctedSample.normalized.count, stride: MemoryLayout<Double>.stride)
            try admission.reserve(count: 4, stride: MemoryLayout<(lower: Double, upper: Double)>.stride)
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
      try admission.reserve(count: 1, stride: MemoryLayout<Sample>.stride)
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
        try admission.reserve(count: nextTangent.count, stride: MemoryLayout<Double>.stride)
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
    try admission.reserve(count: predictor.count, stride: MemoryLayout<Double>.stride)
    var parameters = predictor.map { min(max($0, 0.0), 1.0) }
    for _ in 0..<options.maximumIterations {
      try admission.step()
      let sample = try rootRefiner.sample(normalized: parameters)
      var gauge = 0.0
      for index in parameters.indices {
        try admission.step()
        gauge += (parameters[index] - predictor[index]) * tangent[index]
      }
      if sample.residual <= tolerance.distance * 0.1,
        abs(gauge) <= 1.0e-10
      {
        return sample
      }
      let columns = try rootRefiner.jacobianColumns(at: sample)
      let difference = sample.firstPoint - sample.secondPoint
      try admission.reserve(count: 12, stride: MemoryLayout<Double>.stride)
      try admission.reserve(count: 4, stride: MemoryLayout<Array<Double>>.stride)
      let matrix = [
        columns.map({ $0.x }),
        columns.map({ $0.y }),
        columns.map({ $0.z }),
        tangent,
      ]
      try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
      let rhs = [-difference.x, -difference.y, -difference.z, -gauge]
      guard
        let delta = try SmallLinearSystem4.solve(
          matrix: matrix,
          rightHandSide: rhs,
          admission: admission
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
    try admission.reserve(count: 1, stride: MemoryLayout<Sample>.stride)
    var result = [samples[0]]
    for index in 1..<samples.count {
      try admission.step()
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
    try admission.step()
    let residual = try linearSegmentResidual(
      firstSample: firstSample,
      secondSample: secondSample
    )
    if residual <= tolerance.distance * 0.5 {
      try admission.reserve(count: 1, stride: MemoryLayout<Sample>.stride)
      result.append(secondSample)
      return
    }
    try admission.reserve(count: firstSample.normalized.count, stride: MemoryLayout<Double>.stride)
    let difference = zip(
      secondSample.normalized,
      firstSample.normalized
    ).map { $0.0 - $0.1 }
    guard let tangent = try normalized(difference) else { return }
    try admission.reserve(count: firstSample.normalized.count, stride: MemoryLayout<Double>.stride)
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
    guard depth < min(18, options.maximumResidualCertificationDepth, admission.maximumSubdivisionDepth), remainingPointCount > 0 else {
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
    for index in 1...3 {
      try admission.step()
      let fraction = Double(index) * 0.25
      try admission.reserve(count: firstSample.normalized.count, stride: MemoryLayout<Double>.stride)
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

  private func normalized(_ values: [Double]) throws -> [Double]? {
    var sum = 0.0
    for value in values {
      try admission.step()
      sum += value * value
    }
    let length = sqrt(sum)
    guard length.isFinite, length > Double.ulpOfOne else { return nil }
    try admission.reserve(count: values.count, stride: MemoryLayout<Double>.stride)
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
