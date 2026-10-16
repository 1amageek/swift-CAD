import CADCore

/// Exact original convex-planar bilinear authority, including a stationary corner.
struct OriginalBilinearEmbeddingCertificate {
  let vertices: [[ExactRationalCoefficient]]
  let normal: [ExactRationalCoefficient]

  static func proven<B: ExactScalarAdmission & ~Copyable>(
    _ source: BSplineSurface3D,
    usage: inout B
  ) throws -> Self? {
    try usage.consumeWork(32)
    guard source.uDegree == 1, source.vDegree == 1, unitKnots(source.uKnots),
      unitKnots(source.vKnots), source.controlPoints.count == 2,
      source.controlPoints.allSatisfy({ $0.count == 2 }), source.weights.count == 2,
      source.weights.allSatisfy({ $0.count == 2 && $0[0] == 1 && $0[1] == 1 })
    else { return nil }
    try OriginalCoefficientAllocation.reserve(count: 4, of: Point3D.self, using: &usage)
    let points = [
      source.controlPoints[0][0], source.controlPoints[0][1],
      source.controlPoints[1][1], source.controlPoints[1][0],
    ]
    try OriginalCoefficientAllocation.reserve(
      count: 4, of: [ExactRationalCoefficient].self, using: &usage)
    var vertices: [[ExactRationalCoefficient]] = []
    vertices.reserveCapacity(4)
    for p in points {
      vertices.append(
        try OriginalCoefficientAllocation.map(elements: 0..<3, using: &usage) { axis, usage in
          try .originalDouble(axis == 0 ? p.x : axis == 1 ? p.y : p.z, usage: &usage)
        })
    }
    for a in 0..<4 {
      for b in (a + 1)..<4 {
        try usage.consumeWork(3)
        if vertices[a] == vertices[b] { return nil }
      }
    }
    var planeNormal: [ExactRationalCoefficient]?
    for axis in 0..<3 {
      let axisPair = (axis, (axis + 1) % 3)
      var orientation = 0
      var zeros = 0
      var candidateNormal: [ExactRationalCoefficient]?
      for index in 0..<4 {
        let a = try subtract(vertices[(index + 1) % 4], vertices[index], usage: &usage)
        let b = try subtract(vertices[(index + 2) % 4], vertices[index], usage: &usage)
        let determinant = try a[axisPair.0].multiplied(by: b[axisPair.1], usage: &usage)
          .subtracting(a[axisPair.1].multiplied(by: b[axisPair.0], usage: &usage), usage: &usage)
        if determinant.isZero {
          zeros += 1
          continue
        }
        let sign = determinant.isPositive ? 1 : -1
        if orientation != 0, orientation != sign {
          orientation = 0
          zeros = 4
          break
        }
        orientation = sign
        if candidateNormal == nil { candidateNormal = try cross(a, b, usage: &usage) }
      }
      if orientation != 0, zeros <= 1, let candidateNormal {
        planeNormal = candidateNormal
        break
      }
    }
    guard let normal = planeNormal else { return nil }
    for vertex in vertices {
      let displacement = try subtract(vertex, vertices[0], usage: &usage)
      guard try dot(normal, displacement, usage: &usage).isZero else { return nil }
    }
    return .init(vertices: vertices, normal: normal)
  }

  private static func unitKnots(_ knots: [Double]) -> Bool {
    knots.count == 4 && knots[0] == 0 && knots[1] == 0 && knots[2] == 1 && knots[3] == 1
  }

  static func subtract<B: ExactScalarAdmission & ~Copyable>(
    _ a: [ExactRationalCoefficient],
    _ b: [ExactRationalCoefficient], usage: inout B
  ) throws -> [ExactRationalCoefficient] {
    return try OriginalCoefficientAllocation.map(elements: 0..<3, using: &usage) { axis, usage in
      try a[axis].subtracting(b[axis], usage: &usage)
    }
  }
  static func cross<B: ExactScalarAdmission & ~Copyable>(
    _ a: [ExactRationalCoefficient],
    _ b: [ExactRationalCoefficient], usage: inout B
  ) throws -> [ExactRationalCoefficient] {
    return try OriginalCoefficientAllocation.map(elements: 0..<3, using: &usage) { axis, usage in
      let next = (axis + 1) % 3
      let last = (axis + 2) % 3
      return try a[next].multiplied(by: b[last], usage: &usage)
        .subtracting(a[last].multiplied(by: b[next], usage: &usage), usage: &usage)
    }
  }
  static func dot<B: ExactScalarAdmission & ~Copyable>(
    _ a: [ExactRationalCoefficient],
    _ b: [ExactRationalCoefficient], usage: inout B
  ) throws -> ExactRationalCoefficient {
    var result = ExactRationalCoefficient.zero
    for axis in 0..<3 {
      try usage.consumeWork(1)
      result = try result.adding(a[axis].multiplied(by: b[axis], usage: &usage), usage: &usage)
    }
    return result
  }
}
