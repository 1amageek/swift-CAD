import CADCore

extension OriginalBoundaryCorrectedSurface3D {
  private var retainedSourceDepth: Int {
    get throws {
      let boundaryDepth = max(
        boundaries.vMinimumBoundary.remainingSourceDepth,
        boundaries.vMaximumBoundary.remainingSourceDepth,
        boundaries.uMinimumBoundary.remainingSourceDepth,
        boundaries.uMaximumBoundary.remainingSourceDepth)
      let depth =
        boundaryDepth == Int.max
        ? (partialValue: Int.max, overflow: false) : boundaryDepth.addingReportingOverflow(1)
      guard !depth.overflow else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original corrected source depth overflows.")
      }
      return depth.partialValue
    }
  }

  package func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance)
    throws -> SurfaceIntervalVectorJet
  {
    var execution = try preparationReceipt.makeExecution()
    return try intervalJet(over: box, tolerance: tolerance, using: &execution)
  }

  package func intervalJet(
    over box: SurfaceParameterBox, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> SurfaceIntervalVectorJet
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try intervalJet(
        over: box, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: retainedSourceDepth,
        using: &execution)

    }
  }

  public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var execution = try preparationReceipt.makeExecution()
    return try point(u: u, v: v, tolerance: tolerance, using: &execution)
  }


  public func point(
    u: Double, v: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let q = try intervalTaylorJet(
        over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)), throughOrder: 0,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: retainedSourceDepth,
        using: &execution)
      return try numericalPosition(
        x: q.x.coefficient(0, 0), y: q.y.coefficient(0, 0),
        z: q.z.coefficient(0, 0), tolerance: tolerance)

    }
  }
  public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance)
    throws -> SurfaceParameterDerivatives
  {
    var execution = try preparationReceipt.makeExecution()
    return try parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
  }

  public func parameterDerivatives(
    u: Double, v: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> SurfaceParameterDerivatives
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        .secondOrder

    }
  }
  public func parameterDerivativesThroughThirdOrder(
    u: Double, v: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterThirdOrderDerivatives {
    var execution = try preparationReceipt.makeExecution()
    return try parameterDerivativesThroughThirdOrder(
      u: u, v: v, tolerance: tolerance, using: &execution)
  }

  public func parameterDerivativesThroughThirdOrder(
    u: Double, v: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterThirdOrderDerivatives {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let q = try intervalJet(
        over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        tolerance: tolerance, using: &execution)
      func vector(_ field: (SurfaceIntervalJet) -> OutwardScalarInterval) -> Vector3D {
        .init(x: field(q.x).midpoint, y: field(q.y).midpoint, z: field(q.z).midpoint)
      }
      return try .init(
        position: numericalPosition(x: q.x.value, y: q.y.value, z: q.z.value, tolerance: tolerance),
        tangentU: vector { $0.derivativeU }, tangentV: vector { $0.derivativeV },
        secondDerivativeUU: vector { $0.secondDerivativeUU },
        secondDerivativeUV: vector { $0.secondDerivativeUV },
        secondDerivativeVV: vector { $0.secondDerivativeVV },
        thirdDerivativeUUU: vector { $0.thirdDerivativeUUU },
        thirdDerivativeUUV: vector { $0.thirdDerivativeUUV },
        thirdDerivativeUVV: vector { $0.thirdDerivativeUVV },
        thirdDerivativeVVV: vector { $0.thirdDerivativeVVV })

    }
  }
  private func numericalPosition(
    x: OutwardScalarInterval, y: OutwardScalarInterval,
    z: OutwardScalarInterval, tolerance: ModelingTolerance
  ) throws -> Point3D {
    let point = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    let radius = IntervalVector3DBounds(
      x: x - .exact(point.x), y: y - .exact(point.y), z: z - .exact(point.z)
    ).lengthUpperBound
    guard radius.isFinite, radius <= tolerance.distance else {
      throw GeometryConversionError.toleranceRejected
    }
    return point
  }

  package func boundarySource(_ boundary: SurfaceParameterBoundary) -> OriginalCurveRootSpan3D {
    boundaries.boundarySource(boundary)
  }

  package func intervalJet(
    over box: SurfaceParameterBox, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  )
    throws -> SurfaceIntervalVectorJet
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try intervalTaylorJet(
        over: box, throughOrder: 3, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth,
        using: &execution
      ).intervalJet()

    }
  }

  package func preparedFirstOrder(
    over box: SurfaceParameterBox, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalSurfaceFirstOrderEnclosure {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try .init(
        intervalTaylorJet(
          over: box, throughOrder: 1, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, using: &execution))

    }
  }

  func taylorJet(
    u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTaylorVectorJet {
    var execution = try preparationReceipt.makeExecution()
    return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
  }

  func taylorJet(
    u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      guard (0...16).contains(order) else {
        throw GeometryConversionError.invalidInput(
          "Original corrected numeric facade retains Taylor order zero through sixteen.")
      }
      let original = try intervalTaylorJet(
        over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: order,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: retainedSourceDepth,
        using: &execution)
      func candidate(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: order)
        for total in 0...order {
          for a in 0...total {
            try CurrentTaskCancellationChecker().checkCancellation()
            try result.setCoefficient(
              q.coefficient(a, total - a).midpoint, uOrder: a, vOrder: total - a)
          }
        }
        return result
      }
      return try .init(x: candidate(original.x), y: candidate(original.y), z: candidate(original.z))

    }
  }
}
