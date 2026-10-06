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

public struct DefaultCurveDifferentialEncloser: CurveDifferentialEnclosing, Sendable {
  public init() {}

  public func enclosure(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CurveDifferentialEnclosure {
    try validate(curve: curve, parameters: parameters, tolerance: tolerance)
    if case .rigidImage(let image) = curve {
      let source = try enclosure(
        of: image.source,
        over: parameters,
        tolerance: tolerance
      )
      return try transformed(
        source,
        by: image.transform,
        tolerance: tolerance
      )
    }
    if case .affineImage(let image) = curve {
      let source = try enclosure(
        of: image.source,
        over: parameters,
        tolerance: tolerance
      )
      return try transformed(
        source,
        by: image.transform,
        tolerance: tolerance
      )
    }
    if let jet = try directJet(
      curve,
      parameters: parameters,
      tolerance: tolerance
    ) {
      return try publicEnclosure(jet, tolerance: tolerance)
    }
    return try proceduralEnclosure(
      curve,
      parameters: parameters,
      tolerance: tolerance
    )
  }

  func thirdOrderIntervalJet(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try validate(curve: curve, parameters: parameters, tolerance: tolerance)
    if case .rigidImage(let image) = curve {
      return transformed(
        try thirdOrderIntervalJet(
          of: image.source,
          over: parameters,
          tolerance: tolerance
        ),
        by: image.transform
      )
    }
    if case .affineImage(let image) = curve {
      return transformed(
        try thirdOrderIntervalJet(
          of: image.source,
          over: parameters,
          tolerance: tolerance
        ),
        by: image.transform
      )
    }
    if let jet = try directJet(
      curve,
      parameters: parameters,
      tolerance: tolerance
    ) {
      return jet
    }
    switch curve {
    case .analytic(.planeTorus(let planeTorus)):
      let bounds = try planeTorus.spatialDifferentialMagnitudeBounds(
        fromParameter: parameters.lower,
        toParameter: parameters.upper,
        tolerance: tolerance
      )
      return try magnitudeBoundedThirdOrderJet(
        of: curve,
        over: parameters,
        bounds: bounds,
        tolerance: tolerance
      )
    case .implicit(let implicit):
      return try ImplicitCurveIntervalJetEncloser(
        intersection: implicit,
        tolerance: tolerance
      ).intervalJet(
        of: implicit,
        over: parameters,
        tolerance: tolerance
      )
    case .surfaceLift(let lift):
      let bounder = SurfaceLiftDifferentialBounder()
      guard
        let firstMagnitude = try bounder.firstDerivativeMagnitude(
          lift: lift,
          interval: parameters,
          tolerance: tolerance
        ),
        let secondMagnitude = try bounder.secondDerivativeMagnitude(
          lift: lift,
          interval: parameters,
          tolerance: tolerance
        ),
        let thirdMagnitude = try bounder.thirdDerivativeMagnitude(
          lift: lift,
          interval: parameters,
          tolerance: tolerance
        )
      else {
        throw certificationFailure(
          tolerance: tolerance,
          message: "The surface-lift curve has no certified third-order differential bounds."
        )
      }
      return try magnitudeBoundedThirdOrderJet(
        of: curve,
        over: parameters,
        bounds: SpatialDifferentialMagnitudeBounds(
          first: firstMagnitude,
          second: secondMagnitude,
          third: thirdMagnitude
        ),
        tolerance: tolerance,
        positionEnclosure: try surfaceLiftPositionEnclosure(
          lift, parameters: parameters, tolerance: tolerance
        )
      )
    case .certifiedIntersection(let intersection):
      let bounds = try intersection.spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction: parameters.lower,
        toNormalizedFraction: parameters.upper,
        tolerance: tolerance
      )
      return try magnitudeBoundedThirdOrderJet(
        of: curve,
        over: parameters,
        bounds: bounds,
        tolerance: tolerance
      )
    case .line, .circle, .analytic, .bSpline, .rigidImage, .affineImage, .parameterImage, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A directly enclosed curve reached the procedural third-order enclosure path."
      )
    }
  }

  private func magnitudeBoundedThirdOrderJet(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    bounds: SpatialDifferentialMagnitudeBounds,
    tolerance: ModelingTolerance,
    positionEnclosure: CoordinateEnclosure3D? = nil
  ) throws -> SurfaceIntervalVectorJet {
    guard bounds.first.isFinite,
      bounds.second.isFinite,
      let thirdMagnitude = bounds.third,
      thirdMagnitude.isFinite,
      bounds.first >= 0.0,
      bounds.second >= 0.0,
      thirdMagnitude >= 0.0
    else {
      throw certificationFailure(
        tolerance: tolerance,
        message: "The curve has no finite certified third-order differential bounds."
      )
    }
    let center = try curve.differentialGeometry(
      at: parameters.midpoint,
      tolerance: tolerance
    )
    let halfWidth = (parameters.width * 0.5).nextUp
    return SurfaceIntervalVectorJet(
      x: thirdOrderJet(
        position: center.position.x,
        first: center.firstDerivative.x,
        second: center.secondDerivative.x,
        positionRadius: (bounds.first * halfWidth).nextUp,
        firstRadius: (bounds.second * halfWidth).nextUp,
        secondRadius: (thirdMagnitude * halfWidth).nextUp,
        thirdMagnitude: thirdMagnitude,
        positionEnclosure: positionEnclosure?.x
      ),
      y: thirdOrderJet(
        position: center.position.y,
        first: center.firstDerivative.y,
        second: center.secondDerivative.y,
        positionRadius: (bounds.first * halfWidth).nextUp,
        firstRadius: (bounds.second * halfWidth).nextUp,
        secondRadius: (thirdMagnitude * halfWidth).nextUp,
        thirdMagnitude: thirdMagnitude,
        positionEnclosure: positionEnclosure?.y
      ),
      z: thirdOrderJet(
        position: center.position.z,
        first: center.firstDerivative.z,
        second: center.secondDerivative.z,
        positionRadius: (bounds.first * halfWidth).nextUp,
        firstRadius: (bounds.second * halfWidth).nextUp,
        secondRadius: (thirdMagnitude * halfWidth).nextUp,
        thirdMagnitude: thirdMagnitude,
        positionEnclosure: positionEnclosure?.z
      )
    )
  }

  private func thirdOrderJet(
    position: Double,
    first: Double,
    second: Double,
    positionRadius: Double,
    firstRadius: Double,
    secondRadius: Double,
    thirdMagnitude: Double,
    positionEnclosure: ScalarInterval?
  ) -> SurfaceIntervalJet {
    let zero = OutwardScalarInterval(0.0)
    return SurfaceIntervalJet(
      value: positionEnclosure.map { OutwardScalarInterval(lower: $0.lower, upper: $0.upper) }
        ?? centeredInterval(position, radius: positionRadius),
      derivativeU: centeredInterval(first, radius: firstRadius),
      derivativeV: zero,
      secondDerivativeUU: centeredInterval(second, radius: secondRadius),
      secondDerivativeUV: zero,
      secondDerivativeVV: zero,
      thirdDerivativeUUU: OutwardScalarInterval(
        lower: (-thirdMagnitude).nextDown,
        upper: thirdMagnitude.nextUp
      ),
      thirdDerivativeUUV: zero,
      thirdDerivativeUVV: zero,
      thirdDerivativeVVV: zero
    )
  }

  private func centeredInterval(
    _ value: Double,
    radius: Double
  ) -> OutwardScalarInterval {
    OutwardScalarInterval(
      lower: (value - radius).nextDown,
      upper: (value + radius).nextUp
    )
  }

  private func transformed(
    _ jet: SurfaceIntervalVectorJet,
    by transform: RigidTransform3D
  ) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet.constant(
      Point3D(
        x: transform.translation.x,
        y: transform.translation.y,
        z: transform.translation.z
      ))
      + SurfaceIntervalVectorJet.constant(transform.basisX) * jet.x
      + SurfaceIntervalVectorJet.constant(transform.basisY) * jet.y
      + SurfaceIntervalVectorJet.constant(transform.basisZ) * jet.z
  }

  private func transformed(
    _ jet: SurfaceIntervalVectorJet,
    by transform: AffineTransform3D
  ) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet.constant(
      Point3D(
        x: transform.translation.x,
        y: transform.translation.y,
        z: transform.translation.z
      ))
      + SurfaceIntervalVectorJet.constant(transform.basisX) * jet.x
      + SurfaceIntervalVectorJet.constant(transform.basisY) * jet.y
      + SurfaceIntervalVectorJet.constant(transform.basisZ) * jet.z
  }

  func directJet(
    _ curve: Curve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance,
    preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
    consumeStorage: ((Int) throws -> Void)? = nil
  ) throws -> SurfaceIntervalVectorJet? {
    try consumeWork()
    switch curve {
    case .originalAngularTransport(let image):
      return try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
        consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
    case .originalConstructionChart(let image):
      return try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
        maximumSpanCount: image.maximumSpanCount, maximumSubdivisionDepth: image.maximumSubdivisionDepth,
        remainingSourceDepth: image.remainingSourceDepth == Int.max ? Int.max : image.remainingSourceDepth + 1,
        consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
    case .originalGuideTraversalChain(let source):
      return try source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
        maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
        remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork,
        consumeStorage: consumeStorage).intervalJet()
    case .originalPolyline(let source):
      return try source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
        maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
        remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork,
        consumeStorage: consumeStorage).intervalJet()
    case .originalGuideEndpointConnector(let source):
      return try source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
        maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
        remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork,
        consumeStorage: consumeStorage).intervalJet()
    case .originalDrafted(let source):
      return try source.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
        maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
        remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork,
        consumeStorage: consumeStorage).intervalJet()
    case .originalPlaneDerivative(let source):
      let receipt = try source.closedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
        remainingSourceDepth: source.remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      guard let first = receipt.spans.first else { throw GeometryConversionError.invalidInput("Original plane curve cover is empty.") }
      return receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
    case .originalEndpointConnector:
      let receipt = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance)
        .closedNativeJets(over: parameters, tolerance: tolerance,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
      guard let first = receipt.spans.first else {
        throw GeometryConversionError.invalidInput("Original connector has no admitted owning span.")
      }
      var jet = first.jet
      for owner in receipt.spans.dropFirst() { jet = jet.union(owner.jet) }
      return jet
    case .originalAffineWord(let image):
      if let coefficients = image.circularCoefficients {
        return try coefficients.intervalTaylorJet(over: parameters, throughOrder: 3,
          tolerance: tolerance, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      let original = try PreparedCurveDifferentialEncloser(curve: image.source, tolerance: tolerance)
        .closedNativeJets(over: parameters, tolerance: tolerance, consumeWork: {})
      guard let first = original.spans.first else { return nil }
      var usage = OriginalAffineImageLegacyUsage()
      return try OriginalAffineWordJetTransport.applying(image.preparedWord,
        to: original.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }, usage: &usage)
    case .parameterImage(let image):
      let native = try image.originalInterval(parameters)
      let prepared = try PreparedCurveDifferentialEncloser(curve: image.source, tolerance: tolerance)
      let receipt = try prepared.closedNativeJets(over: native, tolerance: tolerance, consumeWork: {})
      guard let first = receipt.spans.first else { return nil }
      return try image.mappedJet(receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) })

    case .line(let line):
      return SurfaceIntervalVectorJet.constant(line.origin)
        + SurfaceIntervalVectorJet.constant(line.direction)
        * .parameterU(parameters)
    case .circle(let circle):
      let basis = try circleOrthonormalBasis(
        circle.normal,
        tolerance: tolerance
      )
      return try circularJet(
        center: circle.center,
        basis: basis,
        majorRadius: circle.radius,
        minorRadius: circle.radius,
        parameters: parameters, consumeWork: consumeWork
      )
    case .analytic(let analytic):
      return try analyticJet(
        analytic,
        parameters: parameters,
        tolerance: tolerance, consumeWork: consumeWork
      )
    case .bSpline(let curve):
      // Both entries use original native coefficients; the prepared native
      // branch never re-enters this one-shot dispatcher.
      return try PreparedCurveDifferentialEncloser(curve: .bSpline(curve), tolerance: tolerance)
        .thirdOrderIntervalJet(over: parameters, tolerance: tolerance)
    case .surfaceLift(let lift):
      if case .originalAffineWord(let image) = lift.parameterCurve {
        return try image.modelSpaceIntervalJet(over: parameters, tolerance: tolerance, preparedImplicit: preparedImplicit)
      }
      if case .originalImage(let image) = lift.parameterCurve {
        return try image.modelSpaceIntervalJet(over: parameters, tolerance: tolerance, preparedImplicit: preparedImplicit)
      }
      if case let .procedural(.ruled(ruled)) = lift.surface,
        case let .constantV(v, start, end) = lift.parameterCurve,
        start == 0, end == 1, v == 0 || v == 1 {
        // Exact boundary identity precedes general surface composition.
        return try thirdOrderIntervalJet(
          of: v == 0 ? ruled.startBoundary : ruled.endBoundary,
          over: parameters, tolerance: tolerance)
      }
      guard let uv = try parameterJets(lift.parameterCurve, over: parameters, tolerance: tolerance,
        preparedImplicit: preparedImplicit) else { return nil }
      let encloser = DefaultSurfaceDifferentialEncloser()
      if let analytic = try encloser.analyticJet(
        of: lift.surface, u: uv.u, v: uv.v, tolerance: tolerance
      ) { return analytic }
      let bounder = SurfaceLiftDifferentialBounder()
      if case .bSpline(let surface) = lift.surface {
        let box = try SurfaceParameterBox(
          u:bounder.closedRange(ScalarInterval(lower:uv.u.value.lower,upper:uv.u.value.upper),
            domain:surface.uDomain,tolerance:tolerance),
          v:bounder.closedRange(ScalarInterval(lower:uv.v.value.lower,upper:uv.v.value.upper),
            domain:surface.vDomain,tolerance:tolerance))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
        return try SurfaceParameterThirdOrderChainRule.intervalJet(
          surface:prepared.intervalJet(overClosedBox:box,tolerance:tolerance),u:uv.u,v:uv.v)
      }
      let box = try SurfaceParameterBox(
        u: bounder.nondegenerateRange(ScalarInterval(lower: uv.u.value.lower, upper: uv.u.value.upper),
            domain: lift.surface.uDomain, tolerance: tolerance),
        v: bounder.nondegenerateRange(ScalarInterval(lower: uv.v.value.lower, upper: uv.v.value.upper),
            domain: lift.surface.vDomain, tolerance: tolerance))
      return try SurfaceParameterThirdOrderChainRule.intervalJet(
        surface: encloser.intervalJet(of: lift.surface, over: box, tolerance: tolerance),
        u: uv.u, v: uv.v)
    case .implicit, .certifiedIntersection, .rigidImage,
      .affineImage:
      return nil
    }
  }

  /// Composes numeric UV charts without materializing a new trimmed curve.
  /// Both coordinates retain the same independent normalized curve parameter.
  func parameterJets(
    _ curve: SurfaceParameterCurve,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance,
    preparedImplicit: ImplicitCurveIntervalJetEncloser? = nil
  ) throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet)? {
    switch curve {
    case .originalAffineWord(let image):
      return try image.intervalJet(over: parameters, tolerance: tolerance, preparedImplicit: preparedImplicit)
    case .originalImage(let image):
      return try image.intervalJet(over: parameters, tolerance: tolerance, preparedImplicit: preparedImplicit)

    case let .offsetSurfaceImage(image):
      return try parameterJets(image.source, over: parameters, tolerance: tolerance, preparedImplicit: preparedImplicit)
    case let .periodicTranslation(base, uShift, vShift):
      guard let base = try parameterJets(base, over: parameters, tolerance: tolerance, preparedImplicit: preparedImplicit) else { return nil }
      return (base.u + .constant(uShift), base.v + .constant(vShift))
    case let .certifiedImplicit(implicit):
      let span = OutwardScalarInterval(implicit.endFraction) - OutwardScalarInterval(implicit.startFraction)
      let mapped = OutwardScalarInterval(implicit.startFraction)
        + span * OutwardScalarInterval(lower: parameters.lower, upper: parameters.upper)
      let lower = max(min(implicit.startFraction, implicit.endFraction), mapped.lower)
      let upper = min(max(implicit.startFraction, implicit.endFraction), mapped.upper)
      guard upper > lower else {
        throw certificationFailure(tolerance: tolerance,
          message: "Implicit lift interval mapping has no representable positive span.")
      }
      let local = CertifiedImplicitSurfaceParameterCurve(
        validatedIntersection: implicit.intersection, role: implicit.role,
        startFraction: lower, endFraction: upper)
      let uv = try SurfaceLiftDifferentialBounder().implicitParameterBounds(local, tolerance: tolerance, prepared: preparedImplicit)
      func jet(_ coordinate: CertifiedImplicitParameterIntervalJet.Coordinate) -> SurfaceIntervalJet {
        func interval(_ value: ScalarInterval) -> OutwardScalarInterval {
          OutwardScalarInterval(lower: value.lower, upper: value.upper)
        }
        let zero = OutwardScalarInterval(0)
        return SurfaceIntervalJet(value: interval(coordinate.value),
          derivativeU: interval(coordinate.firstDerivative) * span, derivativeV: zero,
          secondDerivativeUU: interval(coordinate.secondDerivative) * span * span,
          secondDerivativeUV: zero, secondDerivativeVV: zero,
          thirdDerivativeUUU: interval(coordinate.thirdDerivative) * span * span * span,
          thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
      }
      return (jet(uv.u), jet(uv.v))
    default:
      return try SurfaceParameterIntervalJet.enclose(curve, over: parameters, tolerance: tolerance)
    }
  }

  private func analyticJet(
    _ curve: AnalyticCurve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() }
  ) throws -> SurfaceIntervalVectorJet? {
    switch curve {
    case .line(let origin, let direction):
      return SurfaceIntervalVectorJet.constant(origin)
        + SurfaceIntervalVectorJet.constant(direction)
        * .parameterU(parameters)
    case .circle(let center, let normal, let radius),
      .arc(let center, let normal, let radius, _, _):
      return try circularJet(
        center: center,
        basis: try analyticOrthonormalBasis(
          normal,
          tolerance: tolerance
        ),
        majorRadius: radius,
        minorRadius: radius,
        parameters: parameters, consumeWork: consumeWork
      )
    case .ellipse(
      let
        center,
      let
        normal,
      let
        majorAxis,
      let
        majorRadius,
      let
        minorRadius
    ):
      let minorAxis = try normal.cross(majorAxis).normalized(
        tolerance: tolerance.distance
      )
      return try circularJet(
        center: center,
        basis: (u: majorAxis, v: minorAxis),
        majorRadius: majorRadius,
        minorRadius: minorRadius,
        parameters: parameters, consumeWork: consumeWork
      )
    case .hyperbola(let hyperbola):
      let conjugateAxis = try hyperbola.normal
        .cross(hyperbola.transverseAxis)
        .normalized(tolerance: tolerance.distance)
      let parameter = SurfaceIntervalJet.parameterU(parameters)
      return SurfaceIntervalVectorJet.constant(hyperbola.center)
        + SurfaceIntervalVectorJet.constant(hyperbola.transverseAxis)
        * (.constant(hyperbola.transverseRadius)
          * (try .hyperbolicCosine(of: parameter, consumeWork: consumeWork)))
        + SurfaceIntervalVectorJet.constant(conjugateAxis)
        * (.constant(hyperbola.conjugateRadius)
          * (try .hyperbolicSine(of: parameter, consumeWork: consumeWork)))
    case .parabola(let parabola):
      let transverseAxis = try parabola.normal
        .cross(parabola.axis)
        .normalized(tolerance: tolerance.distance)
      let parameter = SurfaceIntervalJet.parameterU(parameters)
      return SurfaceIntervalVectorJet.constant(parabola.vertex)
        + SurfaceIntervalVectorJet.constant(transverseAxis) * parameter
        + SurfaceIntervalVectorJet.constant(parabola.axis)
        * (parameter * parameter
          * .constant(1.0 / (4.0 * parabola.focalLength)))
    case .planeTorus:
      return nil
    }
  }

  private func circularJet(
    center: Point3D,
    basis: (u: Vector3D, v: Vector3D),
    majorRadius: Double,
    minorRadius: Double,
    parameters: ScalarInterval,
    consumeWork: () throws -> Void
  ) rethrows -> SurfaceIntervalVectorJet {
    let parameter = SurfaceIntervalJet.parameterU(parameters)
    return try SurfaceIntervalVectorJet.constant(center)
      + SurfaceIntervalVectorJet.constant(basis.u)
      * (.constant(majorRadius) * CanonicalSphereAngularPhase.harmonic(of: parameter, cosine: true, consumeWork: consumeWork))
      + SurfaceIntervalVectorJet.constant(basis.v)
      * (.constant(minorRadius) * CanonicalSphereAngularPhase.harmonic(of: parameter, cosine: false, consumeWork: consumeWork))
  }

  private func bSplineJet(
    _ curve: BSplineCurve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    let patches = try BSplineCurveBezierDecomposer().curvePatches(
      curve: curve,
      intersecting: parameters,
      tolerance: tolerance
    )
    let encloser = RationalBezierCurveJetEncloser()
    var result: SurfaceIntervalVectorJet?
    for patch in patches {
      let lower = max(parameters.lower, patch.lower)
      let upper = min(parameters.upper, patch.upper)
      guard upper > lower else { continue }
      let patchJet = try encloser.enclosure(
        of: patch,
        over: try ScalarInterval(lower: lower, upper: upper),
        tolerance: tolerance
      )
      result = result.map { $0.union(patchJet) } ?? patchJet
    }
    guard let result else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "The curve parameter interval did not intersect a B-spline Bezier span."
      )
    }
    return result
  }

  private func proceduralEnclosure(
    _ curve: Curve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CurveDifferentialEnclosure {
    let position: CoordinateEnclosure3D
    let firstDerivative: CoordinateEnclosure3D
    let secondDerivative: CoordinateEnclosure3D
    switch curve {
    case .analytic(.planeTorus(let curve)):
      position = try coordinateEnclosure(
        curve.boundingBox(tolerance: tolerance)
      )
      let bounds = try curve.spatialDifferentialMagnitudeBounds(
        fromParameter: parameters.lower,
        toParameter: parameters.upper,
        tolerance: tolerance
      )
      firstDerivative = try symmetricEnclosure(
        magnitudeUpperBound: bounds.first,
        tolerance: tolerance
      )
      secondDerivative = try symmetricEnclosure(
        magnitudeUpperBound: bounds.second,
        tolerance: tolerance
      )
    case .implicit(let implicit):
      let jet = try ImplicitCurveIntervalJetEncloser(
        intersection: implicit,
        tolerance: tolerance
      ).intervalJet(
        of: implicit,
        over: parameters,
        tolerance: tolerance
      )
      position = try coordinateEnclosure(
        jet,
        keyPath: { $0.value },
        tolerance: tolerance
      )
      firstDerivative = try coordinateEnclosure(
        jet,
        keyPath: { $0.derivativeU },
        tolerance: tolerance
      )
      secondDerivative = try coordinateEnclosure(
        jet,
        keyPath: { $0.secondDerivativeUU },
        tolerance: tolerance
      )
    case .surfaceLift(let lift):
      position = try surfaceLiftPositionEnclosure(
        lift,
        parameters: parameters,
        tolerance: tolerance
      )
      firstDerivative = try resolvedFirstDerivativeEnclosure(
        curve,
        parameters: parameters,
        tolerance: tolerance
      )
      guard
        let bound = try SurfaceLiftDifferentialBounder()
          .secondDerivativeMagnitude(
            lift: lift,
            interval: parameters,
            tolerance: tolerance
          )
      else {
        throw certificationFailure(
          tolerance: tolerance,
          message: "The surface-lift curve has no certified second-derivative enclosure."
        )
      }
      secondDerivative = try symmetricEnclosure(
        magnitudeUpperBound: bound,
        tolerance: tolerance
      )
    case .certifiedIntersection(let intersection):
      position = try coordinateEnclosure(
        intersection.boundingBox(tolerance: tolerance)
      )
      firstDerivative = try resolvedFirstDerivativeEnclosure(
        curve,
        parameters: parameters,
        tolerance: tolerance
      )
      let bounds = try intersection.spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction: parameters.lower,
        toNormalizedFraction: parameters.upper,
        tolerance: tolerance
      )
      secondDerivative = try symmetricEnclosure(
        magnitudeUpperBound: bounds.second,
        tolerance: tolerance
      )
    case .line, .circle, .analytic, .bSpline, .rigidImage, .affineImage, .parameterImage, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A directly enclosed curve reached the procedural enclosure path."
      )
    }
    return CurveDifferentialEnclosure(
      position: position,
      firstDerivative: firstDerivative,
      secondDerivative: secondDerivative
    )
  }

  private func surfaceLiftPositionEnclosure(
    _ lift: SurfaceLiftCurve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    let box = try lift.boundingBox(
      over: parameters,
      tolerance: tolerance
    )
    return try coordinateEnclosure(box)
  }

  private func resolvedFirstDerivativeEnclosure(
    _ curve: Curve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    guard
      let range = try DefaultCurveSpatialDerivativeRangeResolver()
        .derivativeRange(
          curve: curve,
          interval: parameters,
          tolerance: tolerance
        )
    else {
      throw certificationFailure(
        tolerance: tolerance,
        message: "The curve has no certified first-derivative enclosure."
      )
    }
    return CoordinateEnclosure3D(x: range.x, y: range.y, z: range.z)
  }

  package func publicEnclosure(
    _ jet: SurfaceIntervalVectorJet,
    tolerance: ModelingTolerance
  ) throws -> CurveDifferentialEnclosure {
    try CurveDifferentialEnclosure(
      position: coordinateEnclosure(
        jet,
        keyPath: { $0.value },
        tolerance: tolerance
      ),
      firstDerivative: coordinateEnclosure(
        jet,
        keyPath: { $0.derivativeU },
        tolerance: tolerance
      ),
      secondDerivative: coordinateEnclosure(
        jet,
        keyPath: { $0.secondDerivativeUU },
        tolerance: tolerance
      )
    )
  }

  private func coordinateEnclosure(
    _ jet: SurfaceIntervalVectorJet,
    keyPath: (SurfaceIntervalJet) -> OutwardScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    let x = keyPath(jet.x)
    let y = keyPath(jet.y)
    let z = keyPath(jet.z)
    guard x.isFinite, y.isFinite, z.isFinite else {
      throw arithmeticFailure(
        tolerance: tolerance,
        message: "Curve differential interval arithmetic exceeded finite values."
      )
    }
    return CoordinateEnclosure3D(
      x: try ScalarInterval(lower: x.lower, upper: x.upper),
      y: try ScalarInterval(lower: y.lower, upper: y.upper),
      z: try ScalarInterval(lower: z.lower, upper: z.upper)
    )
  }

  private func coordinateEnclosure(
    _ box: BoundingBox3D
  ) throws -> CoordinateEnclosure3D {
    CoordinateEnclosure3D(
      x: try ScalarInterval(
        lower: box.minimum.x.nextDown,
        upper: box.maximum.x.nextUp
      ),
      y: try ScalarInterval(
        lower: box.minimum.y.nextDown,
        upper: box.maximum.y.nextUp
      ),
      z: try ScalarInterval(
        lower: box.minimum.z.nextDown,
        upper: box.maximum.z.nextUp
      )
    )
  }

  private func symmetricEnclosure(
    magnitudeUpperBound: Double,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    guard magnitudeUpperBound.isFinite, magnitudeUpperBound >= 0.0 else {
      throw arithmeticFailure(
        tolerance: tolerance,
        message: "A curve derivative magnitude enclosure must be finite and nonnegative."
      )
    }
    let interval = try ScalarInterval(
      lower: (-magnitudeUpperBound).nextDown,
      upper: magnitudeUpperBound.nextUp
    )
    return CoordinateEnclosure3D(x: interval, y: interval, z: interval)
  }

  private func transformed(
    _ source: CurveDifferentialEnclosure,
    by transform: RigidTransform3D,
    tolerance: ModelingTolerance
  ) throws -> CurveDifferentialEnclosure {
    try CurveDifferentialEnclosure(
      position: transformed(
        source.position,
        by: transform,
        translation: transform.translation,
        tolerance: tolerance
      ),
      firstDerivative: transformed(
        source.firstDerivative,
        by: transform,
        translation: .zero,
        tolerance: tolerance
      ),
      secondDerivative: transformed(
        source.secondDerivative,
        by: transform,
        translation: .zero,
        tolerance: tolerance
      )
    )
  }

  private func transformed(
    _ source: CurveDifferentialEnclosure,
    by transform: AffineTransform3D,
    tolerance: ModelingTolerance
  ) throws -> CurveDifferentialEnclosure {
    try CurveDifferentialEnclosure(
      position: transformed(
        source.position,
        by: transform,
        translation: transform.translation,
        tolerance: tolerance
      ),
      firstDerivative: transformed(
        source.firstDerivative,
        by: transform,
        translation: .zero,
        tolerance: tolerance
      ),
      secondDerivative: transformed(
        source.secondDerivative,
        by: transform,
        translation: .zero,
        tolerance: tolerance
      )
    )
  }

  private func transformed(
    _ source: CoordinateEnclosure3D,
    by transform: RigidTransform3D,
    translation: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    let x = transformedComponent(
      source,
      x: transform.basisX.x,
      y: transform.basisY.x,
      z: transform.basisZ.x,
      translation: translation.x
    )
    let y = transformedComponent(
      source,
      x: transform.basisX.y,
      y: transform.basisY.y,
      z: transform.basisZ.y,
      translation: translation.y
    )
    let z = transformedComponent(
      source,
      x: transform.basisX.z,
      y: transform.basisY.z,
      z: transform.basisZ.z,
      translation: translation.z
    )
    guard x.isFinite, y.isFinite, z.isFinite else {
      throw arithmeticFailure(
        tolerance: tolerance,
        message: "Rigid curve enclosure transformation exceeded finite arithmetic."
      )
    }
    return CoordinateEnclosure3D(
      x: try ScalarInterval(lower: x.lower, upper: x.upper),
      y: try ScalarInterval(lower: y.lower, upper: y.upper),
      z: try ScalarInterval(lower: z.lower, upper: z.upper)
    )
  }

  private func transformed(
    _ source: CoordinateEnclosure3D,
    by transform: AffineTransform3D,
    translation: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    let x = transformedComponent(
      source,
      x: transform.basisX.x,
      y: transform.basisY.x,
      z: transform.basisZ.x,
      translation: translation.x
    )
    let y = transformedComponent(
      source,
      x: transform.basisX.y,
      y: transform.basisY.y,
      z: transform.basisZ.y,
      translation: translation.y
    )
    let z = transformedComponent(
      source,
      x: transform.basisX.z,
      y: transform.basisY.z,
      z: transform.basisZ.z,
      translation: translation.z
    )
    guard x.isFinite, y.isFinite, z.isFinite else {
      throw arithmeticFailure(
        tolerance: tolerance,
        message: "Affine curve enclosure transformation exceeded finite arithmetic."
      )
    }
    return CoordinateEnclosure3D(
      x: try ScalarInterval(lower: x.lower, upper: x.upper),
      y: try ScalarInterval(lower: y.lower, upper: y.upper),
      z: try ScalarInterval(lower: z.lower, upper: z.upper)
    )
  }

  private func transformedComponent(
    _ source: CoordinateEnclosure3D,
    x: Double,
    y: Double,
    z: Double,
    translation: Double
  ) -> OutwardScalarInterval {
    OutwardScalarInterval(lower: source.x.lower, upper: source.x.upper)
      * OutwardScalarInterval(x)
      + OutwardScalarInterval(lower: source.y.lower, upper: source.y.upper)
      * OutwardScalarInterval(y)
      + OutwardScalarInterval(lower: source.z.lower, upper: source.z.upper)
      * OutwardScalarInterval(z)
      + OutwardScalarInterval(translation)
  }

  private func validate(
    curve: Curve3D,
    parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    try curve.validate(tolerance: tolerance)
    guard parameters.width > 0.0 else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A curve differential enclosure requires a positive parameter span."
      )
    }
    if case .closed(let lower, let upper) = curve.parameterDomain {
      guard parameters.lower >= lower, parameters.upper <= upper else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "The curve parameter interval extends beyond the curve domain."
        )
      }
    }
  }

  private func certificationFailure(
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .intersectionFailure,
      tolerance: tolerance,
      message: message
    )
  }

  private func arithmeticFailure(
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      tolerance: tolerance,
      message: message
    )
  }
}
