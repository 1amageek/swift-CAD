import CADCore

public struct ExactCoonsBSplineSurfaceBuilder: TransfiniteBSplineSurfaceBuilding {
  private let basisResolver: any BSplineCurveCommonBasisResolving
  public var maximumPatchCount: Int
  public var maximumResultDegree: Int

  public init(
    basisResolver: any BSplineCurveCommonBasisResolving = DefaultBSplineCurveCommonBasisResolver(),
    maximumPatchCount: Int = 65_536,
    maximumResultDegree: Int = 64
  ) {
    self.basisResolver = basisResolver
    self.maximumPatchCount = maximumPatchCount
    self.maximumResultDegree = maximumResultDegree
  }

  public func build(
    vMinimumBoundary: BSplineCurve3D,
    vMaximumBoundary: BSplineCurve3D,
    uMinimumBoundary: BSplineCurve3D,
    uMaximumBoundary: BSplineCurve3D,
    tolerance: ModelingTolerance
  ) throws -> BSplineSurface3D {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try build(
      vMinimumBoundary: vMinimumBoundary, vMaximumBoundary: vMaximumBoundary,
      uMinimumBoundary: uMinimumBoundary, uMaximumBoundary: uMaximumBoundary, tolerance: tolerance,
      using: &execution)
  }

