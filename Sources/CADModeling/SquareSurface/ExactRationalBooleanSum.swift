import CADCore
import CADGeometry

/// A surface that is a sum of products `f(u)·g(v)` divided by a product `W(u)·V(v)`, assembled as
/// one exact NURBS: every factor a polynomial spline on [0, 1], taken apart into Bézier pieces
/// between its breakpoints, multiplied piece by piece in the Bernstein basis, raised to one
/// degree per direction and joined with full-multiplicity interior knots. The weights are the
/// denominator's coefficients, positive because each factor's are.
///
/// A Boolean sum with rational sides is such a surface: its common denominator is the product of
/// the sides' weight functions, which separates into one of u and one of v.
package struct ExactRationalBooleanSum {
  /// A polynomial spline on [0, 1]: Bernstein coefficients of each piece between `breakpoints`,
  /// vectors (or scalars, in their x).
  package struct Pieces {
    package let breakpoints: [Double]
    package var pieces: [[Vector3D]]

    package var degree: Int { pieces.map { $0.count - 1 }.max() ?? 0 }
  }

  /// One product term: a vector factor times a scalar factor, in either order of directions.
  package struct Term {
    package let u: Pieces
    package let v: Pieces
    /// Whether `u` holds the vector and `v` the scalar (else the other way).
    package let vectorAlongU: Bool
  }

  private let tolerance: ModelingTolerance

  package init(tolerance: ModelingTolerance) {
    self.tolerance = tolerance
  }

  /// The pieces of a spline with `coefficients` on `knots` of `degree` (clamped, domain [0, 1]),
  /// between the spline's distinct knots.
  package func pieces(coefficients: [Vector3D], knots: [Double], degree: Int) throws -> Pieces {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try pieces(coefficients: coefficients, knots: knots, degree: degree, using: &execution)
  }

  package func pieces<A: ExactScalarAdmission & ~Copyable>(
    coefficients: [Vector3D], knots: [Double], degree: Int, using execution: inout A
  ) throws -> Pieces {
    try execution.consumeWork(1)
    try retain(Point3D.self, count: coefficients.count, using: &execution)
    try retain(Double.self, count: knots.count, using: &execution)
    var curve = BSplineCurve3D(
      degree: degree, knots: knots,
      controlPoints: (try coefficients.map {
        try execution.consumeWork(1)
        return .origin + $0
      }))
    var distinct: [Double] = []
    for knot in knots {
      try execution.consumeWork(1)
      guard distinct.last.map({ knot > $0 }) ?? true else { continue }
      distinct.append(knot)
    }
    guard distinct.first == 0, distinct.last == 1 else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "A Boolean sum's factor is a clamped spline on [0, 1].")
    }
    for knot in distinct.dropFirst().dropLast() {
      try execution.consumeWork(1)
      while try curve.knots.reduce(
        0,
        { count, value in
          try execution.consumeWork(1)
          return count + (value == knot ? 1 : 0)
        }) < degree
      {
        try execution.consumeWork(1)
        curve = try curve.insertingKnot(knot, tolerance: tolerance, using: &execution)
      }
    }
    try retain(Vector3D.self, count: curve.controlPoints.count, using: &execution)
    try retain([Vector3D].self, count: max(0, distinct.count - 1), using: &execution)
    let points =
      (try curve.controlPoints.map {
        try execution.consumeWork(1)
        return $0 - Point3D.origin
      })
    return Pieces(
      breakpoints: distinct,
      pieces: (try (0..<(distinct.count - 1)).map { index in
        try execution.consumeWork(1)
        let count = degree.addingReportingOverflow(1)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try retain(Vector3D.self, count: count.partialValue, using: &execution)
        return Array(points[(index * degree)...(index * degree + degree)])
      }))
  }

  /// A polynomial on [0, 1] in Bernstein form restricted to each span between `breakpoints`.
  package func pieces(bezier: [Vector3D], breakpoints: [Double]) throws -> Pieces {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try pieces(bezier: bezier, breakpoints: breakpoints, using: &execution)
  }

  package func pieces<A: ExactScalarAdmission & ~Copyable>(
    bezier: [Vector3D], breakpoints: [Double], using execution: inout A
  ) throws -> Pieces {
    try execution.consumeWork(1)
    let degree = bezier.count - 1
    try retain([Vector3D].self, count: max(0, breakpoints.count - 1), using: &execution)
    return Pieces(
      breakpoints: breakpoints,
      pieces: (try zip(breakpoints, breakpoints.dropFirst()).map { lower, upper in
        try execution.consumeWork(1)
        try retain(Vector3D.self, count: bezier.count, using: &execution)
        return
          (try (0...degree).map { j in
            try execution.consumeWork(1)
            try retain(Double.self, count: degree, using: &execution)
            return try blossom(
              bezier,
              Array(repeating: lower, count: degree - j) + Array(repeating: upper, count: j),
              using: &execution)
          })
      }))
  }

  /// The product of two splines on the same breakpoints, one of them scalar (in its x).
  package func product(_ first: Pieces, scalar second: Pieces) throws -> Pieces {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try product(first, scalar: second, using: &execution)
  }

  package func product<A: ExactScalarAdmission & ~Copyable>(
    _ first: Pieces, scalar second: Pieces, using execution: inout A
  ) throws -> Pieces {
    try execution.consumeWork(1)
    guard first.breakpoints == second.breakpoints else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "A Boolean sum multiplies factors on one set of breakpoints.")
    }
    try retain([Vector3D].self, count: first.pieces.count, using: &execution)
    return Pieces(
      breakpoints: first.breakpoints,
      pieces: (try zip(first.pieces, second.pieces).map { a, b in
        try execution.consumeWork(1)
        let (m, n) = (a.count - 1, b.count - 1)
        let degree = m.addingReportingOverflow(n)
        let count = degree.partialValue.addingReportingOverflow(1)
        guard !degree.overflow, !count.overflow else { throw ExactScalarFailure.countOverflow }
        try retain(Vector3D.self, count: count.partialValue, using: &execution)
        return
          (try (0...degree.partialValue).map { k in
            try execution.consumeWork(1)
            var sum = Vector3D.zero
            for i in max(0, k - n)...min(m, k) {
              try execution.consumeWork(1)
              sum =
                sum + a[i]
                * (try binomial(m, i, using: &execution)
                  * (try binomial(n, k - i, using: &execution))
                  / (try binomial(m + n, k, using: &execution)) * b[k - i].x)
            }
            return sum
          })
      }))
  }

  /// `first + second`, on the same breakpoints.
  package func sum(_ first: Pieces, _ second: Pieces) throws -> Pieces {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try sum(first, second, using: &execution)
  }

  package func sum<A: ExactScalarAdmission & ~Copyable>(
    _ first: Pieces, _ second: Pieces, using execution: inout A
  ) throws -> Pieces {
    try execution.consumeWork(1)
    guard first.breakpoints == second.breakpoints else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "A Boolean sum adds factors on one set of breakpoints.")
    }
    let degree = max(
      try maximumDegree(of: first, using: &execution),
      try maximumDegree(of: second, using: &execution))
    try retain([Vector3D].self, count: first.pieces.count, using: &execution)
    return Pieces(
      breakpoints: first.breakpoints,
      pieces: (try zip(first.pieces, second.pieces).map { a, b in
        try execution.consumeWork(1)
        let count = degree.addingReportingOverflow(1)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try retain(Vector3D.self, count: count.partialValue, using: &execution)
        return
          (try zip(
            try elevate(a, to: degree, using: &execution),
            try elevate(b, to: degree, using: &execution)
          ).map {
            try execution.consumeWork(1)
            return $0 + $1
          })
      }))
  }

  /// `pieces` scaled by `factor`.
  package func scaled(_ pieces: Pieces, by factor: Double) throws -> Pieces {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try scaled(pieces, by: factor, using: &execution)
  }

  package func scaled<A: ExactScalarAdmission & ~Copyable>(
    _ pieces: Pieces, by factor: Double, using execution: inout A
  ) throws -> Pieces {
    try execution.consumeWork(1)
    try retain([Vector3D].self, count: pieces.pieces.count, using: &execution)
    return Pieces(
      breakpoints: pieces.breakpoints,
      pieces: (try pieces.pieces.map {
        try execution.consumeWork(1)
        try retain(Vector3D.self, count: $0.count, using: &execution)
        return
          (try $0.map {
            try execution.consumeWork(1)
            return $0 * factor
          })
      }))
  }

  /// The surface `Σ termᵢ / (denominatorU · denominatorV)`.
  package func surface(terms: [Term], denominatorU: Pieces, denominatorV: Pieces) throws
    -> BSplineSurface3D
  {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try surface(
      terms: terms, denominatorU: denominatorU, denominatorV: denominatorV, using: &execution)
  }

  package func surface<A: ExactScalarAdmission & ~Copyable>(
    terms: [Term], denominatorU: Pieces, denominatorV: Pieces, using execution: inout A
  ) throws -> BSplineSurface3D {
    try execution.consumeWork(1)
    var uDegree = max(try maximumDegree(of: denominatorU, using: &execution), 1)
    var vDegree = max(try maximumDegree(of: denominatorV, using: &execution), 1)
    for term in terms {
      try execution.consumeWork(1)
      uDegree = max(uDegree, try maximumDegree(of: term.u, using: &execution))
      vDegree = max(vDegree, try maximumDegree(of: term.v, using: &execution))
    }
    func flattened(_ pieces: Pieces, degree: Int, using execution: inout A) throws -> [Vector3D] {
      try execution.consumeWork(1)
      var result: [Vector3D] = []
      for (index, piece) in pieces.pieces.enumerated() {
        try execution.consumeWork(1)
        let raised = try elevate(piece, to: degree, using: &execution)
        let addition = index == 0 ? raised.count : max(0, raised.count - 1)
        let count = result.count.addingReportingOverflow(addition)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try retain(Vector3D.self, count: count.partialValue, using: &execution)
        result.append(contentsOf: index == 0 ? raised[...] : raised.dropFirst())
      }
      return result
    }
    func knots(_ breakpoints: [Double], degree: Int, using execution: inout A) throws -> [Double] {
      try execution.consumeWork(1)
      let endpointCount = degree.addingReportingOverflow(1)
      let interiorCount = max(0, breakpoints.count - 2).multipliedReportingOverflow(by: degree)
      let endCount = endpointCount.partialValue.multipliedReportingOverflow(by: 2)
      let totalCount = interiorCount.partialValue.addingReportingOverflow(endCount.partialValue)
      guard degree >= 0, !endpointCount.overflow, !interiorCount.overflow,
        !endCount.overflow, !totalCount.overflow
      else { throw ExactScalarFailure.countOverflow }
      try retain(Double.self, count: totalCount.partialValue, using: &execution)
      var result = Array(repeating: 0.0, count: endpointCount.partialValue)
      result.reserveCapacity(totalCount.partialValue)
      for breakpoint in breakpoints.dropFirst().dropLast() {
        try execution.consumeWork(1)
        result.append(contentsOf: repeatElement(breakpoint, count: degree))
      }
      result.append(contentsOf: repeatElement(1.0, count: endpointCount.partialValue))
      return result
    }
    let denominatorUValues = try flattened(denominatorU, degree: uDegree, using: &execution)
    try retain(Double.self, count: denominatorUValues.count, using: &execution)
    let wu = try
      (denominatorUValues.map {
        try execution.consumeWork(1)
        return $0.x
      })
    let denominatorVValues = try flattened(denominatorV, degree: vDegree, using: &execution)
    try retain(Double.self, count: denominatorVValues.count, using: &execution)
    let wv = try
      (denominatorVValues.map {
        try execution.consumeWork(1)
        return $0.x
      })
    try retain(([Vector3D], [Vector3D], Bool).self, count: terms.count, using: &execution)
    let flat =
      (try terms.map {
        try execution.consumeWork(1)
        return (
          try flattened($0.u, degree: uDegree, using: &execution),
          try flattened($0.v, degree: vDegree, using: &execution), $0.vectorAlongU
        )
      })
    try retain([Point3D].self, count: wv.count, using: &execution)
    try retain([Double].self, count: wv.count, using: &execution)
    var points: [[Point3D]] = []
    var weights: [[Double]] = []
    for j in wv.indices {
      try execution.consumeWork(1)
      try retain(Point3D.self, count: wu.count, using: &execution)
      try retain(Double.self, count: wu.count, using: &execution)
      var row: [Point3D] = []
      var rowWeights: [Double] = []
      for i in wu.indices {
        try execution.consumeWork(1)
        let weight = wu[i] * wv[j]
        guard weight.isFinite, weight > 0 else {
          throw KernelError(
            phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "A rational Boolean sum's weights must be positive.")
        }
        var numerator = Vector3D.zero
        for (u, v, vectorAlongU) in flat {
          try execution.consumeWork(1)
          numerator = numerator + (vectorAlongU ? u[i] * v[j].x : v[j] * u[i].x)
        }
        let point = Point3D.origin + numerator * (1 / weight)
        try point.validate()
        row.append(point)
        rowWeights.append(weight)
      }
      points.append(row)
      weights.append(rowWeights)
    }
    return BSplineSurface3D(
      uDegree: uDegree, vDegree: vDegree,
      uKnots: try knots(denominatorU.breakpoints, degree: uDegree, using: &execution),
      vKnots: try knots(denominatorV.breakpoints, degree: vDegree, using: &execution),
      controlPoints: points, weights: weights)
  }

  private func elevate<A: ExactScalarAdmission & ~Copyable>(
    _ bezier: [Vector3D], to degree: Int, using execution: inout A
  ) throws -> [Vector3D] {
    try execution.consumeWork(1)
    var values = bezier
    while values.count - 1 < degree {
      try execution.consumeWork(1)
      let n = values.count - 1
      let next = values.count.addingReportingOverflow(1)
      guard !next.overflow else { throw ExactScalarFailure.countOverflow }
      try retain(Vector3D.self, count: next.partialValue, using: &execution)
      values =
        (try (0...(n + 1)).map { i in
          try execution.consumeWork(1)
          let a = i > 0 ? values[i - 1] * (Double(i) / Double(n + 1)) : .zero
          let b = i <= n ? values[i] * (1 - Double(i) / Double(n + 1)) : .zero
          return a + b
        })
    }
    return values
  }

  private func blossom<A: ExactScalarAdmission & ~Copyable>(
    _ bezier: [Vector3D], _ parameters: [Double], using execution: inout A
  ) throws -> Vector3D {
    try execution.consumeWork(1)
    var values = bezier
    for t in parameters {
      try execution.consumeWork(1)
      try retain(Vector3D.self, count: values.count - 1, using: &execution)
      values =
        (try (0..<(values.count - 1)).map {
          try execution.consumeWork(1)
          return values[$0] * (1 - t) + values[$0 + 1] * t
        })
    }
    return values[0]
  }

  private func retain<Element, A: ExactScalarAdmission & ~Copyable>(
    _ type: Element.Type,
    count: Int, using execution: inout A
  ) throws {
    let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
    guard count >= 0, !bytes.overflow else { throw ExactScalarFailure.countOverflow }
    try execution.retainStorage(bytes: bytes.partialValue)
  }

  private func maximumDegree<A: ExactScalarAdmission & ~Copyable>(
    of value: Pieces,
    using execution: inout A
  ) throws -> Int {
    var degree: Int?
    for piece in value.pieces {
      try execution.consumeWork(1)
      degree = max(degree ?? (piece.count - 1), piece.count - 1)
    }
    return degree ?? 0
  }

  private func binomial<A: ExactScalarAdmission & ~Copyable>(
    _ n: Int, _ k: Int, using execution: inout A
  ) throws -> Double {
    try execution.consumeWork(1)
    guard k >= 0, k <= n else { return 0 }
    var result = 1.0
    for i in 0..<min(k, n - k) {
      try execution.consumeWork(1)
      result = result * Double(n - i) / Double(i + 1)
    }
    return result
  }
}
