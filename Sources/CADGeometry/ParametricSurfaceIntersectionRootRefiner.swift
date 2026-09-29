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

  func sample(normalized: [Double]) throws -> ParametricSurfaceIntersectionSample {
    let actual = domains.actual(normalized)
    return ParametricSurfaceIntersectionSample(
      normalized: normalized,
      actual: actual,
      firstPoint: try first.point(
        u: actual[0],
        v: actual[1],
        tolerance: tolerance
      ),
      secondPoint: try second.point(
        u: actual[2],
        v: actual[3],
        tolerance: tolerance
      )
    )
  }

  func closestRoot(
    seed: [Double],
    constraints: [(lower: Double, upper: Double)]
  ) throws -> ParametricSurfaceIntersectionSample? {
    var parameters = seed
    for _ in 0..<maximumIterations {
      let current = try sample(normalized: parameters)
      let columns = try jacobianColumns(at: current)
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
      let maximumDiagonal = (0..<4).map { matrix[$0][$0] }.max() ?? 1.0
      let damping = max(maximumDiagonal * 1.0e-10, 1.0e-14)
      for index in 0..<4 { matrix[index][index] += damping }
      guard
        let delta = SmallLinearSystem4.solve(
          matrix: matrix,
          rightHandSide: rightHandSide
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
      if delta.map(abs).max() ?? 0.0 <= tolerance.relative * 0.1 {
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
    let dependentIndexes = seed.indices.filter {
      $0 != fixedParameterIndex
    }
    let fixedValue = min(
      max(seed[fixedParameterIndex], constraints[fixedParameterIndex].lower),
      constraints[fixedParameterIndex].upper
    )
    var parameters = seed.indices.map { index in
      min(max(seed[index], constraints[index].lower), constraints[index].upper)
    }
    parameters[fixedParameterIndex] = fixedValue
    let residualTarget = max(
      min(tolerance.distance * 1.0e-4, tolerance.relative * 0.1),
      Double.ulpOfOne * 4_096.0
    )

    for _ in 0..<maximumIterations {
      let current = try sample(normalized: parameters)
      if current.residual == 0 { return current }
      let columns = try jacobianColumns(at: current)
      let difference = current.firstPoint - current.secondPoint
      guard
        let delta = solveThreeColumnSystem(
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
    let firstGeometry = try first.differentialGeometry(
      atU: sample.actual[0],
      v: sample.actual[1],
      tolerance: tolerance
    )
    let secondGeometry = try second.differentialGeometry(
      atU: sample.actual[2],
      v: sample.actual[3],
      tolerance: tolerance
    )
    return [
      firstGeometry.tangentU * domains.spans[0],
      firstGeometry.tangentV * domains.spans[1],
      secondGeometry.tangentU * -domains.spans[2],
      secondGeometry.tangentV * -domains.spans[3],
    ]
  }

  private func solveThreeColumnSystem(
    columns: [Vector3D],
    rightHandSide: Vector3D
  ) -> [Double]? {
    guard columns.count == 3 else { return nil }
    let denominator = determinant(columns[0], columns[1], columns[2])
    let scale = columns.map(\.length).reduce(1.0, *)
    let floor = max(tolerance.relative, Double.ulpOfOne * 64.0) * scale
    guard denominator.isFinite,
      scale.isFinite,
      scale > 0.0,
      abs(denominator) > floor
    else {
      return nil
    }
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
