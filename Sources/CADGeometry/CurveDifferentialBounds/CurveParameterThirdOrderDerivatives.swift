import CADCore

#if !hasFeature(Embedded)
  import Foundation
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("CADGeometry numeric algorithms require the target C math module.")
#endif

struct CurveParameterThirdOrderDerivatives: Sendable {
  let position: Point3D
  let firstDerivative: Vector3D
  let secondDerivative: Vector3D
  let thirdDerivative: Vector3D
}

extension Curve3D {
  func parameterDerivativesThroughThirdOrder(at parameter: Double, tolerance: ModelingTolerance)
    throws -> CurveParameterThirdOrderDerivatives
  {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try parameterDerivativesThroughThirdOrder(
      at: parameter, tolerance: tolerance, using: &execution)
  }

  func parameterDerivativesThroughThirdOrder(
    at parameter: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterThirdOrderDerivatives {
    let result = try parameterDerivativesThroughThirdOrderBody(
      at: parameter, tolerance: tolerance, using: &execution)
    try execution.checkpoint()
    return result
  }



  private func parameterDerivativesThroughThirdOrderBody(
    at parameter: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveParameterThirdOrderDerivatives {
    try validate(tolerance: tolerance, using: &execution)
    guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
      throw GeometryError.invalidDistance(parameter)
    }
    let lower = try differentialGeometry(
      at: parameter,
      tolerance: tolerance, using: &execution)
    let third: Vector3D
    switch self {
    case .line, .analytic(.line), .analytic(.parabola):
      third = .zero
    case .circle,
      .analytic(.circle),
      .analytic(.arc),
      .analytic(.ellipse):
      let scale = CanonicalSphereAngularPhase.scaleBounds.midpoint
      third = lower.firstDerivative * (-scale * scale)
    case .analytic(.hyperbola):
      third = lower.firstDerivative
    case .analytic(.planeTorus(let curve)):
      third = try curve.thirdDerivative(
        at: parameter,
        tolerance: tolerance, using: &execution)
    case .implicit(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: parameter,
        tolerance: tolerance, using: &execution)
    case .certifiedIntersection(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: parameter,
        tolerance: tolerance, using: &execution)
    case .bSpline(let curve):
      third = try curve.thirdDerivative(
        at: parameter,
        tolerance: tolerance, using: &execution)
    case .surfaceLift(let lift):
      third = try lift.thirdDerivative(
        atNormalizedFraction: parameter,
        tolerance: tolerance, using: &execution)
    case .rigidImage(let image):
      third = image.transform.applying(
        to: try image.source
          .parameterDerivativesThroughThirdOrder(
            at: parameter,
            tolerance: tolerance, using: &execution
          ).thirdDerivative)
    case .parameterImage(let image):
      third =
        try image.source.parameterDerivativesThroughThirdOrder(
          at: OriginalParameterImageMap.parameter(
            parameter, gain: image.parameterGain, offset: image.offset),
          tolerance: tolerance, using: &execution
        ).thirdDerivative * (image.gain * image.gain * image.gain)
    case .originalAngularTransport(let curve):
      let jet = try curve.intervalTaylorJet(
        over: .init(lower: parameter, upper: parameter), throughOrder: 3,
        tolerance: tolerance, using: &execution)
      third = try .init(
        x: (jet.x.coefficient(3, 0) * .exact(6)).midpoint,
        y: (jet.y.coefficient(3, 0) * .exact(6)).midpoint,
        z: (jet.z.coefficient(3, 0) * .exact(6)).midpoint)
    case .originalConstructionChart(let curve):
      let jet = try curve.intervalTaylorJet(
        over: .init(lower: parameter, upper: parameter), throughOrder: 3,
        tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
        maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
        remainingSourceDepth: curve.remainingSourceDepth == Int.max
          ? Int.max : curve.remainingSourceDepth + 1,
        using: &execution)
      third = .init(
        x: try (jet.x.coefficient(3, 0) * .exact(6)).midpoint,
        y: try (jet.y.coefficient(3, 0) * .exact(6)).midpoint,
        z: try (jet.z.coefficient(3, 0) * .exact(6)).midpoint)
    case .originalGuideTraversalChain(let curve):
      let jet = try curve.derivatives(
        over: .init(lower: parameter, upper: parameter),
        throughOrder: 3, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
        maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
        remainingSourceDepth: curve.remainingSourceDepth,
        using: &execution)
      third = .init(
        x: jet.x.derivatives[3].midpoint,
        y: jet.y.derivatives[3].midpoint, z: jet.z.derivatives[3].midpoint)
    case .originalGuideEndpointConnector(let curve):
      let jet = try curve.derivatives(
        over: .init(lower: parameter, upper: parameter),
        throughOrder: 3, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
        maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
        remainingSourceDepth: curve.remainingSourceDepth,
        using: &execution)
      third = .init(
        x: jet.x.derivatives[3].midpoint,
        y: jet.y.derivatives[3].midpoint, z: jet.z.derivatives[3].midpoint)
    case .originalPolyline(let curve):
      let singleton = try ScalarInterval(lower: parameter, upper: parameter)
      guard
        try curve.hasSmoothNativeInterval(
          over: singleton, tolerance: tolerance,
          maximumSpanCount: curve.maximumSpanCount,
          maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
          remainingSourceDepth: curve.remainingSourceDepth,
          using: &execution)
      else {
        throw KernelError(
          phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message: "An original polyline corner has no smooth third-order differential law.")
      }
      let jet = try curve.derivatives(
        over: singleton, throughOrder: 3, tolerance: tolerance,
        maximumSpanCount: curve.maximumSpanCount,
        maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
        remainingSourceDepth: curve.remainingSourceDepth, using: &execution)
      third = .init(
        x: jet.x.derivatives[3].midpoint,
        y: jet.y.derivatives[3].midpoint, z: jet.z.derivatives[3].midpoint)
    case .originalDrafted(let curve):
      let jet = try curve.derivatives(
        over: .init(lower: parameter, upper: parameter),
        throughOrder: 3, tolerance: tolerance, using: &execution)
      third = .init(
        x: jet.x.derivatives[3].midpoint, y: jet.y.derivatives[3].midpoint,
        z: jet.z.derivatives[3].midpoint)
    case .originalPlaneDerivative(let curve):
      let jet = try curve.derivatives(
        over: .init(lower: parameter, upper: parameter),
        throughOrder: 3, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
        maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
        remainingSourceDepth: curve.remainingSourceDepth,
        using: &execution)
      third = .init(
        x: jet.x.derivatives[3].midpoint, y: jet.y.derivatives[3].midpoint,
        z: jet.z.derivatives[3].midpoint)
    case .originalEndpointConnector(let curve):
      let jet = try curve.derivatives(
        over: .init(lower: parameter, upper: parameter),
        throughOrder: 3, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
        maximumSubdivisionDepth: curve.maximumSubdivisionDepth, remainingSourceDepth: 0,
        using: &execution)
      third = .init(
        x: jet.x.derivatives[3].midpoint,
        y: jet.y.derivatives[3].midpoint, z: jet.z.derivatives[3].midpoint)
    case .originalAffineWord(let image):
      third = try image.preparedWord.applying(
        to: image.source
          .parameterDerivativesThroughThirdOrder(
            at: parameter, tolerance: image.sourceTolerance, using: &execution
          ).thirdDerivative,
        usage: &execution)
    case .affineImage(let image):
      third = image.transform.applying(
        to: try image.source
          .parameterDerivativesThroughThirdOrder(
            at: parameter,
            tolerance: tolerance, using: &execution
          ).thirdDerivative)
    }
    return CurveParameterThirdOrderDerivatives(
      position: lower.position,
      firstDerivative: lower.firstDerivative,
      secondDerivative: lower.secondDerivative,
      thirdDerivative: third
    )
  }

}

extension CertifiedIntersectionCurve3D {
  fileprivate func thirdDerivative(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Vector3D {
    switch self {
    case .coneTorus(let curve):
      return try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .sphereCone(let curve):
      return try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .coneCone(let curve):
      return try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .coneCylinder(let curve):
      return try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .parallelTorusTorus(let curve):
      return try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    }
  }
}

extension BSplineCurve3D {
  fileprivate struct HomogeneousDerivative {
    let vector: Vector3D
    let weight: Double
  }

