import CADCore

/// One fixed projection with whole original positive principal minors.
struct OriginalCoonsRationalEmbeddingProof {
  private struct Axes {
    let first: Vector3D
    let second: Vector3D
  }

  func proves(
    _ atlas: OriginalCoonsRationalDifferentialAtlas, over domain: SurfaceParameterBox,
    maximumDepth: Int, maximumCells: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let initial = try atlas.fields(over: domain, usage: &execution)
    let capacity = initial.count.addingReportingOverflow(6)
    guard !capacity.overflow else { throw ExactScalarFailure.countOverflow }
    try OriginalCoefficientAllocation.reserve(
      count: capacity.partialValue, of: Axes.self, using: &execution)
    var candidates = [
      Axes(first: .unitX, second: .unitY), Axes(first: .unitY, second: .unitX),
      Axes(first: .unitX, second: .unitZ), Axes(first: .unitZ, second: .unitX),
      Axes(first: .unitY, second: .unitZ), Axes(first: .unitZ, second: .unitY),
    ]
    candidates.reserveCapacity(capacity.partialValue)
    for field in initial {
      try execution.consumeWork(48)
      let a = Vector3D(
        x: field.tangentU[0].midpoint, y: field.tangentU[1].midpoint, z: field.tangentU[2].midpoint)
      let b = Vector3D(
        x: field.tangentV[0].midpoint, y: field.tangentV[1].midpoint, z: field.tangentV[2].midpoint)
      let aa = a.dot(a)
      let ab = a.dot(b)
      let bb = b.dot(b)
      let determinant = aa * bb - ab * ab
      if determinant.isFinite, determinant > 0 {
        let first = (a * bb - b * ab) * (1 / determinant)
        let second = (b * aa - a * ab) * (1 / determinant)
        if first.x.isFinite && first.y.isFinite && first.z.isFinite && second.x.isFinite
          && second.y.isFinite && second.z.isFinite
        {
          candidates.append(Axes(first: first, second: second))
        }
      }
    }
    var visits = 0
    for axes in candidates {
      try OriginalCoefficientAllocation.reserve(
        count: 1, of: (SurfaceParameterBox, Int).self, using: &execution)
      var pending = [(domain, 0)]
      var pendingCapacity = 1
      var firstSign: Int?
      var secondSign: Int?
      var determinantSign: Int?
      var failed = false
      while let (box, depth) = pending.popLast() {
        try execution.visitGeometricCell(depth: depth)
        guard visits < maximumCells else {
          throw KernelError(
            phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message:
              "Original Coons stationary proof exhausted its cumulative native cell capacity.")
        }
        visits += 1
        let fields = try atlas.fields(over: box, usage: &execution)
        var admitted = true
        for field in fields {
          try execution.consumeWork(48)
          guard let a = sign(project(field.tangentU, axes.first)),
            let b = sign(project(field.tangentV, axes.second)),
            let n = sign(project(field.normal, axes.first.cross(axes.second))),
            a * b * n > 0
          else {
            admitted = false
            break
          }
          if let firstSign, firstSign != a {
            failed = true
            break
          }
          if let secondSign, secondSign != b {
            failed = true
            break
          }
          if let determinantSign, determinantSign != n {
            failed = true
            break
          }
          firstSign = a
          secondSign = b
          determinantSign = n
        }
        if failed { break }
        if admitted { continue }
        if depth >= maximumDepth {
          failed = true
          break
        }
        let alongU = box.u.width >= box.v.width
        let axis = alongU ? box.u : box.v
        let middle = axis.lower * 0.5 + axis.upper * 0.5
        guard axis.lower < middle, middle < axis.upper else {
          failed = true
          break
        }
        let lower = try ScalarInterval(lower: axis.lower, upper: middle)
        let upper = try ScalarInterval(lower: middle, upper: axis.upper)
        try OriginalCoefficientAllocation.reserveAppend(
          to: &pending, capacity: &pendingCapacity, using: &execution)
        pending.append(
          (
            alongU
              ? SurfaceParameterBox(u: lower, v: box.v) : SurfaceParameterBox(u: box.u, v: lower),
            depth + 1
          ))
        try OriginalCoefficientAllocation.reserveAppend(
          to: &pending, capacity: &pendingCapacity, using: &execution)
        pending.append(
          (
            alongU
              ? SurfaceParameterBox(u: upper, v: box.v) : SurfaceParameterBox(u: box.u, v: upper),
            depth + 1
          ))
      }
      if !failed { return true }
    }
    return false
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
  private func count(_ a: Int, _ b: Int) throws -> Int {
    let result = a.addingReportingOverflow(b)
    guard !result.overflow else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original Coons projection storage overflows.")
    }
    return result.partialValue
  }
}
