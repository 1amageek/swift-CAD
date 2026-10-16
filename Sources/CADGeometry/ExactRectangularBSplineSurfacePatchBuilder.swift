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

package struct ExactRectangularBSplineSurfacePatchBuilder: Sendable {
  package init() {}

  package func build(
    surface: Surface3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance
  ) throws -> ExactRectangularBSplineSurfacePatch {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try build(
      surface: surface, lowerU: lowerU, upperU: upperU, lowerV: lowerV, upperV: upperV,
      tolerance: tolerance, using: &execution)
  }

  package func build(
    surface: Surface3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch {
    try execution.consumeWork(1)
    try tolerance.validate()
    try surface.validate(tolerance: tolerance, using: &execution)
    guard lowerU.isFinite,
      upperU.isFinite,
      lowerV.isFinite,
      upperV.isFinite,
      upperU - lowerU > tolerance.relative,
      upperV - lowerV > tolerance.relative,
      try surface.uDomain.containsSpan(
        from: lowerU,
        to: upperU,
        tolerance: tolerance
      ),
      try surface.vDomain.containsSpan(
        from: lowerV,
        to: upperV,
        tolerance: tolerance
      )
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "An exact rectangular NURBS patch requires finite contained source bounds."
      )
    }

    let result: ExactRectangularBSplineSurfacePatch
    switch surface {
    case .procedural(.originalAngularTransport), .procedural(.originalAffineWord):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy exact patch conversion
      // does not own original angular/flat-word source station transport.
      // Required conversion must retain that transport before success.
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "Original transported surfaces require source-preserving patch conversion.")
    case .plane, .analytic(.plane):
      result = try planarPatch(
        surface: surface,
        lowerU: lowerU,
        upperU: upperU,
        lowerV: lowerV,
        upperV: upperV,
        tolerance: tolerance, using: &execution)
    case .cylinder(let cylinder):
      let basis = try legacyCylinderBasis(
        axis: cylinder.axis,
        tolerance: tolerance
      )
      result = try cylindricalPatch(
        origin: cylinder.origin,
        axis: cylinder.axis,
        radius: cylinder.radius,
        radialU: basis.u,
        radialV: basis.v,
        lowerU: lowerU,
        upperU: upperU,
        lowerV: lowerV,
        upperV: upperV,
        tolerance: tolerance, using: &execution)
    case .analytic(.cylinder(let origin, let axis, let radius)):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      result = try cylindricalPatch(
        origin: origin,
        axis: axis,
        radius: radius,
        radialU: basis.u,
        radialV: basis.v,
        lowerU: lowerU,
        upperU: upperU,
        lowerV: lowerV,
        upperV: upperV,
        tolerance: tolerance, using: &execution)
    case .analytic(.cone(let apex, let axis, let halfAngle)):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      result = try conicalPatch(
        apex: apex,
        axis: axis,
        halfAngle: halfAngle,
        radialU: basis.u,
        radialV: basis.v,
        lowerU: lowerU,
        upperU: upperU,
        lowerV: lowerV,
        upperV: upperV,
        tolerance: tolerance, using: &execution)
    case .analytic(.sphere(let center, let radius)):
      let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
      result = try sphericalPatch(
        center: center,
        radius: radius,
        radialU: basis.u,
        radialV: basis.v,
        lowerU: lowerU,
        upperU: upperU,
        lowerV: lowerV,
        upperV: upperV,
        tolerance: tolerance, using: &execution)
    case .analytic(.torus(let center, let axis, let majorRadius, let minorRadius)):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      result = try toroidalPatch(
        center: center,
        axis: axis,
        majorRadius: majorRadius,
        minorRadius: minorRadius,
        radialU: basis.u,
        radialV: basis.v,
        lowerU: lowerU,
        upperU: upperU,
        lowerV: lowerV,
        upperV: upperV,
        tolerance: tolerance, using: &execution)
    case .bSpline(let spline):
      result = ExactRectangularBSplineSurfacePatch(
        surface: spline,
        uMapping: .init(
          sourceLower: lowerU,
          sourceUpper: upperU,
          kind: .identity
        ),
        vMapping: .init(
          sourceLower: lowerV,
          sourceUpper: upperV,
          kind: .identity
        )
      )
    case .procedural(.originalImage), .procedural(.originalRevolution), .procedural(.originalCoons),
      .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative),
      .procedural(.originalDrafted), .procedural(.originalAffineWord):
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message:
          "An original foreign chart image requires retained-map surface conversion rather than canonical chart substitution."
      )
    case .procedural(.offset(let offset)):
      if let equivalent = try offset.exactChartPreservingSurface(
        tolerance: tolerance, using: &execution)
      {
        return try build(
          surface: equivalent,
          lowerU: lowerU,
          upperU: upperU,
          lowerV: lowerV,
          upperV: upperV,
          tolerance: tolerance, using: &execution)
      }
      if try DefaultPlanarSurfaceResolver().exactPlane(
        for: surface,
        tolerance: tolerance, using: &execution) != nil
      {
        result = try planarPatch(
          surface: surface,
          lowerU: lowerU,
          upperU: upperU,
          lowerV: lowerV,
          upperV: upperV,
          tolerance: tolerance, using: &execution)
      } else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message:
            "Exact rational B-spline conversion requires a rationally representable source surface."
        )
      }
    case .procedural(.rollingBall):
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "A general rolling-ball blend has no exact rational B-spline conversion.")
    case .procedural(.ruled(let ruled)):
      let interval = try ScalarInterval(lower: lowerU, upper: upperU)
      let curveBuilder = AnalyticCurveBSplineBuilder()
      guard
        let start = try curveBuilder.boundedCurve(
          curve: ruled.startBoundary,
          interval: interval,
          maximumSpanCount: 64,
          tolerance: tolerance, using: &execution),
        let end = try curveBuilder.boundedCurve(
          curve: ruled.endBoundary,
          interval: interval,
          maximumSpanCount: 64,
          tolerance: tolerance, using: &execution)
      else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message:
            "Exact rational B-spline conversion requires rationally representable ruled boundaries."
        )
      }
      let completeSurface = try ExactRuledBSplineSurfaceBuilder().build(
        startBoundary: start,
        endBoundary: end,
        tolerance: tolerance, using: &execution)
      guard
        let uMapping = try ruledParameterMapping(
          start: ruled.startBoundary,
          end: ruled.endBoundary,
          lower: lowerU,
          upper: upperU, using: &execution)
      else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message:
            "Exact rational ruled conversion requires parameter-compatible rational boundary curves."
        )
      }
      result = ExactRectangularBSplineSurfacePatch(
        surface: try completeSurface.trimmed(
          uFrom: 0.0,
          uTo: 1.0,
          vFrom: lowerV,
          vTo: upperV,
          tolerance: tolerance, using: &execution),
        uMapping: uMapping,
        vMapping: identityMapping(lower: lowerV, upper: upperV)
      )
    }
    try result.surface.validate(tolerance: tolerance, using: &execution)
    return result
  }

  private func planarPatch(
    surface: Surface3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch {
    try execution.consumeWork(1)
    func point(_ u: Double, _ v: Double, using execution: inout OriginalQueryExecution) throws
      -> Point3D
    {
      try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
    }
    return ExactRectangularBSplineSurfacePatch(
      surface: BSplineSurface3D(
        uDegree: 1,
        vDegree: 1,
        uKnots: [lowerU, lowerU, upperU, upperU],
        vKnots: [lowerV, lowerV, upperV, upperV],
        controlPoints: [
          [
            try point(lowerU, lowerV, using: &execution),
            try point(upperU, lowerV, using: &execution),
          ],
          [
            try point(lowerU, upperV, using: &execution),
            try point(upperU, upperV, using: &execution),
          ],
        ]
      ),
      uMapping: identityMapping(lower: lowerU, upper: upperU),
      vMapping: identityMapping(lower: lowerV, upper: upperV)
    )
  }

  private func cylindricalPatch(
    origin: Point3D,
    axis: Vector3D,
    radius: Double,
    radialU: Vector3D,
    radialV: Vector3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch {
    try execution.consumeWork(1)
    let arc = try circularArc(
      lower: lowerU,
      upper: upperU,
      tolerance: tolerance, using: &execution)
    try execution.retainStorage(count: arc.controls.count * 2, stride: MemoryLayout<Point3D>.stride)
    let rows = try [lowerV, upperV].map { height in
      return try arc.controls.map { control in
        try execution.consumeWork(1)
        return origin
          + radialU * (control.x * radius)
          + radialV * (control.y * radius)
          + axis * height
      }
    }
    return ExactRectangularBSplineSurfacePatch(
      surface: BSplineSurface3D(
        uDegree: 2,
        vDegree: 1,
        uKnots: arc.knots,
        vKnots: [lowerV, lowerV, upperV, upperV],
        controlPoints: rows,
        weights: [arc.weights, arc.weights]
      ),
      uMapping: arc.mapping,
      vMapping: identityMapping(lower: lowerV, upper: upperV)
    )
  }

  private func conicalPatch(
    apex: Point3D,
    axis: Vector3D,
    halfAngle: Double,
    radialU: Vector3D,
    radialV: Vector3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch {
    try execution.consumeWork(1)
    let arc = try circularArc(lower: lowerU, upper: upperU, tolerance: tolerance, using: &execution)
    let sine = sin(halfAngle)
    let cosine = cos(halfAngle)
    try execution.retainStorage(count: arc.controls.count * 2, stride: MemoryLayout<Point3D>.stride)
    let rows = try [lowerV, upperV].map { slant in
      return try arc.controls.map { control in
        try execution.consumeWork(1)
        return apex
          + axis * (slant * cosine)
          + radialU * (control.x * slant * sine)
          + radialV * (control.y * slant * sine)
      }
    }
    return ExactRectangularBSplineSurfacePatch(
      surface: BSplineSurface3D(
        uDegree: 2,
        vDegree: 1,
        uKnots: arc.knots,
        vKnots: [lowerV, lowerV, upperV, upperV],
        controlPoints: rows,
        weights: [arc.weights, arc.weights]
      ),
      uMapping: arc.mapping,
      vMapping: identityMapping(lower: lowerV, upper: upperV)
    )
  }

  private func sphericalPatch(
    center: Point3D,
    radius: Double,
    radialU: Vector3D,
    radialV: Vector3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch {
    try execution.consumeWork(1)
    let longitude = try circularArc(
      lower: lowerU, upper: upperU, tolerance: tolerance, using: &execution)
    let latitude = try circularArc(
      lower: lowerV, upper: upperV, tolerance: tolerance, using: &execution)
    let count = try exactScalarCount(
      latitude.controls.count, longitude.controls.count, multiply: true)
    try execution.retainStorage(
      count: count, stride: MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
    let rows = try latitude.controls.map { meridian in
      return try longitude.controls.map { parallel in
        try execution.consumeWork(1)
        return center
          + radialU * (parallel.x * meridian.x * radius)
          + radialV * (parallel.y * meridian.x * radius)
          + Vector3D.unitZ * (meridian.y * radius)
      }
    }
    let weights = try latitude.weights.map { latitudeWeight in
      try longitude.weights.map {
        try execution.consumeWork(1)
        return $0 * latitudeWeight
      }
    }
    return ExactRectangularBSplineSurfacePatch(
      surface: BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: longitude.knots,
        vKnots: latitude.knots,
        controlPoints: rows,
        weights: weights
      ),
      uMapping: longitude.mapping,
      vMapping: latitude.mapping
    )
  }

  private func toroidalPatch(
    center: Point3D,
    axis: Vector3D,
    majorRadius: Double,
    minorRadius: Double,
    radialU: Vector3D,
    radialV: Vector3D,
    lowerU: Double,
    upperU: Double,
    lowerV: Double,
    upperV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch {
    try execution.consumeWork(1)
    let major = try circularArc(
      lower: lowerU, upper: upperU, tolerance: tolerance, using: &execution)
    let minor = try circularArc(
      lower: lowerV, upper: upperV, tolerance: tolerance, using: &execution)
    let count = try exactScalarCount(minor.controls.count, major.controls.count, multiply: true)
    try execution.retainStorage(
      count: count, stride: MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
    let rows = try minor.controls.map { minorControl in
      return try major.controls.map { majorControl in
        try execution.consumeWork(1)
        let radialDistance = majorRadius + minorRadius * minorControl.x
        return center
          + radialU * (majorControl.x * radialDistance)
          + radialV * (majorControl.y * radialDistance)
          + axis * (minorControl.y * minorRadius)
      }
    }
    let weights = try minor.weights.map { minorWeight in
      try major.weights.map {
        try execution.consumeWork(1)
        return $0 * minorWeight
      }
    }
    return ExactRectangularBSplineSurfacePatch(
      surface: BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: major.knots,
        vKnots: minor.knots,
        controlPoints: rows,
        weights: weights
      ),
      uMapping: major.mapping,
      vMapping: minor.mapping
    )
  }

  private func circularArc(
    lower: Double,
    upper: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CircularArcData {
    try execution.consumeWork(1)
    let span = upper - lower
    guard span.isFinite,
      span > tolerance.angle,
      span < 2.0 * Double.pi - tolerance.angle
    else {
      throw KernelError(
        phase: .geometry,
        code: .singularGeometry,
        tolerance: tolerance,
        message: "An exact rectangular NURBS patch requires an angular span below one period."
      )
    }
    let segmentCount = max(1, Int(ceil(span / (Double.pi * 0.5))))
    let segmentAngle = span / Double(segmentCount)
    try execution.retainStorage(
      count: segmentCount * 2 + 1,
      stride: MemoryLayout<CircularControl>.stride + MemoryLayout<Double>.stride)
    try execution.retainStorage(count: segmentCount * 2 + 4, stride: MemoryLayout<Double>.stride)
    var controls: [CircularControl] = []
    var weights: [Double] = []
    var knots = [0.0, 0.0, 0.0]
    for segmentIndex in 0..<segmentCount {
      try execution.consumeWork(1)

      let start = lower + Double(segmentIndex) * segmentAngle
      let end = start + segmentAngle
      let middle = (start + end) * 0.5
      let middleWeight = cos(segmentAngle * 0.5)
      guard middleWeight > tolerance.relative else {
        throw KernelError(
          phase: .geometry,
          code: .singularGeometry,
          tolerance: tolerance,
          message: "An exact circular NURBS segment has a singular middle weight."
        )
      }
      let segmentControls = [
        CircularControl(x: cos(start), y: sin(start)),
        CircularControl(
          x: cos(middle) / middleWeight,
          y: sin(middle) / middleWeight
        ),
        CircularControl(x: cos(end), y: sin(end)),
      ]
      if segmentIndex == 0 {
        controls.append(contentsOf: segmentControls)
        weights.append(contentsOf: [1.0, middleWeight, 1.0])
      } else {
        controls.append(contentsOf: segmentControls.dropFirst())
        weights.append(contentsOf: [middleWeight, 1.0])
        knots.append(contentsOf: [Double(segmentIndex), Double(segmentIndex)])
      }
    }
    knots.append(contentsOf: [Double(segmentCount), Double(segmentCount), Double(segmentCount)])
    return CircularArcData(
      controls: controls,
      weights: weights,
      knots: knots,
      mapping: .init(
        sourceLower: lower,
        sourceUpper: upper,
        kind: .rationalCircularArc(segmentCount: segmentCount)
      )
    )
  }

  private func identityMapping(
    lower: Double,
    upper: Double
  ) -> ExactRectangularBSplineSurfacePatch.AxisMapping {
    .init(sourceLower: lower, sourceUpper: upper, kind: .identity)
  }

  private func ruledParameterMapping(
    start: Curve3D,
    end: Curve3D,
    lower: Double,
    upper: Double, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch.AxisMapping? {
    try execution.consumeWork(1)
    guard
      let startKind = try ruledBoundaryMappingKind(
        start,
        lower: lower,
        upper: upper, using: &execution),
      let endKind = try ruledBoundaryMappingKind(
        end,
        lower: lower,
        upper: upper, using: &execution),
      startKind == endKind
    else {
      return nil
    }
    return .init(
      sourceLower: lower,
      sourceUpper: upper,
      kind: startKind
    )
  }

  private func ruledBoundaryMappingKind(
    _ curve: Curve3D,
    lower: Double,
    upper: Double, using execution: inout OriginalQueryExecution
  ) throws -> ExactRectangularBSplineSurfacePatch.AxisMapping.Kind? {
    try execution.consumeWork(1)
    switch curve {
    case .line, .analytic(.line), .analytic(.parabola), .bSpline:
      return .normalized
    case .circle, .analytic(.circle), .analytic(.arc), .analytic(.ellipse):
      return .normalizedRationalCircularArc(
        segmentCount: max(
          1,
          Int(ceil((upper - lower) / (Double.pi * 0.5)))
        )
      )
    case .analytic(.hyperbola):
      return .normalizedRationalHyperbola(
        spanCount: max(1, Int(ceil(upper - lower)))
      )
    case .rigidImage(let image):
      return try ruledBoundaryMappingKind(
        image.source,
        lower: lower,
        upper: upper, using: &execution)
    case .affineImage(let image):
      return try ruledBoundaryMappingKind(
        image.source,
        lower: lower,
        upper: upper, using: &execution)
    case .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative,
      .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector,
      .originalDrafted, .originalAngularTransport, .parameterImage, .originalAffineWord,
      .analytic(.planeTorus), .implicit, .surfaceLift,
      .certifiedIntersection:
      return nil
    }
  }

  private func legacyCylinderBasis(
    axis: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> (u: Vector3D, v: Vector3D) {
    let normalizedAxis = try axis.normalized(tolerance: tolerance.distance)
    let helper = abs(normalizedAxis.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let u = try helper.cross(normalizedAxis).normalized(tolerance: tolerance.distance)
    return (u, normalizedAxis.cross(u))
  }

  private struct CircularControl {
    let x: Double
    let y: Double
  }

  private struct CircularArcData {
    let controls: [CircularControl]
    let weights: [Double]
    let knots: [Double]
    let mapping: ExactRectangularBSplineSurfacePatch.AxisMapping
  }
}
