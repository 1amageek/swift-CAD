import CADCore

/// Coefficient authoring in the original spline space, followed by independent position proof.
public struct NativeKnotPolynomialSurfaceContinuationConstructor:
  GeometryPolynomialSurfaceContinuationConstructing
{
  private typealias Arithmetic = PolynomialSurfacePositionDifferenceNet.Arithmetic
  private let certifier: any GeometryPolynomialSurfaceContinuationPositionCertifying

  public init(
    certifier: any GeometryPolynomialSurfaceContinuationPositionCertifying =
      CertifiedPolynomialSurfaceContinuationPositionCertifier()
  ) {
    self.certifier = certifier
  }

  public func constructContinuationCandidate(
    preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
    uDegree: Int, vDegree: Int,
    maximumSpanCount: Int, maximumControlPointCountPerAxis: Int
  ) throws -> CertifiedPolynomialSurfaceContinuationCandidate {
    var execution = try preparedRequest.independentExecution()
    return try constructContinuationCandidate(
      preparedRequest: preparedRequest, uDegree: uDegree, vDegree: vDegree,
      maximumSpanCount: maximumSpanCount,
      maximumControlPointCountPerAxis: maximumControlPointCountPerAxis,
      using: &execution)
  }

  public func constructContinuationCandidate(
    preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
    uDegree: Int, vDegree: Int,
    maximumSpanCount: Int, maximumControlPointCountPerAxis: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> CertifiedPolynomialSurfaceContinuationCandidate {
    try CurrentTaskCancellationChecker().checkCancellation()
    guard uDegree > 0, vDegree > 0, maximumSpanCount > 0,
      maximumControlPointCountPerAxis > 0
    else {
      throw GeometryConversionError.invalidInput(
        "Polynomial continuation construction requires positive degrees and layout ceilings.")
    }
    let source = preparedRequest.source
    return try execution.withConversionScope(
      maximumWorkUnits: preparedRequest.limits.maximumWorkUnits,
      maximumScalarCount: preparedRequest.limits.maximumScalarCount,
      maximumCertificationBoxes: preparedRequest.limits.maximumCertificationBoxes
    ) { execution in
      try preparedRequest.admit(using: &execution)
      try execution.charge(work: 12)
      guard uDegree <= 3, vDegree <= 3,
        source.uDegree <= uDegree, source.vDegree <= vDegree
      else {
        throw KernelError(
          phase: .geometry, code: .unsupportedCapability, tolerance: preparedRequest.tolerance,
          message:
            "Native-knot continuation construction supports degree elevation through bicubic degree, without degree reduction."
        )
      }
      let u = try PolynomialSurfaceContinuationAxisConstruction(
        knots: source.uKnots, degree: source.uDegree, count: source.uControlPointCount,
        targetDegree: uDegree, interval: preparedRequest.parameters.u,
        maximumSpanCount: maximumSpanCount,
        maximumControlPointCount: maximumControlPointCountPerAxis,
        tolerance: preparedRequest.tolerance, using: &execution)
      let v = try PolynomialSurfaceContinuationAxisConstruction(
        knots: source.vKnots, degree: source.vDegree, count: source.vControlPointCount,
        targetDegree: vDegree, interval: preparedRequest.parameters.v,
        maximumSpanCount: maximumSpanCount,
        maximumControlPointCount: maximumControlPointCountPerAxis,
        tolerance: preparedRequest.tolerance, using: &execution)
      let origin = source.controlPoints[0][0]
      let outputCount = try Arithmetic.multiply(v.controlCount, u.controlCount)
      // Each allocated row owns three-double vectors; array owners are retained separately.
      let rowWords = (MemoryLayout<[SIMD3<Double>]>.stride + 7) / 8
      try execution.charge(
        scalars: Arithmetic.multiply(source.vControlPointCount, rowWords),
        work: source.vControlPointCount)
      var intermediate: [[SIMD3<Double>]] = []
      try OriginalCoefficientAllocation.reserve(
        count: source.vControlPointCount, of: [SIMD3<Double>].self, using: &execution)
      intermediate.reserveCapacity(source.vControlPointCount)
      for row in source.controlPoints {
        try CurrentTaskCancellationChecker().checkCancellation()
        let values = try u.construct(using: &execution) { index in
          let point = row[index]
          return SIMD3(point.x - origin.x, point.y - origin.y, point.z - origin.z)
        }
        intermediate.append(values)
      }
      // The U producer paid its returned vector buffers; only the final owner/capacity
      // reservation above is needed here, rather than a hidden materialized source copy.
      var columns: [[SIMD3<Double>]] = []
      try execution.charge(
        scalars: Arithmetic.multiply(u.controlCount, rowWords), work: u.controlCount)
      try OriginalCoefficientAllocation.reserve(
        count: u.controlCount, of: [SIMD3<Double>].self, using: &execution)
      columns.reserveCapacity(u.controlCount)
      for column in 0..<u.controlCount {
        columns.append(try v.construct(using: &execution) { index in intermediate[index][column] })
      }
      // Actual BSplineSurface3D construction owns point and explicit unit-weight rows.
      let pointRowWords = (MemoryLayout<[Point3D]>.stride + 7) / 8
      let weightRowWords = (MemoryLayout<[Double]>.stride + 7) / 8
      try execution.charge(
        scalars: Arithmetic.add(
          Arithmetic.multiply(outputCount, 4),
          Arithmetic.multiply(v.controlCount, Arithmetic.add(pointRowWords, weightRowWords))),
        work: Arithmetic.multiply(outputCount, 8))
      var points: [[Point3D]] = []
      var weights: [[Double]] = []
      try OriginalCoefficientAllocation.reserve(
        count: v.controlCount, of: [Point3D].self, using: &execution)
      try OriginalCoefficientAllocation.reserve(
        count: v.controlCount, of: [Double].self, using: &execution)
      points.reserveCapacity(v.controlCount)
      weights.reserveCapacity(v.controlCount)
      for row in 0..<v.controlCount {
        try CurrentTaskCancellationChecker().checkCancellation()
        var values: [Point3D] = []
        try OriginalCoefficientAllocation.reserve(
          count: u.controlCount, of: Point3D.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(
          count: u.controlCount, of: Double.self, using: &execution)
        values.reserveCapacity(u.controlCount)
        for column in 0..<u.controlCount {
          let value = columns[column][row]
          let point = Point3D(x: origin.x + value.x, y: origin.y + value.y, z: origin.z + value.z)
          guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            throw GeometryConversionError.toleranceRejected
          }
          values.append(point)
        }
        points.append(values)
        weights.append(Array(repeating: 1, count: u.controlCount))
      }
      let surfaceWords = (MemoryLayout<BSplineSurface3D>.stride + 7) / 8
      let requestWords =
        (MemoryLayout<PreparedPolynomialSurfaceContinuationPositionRequest>.stride + 7) / 8
      let resultWords =
        (MemoryLayout<CertifiedPolynomialSurfaceContinuationCandidate>.stride + 7) / 8
      try execution.charge(
        scalars: Arithmetic.add(surfaceWords, Arithmetic.add(requestWords, resultWords)),
        work: Arithmetic.add(surfaceWords, Arithmetic.add(requestWords, resultWords)))
      let candidate = BSplineSurface3D(
        uDegree: uDegree, vDegree: vDegree,
        uKnots: u.knots, vKnots: v.knots, controlPoints: points, weights: weights)
      let certificate = try certifier.certifyContinuationPosition(
        preparedRequest: preparedRequest,
        candidate: candidate, using: &execution)
      try CurrentTaskCancellationChecker().checkCancellation()
      return CertifiedPolynomialSurfaceContinuationCandidate(
        surface: candidate, certificate: certificate)
    }
  }
}
