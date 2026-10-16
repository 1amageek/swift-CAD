import CADCore

/// Whole convex support admission; touching support is restricted to proven original incidence.
struct OriginalBilinearBoundaryContactCertificate {
  func proves<B: ExactScalarAdmission & ~Copyable>(
    _ first: OriginalBilinearEmbeddingCertificate,
    _ second: OriginalBilinearEmbeddingCertificate,
    sharedBoundaries: [OriginalSurfaceSharedBoundary], allowedCorners: [(Point2D, Point2D)],
    tolerance: ModelingTolerance, usage: inout B
  ) throws -> Bool {
    typealias Proof = OriginalBilinearEmbeddingCertificate
    try OriginalCoefficientAllocation.reserve(
      count: 34, of: [ExactRationalCoefficient].self, using: &usage)
    try OriginalCoefficientAllocation.reserve(
      count: 8, of: [ExactRationalCoefficient].self, using: &usage)
    var axes = [first.normal, second.normal]
    axes.reserveCapacity(34)
    var firstEdges: [[ExactRationalCoefficient]] = []
    var secondEdges: [[ExactRationalCoefficient]] = []
    firstEdges.reserveCapacity(4)
    secondEdges.reserveCapacity(4)
    for index in 0..<4 {
      firstEdges.append(
        try Proof.subtract(first.vertices[(index + 1) % 4], first.vertices[index], usage: &usage))
      secondEdges.append(
        try Proof.subtract(second.vertices[(index + 1) % 4], second.vertices[index], usage: &usage))
    }
    for index in 0..<8 {
      let edge = index < 4 ? firstEdges[index] : secondEdges[index - 4]
      axes.append(try Proof.cross(edge, first.normal, usage: &usage))
      axes.append(try Proof.cross(edge, second.normal, usage: &usage))
    }
    for a in firstEdges {
      for b in secondEdges { axes.append(try Proof.cross(a, b, usage: &usage)) }
    }
    let distance = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &usage)
    let distanceSquared = try distance.multiplied(by: distance, usage: &usage)
    for axis in axes {
      try CurrentTaskCancellationChecker().checkCancellation()
      try usage.visitCell(axis: .value, depth: 0)
      if axis.allSatisfy({ $0.isZero }) { continue }
      let a = try OriginalCoefficientAllocation.map(elements: first.vertices, using: &usage) {
        vertex, usage in
        try Proof.dot(axis, vertex, usage: &usage)
      }
      let b = try OriginalCoefficientAllocation.map(elements: second.vertices, using: &usage) {
        vertex, usage in
        try Proof.dot(axis, vertex, usage: &usage)
      }
      let aBounds = try bounds(a, usage: &usage)
      let bBounds = try bounds(b, usage: &usage)
      for orientation in 0..<2 {
        let firstIsLeft = orientation == 0
        let left = firstIsLeft ? a : b
        let right = firstIsLeft ? b : a
        let leftBounds = firstIsLeft ? aBounds : bBounds
        let rightBounds = firstIsLeft ? bBounds : aBounds
        let gap = try rightBounds.0.subtracting(leftBounds.1, usage: &usage)
        if gap.isPositive {
          let required = try distanceSquared.multiplied(
            by: Proof.dot(axis, axis, usage: &usage), usage: &usage)
          if try gap.multiplied(by: gap, usage: &usage).subtracting(required, usage: &usage)
            .isPositive
          {
            return true
          }
        }
        guard gap.isZero else { continue }
        try usage.consumeWork(8)
        try OriginalCoefficientAllocation.reserve(count: 8, of: Int.self, using: &usage)
        let leftSupport = left.indices.filter { left[$0] == leftBounds.1 }
        let rightSupport = right.indices.filter { right[$0] == rightBounds.0 }
        for seam in sharedBoundaries {
          let leftEdge = edge(firstIsLeft ? seam.first : seam.second)
          let rightEdge = edge(firstIsLeft ? seam.second : seam.first)
          if leftSupport.allSatisfy({ ($0 == leftEdge.0 || $0 == leftEdge.1) })
            || rightSupport.allSatisfy({ ($0 == rightEdge.0 || $0 == rightEdge.1) })
          {
            return true
          }
        }
        for corner in allowedCorners {
          let leftCorner = vertex(firstIsLeft ? corner.0 : corner.1)
          let rightCorner = vertex(firstIsLeft ? corner.1 : corner.0)
          if leftSupport.allSatisfy({ $0 == leftCorner })
            || rightSupport.allSatisfy({ $0 == rightCorner })
          {
            return true
          }
        }
      }
    }
    return false
  }

  private func bounds<B: ExactScalarAdmission & ~Copyable>(
    _ values: [ExactRationalCoefficient], usage: inout B
  )
    throws -> (ExactRationalCoefficient, ExactRationalCoefficient)
  {
    var lower = values[0]
    var upper = values[0]
    for value in values.dropFirst() {
      if try value.subtracting(lower, usage: &usage).isNegative { lower = value }
      if try value.subtracting(upper, usage: &usage).isPositive { upper = value }
    }
    return (lower, upper)
  }
  private func edge(_ boundary: SurfaceParameterBoundary) -> (Int, Int) {
    switch boundary {
    case .uLower: (0, 3)
    case .uUpper: (1, 2)
    case .vLower: (0, 1)
    case .vUpper: (2, 3)
    }
  }
  private func vertex(_ corner: Point2D) -> Int {
    corner.y == 0 ? (corner.x == 0 ? 0 : 1) : (corner.x == 0 ? 3 : 2)
  }
}