  fileprivate func thirdDerivative(
    at parameter: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Vector3D {
    let clamped = BSplineBasis.clampedParameter(
      parameter,
      knots: knots,
      degree: degree
    )
    try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
    var basis: [[Double]] = []
    basis.reserveCapacity(4)
    for order in 0...3 {
      try execution.consumeWork(1)
      basis.append(
        try BSplineBasis.derivativeValues(
          parameter: clamped,
          degree: degree, derivativeOrder: order, knots: knots,
          count: controlPointCount, using: &execution))
    }
    try execution.retainStorage(count: 4, stride: MemoryLayout<HomogeneousDerivative>.stride)
    var homogeneous: [HomogeneousDerivative] = []
    homogeneous.reserveCapacity(4)
    for values in basis {
      try execution.consumeWork(1)
      var vector = Vector3D.zero
      var weight = 0.0
      for index in controlPoints.indices {
        try execution.consumeWork(1)
        let coefficient = values[index] * weights[index]
        vector =
          vector + Vector3D(
            x: controlPoints[index].x,
            y: controlPoints[index].y, z: controlPoints[index].z) * coefficient
        weight += values[index] * weights[index]
      }
      homogeneous.append(HomogeneousDerivative(vector: vector, weight: weight))
    }
    guard homogeneous[0].weight.isFinite,
      homogeneous[0].weight > Double.ulpOfOne
    else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        residual: homogeneous[0].weight,
        tolerance: tolerance,
        message: "Rational B-spline third differentiation requires a positive finite weight."
      )
    }
    try execution.retainStorage(count: 4, stride: MemoryLayout<Vector3D>.stride)
    var euclidean: [Vector3D] = []
    euclidean.reserveCapacity(4)
    for order in 0...3 {
      try execution.consumeWork(1)
      var numerator = homogeneous[order].vector
      if order > 0 {
        for weightOrder in 1...order {
          try execution.consumeWork(1)
          numerator =
            numerator - euclidean[order - weightOrder]
            * (Double(curveBinomial(order, weightOrder))
              * homogeneous[weightOrder].weight)
        }
      }
      euclidean.append(numerator / homogeneous[0].weight)
    }
    guard euclidean[3].isFinite else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Rational B-spline third differentiation exceeded finite arithmetic."
      )
    }
    return euclidean[3]
  }
}

