import CADCore

struct ParametricSurfaceIntersectionSample: Sendable {
  let normalized: [Double]
  let actual: [Double]
  let firstPoint: Point3D
  let secondPoint: Point3D

  var point: Point3D {
    Point3D(
      x: (firstPoint.x + secondPoint.x) * 0.5,
      y: (firstPoint.y + secondPoint.y) * 0.5,
      z: (firstPoint.z + secondPoint.z) * 0.5
    )
  }

  var residual: Double {
    (firstPoint - secondPoint).length
  }
}

/// Owns representation-independent numerical root refinement for a pair of
/// bounded surfaces. Candidate discovery and interval completeness proofs
/// remain backend responsibilities.
struct ParametricSurfaceIntersectionRootRefiner: Sendable {
  let first: Surface3D
  let second: Surface3D
  let domains: BoundedSurfaceParameterDomainMap
  let maximumIterations: Int
  let tolerance: ModelingTolerance
  let admission: SurfaceSurfaceQueryAdmission
  let preparedFirstSurface: PreparedSurfaceDifferentialEncloser?
  let preparedSecondSurface: PreparedSurfaceDifferentialEncloser?

  init(first: Surface3D, second: Surface3D, domains: BoundedSurfaceParameterDomainMap, maximumIterations: Int, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil) {
    self.first = first
    self.second = second
    self.domains = domains
    self.maximumIterations = maximumIterations
    self.tolerance = tolerance
    self.admission = admission
    self.preparedFirstSurface = preparedFirstSurface
    self.preparedSecondSurface = preparedSecondSurface
  }

  func sample(normalized: [Double]) throws -> ParametricSurfaceIntersectionSample {
    try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
    let actual = domains.actual(normalized)
    let firstBounds = try admission.positionBounds(preparedFirstSurface ?? admission.prepare(first, tolerance: tolerance),
      at: SurfaceParameter(u: actual[0], v: actual[1]), tolerance: tolerance)
    let secondBounds = try admission.positionBounds(preparedSecondSurface ?? admission.prepare(second, tolerance: tolerance),
      at: SurfaceParameter(u: actual[2], v: actual[3]), tolerance: tolerance)
    let firstPoint = Point3D(x: firstBounds.x.midpoint, y: firstBounds.y.midpoint, z: firstBounds.z.midpoint)
    let secondPoint = Point3D(x: secondBounds.x.midpoint, y: secondBounds.y.midpoint, z: secondBounds.z.midpoint)
    try firstPoint.validate(); try secondPoint.validate()
    return ParametricSurfaceIntersectionSample(normalized: normalized, actual: actual,
      firstPoint: firstPoint, secondPoint: secondPoint)
  }

  func closestRoot(
    seed: [Double],
    constraints: [(lower: Double, upper: Double)]
  ) throws -> ParametricSurfaceIntersectionSample? {
    try admission.reserve(count: seed.count, stride: MemoryLayout<Double>.stride)
    var parameters = seed
    for _ in 0..<maximumIterations {
      try admission.step()
      let current = try sample(normalized: parameters)
      let columns = try jacobianColumns(at: current)
      try admission.reserve(count: 20, stride: MemoryLayout<Double>.stride)
      try admission.reserve(count: 4, stride: MemoryLayout<Array<Double>>.stride)
      var matrix = Array(
        repeating: Array(repeating: 0.0, count: 4),
        count: 4
      )
      var rightHandSide = Array(repeating: 0.0, count: 4)
      let difference = current.firstPoint - current.secondPoint
      for row in 0..<4 {
        rightHandSide[row] = -columns[row].dot(difference)
        for column in 0..<4 {
          matrix[row][column] = columns[row].dot(columns[column])
        }
      }
      var maximumDiagonal = matrix[0][0]
      for index in 1..<4 { maximumDiagonal = max(maximumDiagonal, matrix[index][index]) }
      let damping = max(maximumDiagonal * 1.0e-10, 1.0e-14)
      for index in 0..<4 { matrix[index][index] += damping }
      guard
        let delta = try SmallLinearSystem4.solve(
          matrix: matrix,
          rightHandSide: rightHandSide, admission: admission
        )
      else {
        return nil
      }
      for index in 0..<4 {
        parameters[index] = min(
          max(parameters[index] + delta[index], constraints[index].lower),
          constraints[index].upper
        )
      }
      var maximumDelta = 0.0
      for value in delta { maximumDelta = max(maximumDelta, abs(value)) }
      if maximumDelta <= tolerance.relative * 0.1 {
        break
      }
    }
    let final = try sample(normalized: parameters)
    return final.residual <= tolerance.distance ? final : nil
  }

