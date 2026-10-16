import CADCore

/// Positive original quotient proofs for an exactly nominated seam or corner.
struct OriginalCoonsRationalBoundaryContactProof {
  private struct Directions {
    let free: [OutwardScalarInterval]
    let transverse: [OutwardScalarInterval]
    let normal: [OutwardScalarInterval]
  }

  func provesSeam(
    first: [OriginalCoonsRationalDifferentialAtlas.Field],
    second: [OriginalCoonsRationalDifferentialAtlas.Field], firstBoundary: SurfaceParameterBoundary,
    secondBoundary: SurfaceParameterBoundary, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let count = first.count.addingReportingOverflow(second.count)
    guard !count.overflow else {
      throw GeometryConversionError.resourceLimitExceeded("Original seam field count overflows.")
    }
    try OriginalCoefficientAllocation.reserve(
      count: count.partialValue, of: Directions.self, using: &execution)
    var directions: [Directions] = []
    directions.reserveCapacity(count.partialValue)
    for index in 0..<2 {
      let fields = index == 0 ? first : second
      let boundary = index == 0 ? firstBoundary : secondBoundary
      let fixedU = boundary == .uLower || boundary == .uUpper
      let upper = boundary == .uUpper || boundary == .vUpper
      let inward = upper == (index == 0) ? 1.0 : -1.0
      for field in fields {
        try execution.consumeWork(12)
        directions.append(
          try Directions(
            free: fixedU ? field.tangentV : field.tangentU,
            transverse: OriginalCoefficientAllocation.map(
              elements: fixedU ? field.tangentU : field.tangentV, using: &execution
            ) { value, _ in value * .exact(inward) },
            normal: OriginalCoefficientAllocation.map(elements: field.normal, using: &execution) {
              value, _ in value * .exact((fixedU ? -1.0 : 1.0) * inward)
            }))
      }
    }
    guard !directions.isEmpty else { return false }
    // Projection coefficients are finite candidates only. Every original
    // quotient field below must admit the same principal-minor signs.
    for seed in directions {
      try execution.consumeWork(48)
      let a = midpoint(seed.free)
      let b = midpoint(seed.transverse)
      let aa = a.dot(a)
      let ab = a.dot(b)
      let bb = b.dot(b)
      let determinant = aa * bb - ab * ab
      guard determinant.isFinite, determinant > 0 else { continue }
      let firstAxis = (a * bb - b * ab) * (1 / determinant)
      let secondAxis = (b * aa - a * ab) * (1 / determinant)
      guard finite(firstAxis), finite(secondAxis) else { continue }
      let normalAxis = firstAxis.cross(secondAxis)
      var firstSign: Int?
      var secondSign: Int?
      var normalSign: Int?
      var admitted = true
      for field in directions {
        try execution.consumeWork(48)
        guard let u = sign(project(field.free, firstAxis)),
          let v = sign(project(field.transverse, secondAxis)),
          let n = sign(project(field.normal, normalAxis)), u * v * n > 0,
          firstSign == nil || firstSign == u,
          secondSign == nil || secondSign == v,
          normalSign == nil || normalSign == n
        else {
          admitted = false
          break
        }
        firstSign = u
        secondSign = v
        normalSign = n
      }
      if admitted { return true }
    }
    return false
  }

  func provesCorner(
    first: [OriginalCoonsRationalDifferentialAtlas.Field],
    second: [OriginalCoonsRationalDifferentialAtlas.Field], firstCorner: Point2D,
    secondCorner: Point2D, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    guard !first.isEmpty, !second.isEmpty else { return false }
    let total = first.count.addingReportingOverflow(second.count)
    guard !total.overflow else {
      throw GeometryConversionError.resourceLimitExceeded("Original corner field count overflows.")
    }
    let firstCount = first.count.multipliedReportingOverflow(by: 2)
    let secondCount = second.count.multipliedReportingOverflow(by: 2)
    guard !firstCount.overflow, !secondCount.overflow else {
      throw ExactScalarFailure.countOverflow
    }
    try OriginalCoefficientAllocation.reserve(
      count: firstCount.partialValue, of: [OutwardScalarInterval].self, using: &execution)
    try OriginalCoefficientAllocation.reserve(
      count: secondCount.partialValue, of: [OutwardScalarInterval].self, using: &execution)
    var firstCone: [[OutwardScalarInterval]] = []
    var secondCone: [[OutwardScalarInterval]] = []
    firstCone.reserveCapacity(firstCount.partialValue)
    secondCone.reserveCapacity(secondCount.partialValue)
    for field in first {
      try execution.consumeWork(6)
      firstCone.append(
        try OriginalCoefficientAllocation.map(elements: field.tangentU, using: &execution) {
          value, _ in value * .exact(firstCorner.x == 0 ? 1 : -1)
        })
      firstCone.append(
        try OriginalCoefficientAllocation.map(elements: field.tangentV, using: &execution) {
          value, _ in value * .exact(firstCorner.y == 0 ? 1 : -1)
        })
    }
    for field in second {
      try execution.consumeWork(6)
      secondCone.append(
        try OriginalCoefficientAllocation.map(elements: field.tangentU, using: &execution) {
          value, _ in value * .exact(secondCorner.x == 0 ? 1 : -1)
        })
      secondCone.append(
        try OriginalCoefficientAllocation.map(elements: field.tangentV, using: &execution) {
          value, _ in value * .exact(secondCorner.y == 0 ? 1 : -1)
        })
    }
    for a in firstCone {
      for b in secondCone {
        try execution.consumeWork(6)
        let candidate = midpoint(a) - midpoint(b)
        guard finite(candidate) else { continue }
        var admitted = true
        for ray in firstCone {
          try execution.consumeWork(12)
          if project(ray, candidate).lower <= 0 {
            admitted = false
            break
          }
        }
        if !admitted { continue }
        for ray in secondCone {
          try execution.consumeWork(12)
          if project(ray, candidate).upper >= 0 {
            admitted = false
            break
          }
        }
        if admitted { return true }
      }
    }
    return false
  }

  private func midpoint(_ vector: [OutwardScalarInterval]) -> Vector3D {
    .init(x: vector[0].midpoint, y: vector[1].midpoint, z: vector[2].midpoint)
  }
  private func finite(_ vector: Vector3D) -> Bool {
    vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
  }
  private func project(_ vector: [OutwardScalarInterval], _ axis: Vector3D) -> OutwardScalarInterval
  {
    vector[0] * .exact(axis.x) + vector[1] * .exact(axis.y) + vector[2] * .exact(axis.z)
  }
  private func sign(_ interval: OutwardScalarInterval) -> Int? {
    if interval.lower > 0 { return 1 }
    if interval.upper < 0 { return -1 }
    return nil
  }
}
