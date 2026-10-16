import CADCore

/// Shared original position formula formerly composed by the differential atlas.
package struct OriginalCoonsHomogeneousAtlas: Sendable {
  package struct Cell: Sendable {
    package let lowerU: ExactRationalCoefficient
    package let upperU: ExactRationalCoefficient
    package let lowerV: ExactRationalCoefficient
    package let upperV: ExactRationalCoefficient
    package let homogeneous: [ExactBivariatePolynomial]
  }
  package let source: OriginalCoonsSurface3D
  package let boundaryPieces: [[OriginalSplineTraversalPolynomialPiece]]
  package let corners: [[ExactRationalCoefficient]]
  package let cells: [Cell]

  package static func prepared<B: ExactScalarAdmission & ~Copyable>(
    _ surface: OriginalCoonsSurface3D,
    usage: inout B
  ) throws -> Self? {
    try surface.admitScalarPreparation(using: &usage)
    try intersectionAlgebraStep(&usage)
    guard surface.hasOriginalPositionContinuity else { return nil }
    try RationalAlgebraStorage.retain(4, of: OriginalCurveRootSpan3D.self, usage: &usage)
    let boundaries = [
      surface.vMinimumBoundary, surface.vMaximumBoundary,
      surface.uMinimumBoundary, surface.uMaximumBoundary,
    ]
    for boundary in boundaries {
      guard try OriginalSplineTraversalPolynomialPiece.supports(boundary, usage: &usage) else {
        return nil
      }
    }
    try RationalAlgebraStorage.retain(
      4, of: [OriginalSplineTraversalPolynomialPiece].self, usage: &usage)
    let bottom = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[0], usage: &usage)
    let top = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[1], usage: &usage)
    let left = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[2], usage: &usage)
    let right = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[3], usage: &usage)
    let boundaryPieces = [bottom, top, left, right]
    try RationalAlgebraStorage.retain(4, of: [ExactRationalCoefficient].self, usage: &usage)
    var corners: [[ExactRationalCoefficient]] = []
    corners.reserveCapacity(4)
    for boundary in boundaries.prefix(2) {
      for endpoint in 0..<2 {
        corners.append(
          try OriginalSplineTraversalPolynomialPiece.endpoint(
            boundary,
            atEnd: endpoint == 1, usage: &usage))
      }
    }
    let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
    let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
    let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
    let um = try one.subtracting(u, usage: &usage)
    let vm = try one.subtracting(v, usage: &usage)
    try RationalAlgebraStorage.retain(8, of: ExactBivariatePolynomial.self, usage: &usage)
    let blends = [vm, v, um, u]
    let cornerBlends = try [
      um.multiplied(by: vm, usage: &usage), u.multiplied(by: vm, usage: &usage),
      um.multiplied(by: v, usage: &usage), u.multiplied(by: v, usage: &usage),
    ]
    try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
    var bilinear: [ExactBivariatePolynomial] = []
    bilinear.reserveCapacity(3)
    for axis in 0..<3 {
      var value = ExactBivariatePolynomial.zero
      for corner in 0..<4 {
        value = try value.adding(
          cornerBlends[corner].scaled(by: corners[corner][axis], usage: &usage), usage: &usage)
      }
      bilinear.append(value)
    }
    func maximum(
      _ a: ExactRationalCoefficient, _ b: ExactRationalCoefficient,
      usage: inout B
    ) throws -> ExactRationalCoefficient {
      try a.subtracting(b, usage: &usage).isPositive ? a : b
    }
    func minimum(
      _ a: ExactRationalCoefficient, _ b: ExactRationalCoefficient,
      usage: inout B
    ) throws -> ExactRationalCoefficient {
      try a.subtracting(b, usage: &usage).isNegative ? a : b
    }
    var result: [Cell] = []
    var capacity = 0
    for a in bottom {
      for b in top {
        let loU = try maximum(a.lower, b.lower, usage: &usage)
        let hiU = try minimum(a.upper, b.upper, usage: &usage)
        guard try hiU.subtracting(loU, usage: &usage).isPositive else { continue }
        for c in left {
          for d in right {
            try CurrentTaskCancellationChecker().checkCancellation()
            try usage.visitCell(axis: .value, depth: 0)
            let loV = try maximum(c.lower, d.lower, usage: &usage)
            let hiV = try minimum(c.upper, d.upper, usage: &usage)
            guard try hiV.subtracting(loV, usage: &usage).isPositive else { continue }
            try RationalAlgebraStorage.retain(4, of: [ExactBivariatePolynomial].self, usage: &usage)
            var laws: [[ExactBivariatePolynomial]] = []
            laws.reserveCapacity(4)
            laws.append(a.homogeneous)
            laws.append(b.homogeneous)
            for boundary in 0..<2 {
              let piece = boundary == 0 ? c : d
              try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
              var swapped: [ExactBivariatePolynomial] = []
              swapped.reserveCapacity(4)
              for law in piece.homogeneous { swapped.append(try law.exchangedAxes(usage: &usage)) }
              laws.append(swapped)
            }
            var denominator = one
            try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
            var position = [ExactBivariatePolynomial](repeating: .zero, count: 3)
            for boundary in 0..<4 {
              try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
              var next: [ExactBivariatePolynomial] = []
              next.reserveCapacity(3)
              for axis in 0..<3 {
                next.append(
                  try position[axis].multiplied(by: laws[boundary][3], usage: &usage)
                    .adding(
                      laws[boundary][axis].multiplied(by: blends[boundary], usage: &usage)
                        .multiplied(by: denominator, usage: &usage), usage: &usage))
              }
              position = next
              denominator = try denominator.multiplied(by: laws[boundary][3], usage: &usage)
            }
            for axis in 0..<3 {
              position[axis] = try position[axis].subtracting(
                bilinear[axis].multiplied(by: denominator, usage: &usage), usage: &usage)
            }
            try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
            var h: [ExactBivariatePolynomial] = []
            h.reserveCapacity(4)
            for value in position { h.append(value) }
            h.append(denominator)
            if result.count == capacity {
              let next = capacity == 0 ? 1 : try exactScalarCount(capacity, 2, multiply: true)
              try RationalAlgebraStorage.retain(next, of: Cell.self, usage: &usage)
              try usage.consumeWork(result.count)
              result.reserveCapacity(next)
              capacity = next
            }
            result.append(.init(lowerU: loU, upperU: hiU, lowerV: loV, upperV: hiV, homogeneous: h))
          }
        }
      }
    }
    guard !result.isEmpty else {
      throw GeometryConversionError.invalidInput(
        "Original Coons rational atlas has no positive source cells.")
    }
    try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
    try CurrentTaskCancellationChecker().checkCancellation()
    return .init(source: surface, boundaryPieces: boundaryPieces, corners: corners, cells: result)
  }
}