  func gaugeRoot(
    seed: [Double],
    fixedParameterIndex: Int,
    constraints: [(lower: Double, upper: Double)]
  ) throws -> ParametricSurfaceIntersectionSample? {
    guard seed.count == 4,
      constraints.count == 4,
      seed.indices.contains(fixedParameterIndex)
    else {
      return nil
    }
    try admission.reserve(count: 3, stride: MemoryLayout<Int>.stride)
    let dependentIndexes = seed.indices.filter {
      $0 != fixedParameterIndex
    }
    let fixedValue = min(
      max(seed[fixedParameterIndex], constraints[fixedParameterIndex].lower),
      constraints[fixedParameterIndex].upper
    )
    try admission.reserve(count: seed.count, stride: MemoryLayout<Double>.stride)
    var parameters = seed.indices.map { index in
      min(max(seed[index], constraints[index].lower), constraints[index].upper)
    }
    parameters[fixedParameterIndex] = fixedValue
    let residualTarget = max(
      min(tolerance.distance * 1.0e-4, tolerance.relative * 0.1),
      Double.ulpOfOne * 4_096.0
    )

    for _ in 0..<maximumIterations {
      try admission.step()
      let current = try sample(normalized: parameters)
      if current.residual == 0 { return current }
      let columns = try jacobianColumns(at: current)
      let difference = current.firstPoint - current.secondPoint
      try admission.reserve(count: dependentIndexes.count, stride: MemoryLayout<Vector3D>.stride)
      guard
        let delta = try solveThreeColumnSystem(
          columns: dependentIndexes.map { columns[$0] },
          rightHandSide: difference * -1.0
        )
      else {
        return nil
      }
      if current.residual <= residualTarget,
        delta.allSatisfy({ abs($0) <= tolerance.relative * 0.1 }) {
        return current
      }
      var acceptedParameters: [Double]?
      var scale = 1.0
      for _ in 0..<12 {
        try admission.step()
        try admission.reserve(count: parameters.count, stride: MemoryLayout<Double>.stride)
        var candidate = parameters
        for localIndex in dependentIndexes.indices {
          let parameterIndex = dependentIndexes[localIndex]
          candidate[parameterIndex] = min(
            max(
              parameters[parameterIndex] + delta[localIndex] * scale,
              constraints[parameterIndex].lower
            ),
            constraints[parameterIndex].upper
          )
        }
        candidate[fixedParameterIndex] = fixedValue
        let candidateSample = try sample(normalized: candidate)
        if candidateSample.residual < current.residual {
          acceptedParameters = candidate
          break
        }
        scale *= 0.5
      }
      guard let acceptedParameters else { return nil }
      parameters = acceptedParameters
    }
    return nil
  }

  func jacobianColumns(
    at sample: ParametricSurfaceIntersectionSample
  ) throws -> [Vector3D] {
    let firstGeometry = try admission.numericalSample(preparedFirstSurface ?? admission.prepare(first, tolerance: tolerance),
      at: SurfaceParameter(u: sample.actual[0], v: sample.actual[1]), tolerance: tolerance)
    let secondGeometry = try admission.numericalSample(preparedSecondSurface ?? admission.prepare(second, tolerance: tolerance),
      at: SurfaceParameter(u: sample.actual[2], v: sample.actual[3]), tolerance: tolerance)
    try admission.reserve(count: 4, stride: MemoryLayout<Vector3D>.stride)
    try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
    let spans = domains.spans
    return [
      firstGeometry.derivativeU * spans[0],
      firstGeometry.derivativeV * spans[1],
      secondGeometry.derivativeU * -spans[2],
      secondGeometry.derivativeV * -spans[3],
    ]
  }

  private func solveThreeColumnSystem(
    columns: [Vector3D],
    rightHandSide: Vector3D
  ) throws -> [Double]? {
    try admission.step()
    guard columns.count == 3 else { return nil }
    let denominator = determinant(columns[0], columns[1], columns[2])
    var scale = 1.0
    for column in columns { scale *= column.length }
    let floor = max(tolerance.relative, Double.ulpOfOne * 64.0) * scale
    guard denominator.isFinite,
      scale.isFinite,
      scale > 0.0,
      abs(denominator) > floor
    else {
      return nil
    }
    try admission.reserve(count: 3, stride: MemoryLayout<Double>.stride)
    let result = [
      determinant(rightHandSide, columns[1], columns[2]) / denominator,
      determinant(columns[0], rightHandSide, columns[2]) / denominator,
      determinant(columns[0], columns[1], rightHandSide) / denominator,
    ]
    return result.allSatisfy(\.isFinite) ? result : nil
  }

  private func determinant(
    _ first: Vector3D,
    _ second: Vector3D,
    _ third: Vector3D
  ) -> Double {
    first.dot(second.cross(third))
  }
}