extension SurfaceLiftCurve3D {
  func thirdDerivative(atNormalizedFraction fraction: Double, tolerance: ModelingTolerance) throws
    -> Vector3D
  {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try thirdDerivative(
      atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
  }

  func thirdDerivative(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Vector3D {
    if let exactBSplineImage {
      return try exactBSplineImage.thirdDerivative(
        at: fraction,
        tolerance: tolerance, using: &execution)
    }
    if case .originalAffineWord(let curve) = parameterCurve {
      return try curve.modelSpaceThirdOrder(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution
      ).thirdDerivative
    }
    if case .originalImage(let curve) = parameterCurve {
      return try curve.modelSpaceThirdOrder(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution
      ).thirdDerivative
    }
    if case .certifiedAnalyticPair(let curve) = parameterCurve {
      return try curve.modelSpaceThirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    }
    let parameter = try parameterCurve.thirdOrderDifferential(
      atNormalizedFraction: fraction,
      on: surface,
      tolerance: tolerance, using: &execution)
    let surfaceDerivatives = try surface.parameterDerivativesThroughThirdOrder(
      u: parameter.parameter.u,
      v: parameter.parameter.v,
      tolerance: tolerance, using: &execution)
    return SurfaceParameterThirdOrderChainRule.thirdDerivative(
      surface: surfaceDerivatives,
      firstParameterDerivative: parameter.firstDerivative,
      secondParameterDerivative: parameter.secondDerivative,
      thirdParameterDerivative: parameter.thirdDerivative
    )
  }
}

extension SurfaceParameterCurve {
  internal func thirdOrderDifferential(
    atNormalizedFraction fraction: Double,
    on supportSurface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterCurveThirdOrderDifferential {
    let lower = try differentialGeometry(
      atNormalizedFraction: fraction,
      tolerance: tolerance, using: &execution)
    let third: Point2D
    switch self {
    case .affine, .constantU, .constantV, .polyline:
      third = Point2D(x: 0.0, y: 0.0)
    case .harmonic(_, _, _, let startParameter, let endParameter):
      let span = endParameter - startParameter
      third = Point2D(
        x: -lower.firstDerivative.x * span * span,
        y: -lower.firstDerivative.y * span * span
      )
    case .bSpline(let curve):
      third = try curve.normalizedThirdDerivative(
        atFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .periodicTranslation(let base, _, _):
      return try base.thirdOrderDifferential(
        atNormalizedFraction: fraction,
        on: supportSurface,
        tolerance: tolerance, using: &execution)
    case .certifiedImplicit(let curve):
      let mapped =
        curve.startFraction
        + (curve.endFraction - curve.startFraction)
        * min(max(fraction, 0.0), 1.0)
      let canonical =
        curve.intersection.isClosed && mapped > 1.0
        ? mapped - 1.0
        : mapped
      let source = try curve.intersection.differential(
        atNormalizedFraction: canonical,
        tolerance: tolerance, using: &execution)
      let derivative =
        curve.role == .first
        ? source.thirdParameterDerivatives.first
        : source.thirdParameterDerivatives.second
      let scale = curve.endFraction - curve.startFraction
      third = Point2D(
        x: derivative.u * scale * scale * scale,
        y: derivative.v * scale * scale * scale
      )
    case .sphericalGreatCircle(let cosine, let sine, let start, let end):
      guard case .analytic(.sphere(_, let radius)) = supportSurface else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "A spherical great-circle pcurve requires its spherical support surface."
        )
      }
      let span = end - start
      let angle = start + span * min(max(fraction, 0.0), 1.0)
      let radialFirst = (cosine * -sin(angle) + sine * cos(angle)) * span
      let spatialThird = radialFirst * (-radius * span * span)
      let surface = try supportSurface.parameterDerivativesThroughThirdOrder(
        u: lower.parameter.u,
        v: lower.parameter.v,
        tolerance: tolerance, using: &execution)
      third = try SurfaceParameterThirdDerivativeSolver().solve(
        surface: surface,
        firstParameterDerivative: lower.firstDerivative,
        secondParameterDerivative: lower.secondDerivative,
        spatialThirdDerivative: spatialThird,
        tolerance: tolerance,
        diagnosticContext: "Spherical great-circle pcurve"
      )
    case .certifiedAnalyticImplicit(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .originalBSplineContinuation(let curve):
      let jet = try curve.intervalJet(
        over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance,
        using: &execution)
      third = Point2D(x: jet.u.thirdDerivativeUUU.midpoint, y: jet.v.thirdDerivativeUUU.midpoint)
    case .projectedAnalytic(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .originalAffineWord(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    case .originalImage(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    case .rigidImage(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    case .offsetSurfaceImage(let curve):
      return try curve.source.thirdOrderDifferential(
        atNormalizedFraction: fraction,
        on: curve.sourceSurface,
        tolerance: tolerance, using: &execution)
    case .certifiedAnalyticPair(let curve):
      third = try curve.thirdDerivative(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution)
    }
    return SurfaceParameterCurveThirdOrderDifferential(
      parameter: lower.parameter,
      firstDerivative: lower.firstDerivative,
      secondDerivative: lower.secondDerivative,
      thirdDerivative: third
    )
  }

}

extension BSplineCurve2D {
  fileprivate func normalizedThirdDerivative(
    atFraction fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Point2D {
    guard case .closed(let lower, let upper) = domain else {
      throw GeometryError.invalidDistance(fraction)
    }
    let span = upper - lower
    let parameter = lower + span * min(max(fraction, 0.0), 1.0)
    let embeddedPoints = try OriginalCoefficientAllocation.map(
      elements: controlPoints, using: &execution
    ) {
      point, execution in
      Point3D(x: point.x, y: point.y, z: 0.0)
    }
    let embedded = BSplineCurve3D(
      degree: degree,
      knots: knots,
      controlPoints: embeddedPoints,
      weights: weights
    )
    let derivative =
      try embedded.thirdDerivative(
        at: parameter,
        tolerance: tolerance, using: &execution) * (span * span * span)
    return Point2D(x: derivative.x, y: derivative.y)
  }
}

private func curveBinomial(_ n: Int, _ k: Int) -> Int {
  guard k >= 0, k <= n else { return 0 }
  if k == 0 || k == n { return 1 }
  if n == 2 { return 2 }
  if n == 3, k == 1 || k == 2 { return 3 }
  return 1
}