  public func build(
    vMinimumBoundary: BSplineCurve3D,
    vMaximumBoundary: BSplineCurve3D,
    uMinimumBoundary: BSplineCurve3D,
    uMaximumBoundary: BSplineCurve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BSplineSurface3D {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard maximumPatchCount > 0, maximumResultDegree > 0 else {
      throw diagnostic(
        code: .invalidInput,
        tolerance: tolerance,
        message: "Exact Coons construction requires positive resource limits."
      )
    }
    let horizontal = try basisResolver.resolve(
      first: vMinimumBoundary,
      second: vMaximumBoundary,
      tolerance: tolerance, using: &execution
    )
    let vertical = try basisResolver.resolve(
      first: uMinimumBoundary,
      second: uMaximumBoundary,
      tolerance: tolerance, using: &execution
    )
    let corners = try validatedCorners(
      vMinimum: horizontal.first,
      vMaximum: horizontal.second,
      uMinimum: vertical.first,
      uMaximum: vertical.second,
      tolerance: tolerance, using: &execution)
    let horizontalMinimumPatches = try patches(
      of: horizontal.first,
      tolerance: tolerance, using: &execution)
    let horizontalMaximumPatches = try patches(
      of: horizontal.second,
      tolerance: tolerance, using: &execution)
    let verticalMinimumPatches = try patches(
      of: vertical.first,
      tolerance: tolerance, using: &execution)
    let verticalMaximumPatches = try patches(
      of: vertical.second,
      tolerance: tolerance, using: &execution)
    guard horizontalMinimumPatches.count == horizontalMaximumPatches.count,
      verticalMinimumPatches.count == verticalMaximumPatches.count
    else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Exact Coons construction lost an aligned boundary span."
      )
    }
    let patchCount = try exactScalarCount(
      horizontalMinimumPatches.count, verticalMinimumPatches.count, multiply: true)
    guard patchCount <= maximumPatchCount else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        residual: Double(patchCount),
        tolerance: tolerance,
        message: "Exact Coons construction exceeded its tensor patch budget."
      )
    }
    let polynomial = try [horizontal.first, horizontal.second, vertical.first, vertical.second]
      .allSatisfy { curve in
        try curve.weights.allSatisfy { weight in
          try execution.consumeWork(1)
          return weight == 1.0
        }
      }
    let uDegree =
      polynomial
      ? horizontal.first.degree
      : try exactScalarCount(try exactScalarCount(horizontal.first.degree, 2, multiply: true), 1)
    let vDegree =
      polynomial
      ? vertical.first.degree
      : try exactScalarCount(try exactScalarCount(vertical.first.degree, 2, multiply: true), 1)
    guard uDegree <= maximumResultDegree, vDegree <= maximumResultDegree else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        residual: Double(max(uDegree, vDegree)),
        tolerance: tolerance,
        message: "Exact Coons construction exceeded its result-degree budget."
      )
    }

    if polynomial {
      return try polynomialSurface(
        horizontal: horizontal, vertical: vertical,
        corners: corners, tolerance: tolerance, using: &execution)
    }

    try execution.retainStorage(
      count: verticalMinimumPatches.count, stride: MemoryLayout<[TensorPatch]>.stride)
    try execution.retainStorage(count: patchCount, stride: MemoryLayout<TensorPatch>.stride)
    var tensorPatches: [[TensorPatch]] = []
    tensorPatches.reserveCapacity(verticalMinimumPatches.count)
    for vIndex in verticalMinimumPatches.indices {
      try execution.consumeWork(1)

      var row: [TensorPatch] = []
      row.reserveCapacity(horizontalMinimumPatches.count)
      for uIndex in horizontalMinimumPatches.indices {
        try execution.consumeWork(1)

        row.append(
          try tensorPatch(
            vMinimum: horizontalMinimumPatches[uIndex],
            vMaximum: horizontalMaximumPatches[uIndex],
            uMinimum: verticalMinimumPatches[vIndex],
            uMaximum: verticalMaximumPatches[vIndex],
            corners: corners,
            uDegree: uDegree,
            vDegree: vDegree,
            tolerance: tolerance, using: &execution))
      }
      tensorPatches.append(row)
    }
    return try assemble(
      patches: tensorPatches,
      uBreaks: try breaks(from: horizontalMinimumPatches, using: &execution),
      vBreaks: try breaks(from: verticalMinimumPatches, using: &execution),
      uDegree: uDegree,
      vDegree: vDegree,
      tolerance: tolerance, using: &execution)
  }

  private func polynomialSurface(
    horizontal: BSplineCurveCommonBasisPair,
    vertical: BSplineCurveCommonBasisPair,
    corners: Corners,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BSplineSurface3D {
    try execution.consumeWork(1)
    // In the normalized common basis, Greville coefficients represent the
    // linear coordinates exactly; no rational products or degree growth occur.
    func parameters(_ curve: BSplineCurve3D, using execution: inout OriginalQueryExecution) throws
      -> [Double]
    {
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: curve.controlPointCount, stride: MemoryLayout<Double>.stride)
      return try (0..<curve.controlPointCount).map { index in
        try execution.consumeWork(1)
        let sum = try curve.knots[(index + 1)...(index + curve.degree)].reduce(0.0) { sum, knot in
          try execution.consumeWork(1)
          return sum + knot
        }
        return sum / Double(curve.degree)
      }
    }
    let us = try parameters(horizontal.first, using: &execution)
    let vs = try parameters(vertical.first, using: &execution)
    try execution.retainStorage(
      count: try exactScalarCount(us.count, vs.count, multiply: true),
      stride: MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
    var points = Array(
      repeating: Array(repeating: Point3D.origin, count: us.count), count: vs.count)
    for j in vs.indices {
      try execution.consumeWork(1)

      for i in us.indices {
        try execution.consumeWork(1)

        if j == 0 {
          points[j][i] = horizontal.first.controlPoints[i]
          continue
        }
        if j == vs.count - 1 {
          points[j][i] = horizontal.second.controlPoints[i]
          continue
        }
        if i == 0 {
          points[j][i] = vertical.first.controlPoints[j]
          continue
        }
        if i == us.count - 1 {
          points[j][i] = vertical.second.controlPoints[j]
          continue
        }
        let u = us[i]
        let v = vs[j]
        let bottom = corners.minimumMinimum + (corners.maximumMinimum - corners.minimumMinimum) * u
        let top = corners.minimumMaximum + (corners.maximumMaximum - corners.minimumMaximum) * u
        let bilinear = bottom + (top - bottom) * v
        let across =
          horizontal.first.controlPoints[i]
          + (horizontal.second.controlPoints[i] - horizontal.first.controlPoints[i]) * v
        let along =
          vertical.first.controlPoints[j]
          + (vertical.second.controlPoints[j] - vertical.first.controlPoints[j]) * u
        points[j][i] = across + (along - bilinear)
      }
    }
    let surface = BSplineSurface3D(
      uDegree: horizontal.first.degree, vDegree: vertical.first.degree,
      uKnots: horizontal.first.knots, vKnots: vertical.first.knots, controlPoints: points)
    try surface.validate(tolerance: tolerance, using: &execution)
    return surface
  }

  private struct Corners: Sendable {
    let minimumMinimum: Point3D
    let maximumMinimum: Point3D
    let minimumMaximum: Point3D
    let maximumMaximum: Point3D
  }

  private struct HomogeneousControl: Sendable {
    let numerator: Vector3D
    let weight: Double

    init(point: Point3D, weight: Double) {
      numerator = Vector3D(
        x: point.x * weight,
        y: point.y * weight,
        z: point.z * weight
      )
      self.weight = weight
    }
  }

  private struct TensorPatch: Sendable {
    let controls: [[HomogeneousControl]]
  }

  private func validatedCorners(
    vMinimum: BSplineCurve3D,
    vMaximum: BSplineCurve3D,
    uMinimum: BSplineCurve3D,
    uMaximum: BSplineCurve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Corners {
    try execution.consumeWork(1)
    let minimumMinimum = try vMinimum.point(at: 0.0, tolerance: tolerance, using: &execution)
    let maximumMinimum = try vMinimum.point(at: 1.0, tolerance: tolerance, using: &execution)
    let minimumMaximum = try vMaximum.point(at: 0.0, tolerance: tolerance, using: &execution)
    let maximumMaximum = try vMaximum.point(at: 1.0, tolerance: tolerance, using: &execution)
    let residuals = [
      try (minimumMinimum - uMinimum.point(at: 0.0, tolerance: tolerance, using: &execution))
        .length,
      try (maximumMinimum - uMaximum.point(at: 0.0, tolerance: tolerance, using: &execution))
        .length,
      try (minimumMaximum - uMinimum.point(at: 1.0, tolerance: tolerance, using: &execution))
        .length,
      try (maximumMaximum - uMaximum.point(at: 1.0, tolerance: tolerance, using: &execution))
        .length,
    ]
    let residual = residuals.max() ?? .infinity
    guard residual <= tolerance.distance else {
      throw diagnostic(
        code: .invalidInput,
        residual: residual,
        tolerance: tolerance,
        message: "Oriented patch boundaries do not meet at all four corners."
      )
    }
    return Corners(
      minimumMinimum: minimumMinimum,
      maximumMinimum: maximumMinimum,
      minimumMaximum: minimumMaximum,
      maximumMaximum: maximumMaximum
    )
  }

  private func patches(
    of curve: BSplineCurve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [RationalBezierCurvePatch3D] {
    try execution.consumeWork(1)
    let result = try BSplineCurveBezierDecomposer().curvePatches(
      curve: curve,
      tolerance: tolerance, using: &execution
    )
    guard result.isEmpty == false else {
      throw diagnostic(
        code: .invalidInput,
        tolerance: tolerance,
        message: "Exact Coons construction requires non-empty boundary spans."
      )
    }
    return result
  }

  private func tensorPatch(
    vMinimum: RationalBezierCurvePatch3D,
    vMaximum: RationalBezierCurvePatch3D,
    uMinimum: RationalBezierCurvePatch3D,
    uMaximum: RationalBezierCurvePatch3D,
    corners: Corners,
    uDegree: Int,
    vDegree: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> TensorPatch {
    try execution.consumeWork(1)
    let vMinimumHomogeneous = try homogeneous(vMinimum, using: &execution)
    let vMaximumHomogeneous = try homogeneous(vMaximum, using: &execution)
    let uMinimumHomogeneous = try homogeneous(uMinimum, using: &execution)
    let uMaximumHomogeneous = try homogeneous(uMaximum, using: &execution)
    let horizontalWeightProduct = try product(
      vMinimum.weights,
      vMaximum.weights,
      tolerance: tolerance, using: &execution)
    let verticalWeightProduct = try product(
      uMinimum.weights,
      uMaximum.weights,
      tolerance: tolerance, using: &execution)

    for controls in [
      vMinimumHomogeneous, vMaximumHomogeneous, uMinimumHomogeneous, uMaximumHomogeneous,
    ] {
      try execution.retainStorage(count: controls.count, stride: MemoryLayout<Vector3D>.stride)
    }
    let vMinimumNumerator = try vectorTimesScalar(
      try vMinimumHomogeneous.map({
        try execution.consumeWork(1)
        return $0.numerator
      }),
      vMaximum.weights,
      tolerance: tolerance, using: &execution)
    let vMaximumNumerator = try vectorTimesScalar(
      try vMaximumHomogeneous.map({
        try execution.consumeWork(1)
        return $0.numerator
      }),
      vMinimum.weights,
      tolerance: tolerance, using: &execution)
    let uMinimumNumerator = try vectorTimesScalar(
      try uMinimumHomogeneous.map({
        try execution.consumeWork(1)
        return $0.numerator
      }),
      uMaximum.weights,
      tolerance: tolerance, using: &execution)
    let uMaximumNumerator = try vectorTimesScalar(
      try uMaximumHomogeneous.map({
        try execution.consumeWork(1)
        return $0.numerator
      }),
      uMinimum.weights,
      tolerance: tolerance, using: &execution)

    let uOneMinus = [1.0 - vMinimum.lower, 1.0 - vMinimum.upper]
    let uValue = [vMinimum.lower, vMinimum.upper]
    let vOneMinus = [1.0 - uMinimum.lower, 1.0 - uMinimum.upper]
    let vValue = [uMinimum.lower, uMinimum.upper]

    let horizontalMinimumVFactor = try product(
      verticalWeightProduct,
      vOneMinus,
      tolerance: tolerance, using: &execution)
    let horizontalMaximumVFactor = try product(
      verticalWeightProduct,
      vValue,
      tolerance: tolerance, using: &execution)
    let verticalMinimumUFactor = try product(
      horizontalWeightProduct,
      uOneMinus,
      tolerance: tolerance, using: &execution)
    let verticalMaximumUFactor = try product(
      horizontalWeightProduct,
      uValue,
      tolerance: tolerance, using: &execution)

    var numerator = try zeroVectorGrid(uDegree: uDegree, vDegree: vDegree, using: &execution)
    try addOuter(
      uVector: try elevated(vMinimumNumerator, to: uDegree, using: &execution),
      vScalar: horizontalMinimumVFactor,
      scale: 1.0,
      to: &numerator,
      tolerance: tolerance, using: &execution)
    try addOuter(
      uVector: try elevated(vMaximumNumerator, to: uDegree, using: &execution),
      vScalar: horizontalMaximumVFactor,
      scale: 1.0,
      to: &numerator,
      tolerance: tolerance, using: &execution)
    try addOuter(
      uScalar: verticalMinimumUFactor,
      vVector: try elevated(uMinimumNumerator, to: vDegree, using: &execution),
      scale: 1.0,
      to: &numerator,
      tolerance: tolerance, using: &execution)
    try addOuter(
      uScalar: verticalMaximumUFactor,
      vVector: try elevated(uMaximumNumerator, to: vDegree, using: &execution),
      scale: 1.0,
      to: &numerator,
      tolerance: tolerance, using: &execution)

    try subtractCorner(
      corners.minimumMinimum,
      uFactor: verticalMinimumUFactor,
      vFactor: horizontalMinimumVFactor,
      from: &numerator,
      tolerance: tolerance, using: &execution)
    try subtractCorner(
      corners.maximumMinimum,
      uFactor: verticalMaximumUFactor,
      vFactor: horizontalMinimumVFactor,
      from: &numerator,
      tolerance: tolerance, using: &execution)
    try subtractCorner(
      corners.minimumMaximum,
      uFactor: verticalMinimumUFactor,
      vFactor: horizontalMaximumVFactor,
      from: &numerator,
      tolerance: tolerance, using: &execution)
    try subtractCorner(
      corners.maximumMaximum,
      uFactor: verticalMaximumUFactor,
      vFactor: horizontalMaximumVFactor,
      from: &numerator,
      tolerance: tolerance, using: &execution)

    let uWeights = try elevated(horizontalWeightProduct, to: uDegree, using: &execution)
    let vWeights = try elevated(verticalWeightProduct, to: vDegree, using: &execution)
    try execution.retainStorage(
      count: vDegree + 1, stride: MemoryLayout<[HomogeneousControl]>.stride)
    try execution.retainStorage(
      count: try exactScalarCount(uDegree + 1, vDegree + 1, multiply: true),
      stride: MemoryLayout<HomogeneousControl>.stride)
    var controls: [[HomogeneousControl]] = []
    controls.reserveCapacity(vDegree + 1)
    for vIndex in 0...vDegree {
      try execution.consumeWork(1)

      var row: [HomogeneousControl] = []
      row.reserveCapacity(uDegree + 1)
      for uIndex in 0...uDegree {
        try execution.consumeWork(1)

        let weight = uWeights[uIndex] * vWeights[vIndex]
        let value = numerator[vIndex][uIndex]
        guard weight.isFinite,
          weight > 0.0,
          value.isFinite
        else {
          throw diagnostic(
            code: .resourceLimitExceeded,
            residual: weight,
            tolerance: tolerance,
            message: "Exact Coons homogeneous control exceeded the finite positive-weight range."
          )
        }
        row.append(
          HomogeneousControl(
            point: Point3D(
              x: value.x / weight,
              y: value.y / weight,
              z: value.z / weight
            ),
            weight: weight
          ))
      }
      controls.append(row)
    }
    return TensorPatch(controls: controls)
  }

  private func homogeneous(
    _ patch: RationalBezierCurvePatch3D, using execution: inout OriginalQueryExecution
  ) throws -> [HomogeneousControl] {
    try execution.consumeWork(1)
    try execution.retainStorage(
      count: patch.controlPoints.count, stride: MemoryLayout<HomogeneousControl>.stride)
    return try patch.controlPoints.indices.map { index in
      try execution.consumeWork(1)
      return HomogeneousControl(
        point: patch.controlPoints[index],
        weight: patch.weights[index]
      )
    }
  }

  private func product(
    _ first: [Double],
    _ second: [Double],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    let firstDegree = first.count - 1
    let secondDegree = second.count - 1
    let resultDegree = firstDegree + secondDegree
    try execution.retainStorage(count: resultDegree + 1, stride: MemoryLayout<Double>.stride)
    var result = Array(repeating: 0.0, count: resultDegree + 1)
    for firstIndex in first.indices {
      try execution.consumeWork(1)

      for secondIndex in second.indices {
        try execution.consumeWork(1)

        let resultIndex = firstIndex + secondIndex
        let coefficient = try bernsteinProductCoefficient(
          firstDegree: firstDegree,
          firstIndex: firstIndex,
          secondDegree: secondDegree,
          secondIndex: secondIndex,
          tolerance: tolerance
        )
        result[resultIndex] += first[firstIndex] * second[secondIndex] * coefficient
      }
    }
    guard result.allSatisfy({ $0.isFinite }) else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Bernstein scalar multiplication exceeded the finite numeric range."
      )
    }
    return result
  }

  private func vectorTimesScalar(
    _ vectors: [Vector3D],
    _ scalars: [Double],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Vector3D] {
    try execution.consumeWork(1)
    let vectorDegree = vectors.count - 1
    let scalarDegree = scalars.count - 1
    let resultDegree = vectorDegree + scalarDegree
    try execution.retainStorage(count: resultDegree + 1, stride: MemoryLayout<Vector3D>.stride)
    var result = Array(repeating: Vector3D.zero, count: resultDegree + 1)
    for vectorIndex in vectors.indices {
      try execution.consumeWork(1)

      for scalarIndex in scalars.indices {
        try execution.consumeWork(1)

        let resultIndex = vectorIndex + scalarIndex
        let coefficient = try bernsteinProductCoefficient(
          firstDegree: vectorDegree,
          firstIndex: vectorIndex,
          secondDegree: scalarDegree,
          secondIndex: scalarIndex,
          tolerance: tolerance
        )
        result[resultIndex] =
          result[resultIndex]
          + vectors[vectorIndex] * (scalars[scalarIndex] * coefficient)
      }
    }
    guard result.allSatisfy({ $0.isFinite }) else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Bernstein vector multiplication exceeded the finite numeric range."
      )
    }
    return result
  }

  private func bernsteinProductCoefficient(
    firstDegree: Int,
    firstIndex: Int,
    secondDegree: Int,
    secondIndex: Int,
    tolerance: ModelingTolerance
  ) throws -> Double {
    let numerator =
      binomial(firstDegree, firstIndex)
      * binomial(secondDegree, secondIndex)
    let denominator = binomial(
      firstDegree + secondDegree,
      firstIndex + secondIndex
    )
    let result = numerator / denominator
    guard result.isFinite else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Bernstein product coefficient exceeded the finite numeric range."
      )
    }
    return result
  }

  private func binomial(_ degree: Int, _ index: Int) -> Double {
    let reduced = min(index, degree - index)
    guard reduced > 0 else { return 1.0 }
    var result = 1.0
    for step in 1...reduced {
      result *= Double(degree - reduced + step) / Double(step)
    }
    return result
  }

  private func elevated(
    _ values: [Double], to targetDegree: Int, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    var result = values
    while result.count - 1 < targetDegree {
      try execution.consumeWork(1)

      let degree = result.count - 1
      try execution.retainStorage(count: result.count + 1, stride: MemoryLayout<Double>.stride)
      var next = Array(repeating: 0.0, count: result.count + 1)
      next[0] = result[0]
      next[next.count - 1] = result[result.count - 1]
      if degree > 0 {
        for index in 1...degree {
          try execution.consumeWork(1)

          let alpha = Double(index) / Double(degree + 1)
          next[index] =
            result[index - 1] * alpha
            + result[index] * (1.0 - alpha)
        }
      }
      result = next
    }
    return result
  }

  private func elevated(
    _ values: [Vector3D],
    to targetDegree: Int, using execution: inout OriginalQueryExecution
  ) throws -> [Vector3D] {
    try execution.consumeWork(1)
    var result = values
    while result.count - 1 < targetDegree {
      try execution.consumeWork(1)

      let degree = result.count - 1
      try execution.retainStorage(count: result.count + 1, stride: MemoryLayout<Vector3D>.stride)
      var next = Array(repeating: Vector3D.zero, count: result.count + 1)
      next[0] = result[0]
      next[next.count - 1] = result[result.count - 1]
      if degree > 0 {
        for index in 1...degree {
          try execution.consumeWork(1)

          let alpha = Double(index) / Double(degree + 1)
          next[index] =
            result[index - 1] * alpha
            + result[index] * (1.0 - alpha)
        }
      }
      result = next
    }
    return result
  }

  private func zeroVectorGrid(
    uDegree: Int,
    vDegree: Int, using execution: inout OriginalQueryExecution
  ) throws -> [[Vector3D]] {
    try execution.consumeWork(1)
    try execution.retainStorage(
      count: try exactScalarCount(uDegree + 1, vDegree + 1, multiply: true),
      stride: MemoryLayout<Vector3D>.stride)
    return Array(
      repeating: Array(repeating: .zero, count: uDegree + 1),
      count: vDegree + 1
    )
  }

  private func addOuter(
    uVector: [Vector3D],
    vScalar: [Double],
    scale: Double,
    to result: inout [[Vector3D]],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    guard result.count == vScalar.count,
      result.allSatisfy({ $0.count == uVector.count })
    else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Exact Coons horizontal tensor dimensions are inconsistent."
      )
    }
    for vIndex in vScalar.indices {
      try execution.consumeWork(1)

      for uIndex in uVector.indices {
        try execution.consumeWork(1)

        result[vIndex][uIndex] =
          result[vIndex][uIndex]
          + uVector[uIndex] * (vScalar[vIndex] * scale)
      }
    }
  }

  private func addOuter(
    uScalar: [Double],
    vVector: [Vector3D],
    scale: Double,
    to result: inout [[Vector3D]],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    guard result.count == vVector.count,
      result.allSatisfy({ $0.count == uScalar.count })
    else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Exact Coons vertical tensor dimensions are inconsistent."
      )
    }
    for vIndex in vVector.indices {
      try execution.consumeWork(1)

      for uIndex in uScalar.indices {
        try execution.consumeWork(1)

        result[vIndex][uIndex] =
          result[vIndex][uIndex]
          + vVector[vIndex] * (uScalar[uIndex] * scale)
      }
    }
  }

  private func subtractCorner(
    _ point: Point3D,
    uFactor: [Double],
    vFactor: [Double],
    from result: inout [[Vector3D]],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    let vector = Vector3D(x: point.x, y: point.y, z: point.z)
    try execution.retainStorage(count: uFactor.count, stride: MemoryLayout<Vector3D>.stride)
    let uVector = try uFactor.map {
      try execution.consumeWork(1)
      return vector * $0
    }
    try addOuter(
      uVector: uVector,
      vScalar: vFactor,
      scale: -1.0,
      to: &result,
      tolerance: tolerance, using: &execution)
  }

  private func breaks(
    from patches: [RationalBezierCurvePatch3D], using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    try execution.retainStorage(count: patches.count + 1, stride: MemoryLayout<Double>.stride)
    var result = [patches[0].lower]
    result.reserveCapacity(patches.count + 1)
    for patch in patches {
      try execution.consumeWork(1)
      result.append(patch.upper)
    }
    return result
  }

  private func assemble(
    patches: [[TensorPatch]],
    uBreaks: [Double],
    vBreaks: [Double],
    uDegree: Int,
    vDegree: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BSplineSurface3D {
    try execution.consumeWork(1)
    let uCount = try exactScalarCount(
      try exactScalarCount(uBreaks.count - 1, uDegree, multiply: true), 1)
    let vCount = try exactScalarCount(
      try exactScalarCount(vBreaks.count - 1, vDegree, multiply: true), 1)
    try execution.retainStorage(
      count: try exactScalarCount(uCount, vCount, multiply: true),
      stride: MemoryLayout<HomogeneousControl?>.stride + MemoryLayout<Point3D>.stride
        + MemoryLayout<Double>.stride)
    var net = Array(
      repeating: [HomogeneousControl?](repeating: nil, count: uCount),
      count: vCount
    )
    for vSpan in patches.indices {
      try execution.consumeWork(1)

      for uSpan in patches[vSpan].indices {
        try execution.consumeWork(1)

        let patch = patches[vSpan][uSpan]
        for localV in 0...vDegree {
          try execution.consumeWork(1)

          for localU in 0...uDegree {
            try execution.consumeWork(1)

            let globalV = vSpan * vDegree + localV
            let globalU = uSpan * uDegree + localU
            let candidate = patch.controls[localV][localU]
            if let existing = net[globalV][globalU] {
              try validateSharedControl(
                existing,
                candidate,
                tolerance: tolerance, using: &execution)
            } else {
              net[globalV][globalU] = candidate
            }
          }
        }
      }
    }
    var controlPoints: [[Point3D]] = []
    var weights: [[Double]] = []
    controlPoints.reserveCapacity(vCount)
    weights.reserveCapacity(vCount)
    for row in net {
      try execution.consumeWork(1)

      var pointRow: [Point3D] = []
      var weightRow: [Double] = []
      pointRow.reserveCapacity(uCount)
      weightRow.reserveCapacity(uCount)
      for value in row {
        try execution.consumeWork(1)

        guard let control = value,
          control.weight.isFinite,
          control.weight > 0.0,
          control.numerator.isFinite
        else {
          throw diagnostic(
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Exact Coons global control net is incomplete or non-finite."
          )
        }
        pointRow.append(
          Point3D(
            x: control.numerator.x / control.weight,
            y: control.numerator.y / control.weight,
            z: control.numerator.z / control.weight
          ))
        weightRow.append(control.weight)
      }
      controlPoints.append(pointRow)
      weights.append(weightRow)
    }
    let surface = BSplineSurface3D(
      uDegree: uDegree,
      vDegree: vDegree,
      uKnots: try knotVector(breaks: uBreaks, degree: uDegree, using: &execution),
      vKnots: try knotVector(breaks: vBreaks, degree: vDegree, using: &execution),
      controlPoints: controlPoints,
      weights: weights
    )
    try surface.validate(tolerance: tolerance, using: &execution)
    return surface
  }

  private func validateSharedControl(
    _ first: HomogeneousControl,
    _ second: HomogeneousControl,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    let firstPoint = first.numerator / first.weight
    let secondPoint = second.numerator / second.weight
    let pointResidual = (firstPoint - secondPoint).length
    let weightScale = max(1.0, abs(first.weight), abs(second.weight))
    let weightResidual = abs(first.weight - second.weight) / weightScale
    guard pointResidual <= tolerance.distance,
      weightResidual <= tolerance.relative * 128.0
    else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        residual: max(pointResidual, weightResidual),
        tolerance: tolerance,
        message:
          "Adjacent exact Coons tensor patches did not retain one homogeneous boundary control."
      )
    }
  }

  private func knotVector(
    breaks: [Double], degree: Int, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    try execution.retainStorage(
      count: try exactScalarCount(
        try exactScalarCount(breaks.count - 1, degree, multiply: true), degree + 1),
      stride: MemoryLayout<Double>.stride)
    var result = Array(repeating: breaks[0], count: degree + 1)
    if breaks.count > 2 {
      for value in breaks.dropFirst().dropLast() {
        try execution.consumeWork(1)

        result.append(contentsOf: repeatElement(value, count: degree))
      }
    }
    result.append(contentsOf: repeatElement(breaks[breaks.count - 1], count: degree + 1))
    return result
  }

  private func diagnostic(
    code: KernelErrorCode,
    residual: Double? = nil,
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: code,
      residual: residual,
      tolerance: tolerance,
      message: message
    )
  }
}
