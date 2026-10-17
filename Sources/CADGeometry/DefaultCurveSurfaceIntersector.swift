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

public struct DefaultCurveSurfaceIntersector: CurveSurfaceIntersecting {
  private let certifiedIntersectionCoincidenceResolver:
    any CertifiedIntersectionCoincidenceResolving
  private let certifiedIntersectionReductionIntersector:
    any CertifiedIntersectionReductionIntersecting
  private let certifiedIntersectionReductionResolver: any CertifiedIntersectionReductionResolving
  private let certifiedIntersectionSpatialDisjointnessResolver:
    any CertifiedIntersectionSpatialDisjointnessResolving
  private let parallelTorusTorusPlaneIntersector: any ParallelTorusTorusPlaneIntersecting
  private let coneCylinderSphereIntersector: any ConeCylinderSphereIntersecting
  private let coneCylinderConeIntersector: any ConeCylinderConeIntersecting
  private let coneHostedQuadricIntersector: any ConeHostedQuadricIntersecting
  private let cylinderCylinderReductionEligibility:
    any CertifiedCylinderCylinderReductionEligibility
  private let tangentIntersectionResolver: any CurveSurfaceTangentIntersectionResolving
  private let surfaceNormalResolver: any SurfaceNormalResolving
  private let implicitDifferentialEvaluator: any AnalyticSurfaceImplicitDifferentialEvaluating
  private let planarSurfaceResolver: any PlanarSurfaceResolving
  private let parametricRootCertifier: any ParametricCurveSurfaceRootCertifying
  private let proceduralSourceCoincidenceResolver:
    any ProceduralCurveSourceSurfaceCoincidenceResolving
  private let implicitCurveAnalyticSurfaceIntersector:
    any CertifiedImplicitCurveAnalyticSurfaceIntersecting
  private let searchRangeResolver: any CurveSurfaceSearchRangeResolving

  private struct IntervalVector3 {
    let x: ScalarInterval
    let y: ScalarInterval
    let z: ScalarInterval
  }

  private struct ScalarRootCell {
    let interval: ScalarInterval
    let depth: Int
    let secondDerivativeBound: Double
  }

  private struct UnresolvedScalarRootCandidate {
    let interval: ScalarInterval
    let residual: Double
    let secondDerivativeBound: Double
  }

  private enum ScalarRootCertificate {
    case excluded
    case unique(ScalarInterval)
    case unresolved
  }

  private struct SurfaceParameterBounds {
    let u: ScalarInterval
    let v: ScalarInterval
  }

  public init() {
    certifiedIntersectionCoincidenceResolver =
      DefaultCertifiedIntersectionCoincidenceResolver()
    certifiedIntersectionReductionIntersector =
      DefaultCertifiedIntersectionReductionIntersector()
    certifiedIntersectionReductionResolver =
      DefaultCertifiedIntersectionReductionResolver()
    certifiedIntersectionSpatialDisjointnessResolver =
      DefaultCertifiedIntersectionSpatialDisjointnessResolver()
    parallelTorusTorusPlaneIntersector =
      DefaultParallelTorusTorusPlaneIntersector()
    coneCylinderSphereIntersector =
      DefaultConeCylinderSphereIntersector()
    coneCylinderConeIntersector =
      DefaultConeCylinderConeIntersector()
    coneHostedQuadricIntersector =
      DefaultConeHostedQuadricIntersector()
    cylinderCylinderReductionEligibility =
      DefaultCertifiedCylinderCylinderReductionEligibility()
    tangentIntersectionResolver =
      VerifiedCurveSurfaceTangentIntersectionResolver()
    surfaceNormalResolver = DefaultSurfaceNormalResolver()
    implicitDifferentialEvaluator =
      DefaultAnalyticSurfaceImplicitDifferentialEvaluator()
    planarSurfaceResolver = DefaultPlanarSurfaceResolver()
    parametricRootCertifier =
      DefaultParametricCurveSurfaceRootCertifier()
    proceduralSourceCoincidenceResolver =
      DefaultProceduralCurveSourceSurfaceCoincidenceResolver()
    implicitCurveAnalyticSurfaceIntersector =
      DefaultCertifiedImplicitCurveAnalyticSurfaceIntersector()
    searchRangeResolver = DefaultCurveSurfaceSearchRangeResolver()
  }

  init(
    certifiedIntersectionCoincidenceResolver:
      any CertifiedIntersectionCoincidenceResolving,
    certifiedIntersectionReductionIntersector:
      any CertifiedIntersectionReductionIntersecting,
    certifiedIntersectionReductionResolver:
      any CertifiedIntersectionReductionResolving,
    certifiedIntersectionSpatialDisjointnessResolver:
      any CertifiedIntersectionSpatialDisjointnessResolving =
      DefaultCertifiedIntersectionSpatialDisjointnessResolver(),
    parallelTorusTorusPlaneIntersector:
      any ParallelTorusTorusPlaneIntersecting,
    coneCylinderSphereIntersector:
      any ConeCylinderSphereIntersecting,
    coneCylinderConeIntersector:
      any ConeCylinderConeIntersecting =
      DefaultConeCylinderConeIntersector(),
    coneHostedQuadricIntersector:
      any ConeHostedQuadricIntersecting =
      DefaultConeHostedQuadricIntersector(),
    cylinderCylinderReductionEligibility:
      any CertifiedCylinderCylinderReductionEligibility =
      DefaultCertifiedCylinderCylinderReductionEligibility(),
    tangentIntersectionResolver:
      any CurveSurfaceTangentIntersectionResolving,
    surfaceNormalResolver:
      any SurfaceNormalResolving = DefaultSurfaceNormalResolver(),
    implicitDifferentialEvaluator:
      any AnalyticSurfaceImplicitDifferentialEvaluating =
      DefaultAnalyticSurfaceImplicitDifferentialEvaluator(),
    planarSurfaceResolver:
      any PlanarSurfaceResolving = DefaultPlanarSurfaceResolver(),
    parametricRootCertifier:
      any ParametricCurveSurfaceRootCertifying =
      DefaultParametricCurveSurfaceRootCertifier(),
    proceduralSourceCoincidenceResolver:
      any ProceduralCurveSourceSurfaceCoincidenceResolving =
      DefaultProceduralCurveSourceSurfaceCoincidenceResolver(),
    implicitCurveAnalyticSurfaceIntersector:
      any CertifiedImplicitCurveAnalyticSurfaceIntersecting =
      DefaultCertifiedImplicitCurveAnalyticSurfaceIntersector(),
    searchRangeResolver:
      any CurveSurfaceSearchRangeResolving =
      DefaultCurveSurfaceSearchRangeResolver()
  ) {
    self.certifiedIntersectionCoincidenceResolver =
      certifiedIntersectionCoincidenceResolver
    self.certifiedIntersectionReductionIntersector =
      certifiedIntersectionReductionIntersector
    self.certifiedIntersectionReductionResolver =
      certifiedIntersectionReductionResolver
    self.certifiedIntersectionSpatialDisjointnessResolver =
      certifiedIntersectionSpatialDisjointnessResolver
    self.parallelTorusTorusPlaneIntersector =
      parallelTorusTorusPlaneIntersector
    self.coneCylinderSphereIntersector =
      coneCylinderSphereIntersector
    self.coneCylinderConeIntersector =
      coneCylinderConeIntersector
    self.coneHostedQuadricIntersector =
      coneHostedQuadricIntersector
    self.cylinderCylinderReductionEligibility =
      cylinderCylinderReductionEligibility
    self.tangentIntersectionResolver = tangentIntersectionResolver
    self.surfaceNormalResolver = surfaceNormalResolver
    self.implicitDifferentialEvaluator = implicitDifferentialEvaluator
    self.planarSurfaceResolver = planarSurfaceResolver
    self.parametricRootCertifier = parametricRootCertifier
    self.proceduralSourceCoincidenceResolver =
      proceduralSourceCoincidenceResolver
    self.implicitCurveAnalyticSurfaceIntersector =
      implicitCurveAnalyticSurfaceIntersector
    self.searchRangeResolver = searchRangeResolver
  }

  public func intersections(curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance
  ) throws -> [CurveSurfaceIntersection] {
    let context = OriginalQueryFailureContext(operation: .curveSurface, entry: .ordinary,
      stage: .request, first: .init(role: .curve, request: .curveRange(options.curveRange)),
      second: .init(role: .surface, request: .surfaceRanges(u: options.surfaceURange, v: options.surfaceVRange)))
    do {
      try options.validate(tolerance: tolerance)
      var execution = try OriginalQueryExecution.curveSurface(options: options, context: context)
      return try intersections(curve: curve, surface: surface, options: options,
        tolerance: tolerance, using: &execution)
    } catch { throw OriginalQueryFailure.published(error, context: context, tolerance: tolerance) }
  }

  public func intersections(curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection] {
    execution.context = OriginalQueryFailureContext(operation: .curveSurface,
      entry: execution.context.entry == .unspecified ? .admitted : execution.context.entry,
      stage: .request, first: .init(role: .curve, request: .curveRange(options.curveRange)),
      second: .init(role: .surface, request: .surfaceRanges(u: options.surfaceURange, v: options.surfaceVRange)))
      .fillingMissing(from: execution.context)
    do {
      try execution.checkpoint()
      try options.validate(tolerance: tolerance)
      let result = try resolveIntersections(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      guard result.count <= min(options.maximumCandidateCount, execution.effectiveLimits.maximumResults) else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
          residual: Double(result.count), tolerance: tolerance,
          message: "Original curve-surface publication exceeded the caller's result ceiling.")
      }
      try execution.checkpoint()
      return result
    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  private func resolveIntersections(curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection] {
      if let linear = try OriginalLinearPlanePublicProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return linear.points }
      if let periodic = try OriginalPeriodicOffsetCurvePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return periodic.points }
      if let pairLift = try OriginalCertifiedPairLiftPublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return pairLift.points }
      if let coneCone = try OriginalCertifiedConeConePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return coneCone.points }
      if let node = try OriginalSphereConeNodePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return node.points }
      if let sphereCone = try OriginalCertifiedSphereConePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return sphereCone.points }
      if let coaxial = try OriginalCertifiedCoaxialPublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return coaxial.points }
      if let excluded = try OriginalCertifiedApexPlanePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return excluded.points }
      if let implicit = try OriginalImplicitCurvePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return implicit.points }
      if let angular = try OriginalAngularPlanePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return angular.points }
      if let axis = try OriginalRevolutionAxisLinePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return axis.points }
      if let drafted = try OriginalDraftedZeroLinePublicProducer().resolve(curve:curve,surface:surface,
        options:options,tolerance:tolerance,using:&execution) { return drafted.points }
      if let lift = try OriginalRetainedLiftPlanePublicProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return lift.points }
      if let exact = try NativeExactPublicCurveSurfaceProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return exact.points }
      if let native = try NativeCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return native.points }
      if let original = try OriginalPolynomialCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return original.points }
      if let affine = try OriginalAffineCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return affine.points }
      if let coons = try OriginalCoonsCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution) { return coons.points }
      execution.context = execution.context.at(stage: .source)
      try execution.consumeWork(1)
      try options.validate(tolerance: tolerance)
      try curve.validateOriginalSource(tolerance: tolerance,
        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
      try surface.validateOriginalSource(tolerance: tolerance,
        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
      if case .bSpline(let native) = curve, case .plane(let plane) = surface,
        plane.uDirection != nil {
        return try selectedNativePlaneIntersections(curve: native, plane: plane,
          options: options, tolerance: tolerance, using: &execution)
      }
      execution.context = execution.context.at(stage: .relation)
      // FIXME(INCOMPLETE_IMPLEMENTATION): The public root reaches only original
      // selected-domain certification here. General critical/coincident coverage
      // remains unsupported; residual-only closed-form candidates cannot publish
      // a complete original event set or identify distinct source parameters.
      return try adaptiveIntersections(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
  }

  // The following legacy numerical helpers are not public relation authorities.
  // Public dispatch above uses source producers and selected original certificates.

  private func supportsCertifiedReduction(
    curve: CertifiedIntersectionCurve3D,
    target: CanonicalAnalyticSurface,
    tolerance: ModelingTolerance
  ) throws -> Bool {
    switch target {
    case .plane:
      if case .parallelTorusTorus = curve {
        return false
      }
      return true
    case .sphere:
      switch curve {
      case .sphereCone:
        return true
      case .coneCone, .coneCylinder, .coneTorus,
        .parallelTorusTorus:
        return false
      }
    case .cylinder(let targetCylinder):
      switch curve {
      case .sphereCone:
        return true
      case .coneCone:
        return true
      case .coneCylinder(let coneCylinderCurve):
        guard
          case .cylinder(let sourceCylinder) =
            CanonicalAnalyticSurface(
              coneCylinderCurve.cylinderSurface
            )
        else {
          return false
        }
        if AnalyticAxisRelation.areParallel(
          targetCylinder.axis,
          sourceCylinder.axis,
          tolerance: tolerance
        ) {
          return true
        }
        return
          try cylinderCylinderReductionEligibility
          .supportsCertifiedIntersection(
            first: targetCylinder,
            second: sourceCylinder,
            tolerance: tolerance
          )
      case .coneTorus, .parallelTorusTorus:
        return false
      }
    case .cone, .torus, .unsupported:
      return false
    }
  }

  private func closedFormEllipticPlanarIntersections(
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection]? {
    guard
      case .analytic(
        .ellipse(
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
        )) = curve,
      let plane = planarSurfaceResolver.canonicalPlane(
        for: surface
      )
    else {
      return nil
    }
    let minorAxis = try normal.cross(majorAxis).normalized(
      tolerance: tolerance.distance
    )
    let constant = (center - plane.origin).dot(plane.normal)
    let cosineCoefficient = majorAxis.dot(plane.normal) * majorRadius
    let sineCoefficient = minorAxis.dot(plane.normal) * minorRadius
    let amplitude = hypot(cosineCoefficient, sineCoefficient)
    if amplitude <= tolerance.distance {
      guard abs(constant) > tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .nonDiscreteIntersection,
          residual: abs(constant),
          tolerance: tolerance,
          message:
            "Elliptic curve and plane are coincident; the intersection is not a discrete point set."
        )
      }
      return []
    }
    guard abs(constant) <= amplitude + tolerance.distance else {
      return []
    }

    let phase = atan2(sineCoefficient, cosineCoefficient)
    let normalizedConstant = min(max(-constant / amplitude, -1.0), 1.0)
    let angularOffset = acos(normalizedConstant)
    let first = normalizedPeriodicParameter(CanonicalSphereAngularPhase.candidateLabel(ofPhysicalAngle: phase - angularOffset))
    let second = normalizedPeriodicParameter(CanonicalSphereAngularPhase.candidateLabel(ofPhysicalAngle: phase + angularOffset))
    let parameters =
      abs(sin(angularOffset)) <= tolerance.angle
      ? [first]
      : [first, second]

    var intersections: [CurveSurfaceIntersection] = []
    for parameter in parameters {
      try execution.consumeWork(1)
      guard contains(parameter, range: options.curveRange),
        try curve.parameterDomain.contains(parameter, tolerance: tolerance)
      else {
        continue
      }
      let curveGeometry = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      let surfaceProjection = try surface.parameterProjection(
        of: curveGeometry.position,
        tolerance: tolerance
      )
      guard contains(surfaceProjection.u, range: options.surfaceURange),
        contains(surfaceProjection.v, range: options.surfaceVRange)
      else {
        continue
      }
      let planeResidual = abs(
        (curveGeometry.position - plane.origin).dot(plane.normal)
      )
      let residual = max(planeResidual, surfaceProjection.residual)
      guard residual <= tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          residual: residual,
          tolerance: tolerance,
          message: "Closed-form ellipse-plane intersection failed residual verification."
        )
      }
      intersections.append(
        try CurveSurfaceIntersection(
          point: curveGeometry.position,
          curveParameter: parameter,
          surfaceU: surfaceProjection.u,
          surfaceV: surfaceProjection.v,
          kind: abs(curveGeometry.tangent.dot(plane.normal)) <= tolerance.angle
            ? .tangent
            : .transverse,
          residual: residual,
          iterations: 0
        ))
    }
    return deduplicated(intersections, tolerance: tolerance)
  }

  private func closedFormHarmonicAnalyticIntersections(
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection]? {
    guard
      let harmonic = try harmonicCurveGeometry(
        curve,
        tolerance: tolerance
      ),
      let coefficients = harmonicImplicitPolynomial(
        center: harmonic.center,
        cosine: harmonic.cosine,
        sine: harmonic.sine,
        surface: surface
      )
    else {
      return nil
    }
    let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
    if coefficients.allSatisfy({
      abs($0) <= coefficientScale * tolerance.angle
    }) {
      throw KernelError(
        phase: .geometry,
        code: .nonDiscreteIntersection,
        tolerance: tolerance,
        message: "Harmonic curve and analytic surface share a continuous intersection."
      )
    }
    let solver = try RealPolynomialRootSolver(
      rootTolerance: max(
        tolerance.angle * 0.001,
        Double.ulpOfOne * 64.0
      ),
      residualTolerance: max(
        tolerance.angle * 0.001,
        Double.ulpOfOne * 64.0
      )
    )
    var parameters = try solver.realRoots(coefficients: coefficients, using: &execution).compactMap {
      resolvedCurveParameter(
        normalizedPeriodicParameter(CanonicalSphereAngularPhase.candidateLabel(ofPhysicalAngle: 2.0 * atan($0))),
        domain: curve.parameterDomain,
        range: options.curveRange,
        tolerance: tolerance
      )
    }
    if let poleParameter = resolvedCurveParameter(
      Double.pi,
      domain: curve.parameterDomain,
      range: options.curveRange,
      tolerance: tolerance
    ) {
      let polePoint = try curve.point(
        at: poleParameter,
        tolerance: tolerance
      )
      do {
        _ = try surface.parameterProjection(
          of: polePoint,
          tolerance: tolerance
        )
        parameters.append(poleParameter)
      } catch let error as KernelError
        where error.code == .intersectionFailure
      {
        // The tan-half-angle pole is not an intersection.
      }
    }

    var intersections: [CurveSurfaceIntersection] = []
    for parameter in parameters {
      try execution.consumeWork(1)
      guard contains(parameter, range: options.curveRange) else {
        continue
      }
      let curveGeometry = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      let surfaceProjection = try surface.parameterProjection(
        of: curveGeometry.position,
        tolerance: tolerance
      )
      guard contains(surfaceProjection.u, range: options.surfaceURange),
        contains(surfaceProjection.v, range: options.surfaceVRange)
      else {
        continue
      }
      let residual = surfaceProjection.residual
      guard residual <= tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          residual: residual,
          tolerance: tolerance,
          message: "Closed-form harmonic curve-surface intersection failed residual verification."
        )
      }
      let surfaceNormal = try surfaceNormalResolver.normal(
        at: curveGeometry.position,
        on: surface,
        u: surfaceProjection.u,
        v: surfaceProjection.v,
        tolerance: tolerance, using: &execution
      )
      intersections.append(
        try CurveSurfaceIntersection(
          point: curveGeometry.position,
          curveParameter: parameter,
          surfaceU: surfaceProjection.u,
          surfaceV: surfaceProjection.v,
          kind: abs(curveGeometry.tangent.dot(surfaceNormal)) <= tolerance.angle
            ? .tangent
            : .transverse,
          residual: residual,
          iterations: 0
        ))
    }
    return deduplicated(intersections, tolerance: tolerance)
  }

  private func closedFormUnboundedConicAnalyticIntersections(
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection]? {
    let coefficients: [Double]
    let parameterForRoot: (Double) -> Double?
    switch curve {
    case .analytic(.hyperbola(let hyperbola)):
      let conjugateAxis = try hyperbola.normal
        .cross(hyperbola.transverseAxis)
        .normalized(tolerance: tolerance.distance)
      let transverse = hyperbola.transverseAxis * hyperbola.transverseRadius
      let conjugate = conjugateAxis * hyperbola.conjugateRadius
      let denominator = [0.0, 1.0]
      guard
        let polynomial = rationalCurveImplicitPolynomial(
          relativeNumerator: { origin in
            [
              (transverse - conjugate) * 0.5,
              hyperbola.center - origin,
              (transverse + conjugate) * 0.5,
            ]
          },
          denominator: denominator,
          surface: surface
        )
      else {
        return nil
      }
      coefficients = polynomial
      parameterForRoot = { root in
        guard root.isFinite, root > 0.0 else { return nil }
        let parameter = log(root)
        return parameter.isFinite ? parameter : nil
      }
    case .analytic(.parabola(let parabola)):
      let transverseAxis = try parabola.normal
        .cross(parabola.axis)
        .normalized(tolerance: tolerance.distance)
      guard
        let polynomial = rationalCurveImplicitPolynomial(
          relativeNumerator: { origin in
            [
              parabola.vertex - origin,
              transverseAxis,
              parabola.axis * (1.0 / (4.0 * parabola.focalLength)),
            ]
          },
          denominator: [1.0],
          surface: surface
        )
      else {
        return nil
      }
      coefficients = polynomial
      parameterForRoot = { root in root.isFinite ? root : nil }
    case .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector, .originalDrafted, .originalAngularTransport, .originalAffineWord, .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .rigidImage, .affineImage, .parameterImage:
      return nil
    }

    let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
    if coefficients.allSatisfy({
      abs($0) <= coefficientScale * tolerance.relative
    }) {
      throw KernelError(
        phase: .geometry,
        code: .nonDiscreteIntersection,
        tolerance: tolerance,
        message: "An unbounded conic and analytic surface share a continuous intersection."
      )
    }
    let solver = try RealPolynomialRootSolver(
      rootTolerance: max(
        tolerance.relative * 0.001,
        Double.ulpOfOne * 64.0
      ),
      residualTolerance: max(
        tolerance.relative * 0.001,
        Double.ulpOfOne * 64.0
      )
    )
    let parameters = try solver.realRoots(coefficients: coefficients, using: &execution)
      .compactMap(parameterForRoot)
      .filter { parameter in
        options.curveRange?.contains(parameter) ?? true
      }
    return try verifiedConicIntersections(
      parameters: parameters,
      curve: curve,
      surface: surface,
      options: options,
      tolerance: tolerance,
    using: &execution)
  }

  private func verifiedConicIntersections(
    parameters: [Double],
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection] {
    var result: [CurveSurfaceIntersection] = []
    for parameter in parameters {
      try execution.consumeWork(1)
      let curveGeometry = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      let projection = try surface.parameterProjection(
        of: curveGeometry.position,
        tolerance: tolerance
      )
      guard contains(projection.u, range: options.surfaceURange),
        contains(projection.v, range: options.surfaceVRange),
        try surface.uDomain.contains(projection.u, tolerance: tolerance),
        try surface.vDomain.contains(projection.v, tolerance: tolerance)
      else {
        continue
      }
      let surfacePoint = try surface.point(
        u: projection.u,
        v: projection.v,
        tolerance: tolerance
      )
      let residual = max(
        projection.residual,
        (surfacePoint - curveGeometry.position).length
      )
      guard residual <= tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          residual: residual,
          tolerance: tolerance,
          message: "Closed-form unbounded conic intersection failed residual verification."
        )
      }
      let surfaceNormal = try surfaceNormalResolver.normal(
        at: curveGeometry.position,
        on: surface,
        u: projection.u,
        v: projection.v,
        tolerance: tolerance, using: &execution
      )
      result.append(
        try CurveSurfaceIntersection(
          point: curveGeometry.position,
          curveParameter: parameter,
          surfaceU: projection.u,
          surfaceV: projection.v,
          kind: abs(curveGeometry.tangent.dot(surfaceNormal)) <= tolerance.angle
            ? .tangent
            : .transverse,
          residual: residual,
          iterations: 0
        ))
    }
    return deduplicated(result, tolerance: tolerance)
  }

  private func harmonicCurveGeometry(
    _ curve: Curve3D,
    tolerance: ModelingTolerance
  ) throws -> (center: Point3D, cosine: Vector3D, sine: Vector3D)? {
    switch curve {
    case .circle(let circle):
      let normal = try circle.normal.normalized(
        tolerance: tolerance.distance
      )
      let helper =
        abs(normal.z) < 0.9
        ? Vector3D.unitZ
        : Vector3D.unitY
      let cosine =
        try helper.cross(normal).normalized(
          tolerance: tolerance.distance
        ) * circle.radius
      return (
        circle.center,
        cosine,
        normal.cross(cosine)
      )
    case .analytic(let analytic):
      switch analytic {
      case .circle(let center, let normal, let radius),
        .arc(let center, let normal, let radius, _, _):
        let basis = try analyticOrthonormalBasis(
          normal,
          tolerance: tolerance
        )
        return (center, basis.u * radius, basis.v * radius)
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
        return (
          center,
          majorAxis * majorRadius,
          minorAxis * minorRadius
        )
      case .line, .hyperbola, .parabola:
        return nil
      case .planeTorus:
        return nil
      }
    case .rigidImage(let image):
      guard
        let source = try harmonicCurveGeometry(
          image.source,
          tolerance: tolerance
        )
      else {
        return nil
      }
      return (
        image.transform.applying(to: source.center),
        image.transform.applying(to: source.cosine),
        image.transform.applying(to: source.sine)
      )
    case .affineImage(let image):
      guard
        let source = try harmonicCurveGeometry(
          image.source,
          tolerance: tolerance
        )
      else {
        return nil
      }
      return (
        image.transform.applying(to: source.center),
        image.transform.applying(to: source.cosine),
        image.transform.applying(to: source.sine)
      )
    case .line, .bSpline, .implicit, .surfaceLift, .certifiedIntersection, .parameterImage, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
      return nil
    }
  }

  private func harmonicImplicitPolynomial(
    center: Point3D,
    cosine: Vector3D,
    sine: Vector3D,
    surface: Surface3D
  ) -> [Double]? {
    let denominator = [1.0, 0.0, 1.0]
    return rationalCurveImplicitPolynomial(
      relativeNumerator: { origin in
        [
          center + cosine - origin,
          sine * 2.0,
          center + (-cosine) - origin,
        ]
      },
      denominator: denominator,
      surface: surface
    )
  }

  private func rationalCurveImplicitPolynomial(
    relativeNumerator: (Point3D) -> [Vector3D],
    denominator: [Double],
    surface: Surface3D
  ) -> [Double]? {
    let denominatorSquared = multiplied(denominator, denominator)

    func cylinder(
      origin: Point3D,
      axis: Vector3D,
      radius: Double
    ) -> [Double] {
      let offset = relativeNumerator(origin)
      let squaredDistance = vectorDot(offset, offset)
      let axial = offset.map { $0.dot(axis) }
      return subtracting(
        subtracting(squaredDistance, multiplied(axial, axial)),
        scaled(denominatorSquared, by: radius * radius)
      )
    }

    func cone(
      apex: Point3D,
      axis: Vector3D,
      halfAngle: Double
    ) -> [Double] {
      let offset = relativeNumerator(apex)
      let squaredDistance = vectorDot(offset, offset)
      let axial = offset.map { $0.dot(axis) }
      return subtracting(
        squaredDistance,
        scaled(
          multiplied(axial, axial),
          by: 1.0 + pow(tan(halfAngle), 2.0)
        )
      )
    }

    func sphere(center: Point3D, radius: Double) -> [Double] {
      let offset = relativeNumerator(center)
      return subtracting(
        vectorDot(offset, offset),
        scaled(denominatorSquared, by: radius * radius)
      )
    }

    func torus(
      center: Point3D,
      axis: Vector3D,
      majorRadius: Double,
      minorRadius: Double
    ) -> [Double] {
      let offset = relativeNumerator(center)
      let squaredDistance = vectorDot(offset, offset)
      let axial = offset.map { $0.dot(axis) }
      let radialSquared = subtracting(
        squaredDistance,
        multiplied(axial, axial)
      )
      let implicitQuadratic = adding(
        squaredDistance,
        scaled(
          denominatorSquared,
          by: majorRadius * majorRadius - minorRadius * minorRadius
        )
      )
      return subtracting(
        multiplied(implicitQuadratic, implicitQuadratic),
        scaled(
          multiplied(radialSquared, denominatorSquared),
          by: 4.0 * majorRadius * majorRadius
        )
      )
    }

    switch surface {
    case .plane(let plane):
      return relativeNumerator(plane.origin).map { $0.dot(plane.normal) }
    case .cylinder(let value):
      return cylinder(
        origin: value.origin,
        axis: value.axis,
        radius: value.radius
      )
    case .analytic(let analytic):
      switch analytic {
      case .plane(let origin, let normal):
        return relativeNumerator(origin).map { $0.dot(normal) }
      case .cylinder(let origin, let axis, let radius):
        return cylinder(origin: origin, axis: axis, radius: radius)
      case .cone(let apex, let axis, let halfAngle):
        return cone(apex: apex, axis: axis, halfAngle: halfAngle)
      case .sphere(let center, let radius):
        return sphere(center: center, radius: radius)
      case .torus(let center, let axis, let majorRadius, let minorRadius):
        return torus(
          center: center,
          axis: axis,
          majorRadius: majorRadius,
          minorRadius: minorRadius
        )
      }
    case .bSpline:
      return nil
    case .procedural:
      return nil
    }
  }

  private func vectorDot(
    _ lhs: [Vector3D],
    _ rhs: [Vector3D]
  ) -> [Double] {
    var result = Array(
      repeating: 0.0,
      count: lhs.count + rhs.count - 1
    )
    for lhsIndex in lhs.indices {
      for rhsIndex in rhs.indices {
        result[lhsIndex + rhsIndex] += lhs[lhsIndex].dot(rhs[rhsIndex])
      }
    }
    return result
  }

  private func multiplied(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
    var result = Array(
      repeating: 0.0,
      count: lhs.count + rhs.count - 1
    )
    for lhsIndex in lhs.indices {
      for rhsIndex in rhs.indices {
        result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
      }
    }
    return result
  }

  private func adding(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
    let count = max(lhs.count, rhs.count)
    return (0..<count).map { index in
      (index < lhs.count ? lhs[index] : 0.0)
        + (index < rhs.count ? rhs[index] : 0.0)
    }
  }

  private func subtracting(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
    adding(lhs, scaled(rhs, by: -1.0))
  }

  private func scaled(_ polynomial: [Double], by scale: Double) -> [Double] {
    polynomial.map { $0 * scale }
  }

  private func resolvedCurveParameter(
    _ canonical: Double,
    domain: ParameterDomain,
    range: ScalarInterval?,
    tolerance: ModelingTolerance
  ) -> Double? {
    switch domain {
    case .periodic(let period):
      guard let range else { return canonical }
      let cycle = ceil((range.lower - canonical - tolerance.angle) / period)
      let candidate = canonical + cycle * period
      return candidate <= range.upper + tolerance.angle ? candidate : nil
    case .closed(let lower, let upper):
      let effectiveLower = max(lower, range?.lower ?? lower)
      let effectiveUpper = min(upper, range?.upper ?? upper)
      guard effectiveLower <= effectiveUpper else { return nil }
      let period = 2.0 * Double.pi
      let cycle = ceil((effectiveLower - canonical - tolerance.angle) / period)
      let candidate = canonical + cycle * period
      return candidate <= effectiveUpper + tolerance.angle ? candidate : nil
    case .unbounded:
      return nil
    }
  }

  private func closedFormCircularPlanarIntersections(
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection]? {
    guard let circle = circularGeometry(curve),
      let plane = planarSurfaceResolver.canonicalPlane(
        for: surface
      )
    else {
      return nil
    }

    let normalCross = circle.normal.cross(plane.normal)
    let signedCenterDistance = (circle.center - plane.origin).dot(plane.normal)
    if normalCross.length <= tolerance.angle {
      guard abs(signedCenterDistance) > tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .nonDiscreteIntersection,
          residual: abs(signedCenterDistance),
          tolerance: tolerance,
          message:
            "Circular curve and plane are coincident; the intersection is not a discrete point set."
        )
      }
      return []
    }

    let inCirclePlaneNormal = plane.normal - circle.normal * plane.normal.dot(circle.normal)
    let squaredLength = inCirclePlaneNormal.dot(inCirclePlaneNormal)
    guard squaredLength > tolerance.angle * tolerance.angle else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "Circle-plane intersection could not construct a stable in-plane normal."
      )
    }
    let lineAnchor =
      circle.center
      + inCirclePlaneNormal * (-signedCenterDistance / squaredLength)
    let centerToLineDistance = (lineAnchor - circle.center).length
    guard centerToLineDistance <= circle.radius + tolerance.distance else {
      return []
    }

    let lineDirection = try normalCross.normalized(tolerance: tolerance.angle)
    let halfChordSquared = max(
      0.0,
      circle.radius * circle.radius - centerToLineDistance * centerToLineDistance
    )
    let halfChord = sqrt(halfChordSquared)
    let candidates: [Point3D]
    if halfChord <= tolerance.distance {
      candidates = [lineAnchor]
    } else {
      candidates = [
        lineAnchor + lineDirection * -halfChord,
        lineAnchor + lineDirection * halfChord,
      ]
    }

    var intersections: [CurveSurfaceIntersection] = []
    for point in candidates {
      try execution.consumeWork(1)
      let curveProjection: CurveParameterProjection
      do {
        curveProjection = try curve.parameterProjection(
          of: point,
          tolerance: tolerance
        )
      } catch let error as KernelError where error.code == .intersectionFailure {
        continue
      }
      guard contains(curveProjection.parameter, range: options.curveRange) else {
        continue
      }
      let surfaceProjection = try surface.parameterProjection(
        of: point,
        tolerance: tolerance
      )
      guard contains(surfaceProjection.u, range: options.surfaceURange),
        contains(surfaceProjection.v, range: options.surfaceVRange)
      else {
        continue
      }
      let curveGeometry = try curve.differentialGeometry(
        at: curveProjection.parameter,
        tolerance: tolerance
      )
      let residual = max(curveProjection.residual, surfaceProjection.residual)
      guard residual <= tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          residual: residual,
          tolerance: tolerance,
          message: "Closed-form circle-plane intersection failed residual verification."
        )
      }
      intersections.append(
        try CurveSurfaceIntersection(
          point: point,
          curveParameter: curveProjection.parameter,
          surfaceU: surfaceProjection.u,
          surfaceV: surfaceProjection.v,
          kind: abs(curveGeometry.tangent.dot(plane.normal)) <= tolerance.angle
            ? .tangent
            : .transverse,
          residual: residual,
          iterations: 0
        ))
    }
    return deduplicated(intersections, tolerance: tolerance)
  }

  private func circularGeometry(
    _ curve: Curve3D
  ) -> (center: Point3D, normal: Vector3D, radius: Double)? {
    switch curve {
    case .circle(let circle):
      return (circle.center, circle.normal, circle.radius)
    case .analytic(.circle(let center, let normal, let radius)),
      .analytic(.arc(let center, let normal, let radius, _, _)):
      return (center, normal, radius)
    case .rigidImage(let image):
      guard let source = circularGeometry(image.source) else {
        return nil
      }
      return (
        image.transform.applying(to: source.center),
        image.transform.applying(to: source.normal),
        source.radius
      )
    case .line, .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .affineImage, .parameterImage, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
      return nil
    }
  }

  private func lineGeometry(_ curve: Curve3D) -> Line3D? {
    switch curve {
    case .parameterImage(let image):
      guard let source = lineGeometry(image.source) else { return nil }
      return Line3D(origin: source.origin + source.direction * image.offset,
        direction: source.direction * image.gain)

    case .line(let line):
      return line
    case .analytic(.line(let origin, let direction)):
      return Line3D(origin: origin, direction: direction)
    case .rigidImage(let image):
      guard let source = lineGeometry(image.source) else {
        return nil
      }
      return Line3D(
        origin: image.transform.applying(to: source.origin),
        direction: image.transform.applying(to: source.direction)
      )
    case .affineImage(let image):
      guard let source = lineGeometry(image.source) else {
        return nil
      }
      let direction = image.transform.applying(to: source.direction)
      guard direction.length > 0.0 else {
        return nil
      }
      return Line3D(
        origin: image.transform.applying(to: source.origin),
        direction: direction
      )
    case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
      return nil
    }
  }

  private func implicitPolynomial(
    line: Line3D,
    surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> [Double]? {
    switch surface {
    case .plane(let plane):
      return try planePolynomial(
        line: line, origin: plane.origin, normal: plane.normal, tolerance: tolerance)
    case .cylinder(let cylinder):
      return cylinderPolynomial(
        line: line,
        origin: cylinder.origin,
        axis: cylinder.axis,
        radius: cylinder.radius
      )
    case .analytic(let surface):
      switch surface {
      case .plane(let origin, let normal):
        return try planePolynomial(line: line, origin: origin, normal: normal, tolerance: tolerance)
      case .cylinder(let origin, let axis, let radius):
        return cylinderPolynomial(line: line, origin: origin, axis: axis, radius: radius)
      case .cone(let apex, let axis, let halfAngle):
        return conePolynomial(line: line, apex: apex, axis: axis, halfAngle: halfAngle)
      case .sphere(let center, let radius):
        let offset = line.origin - center
        return [
          offset.dot(offset) - radius * radius,
          2.0 * offset.dot(line.direction),
          line.direction.dot(line.direction),
        ]
      case .torus(let center, let axis, let majorRadius, let minorRadius):
        return torusPolynomial(
          line: line,
          center: center,
          axis: axis,
          majorRadius: majorRadius,
          minorRadius: minorRadius
        )
      }
    case .bSpline:
      return nil
    case .procedural(.offset(let offset)):
      guard
        let equivalent = try offset.exactChartPreservingSurface(
          tolerance: tolerance
        )
      else {
        return nil
      }
      return try implicitPolynomial(
        line: line,
        surface: equivalent,
        tolerance: tolerance
      )
    case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalImage), .procedural(.originalAffineWord), .procedural(.originalAngularTransport), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
      return nil
    }
  }

  private func planePolynomial(
    line: Line3D,
    origin: Point3D,
    normal: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> [Double] {
    let constant = (line.origin - origin).dot(normal)
    let linear = line.direction.dot(normal)
    if abs(constant) <= tolerance.distance,
      abs(linear) <= tolerance.angle
    {
      throw KernelError(
        phase: .geometry,
        code: .nonDiscreteIntersection,
        residual: abs(constant),
        tolerance: tolerance,
        message: "Curve and surface are coincident; the intersection is not a discrete point set."
      )
    }
    return [constant, linear]
  }

  private func cylinderPolynomial(
    line: Line3D,
    origin: Point3D,
    axis: Vector3D,
    radius: Double
  ) -> [Double] {
    let offset = line.origin - origin
    let axialPoint = offset.dot(axis)
    let axialDirection = line.direction.dot(axis)
    let radialPoint = offset - axis * axialPoint
    let radialDirection = line.direction - axis * axialDirection
    return [
      radialPoint.dot(radialPoint) - radius * radius,
      2.0 * radialPoint.dot(radialDirection),
      radialDirection.dot(radialDirection),
    ]
  }

  private func conePolynomial(
    line: Line3D,
    apex: Point3D,
    axis: Vector3D,
    halfAngle: Double
  ) -> [Double] {
    let offset = line.origin - apex
    let axialPoint = offset.dot(axis)
    let axialDirection = line.direction.dot(axis)
    let radialPoint = offset - axis * axialPoint
    let radialDirection = line.direction - axis * axialDirection
    let tangentSquared = pow(tan(halfAngle), 2.0)
    return [
      radialPoint.dot(radialPoint) - axialPoint * axialPoint * tangentSquared,
      2.0 * (radialPoint.dot(radialDirection) - axialPoint * axialDirection * tangentSquared),
      radialDirection.dot(radialDirection) - axialDirection * axialDirection * tangentSquared,
    ]
  }

  private func torusPolynomial(
    line: Line3D,
    center: Point3D,
    axis: Vector3D,
    majorRadius: Double,
    minorRadius: Double
  ) -> [Double] {
    let offset = line.origin - center
    let directionSquared = line.direction.dot(line.direction)
    let pointDirection = offset.dot(line.direction)
    let pointSquared = offset.dot(offset)
    let axialPoint = offset.dot(axis)
    let axialDirection = line.direction.dot(axis)
    let q0 = pointSquared + majorRadius * majorRadius - minorRadius * minorRadius
    let q1 = 2.0 * pointDirection
    let q2 = directionSquared
    let radial0 = pointSquared - axialPoint * axialPoint
    let radial1 = 2.0 * (pointDirection - axialPoint * axialDirection)
    let radial2 = directionSquared - axialDirection * axialDirection
    let majorFactor = 4.0 * majorRadius * majorRadius
    return [
      q0 * q0 - majorFactor * radial0,
      2.0 * q0 * q1 - majorFactor * radial1,
      q1 * q1 + 2.0 * q0 * q2 - majorFactor * radial2,
      2.0 * q1 * q2,
      q2 * q2,
    ]
  }

  private func closedFormLineIntersections(
    line: Line3D,
    curve: Curve3D,
    surface: Surface3D,
    coefficients: [Double],
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection] {
    let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
    if coefficients.allSatisfy({ abs($0) <= coefficientScale * tolerance.angle }) {
      throw KernelError(
        phase: .geometry,
        code: .nonDiscreteIntersection,
        tolerance: tolerance,
        message:
          "Curve and surface share a continuous intersection; a discrete point set cannot represent it."
      )
    }
    let solver = try RealPolynomialRootSolver(
      rootTolerance: max(tolerance.distance * 0.001, Double.ulpOfOne * 64.0),
      residualTolerance: max(tolerance.angle * 0.001, Double.ulpOfOne * 64.0)
    )
    let roots = try solver.realRoots(coefficients: coefficients, using: &execution)
    var results: [CurveSurfaceIntersection] = []
    for parameter in roots {
      try execution.consumeWork(1)
      if let range = options.curveRange,
        range.contains(parameter) == false
      {
        continue
      }
      guard try curve.parameterDomain.contains(parameter, tolerance: tolerance) else {
        continue
      }
      let point = line.origin + line.direction * parameter
      let surfaceParameter = try surface.parameterProjection(of: point, tolerance: tolerance)
      guard contains(surfaceParameter.u, range: options.surfaceURange),
        contains(surfaceParameter.v, range: options.surfaceVRange),
        try surface.uDomain.contains(surfaceParameter.u, tolerance: tolerance),
        try surface.vDomain.contains(surfaceParameter.v, tolerance: tolerance)
      else {
        continue
      }
      let surfacePoint = try surface.point(
        u: surfaceParameter.u,
        v: surfaceParameter.v,
        tolerance: tolerance
      )
      let residual = (point - surfacePoint).length
      guard residual <= tolerance.distance else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          residual: residual,
          tolerance: tolerance,
          message: "Closed-form curve-surface intersection failed residual verification."
        )
      }
      let normal = try surfaceNormalResolver.normal(
        at: point,
        on: surface,
        u: surfaceParameter.u,
        v: surfaceParameter.v,
        tolerance: tolerance, using: &execution
      )
      let kind: CurveSurfaceIntersectionKind =
        abs(line.direction.dot(normal)) <= tolerance.angle
        ? .tangent
        : .transverse
      results.append(
        try CurveSurfaceIntersection(
          point: point,
          curveParameter: parameter,
          surfaceU: surfaceParameter.u,
          surfaceV: surfaceParameter.v,
          kind: kind,
          residual: residual,
          iterations: 0
        ))
    }
    return deduplicated(results, tolerance: tolerance)
  }

  private func certifiedSurfaceLiftAnalyticIntersections(
    lift: SurfaceLiftCurve3D?,
    certifiedCurve: CertifiedIntersectionCurve3D? = nil,
    planeTorusCurve: CertifiedPlaneTorusIntersectionCurve? = nil,
    curve: Curve3D,
    surface: Surface3D,
    canonicalSurface: CanonicalAnalyticSurface,
    curveRange: ScalarInterval,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> [CurveSurfaceIntersection] {
    let bounder = SurfaceLiftDifferentialBounder()
    let breaks: [Double]
    if let lift {
      let supportSurface = CanonicalAnalyticSurface(lift.surface)
      guard lift.surface != surface,
        try representDifferentLoci(
          supportSurface,
          canonicalSurface,
          tolerance: tolerance
        )
      else {
        throw KernelError(
          phase: .geometry,
          code: .nonDiscreteIntersection,
          tolerance: tolerance,
          message: "A surface-lift curve lies continuously on its target support surface."
        )
      }
      breaks = try bounder.breakParameters(
        lift: lift,
        within: curveRange,
        tolerance: tolerance
      )
    } else if let certifiedCurve {
      breaks = certifiedCurve.structuralBreakParameters(
        within: curveRange
      )
    } else if planeTorusCurve != nil {
      // A certified plane-torus branch is smooth over its normalized
      // parameterization, so no structural break parameters exist.
      breaks = []
    } else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Structural curve root isolation requires a certified differential source."
      )
    }
    let partition = [curveRange.lower] + breaks + [curveRange.upper]
    var pending: [ScalarRootCell] = []
    for index in 1..<partition.count {
      try execution.consumeWork(1)
      let interval = try ScalarInterval(
        lower: partition[index - 1],
        upper: partition[index]
      )
      let secondDerivativeBound: Double
      if let lift {
        guard
          let bound = try bounder.secondDerivativeMagnitude(
            lift: lift,
            interval: interval,
            tolerance: tolerance
          )
        else {
          throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message:
              "A certified surface-lift representation requires its structural curve root solver."
          )
        }
        secondDerivativeBound = bound
      } else if let certifiedCurve {
        secondDerivativeBound =
          try certifiedCurve
          .spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: interval.lower,
            toNormalizedFraction: interval.upper,
            tolerance: tolerance
          ).second
      } else if let planeTorusCurve {
        // The curve parameter is the major angle in [0, 2π], while
        // the certified bounds take normalized fractions; the bounds
        // themselves are stated against the angle parameter, so only
        // the arguments rescale. A span lifted past the periodic
        // seam maps to a wrapped fraction pair, which the bounds
        // union across the seam.
        let period = 2.0 * Double.pi
        var lowerFraction = interval.lower / period
        var upperFraction = interval.upper / period
        if lowerFraction > 1.0 {
          lowerFraction -= 1.0
        }
        if upperFraction > 1.0 {
          upperFraction -= 1.0
        }
        secondDerivativeBound =
          try planeTorusCurve
          .spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            tolerance: tolerance
          ).second
      } else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Structural curve root isolation lost its certified differential source."
        )
      }
      pending.append(
        ScalarRootCell(
          interval: interval,
          depth: 0,
          secondDerivativeBound: secondDerivativeBound
        ))
    }
    var remainingCells = options.maximumSubdivisionCells
    var intersections: [CurveSurfaceIntersection] = []
    var unresolved: [UnresolvedScalarRootCandidate] = []
    while let cell = pending.popLast() {
      try execution.visitGeometricCell(depth: cell.depth)
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Certified surface-lift root isolation exceeded its cell budget."
        )
      }
      remainingCells -= 1
      let curveBounds: BoundingBox3D
      if cell.interval.width
        > max(tolerance.angle, tolerance.distance)
      {
        curveBounds = try bounds(
          curve: curve,
          interval: cell.interval,
          tolerance: tolerance,
        using: &execution)
      } else {
        curveBounds = try differentialCurveBounds(
          curve: curve,
          interval: cell.interval,
          secondDerivativeBound: cell.secondDerivativeBound,
          tolerance: tolerance
        )
      }
      let position = try intervalVector(curveBounds)
      let functionRange = try implicitRange(
        position: position,
        surface: canonicalSurface
      )
      guard containsZero(functionRange) else { continue }
      let refinedRanges = try surfaceLiftImplicitRanges(
        curve: curve,
        position: position,
        surface: canonicalSurface,
        interval: cell.interval,
        secondDerivativeBound: cell.secondDerivativeBound,
        tolerance: tolerance
      )
      guard containsZero(refinedRanges.value) else { continue }
      let certificate = try scalarRootCertificate(
        curve: curve,
        surface: canonicalSurface,
        interval: cell.interval,
        derivative: refinedRanges.derivative,
        tolerance: tolerance
      )
      switch certificate {
      case .excluded:
        continue
      case .unique(let rootInterval):
        guard
          let intersection = try refinedAnalyticSurfaceIntersection(
            curve: curve,
            surface: surface,
            canonicalSurface: canonicalSurface,
            rootInterval: rootInterval,
            polishingRange: curveRange,
            options: options,
            tolerance: tolerance,
          using: &execution)
        else { continue }
        intersections.append(intersection)
      case .unresolved:
        // Splitting a tangency band multiplies leaf cells by the
        // band-to-leaf width ratio, so a cell whose spatial extent
        // is already far below the tolerance hands over to the
        // stationary-point band absorption instead of splitting;
        // the threshold stays below the exclusion scale a strict
        // near-miss needs, so separated bands still resolve by
        // value bounds first.
        let spatialExtent = max(
          curveBounds.maximum.x - curveBounds.minimum.x,
          max(
            curveBounds.maximum.y - curveBounds.minimum.y,
            curveBounds.maximum.z - curveBounds.minimum.z
          )
        )
        guard cell.depth < options.maximumSubdivisionDepth,
          spatialExtent > tolerance.distance / 64.0
        else {
          let stationary = try refinedStationaryParameter(
            curve: curve,
            surface: canonicalSurface,
            interval: cell.interval,
            searchInterval: curveRange,
            maximumIterations: options.maximumIterations,
            tolerance: tolerance,
          using: &execution)
          let stationaryTolerance = max(
            tolerance.relative,
            Double.ulpOfOne
              * max(
                abs(stationary.parameter),
                1.0
              ) * 256.0
          )
          // Neighboring leaf cells inside one tangency band all
          // converge to the same stationary parameter; the first
          // resolved tangent accounts for the whole band.
          if intersections.contains(where: { intersection in
            intersection.kind == .tangent
              && abs(
                intersection.curveParameter
                  - stationary.parameter
              ) <= stationaryTolerance
          }) {
            continue
          }
          let geometry = try curve.differentialGeometry(
            at: stationary.parameter,
            tolerance: tolerance
          )
          let implicit =
            try implicitDifferentialEvaluator
            .differential(
              at: geometry.position,
              on: canonicalSurface
            )
          let incidence = abs(
            implicit.gradient.dot(geometry.firstDerivative)
          )
          let scale = max(
            implicit.gradient.length * geometry.firstDerivative.length,
            Double.leastNonzeroMagnitude
          )
          let distanceResidual =
            abs(implicit.value)
            / max(
              implicit.gradient.length,
              Double.leastNonzeroMagnitude
            )
          if distanceResidual <= tolerance.distance,
            incidence <= tolerance.angle * scale
          {
            if let intersection =
              try tangentIntersectionResolver
              .intersection(
                curve: curve,
                surface: surface,
                parameter: stationary.parameter,
                options: options,
                iterations: stationary.iterations,
                tolerance: tolerance
              )
            {
              intersections.append(intersection)
            }
            continue
          }
          unresolved.append(
            UnresolvedScalarRootCandidate(
              interval: cell.interval,
              residual: min(
                abs(refinedRanges.value.lower),
                abs(refinedRanges.value.upper)
              ),
              secondDerivativeBound: cell.secondDerivativeBound
            ))
          continue
        }
        let midpoint = cell.interval.midpoint
        pending.append(
          ScalarRootCell(
            interval: try ScalarInterval(
              lower: midpoint,
              upper: cell.interval.upper
            ),
            depth: cell.depth + 1,
            secondDerivativeBound: cell.secondDerivativeBound
          ))
        pending.append(
          ScalarRootCell(
            interval: try ScalarInterval(
              lower: cell.interval.lower,
              upper: midpoint
            ),
            depth: cell.depth + 1,
            secondDerivativeBound: cell.secondDerivativeBound
          ))
      }
    }
    let result = deduplicated(intersections, tolerance: tolerance)
    let parameterTolerance = max(
      tolerance.relative,
      Double.ulpOfOne
        * max(
          max(abs(curveRange.lower), abs(curveRange.upper)),
          1.0
        ) * 256.0
    )
    var unaccounted: [UnresolvedScalarRootCandidate] = []
    for candidate in unresolved {
      try execution.consumeWork(1)
      let parameterAccounted = result.contains { intersection in
        intersection.curveParameter
          >= candidate.interval.lower - parameterTolerance
          && intersection.curveParameter
            <= candidate.interval.upper + parameterTolerance
      }
      if parameterAccounted {
        continue
      }
      let centerGeometry = try curve.differentialGeometry(
        at: candidate.interval.midpoint,
        tolerance: tolerance
      )
      let halfWidth = (candidate.interval.width * 0.5).nextUp
      let spatialRadius =
        (centerGeometry.firstDerivative.length * halfWidth
        + 0.5 * candidate.secondDerivativeBound
        * halfWidth * halfWidth).nextUp
      let spatiallyAccounted = result.contains { intersection in
        guard intersection.kind == .tangent else { return false }
        return
          ((centerGeometry.position - intersection.point).length
          + spatialRadius).nextUp <= tolerance.distance
      }
      if spatiallyAccounted == false {
        unaccounted.append(candidate)
      }
    }
    if let candidate = unaccounted.min(by: {
      $0.residual < $1.residual
    }) {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        residual: candidate.residual,
        tolerance: tolerance,
        message: "Surface-lift root isolation exceeded its subdivision depth."
      )
    }
    return result
  }

  private func differentialCurveBounds(
    curve: Curve3D,
    validatedCurve: ValidatedCurve3D? = nil,
    interval: ScalarInterval,
    secondDerivativeBound: Double,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    let admitted = try validatedCurve ?? ValidatedCurve3D(curve, tolerance: tolerance)
    let geometry = try admitted.differentialGeometry(at: interval.midpoint)
    let halfWidth = (interval.width * 0.5).nextUp
    let arithmeticEnvelope =
      (Double.ulpOfOne
      * max(
        (geometry.position - .origin).length,
        geometry.firstDerivative.length,
        secondDerivativeBound,
        1.0
      )
      * 65_536.0).nextUp
    let radius =
      (geometry.firstDerivative.length * halfWidth
      + 0.5 * secondDerivativeBound * halfWidth * halfWidth
      + arithmeticEnvelope).nextUp
    guard radius.isFinite, radius >= 0.0 else {
      throw intervalArithmeticFailure()
    }
    return try BoundingBox3D(
      minimum: Point3D(
        x: (geometry.position.x - radius).nextDown,
        y: (geometry.position.y - radius).nextDown,
        z: (geometry.position.z - radius).nextDown
      ),
      maximum: Point3D(
        x: (geometry.position.x + radius).nextUp,
        y: (geometry.position.y + radius).nextUp,
        z: (geometry.position.z + radius).nextUp
      )
    )
  }

  private func surfaceLiftImplicitRanges(
    curve: Curve3D,
    position: IntervalVector3,
    surface: CanonicalAnalyticSurface,
    interval: ScalarInterval,
    secondDerivativeBound: Double,
    tolerance: ModelingTolerance
  ) throws -> (value: ScalarInterval, derivative: ScalarInterval) {
    if case .plane(let plane) = surface {
      let geometry = try curve.differentialGeometry(
        at: interval.midpoint,
        tolerance: tolerance
      )
      let relative = geometry.position - plane.origin
      let centerValue = relative.dot(plane.normal)
      let centerDerivative = geometry.firstDerivative.dot(plane.normal)
      let halfWidth = (interval.width * 0.5).nextUp
      let normalLength = plane.normal.length.nextUp
      let derivativeRadius = (normalLength * secondDerivativeBound * halfWidth).nextUp
      let arithmeticEnvelope =
        (Double.ulpOfOne
        * max(
          abs(centerValue),
          (geometry.position - .origin).length * normalLength,
          1.0
        )
        * 65_536.0).nextUp
      let valueRadius =
        (abs(centerDerivative) * halfWidth
        + 0.5 * normalLength * secondDerivativeBound
        * halfWidth * halfWidth
        + arithmeticEnvelope).nextUp
      return (
        value: try outwardInterval([
          centerValue - valueRadius,
          centerValue + valueRadius,
        ]),
        derivative: try outwardInterval([
          centerDerivative - derivativeRadius,
          centerDerivative + derivativeRadius,
        ])
      )
    }
    let derivative = try curveDerivativeRange(
      curve: curve,
      interval: interval,
      secondDerivativeBound: secondDerivativeBound,
      tolerance: tolerance
    )
    let gradient = try implicitGradientRange(
      position: position,
      surface: surface
    )
    return (
      value: try implicitRange(position: position, surface: surface),
      derivative: try dot(gradient, derivative)
    )
  }

  private func refinedStationaryParameter(
    curve: Curve3D,
    surface: CanonicalAnalyticSurface,
    interval: ScalarInterval,
    searchInterval: ScalarInterval,
    maximumIterations: Int,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> (parameter: Double, iterations: Int) {
    var parameter = interval.midpoint
    var iterations = 0
    for iteration in 0..<maximumIterations {
      try execution.consumeWork(1)
      iterations = iteration + 1
      let geometry = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      let implicit = try implicitDifferentialEvaluator.differential(
        at: geometry.position,
        on: surface
      )
      let firstDerivative = implicit.gradient.dot(
        geometry.firstDerivative
      )
      let secondDerivative =
        try implicitDifferentialEvaluator
        .curveSecondDerivative(
          geometry: geometry,
          implicitGradient: implicit.gradient,
          surface: surface
        )
      let derivativeFloor = max(
        Double.ulpOfOne * 256.0 * max(abs(firstDerivative), 1.0),
        Double.leastNonzeroMagnitude
      )
      guard secondDerivative.isFinite,
        abs(secondDerivative) > derivativeFloor
      else {
        break
      }
      // The stationary point of a tangential contact usually lies
      // outside the leaf cell that triggered the refinement, so the
      // Newton step is clamped to the full isolation range rather than
      // the leaf interval.
      let candidate = min(
        max(
          parameter - firstDerivative / secondDerivative,
          searchInterval.lower
        ),
        searchInterval.upper
      )
      guard candidate.isFinite else { break }
      let parameterTolerance = max(
        tolerance.relative,
        Double.ulpOfOne * max(abs(parameter), 1.0) * 256.0
      )
      if abs(candidate - parameter) <= parameterTolerance {
        parameter = candidate
        break
      }
      parameter = candidate
    }
    return (parameter, iterations)
  }

  private func representDifferentLoci(
    _ first: CanonicalAnalyticSurface,
    _ second: CanonicalAnalyticSurface,
    tolerance: ModelingTolerance
  ) throws -> Bool {
    switch (first, second) {
    case (.plane(let lhs), .plane(let rhs)):
      let lhsNormal = try lhs.normal.normalized(
        tolerance: tolerance.distance
      )
      let rhsNormal = try rhs.normal.normalized(
        tolerance: tolerance.distance
      )
      let parallel =
        abs(lhsNormal.dot(rhsNormal))
        >= 1.0 - tolerance.angle
      let separation = abs((rhs.origin - lhs.origin).dot(lhsNormal))
      return parallel == false || separation > tolerance.distance
    case (.cylinder(let lhs), .cylinder(let rhs)):
      return try axesRepresentDifferentLines(
        lhsOrigin: lhs.origin,
        lhsAxis: lhs.axis,
        rhsOrigin: rhs.origin,
        rhsAxis: rhs.axis,
        tolerance: tolerance
      ) || abs(lhs.radius - rhs.radius) > tolerance.distance
    case (.cone(let lhs), .cone(let rhs)):
      let lhsAxis = try lhs.axis.normalized(tolerance: tolerance.distance)
      let rhsAxis = try rhs.axis.normalized(tolerance: tolerance.distance)
      return lhs.apex.isApproximatelyEqual(
        to: rhs.apex,
        tolerance: tolerance.distance
      ) == false
        || abs(lhsAxis.dot(rhsAxis)) < 1.0 - tolerance.angle
        || abs(lhs.halfAngle - rhs.halfAngle) > tolerance.angle
    case (.sphere(let lhs), .sphere(let rhs)):
      return lhs.center.isApproximatelyEqual(
        to: rhs.center,
        tolerance: tolerance.distance
      ) == false
        || abs(lhs.radius - rhs.radius) > tolerance.distance
    case (.torus(let lhs), .torus(let rhs)):
      let lhsAxis = try lhs.axis.normalized(tolerance: tolerance.distance)
      let rhsAxis = try rhs.axis.normalized(tolerance: tolerance.distance)
      return lhs.center.isApproximatelyEqual(
        to: rhs.center,
        tolerance: tolerance.distance
      ) == false
        || abs(lhsAxis.dot(rhsAxis)) < 1.0 - tolerance.angle
        || abs(lhs.majorRadius - rhs.majorRadius) > tolerance.distance
        || abs(lhs.minorRadius - rhs.minorRadius) > tolerance.distance
    case (.unsupported, _), (_, .unsupported):
      return true
    default:
      return true
    }
  }

  private func axesRepresentDifferentLines(
    lhsOrigin: Point3D,
    lhsAxis: Vector3D,
    rhsOrigin: Point3D,
    rhsAxis: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> Bool {
    let lhsDirection = try lhsAxis.normalized(tolerance: tolerance.distance)
    let rhsDirection = try rhsAxis.normalized(tolerance: tolerance.distance)
    guard abs(lhsDirection.dot(rhsDirection)) >= 1.0 - tolerance.angle else {
      return true
    }
    let offset = rhsOrigin - lhsOrigin
    let perpendicular = offset - lhsDirection * offset.dot(lhsDirection)
    return perpendicular.length > tolerance.distance
  }

  private func scalarRootCertificate(
    curve: Curve3D,
    surface: CanonicalAnalyticSurface,
    interval: ScalarInterval,
    derivative: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> ScalarRootCertificate {
    guard excludesZero(derivative) else { return .unresolved }
    let lowerValue = try implicitDifferentialEvaluator.differential(
      at: curve.point(at: interval.lower, tolerance: tolerance),
      on: surface
    ).value
    let upperValue = try implicitDifferentialEvaluator.differential(
      at: curve.point(at: interval.upper, tolerance: tolerance),
      on: surface
    ).value
    let lowerRange = try constantInterval(lowerValue)
    let upperRange = try constantInterval(upperValue)
    if hasStrictSameSign(lowerRange, upperRange) {
      return .excluded
    }
    if containsZero(lowerRange) || containsZero(upperRange)
      || haveOppositeSigns(lowerRange, upperRange)
    {
      return .unique(interval)
    }
    let midpointValue = try implicitDifferentialEvaluator.differential(
      at: curve.point(at: interval.midpoint, tolerance: tolerance),
      on: surface
    ).value
    let quotient = try divided(
      constantInterval(midpointValue),
      by: derivative
    )
    let newton = try added(
      constantInterval(interval.midpoint),
      scaled(quotient, by: -1.0)
    )
    guard let contraction = try intersection(interval, newton) else {
      return .excluded
    }
    let margin = max(
      tolerance.relative,
      Double.ulpOfOne
        * max(max(abs(interval.lower), abs(interval.upper)), 1.0)
        * 256.0
    )
    if contraction.lower > interval.lower + margin,
      contraction.upper < interval.upper - margin
    {
      return .unique(contraction)
    }
    return .unresolved
  }

  private func refinedAnalyticSurfaceIntersection(
    curve: Curve3D,
    surface: Surface3D,
    canonicalSurface: CanonicalAnalyticSurface,
    rootInterval: ScalarInterval,
    polishingRange: ScalarInterval,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> CurveSurfaceIntersection? {
    var parameter = rootInterval.midpoint
    var iterations = 0
    for iteration in 0..<options.maximumIterations {
      try execution.consumeWork(1)
      iterations = iteration + 1
      let geometry = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      let implicit = try implicitDifferentialEvaluator.differential(
        at: geometry.position,
        on: canonicalSurface
      )
      let derivative = implicit.gradient.dot(geometry.firstDerivative)
      let derivativeFloor = max(
        implicit.gradient.length * geometry.firstDerivative.length
          * Double.ulpOfOne * 256.0,
        Double.leastNonzeroMagnitude
      )
      guard derivative.isFinite, abs(derivative) > derivativeFloor else {
        break
      }
      let next = min(
        max(parameter - implicit.value / derivative, rootInterval.lower),
        rootInterval.upper
      )
      if abs(next - parameter)
        <= max(
          tolerance.relative,
          Double.ulpOfOne * max(abs(parameter), 1.0) * 256.0
        )
      {
        parameter = next
        break
      }
      parameter = next
    }
    let curveGeometry = try curve.differentialGeometry(
      at: parameter,
      tolerance: tolerance
    )
    let projection = try surface.parameterProjection(
      of: curveGeometry.position,
      tolerance: tolerance
    )
    let rangeResolver = SurfaceParameterRangeResolver()
    guard
      let surfaceU = rangeResolver.resolvedParameter(
        projection.u,
        domain: surface.uDomain,
        requestedRange: options.surfaceURange,
        tolerance: tolerance
      ),
      let surfaceV = rangeResolver.resolvedParameter(
        projection.v,
        domain: surface.vDomain,
        requestedRange: options.surfaceVRange,
        tolerance: tolerance
      )
    else { return nil }
    let surfaceGeometry = try surface.differentialGeometry(
      u: surfaceU,
      v: surfaceV,
      tolerance: tolerance
    )
    guard projection.residual <= tolerance.distance else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: projection.residual,
        tolerance: tolerance,
        message: "A certified surface-lift root failed geometric residual verification."
      )
    }
    let kind: CurveSurfaceIntersectionKind =
      abs(
        curveGeometry.tangent.dot(surfaceGeometry.normal)
      ) <= tolerance.angle ? .tangent : .transverse
    let verified = try CurveSurfaceIntersection(
      point: curveGeometry.position,
      curveParameter: parameter,
      surfaceU: surfaceU,
      surfaceV: surfaceV,
      kind: kind,
      residual: projection.residual,
      iterations: iterations
    )
    if kind == .transverse {
      return try polishedAnalyticSurfaceTangency(
        seed: ParameterSeed(t: parameter, u: surfaceU, v: surfaceV),
        initialIterations: iterations,
        curve: curve,
        surface: surface,
        canonicalSurface: canonicalSurface,
        curveRange: polishingRange,
        options: options,
        tolerance: tolerance,
      using: &execution) ?? verified
    }
    return verified
  }

  private func curveDerivativeRange(
    curve: Curve3D,
    validatedCurve: ValidatedCurve3D? = nil,
    interval: ScalarInterval,
    secondDerivativeBound: Double,
    tolerance: ModelingTolerance
  ) throws -> IntervalVector3 {
    let admitted = try validatedCurve ?? ValidatedCurve3D(curve, tolerance: tolerance)
    let derivative = try admitted.differentialGeometry(at: interval.midpoint).firstDerivative
    let radius = (secondDerivativeBound * interval.width * 0.5).nextUp
    return try IntervalVector3(
      x: outwardInterval([derivative.x - radius, derivative.x + radius]),
      y: outwardInterval([derivative.y - radius, derivative.y + radius]),
      z: outwardInterval([derivative.z - radius, derivative.z + radius])
    )
  }

  private func implicitRange(
    position: IntervalVector3,
    surface: CanonicalAnalyticSurface
  ) throws -> ScalarInterval {
    switch surface {
    case .plane(let plane):
      return try dot(
        subtracting(position, constantVector(plane.origin)),
        plane.normal
      )
    case .cylinder(let cylinder):
      let relative = try subtracting(position, constantVector(cylinder.origin))
      let axial = try dot(relative, cylinder.axis)
      let radial = try subtracting(relative, scaled(cylinder.axis, by: axial))
      return try added(
        squaredLength(radial),
        constantInterval(-cylinder.radius * cylinder.radius)
      )
    case .cone(let cone):
      let relative = try subtracting(position, constantVector(cone.apex))
      let axial = try dot(relative, cone.axis)
      let radial = try subtracting(relative, scaled(cone.axis, by: axial))
      return try added(
        squaredLength(radial),
        scaled(multiplied(axial, axial), by: -pow(tan(cone.halfAngle), 2.0))
      )
    case .sphere(let sphere):
      let relative = try subtracting(position, constantVector(sphere.center))
      return try added(
        squaredLength(relative),
        constantInterval(-sphere.radius * sphere.radius)
      )
    case .torus(let torus):
      let relative = try subtracting(position, constantVector(torus.center))
      let axial = try dot(relative, torus.axis)
      let radial = try subtracting(relative, scaled(torus.axis, by: axial))
      let radialSquared = try squaredLength(radial)
      let distanceSquared = try squaredLength(relative)
      let quadratic = try added(
        distanceSquared,
        constantInterval(
          torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        )
      )
      return try added(
        multiplied(quadratic, quadratic),
        scaled(
          radialSquared,
          by: -4.0 * torus.majorRadius * torus.majorRadius
        )
      )
    case .unsupported:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: nil,
        message: "Implicit interval evaluation requires an analytic target surface."
      )
    }
  }

  private func implicitGradientRange(
    position: IntervalVector3,
    surface: CanonicalAnalyticSurface
  ) throws -> IntervalVector3 {
    switch surface {
    case .plane(let plane):
      return try constantVector(plane.normal)
    case .cylinder(let cylinder):
      let relative = try subtracting(position, constantVector(cylinder.origin))
      let axial = try dot(relative, cylinder.axis)
      let radial = try subtracting(relative, scaled(cylinder.axis, by: axial))
      return try scaled(radial, by: 2.0)
    case .cone(let cone):
      let relative = try subtracting(position, constantVector(cone.apex))
      let axial = try dot(relative, cone.axis)
      let radial = try subtracting(relative, scaled(cone.axis, by: axial))
      return try subtracting(
        scaled(radial, by: 2.0),
        scaled(
          cone.axis,
          by: scaled(
            axial,
            by: 2.0 * pow(tan(cone.halfAngle), 2.0)
          )
        )
      )
    case .sphere(let sphere):
      return try scaled(
        subtracting(position, constantVector(sphere.center)),
        by: 2.0
      )
    case .torus(let torus):
      let relative = try subtracting(position, constantVector(torus.center))
      let axial = try dot(relative, torus.axis)
      let radial = try subtracting(relative, scaled(torus.axis, by: axial))
      let quadratic = try added(
        squaredLength(relative),
        constantInterval(
          torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        )
      )
      return try subtracting(
        scaled(relative, by: scaled(quadratic, by: 4.0)),
        scaled(radial, by: 8.0 * torus.majorRadius * torus.majorRadius)
      )
    case .unsupported:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: nil,
        message: "Implicit gradient evaluation requires an analytic target surface."
      )
    }
  }

  private func adaptiveIntersections(curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection] {
    let curveRange = try resolvedInterval(domain: curve.parameterDomain,
      explicit: options.curveRange, label: "curve", tolerance: tolerance)
    let uRange = try resolvedInterval(domain: surface.uDomain,
      explicit: options.surfaceURange, label: "surface U", tolerance: tolerance)
    let vRange = try resolvedInterval(domain: surface.vDomain,
      explicit: options.surfaceVRange, label: "surface V", tolerance: tolerance)
    return try selectedAdaptiveIntersections(curve: curve, surface: surface,
      root: ParameterCell(t: curveRange, u: uRange, v: vRange, depth: 0),
      options: options, tolerance: tolerance, using: &execution)
  }

  private func selectedAdaptiveIntersections(
    curve: Curve3D, surface: Surface3D, root: ParameterCell,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection] {
    let curveSource = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    let surfaceSource = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    let certification = try parametricRootCertifier.prepare(preparedCurve: curveSource,
      preparedSurface: surfaceSource, domain: ParametricCurveSurfaceRootCell(curve: root.t,
        surfaceU: root.u, surfaceV: root.v, surfacePatches: [], depth: root.depth),
      tolerance: tolerance, using: &execution)
    let maximumDepth = min(options.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    let stackCapacity = maximumDepth.addingReportingOverflow(1)
    guard !stackCapacity.overflow else { throw ExactScalarFailure.countOverflow }
    try reserve(count: stackCapacity.partialValue, stride: MemoryLayout<ParameterCell>.stride, using: &execution)
    var pending: [ParameterCell] = []
    pending.reserveCapacity(stackCapacity.partialValue)
    pending.append(root)
    struct Accepted {
      var cell: ParameterCell
      var intersection: CurveSurfaceIntersection
    }
    try reserve(count: options.maximumCandidateCount, stride: MemoryLayout<Accepted>.stride, using: &execution)
    var accepted: [Accepted] = []
    accepted.reserveCapacity(options.maximumCandidateCount)
    var remainingCells = options.maximumSubdivisionCells
    while let cell = pending.popLast() {
      try execution.visitGeometricCell(depth: cell.depth)
      guard remainingCells > 0 else { throw selectedCoverageFailure(tolerance) }
      remainingCells -= 1
      let curveJet = try selectedCurveJet(curveSource, over: cell.t, depth: cell.depth,
        tolerance: tolerance, using: &execution)
      let surfaceJet = try selectedSurfaceJet(surfaceSource,
        over: SurfaceParameterBox(u: cell.u, v: cell.v), depth: cell.depth,
        tolerance: tolerance, using: &execution)
      let curveBounds = try BoundingBox3D(
        minimum: Point3D(x: curveJet.x.value.lower, y: curveJet.y.value.lower, z: curveJet.z.value.lower),
        maximum: Point3D(x: curveJet.x.value.upper, y: curveJet.y.value.upper, z: curveJet.z.value.upper))
      let surfaceBounds = try BoundingBox3D(
        minimum: Point3D(x: surfaceJet.x.value.lower, y: surfaceJet.y.value.lower, z: surfaceJet.z.value.lower),
        maximum: Point3D(x: surfaceJet.x.value.upper, y: surfaceJet.y.value.upper, z: surfaceJet.z.value.upper))
      guard curveBounds.intersects(surfaceBounds, tolerance: tolerance.distance) else { continue }
      let originalCell = ParametricCurveSurfaceRootCell(curve: cell.t, surfaceU: cell.u,
        surfaceV: cell.v, surfacePatches: [], depth: cell.depth)
      let certificate = try certification.certificate(cell: originalCell, tolerance: tolerance, using: &execution)
      if case .excluded = certificate { continue }
      var intersection: CurveSurfaceIntersection?
      if case .unique = certificate {
        intersection = try selectedRefinedIntersection(curveSource: curveSource,
          surfaceSource: surfaceSource, cell: cell, maximumIterations: options.maximumIterations,
          tolerance: tolerance, using: &execution)
      } else if cell.depth == maximumDepth {
        if let proposal = try selectedRefinedIntersection(curveSource: curveSource,
          surfaceSource: surfaceSource, cell: cell, maximumIterations: options.maximumIterations,
          tolerance: tolerance, using: &execution),
          case .unique = try certification.boundaryCertificate(cell: originalCell,
            witness: proposal, tolerance: tolerance, using: &execution) {
          intersection = proposal
        }
      }
      if let intersection {
        var merged = false
        for index in accepted.indices {
          try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
          let existing = accepted[index]
          let hull = ParameterCell(
            t: try ScalarInterval(lower: min(existing.cell.t.lower, cell.t.lower),
              upper: max(existing.cell.t.upper, cell.t.upper)),
            u: try ScalarInterval(lower: min(existing.cell.u.lower, cell.u.lower),
              upper: max(existing.cell.u.upper, cell.u.upper)),
            v: try ScalarInterval(lower: min(existing.cell.v.lower, cell.v.lower),
              upper: max(existing.cell.v.upper, cell.v.upper)),
            depth: min(existing.cell.depth, cell.depth))
          let enclosing = ParametricCurveSurfaceRootCell(curve: hull.t, surfaceU: hull.u,
            surfaceV: hull.v, surfacePatches: [], depth: hull.depth)
          // Only a proof covering both original cells establishes shared root identity.
          let shared = try certification.certificate(cell: enclosing, tolerance: tolerance, using: &execution)
          var sameRoot = false
          if case .unique = shared { sameRoot = true }
          if !sameRoot, case .unique = try certification.boundaryCertificate(cell: enclosing,
            witness: intersection, tolerance: tolerance, using: &execution) { sameRoot = true }
          if sameRoot {
            accepted[index].cell = hull
            if intersection.residual < existing.intersection.residual {
              accepted[index].intersection = intersection
            }
            merged = true
            break
          }
        }
        if !merged {
          guard accepted.count < options.maximumCandidateCount else {
            throw selectedCoverageFailure(tolerance)
          }
          accepted.append(Accepted(cell: cell, intersection: intersection))
        }
        continue
      }
      guard cell.depth < maximumDepth else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): The selected original curve-surface
        // route has no critical/coincident atlas for a cell lacking exclusion or
        // uniqueness. Such a cell must not be absorbed by numerical root proximity.
        throw selectedCoverageFailure(tolerance)
      }
      let derivative = try CurveSpatialDerivativeRange(
        x: ScalarInterval(lower: curveJet.x.derivativeU.lower, upper: curveJet.x.derivativeU.upper),
        y: ScalarInterval(lower: curveJet.y.derivativeU.lower, upper: curveJet.y.derivativeU.upper),
        z: ScalarInterval(lower: curveJet.z.derivativeU.lower, upper: curveJet.z.derivativeU.upper))
      try reserve(count: 2, stride: MemoryLayout<ParameterCell>.stride, using: &execution)
      let children = try subdivided(cell, root: root, curveBounds: curveBounds,
        curveDerivative: derivative, surfaceBounds: surfaceBounds)
      for child in children.reversed() {
        try execution.admitGeometricDepth(child.depth); try execution.consumeWork(1)
        guard child.t.lower < child.t.upper, child.u.lower < child.u.upper,
          child.v.lower < child.v.upper,
          child.t != cell.t || child.u != cell.u || child.v != cell.v else {
          throw selectedCoverageFailure(tolerance)
        }
        pending.append(child)
      }
    }
    // Stable insertion order is caller-paid and requires no sorting scratch buffer.
    for index in accepted.indices.dropFirst() {
      var position = index
      while position > 0 {
        try execution.consumeWork(1)
        let left = accepted[position - 1].intersection
        let right = accepted[position].intersection
        let ordered = left.curveParameter < right.curveParameter
          || (left.curveParameter == right.curveParameter && (left.surfaceU < right.surfaceU
            || (left.surfaceU == right.surfaceU && left.surfaceV <= right.surfaceV)))
        if ordered { break }
        accepted.swapAt(position - 1, position)
        position -= 1
      }
    }
    try reserve(count: accepted.count, stride: MemoryLayout<CurveSurfaceIntersection>.stride, using: &execution)
    var result: [CurveSurfaceIntersection] = []
    result.reserveCapacity(accepted.count)
    for value in accepted {
      try execution.consumeWork(1)
      result.append(value.intersection)
    }
    return result
  }



  private func selectedNativePlaneIntersections(curve: BSplineCurve3D, plane: Plane3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection] {
    guard curve.degree <= options.maximumPolynomialDegree else {
      throw selectedCoverageFailure(tolerance)
    }
    let interval = try selectedNativePlaneRange(source: curve, options: options, tolerance: tolerance)
    let contacts = try OriginalNativePlaneContactProducer().contacts(source: curve,
      over: interval, plane: plane, tolerance: tolerance, using: &execution)
    guard contacts.isolated.count <= options.maximumCandidateCount else {
      throw selectedCoverageFailure(tolerance)
    }
    let surface = try PreparedSurfaceDifferentialEncloser(surface: .plane(plane), tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    try reserve(count: options.maximumCandidateCount, stride: MemoryLayout<CurveSurfaceIntersection>.stride, using: &execution)
    var result: [CurveSurfaceIntersection] = []
    result.reserveCapacity(options.maximumCandidateCount)
    try reserve(count: options.maximumCandidateCount,
      stride: MemoryLayout<OriginalNativePlaneContactProducer.Isolated>.stride, using: &execution)
    var originalEvents: [OriginalNativePlaneContactProducer.Isolated] = []
    originalEvents.reserveCapacity(options.maximumCandidateCount)
    func retain(_ contact: OriginalNativePlaneContactProducer.Isolated) throws {
      for index in originalEvents.indices {
        try execution.consumeWork(1)
        if let merged = try originalEvents[index].mergingNativeKnotEvent(contact, using: &execution) {
          originalEvents[index] = merged
          return
        }
      }
      guard originalEvents.count < options.maximumCandidateCount else { throw selectedCoverageFailure(tolerance) }
      originalEvents.append(contact)
    }
    func publish(_ contact: OriginalNativePlaneContactProducer.Isolated) throws {
      guard let event = try publishOriginalNativePlaneContact(contact, preparedPlane: surface,
        options: options, tolerance: tolerance, using: &execution) else { return }
      guard result.count < options.maximumCandidateCount else { throw selectedCoverageFailure(tolerance) }
      result.append(event)
    }
    for overlap in contacts.overlaps {
      try execution.consumeWork(1)
      let clip = try overlap.clipped(uRange: options.surfaceURange,
        vRange: options.surfaceVRange, using: &execution)
      guard !clip.hasPositiveContact else {
        throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
          message: "The original native curve has a positive interval inside the selected plane domain.")
      }
      for contact in clip.isolated { try retain(contact) }
    }
    for contact in contacts.isolated { try retain(contact) }
    for contact in originalEvents { try publish(contact) }
    for index in result.indices.dropFirst() {
      var position = index
      while position > 0 {
        try execution.consumeWork(1)
        if result[position - 1].curveParameter <= result[position].curveParameter { break }
        result.swapAt(position - 1, position)
        position -= 1
      }
    }
    // Native owners are part of root identity; identical numerical stations do
    // not authorize merging a discontinuous join's original sided contacts.
    return result
  }

  /// Publishes a representative of the retained original root under the same paid plane preparation.
  // FIXME(INCOMPLETE_IMPLEMENTATION): Public native-plane and richer overlap
  // routes retain exact original root events here. Native-knot sided assembly
  // uses its original scalar/jet issuer before publication. General critical,
  // periodic and translated-source event authority remains required; numerical
  // event proximity never substitutes for the original contact proof.
  package func publishOriginalNativePlaneContact(_ contact: OriginalNativePlaneContactProducer.Isolated,
    preparedPlane: PreparedSurfaceDifferentialEncloser, options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveSurfaceIntersection? {
    try options.validate(tolerance: tolerance)
    try execution.consumeWork(1)
    guard case .plane(let plane) = preparedPlane.surface, plane.uDirection != nil else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original native-plane publication requires its retained authored plane preparation.")
    }
    guard let issuedU = contact.originalPlane.uDirection, let suppliedU = plane.uDirection else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original native-plane publication lost its issuing chart.")
    }
    func same(_ first: Double, _ second: Double) throws -> Bool {
      try execution.consumeWork(1)
      return first == second
    }
    guard try same(contact.originalPlane.origin.x, plane.origin.x)
      && same(contact.originalPlane.origin.y, plane.origin.y)
      && same(contact.originalPlane.origin.z, plane.origin.z)
      && same(contact.originalPlane.normal.x, plane.normal.x)
      && same(contact.originalPlane.normal.y, plane.normal.y)
      && same(contact.originalPlane.normal.z, plane.normal.z)
      && same(issuedU.x, suppliedU.x) && same(issuedU.y, suppliedU.y) && same(issuedU.z, suppliedU.z) else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original native-plane publication rejects a foreign issuing plane preparation.")
    }
    let interval = try selectedNativePlaneRange(source: contact.boundary.source,
      options: options, tolerance: tolerance)
    guard try contact.liesIn(uRange: options.surfaceURange, vRange: options.surfaceVRange,
      maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, usage: &execution) else { return nil }
    // Localization width is a proposal only. Halved endpoint arithmetic avoids
    // overflow for a finite interval crossing the full binary coordinate range.
    var width = max(Double.leastNonzeroMagnitude, interval.upper * 0.5 - interval.lower * 0.5)
    for iteration in 0..<options.maximumIterations {
      try execution.consumeWork(1)
      guard width.isFinite, width > 0 else { throw selectedCoverageFailure(tolerance) }
      let native = try contact.boundary.parameterBounds(maximumWidth: width,
        maximumSubdivisionDepth: execution.effectiveLimits.maximumValueDepth, usage: &execution)
      let position = try contact.boundary.positionBounds(maximumParameterWidth: width,
        maximumSubdivisionDepth: execution.effectiveLimits.maximumValueDepth, usage: &execution)
      let uv = try contact.planeParameterBounds(maximumParameterWidth: width,
        maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, usage: &execution)
      let uRange = options.surfaceURange ?? uv.u
      let vRange = options.surfaceVRange ?? uv.v
      let u = clamped(uv.u.lower * 0.5 + uv.u.upper * 0.5, to: uRange)
      let v = clamped(uv.v.lower * 0.5 + uv.v.upper * 0.5, to: vRange)
      let jet = try selectedSurfaceJet(preparedPlane,
        over: SurfaceParameterBox(u: ScalarInterval(lower: u, upper: u),
          v: ScalarInterval(lower: v, upper: v)), depth: 0, tolerance: tolerance, using: &execution)
      let point = Point3D(x: position.x.lower * 0.5 + position.x.upper * 0.5,
        y: position.y.lower * 0.5 + position.y.upper * 0.5,
        z: position.z.lower * 0.5 + position.z.upper * 0.5)
      let radius = IntervalVector3DBounds(x: position.x - .exact(point.x),
        y: position.y - .exact(point.y), z: position.z - .exact(point.z)).lengthUpperBound
      let residual = IntervalVector3DBounds(x: position.x - jet.x.value,
        y: position.y - jet.y.value, z: position.z - jet.z.value).lengthUpperBound
      if radius <= tolerance.distance, residual <= tolerance.distance {
        return try CurveSurfaceIntersection(point: point,
          curveParameter: clamped(native.lower * 0.5 + native.upper * 0.5, to: interval),
          surfaceU: u, surfaceV: v, kind: contact.kind, residual: residual, iterations: iteration,
          originalCurveBoundary: contact.boundary)
      }
      let smaller = width * 0.5
      guard smaller > 0, smaller < width else { throw selectedCoverageFailure(tolerance) }
      width = smaller
    }
    throw selectedCoverageFailure(tolerance)
  }

  private func selectedNativePlaneRange(source: BSplineCurve3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> ScalarInterval {
    let range: ScalarInterval
    if let requested = options.curveRange { range = requested }
    else {
      switch source.domain {
      case .closed(let lower, let upper): range = try ScalarInterval(lower: lower, upper: upper)
      case .periodic(let period): range = try ScalarInterval(lower: 0, upper: period)
      case .unbounded:
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message: "Original native-plane contacts require a finite authored curve range.")
      }
    }
    guard range.lower.isFinite, range.upper.isFinite, range.lower < range.upper else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original native-plane range requires finite ordered positive endpoints.")
    }
    return range
  }

  private func selectedCurveJet(_ source: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval, depth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntervalVectorJet {
    let receipt = try source.closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: execution.effectiveLimits.maximumSpans,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth - depth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
    guard let first = receipt.spans.first else { throw intervalArithmeticFailure() }
    var jet = first.jet
    for span in receipt.spans.dropFirst() {
      try execution.admitGeometricDepth(depth); try execution.consumeWork(1)
      jet = jet.union(span.jet)
    }
    return jet
  }

  private func selectedSurfaceJet(_ source: PreparedSurfaceDifferentialEncloser,
    over parameters: SurfaceParameterBox, depth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntervalVectorJet {
    try source.intervalJet(overClosedBox: parameters, tolerance: tolerance,
      maximumSpanCount: execution.effectiveLimits.maximumSpans,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth - depth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
  }

  private func selectedResidualUpperBound(_ curve: SurfaceIntervalVectorJet,
    _ surface: SurfaceIntervalVectorJet
  ) throws -> Double {
    let x = curve.x.value - surface.x.value
    let y = curve.y.value - surface.y.value
    let z = curve.z.value - surface.z.value
    let bx = OutwardScalarInterval.exact(max(abs(x.lower), abs(x.upper)))
    let by = OutwardScalarInterval.exact(max(abs(y.lower), abs(y.upper)))
    let bz = OutwardScalarInterval.exact(max(abs(z.lower), abs(z.upper)))
    let squared = bx * bx + by * by + bz * bz
    guard squared.isFinite, squared.upper >= 0 else { throw intervalArithmeticFailure() }
    let result = sqrt(squared.upper).nextUp
    guard result.isFinite else { throw intervalArithmeticFailure() }
    return result
  }

  private func selectedIntersectionKind(_ curve: SurfaceIntervalVectorJet,
    _ surface: SurfaceIntervalVectorJet, tolerance: ModelingTolerance
  ) throws -> CurveSurfaceIntersectionKind {
    let tx = curve.x.derivativeU, ty = curve.y.derivativeU, tz = curve.z.derivativeU
    let nx = surface.y.derivativeU * surface.z.derivativeV - surface.z.derivativeU * surface.y.derivativeV
    let ny = surface.z.derivativeU * surface.x.derivativeV - surface.x.derivativeU * surface.z.derivativeV
    let nz = surface.x.derivativeU * surface.y.derivativeV - surface.y.derivativeU * surface.x.derivativeV
    func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
      let minimum = value.excludesZero ? min(abs(value.lower), abs(value.upper)) : 0
      let maximum = max(abs(value.lower), abs(value.upper))
      return .init(lower: max(0, (minimum * minimum).nextDown), upper: (maximum * maximum).nextUp)
    }
    let tangentSquared = square(tx) + square(ty) + square(tz)
    let normalSquared = square(nx) + square(ny) + square(nz)
    guard tangentSquared.isFinite, normalSquared.isFinite,
      tangentSquared.lower > 0, normalSquared.lower > 0 else { return .mixed }
    let denominator = OutwardScalarInterval(
      lower: (sqrt(tangentSquared.lower).nextDown * sqrt(normalSquared.lower).nextDown).nextDown,
      upper: (sqrt(tangentSquared.upper).nextUp * sqrt(normalSquared.upper).nextUp).nextUp)
    guard let cosine = (tx * nx + ty * ny + tz * nz).divided(by: denominator), cosine.isFinite else {
      throw intervalArithmeticFailure()
    }
    let upper = max(abs(cosine.lower), abs(cosine.upper))
    let lower = cosine.excludesZero ? min(abs(cosine.lower), abs(cosine.upper)) : 0
    if upper <= tolerance.angle { return .tangent }
    if lower > tolerance.angle { return .transverse }
    return .mixed
  }

  private func selectedRefinedIntersection(
    curveSource: PreparedCurveDifferentialEncloser,
    surfaceSource: PreparedSurfaceDifferentialEncloser, cell: ParameterCell,
    maximumIterations: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveSurfaceIntersection? {
    var current = ParameterSeed(t: cell.t.midpoint, u: cell.u.midpoint, v: cell.v.midpoint)
    for iteration in 0...maximumIterations {
      try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
      let curve = try selectedCurveJet(curveSource,
        over: ScalarInterval(lower: current.t, upper: current.t), depth: cell.depth,
        tolerance: tolerance, using: &execution)
      let surface = try selectedSurfaceJet(surfaceSource,
        over: SurfaceParameterBox(u: ScalarInterval(lower: current.u, upper: current.u),
          v: ScalarInterval(lower: current.v, upper: current.v)), depth: cell.depth,
        tolerance: tolerance, using: &execution)
      let residual = try selectedResidualUpperBound(curve, surface)
      if residual <= tolerance.distance {
        return try CurveSurfaceIntersection(
          point: Point3D(x: curve.x.value.midpoint, y: curve.y.value.midpoint, z: curve.z.value.midpoint),
          curveParameter: current.t, surfaceU: current.u, surfaceV: current.v,
          kind: selectedIntersectionKind(curve, surface, tolerance: tolerance),
          residual: residual, iterations: iteration)
      }
      guard iteration < maximumIterations else { return nil }
      let columnT = Vector3D(x: curve.x.derivativeU.midpoint,
        y: curve.y.derivativeU.midpoint, z: curve.z.derivativeU.midpoint)
      let columnU = Vector3D(x: -surface.x.derivativeU.midpoint,
        y: -surface.y.derivativeU.midpoint, z: -surface.z.derivativeU.midpoint)
      let columnV = Vector3D(x: -surface.x.derivativeV.midpoint,
        y: -surface.y.derivativeV.midpoint, z: -surface.z.derivativeV.midpoint)
      let right = Vector3D(x: surface.x.value.midpoint - curve.x.value.midpoint,
        y: surface.y.value.midpoint - curve.y.value.midpoint,
        z: surface.z.value.midpoint - curve.z.value.midpoint)
      let d = determinant(columnT, columnU, columnV)
      guard d.isFinite, d != 0 else { return nil }
      let dt = determinant(right, columnU, columnV) / d
      let du = determinant(columnT, right, columnV) / d
      let dv = determinant(columnT, columnU, right) / d
      guard dt.isFinite, du.isFinite, dv.isFinite else { return nil }
      var scale = 1.0
      var next: ParameterSeed?
      while scale >= 1.0 / 128.0 {
        try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
        let candidate = ParameterSeed(t: clamped(current.t + dt * scale, to: cell.t),
          u: clamped(current.u + du * scale, to: cell.u), v: clamped(current.v + dv * scale, to: cell.v))
        let c = try selectedCurveJet(curveSource,
          over: ScalarInterval(lower: candidate.t, upper: candidate.t), depth: cell.depth,
          tolerance: tolerance, using: &execution)
        let s = try selectedSurfaceJet(surfaceSource,
          over: SurfaceParameterBox(u: ScalarInterval(lower: candidate.u, upper: candidate.u),
            v: ScalarInterval(lower: candidate.v, upper: candidate.v)), depth: cell.depth,
          tolerance: tolerance, using: &execution)
        if try selectedResidualUpperBound(c, s) < residual { next = candidate; break }
        scale *= 0.5
      }
      guard let next else { return nil }
      current = next
    }
    return nil
  }

  private func selectedCoverageFailure(_ tolerance: ModelingTolerance) -> KernelError {
    KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
      message: "Original curve-surface cells require complete exclusion or unique root certification within caller admission.")
  }

















  private func contains(
    _ value: Double,
    lower: Double,
    upper: Double,
    tolerance: Double
  ) -> Bool {
    value >= lower - tolerance && value <= upper + tolerance
  }



  private func resolvedInterval(
    domain: ParameterDomain,
    explicit: ScalarInterval?,
    label: String,
    tolerance: ModelingTolerance
  ) throws -> ScalarInterval {
      let range: ScalarInterval
      if let explicit { range = explicit }
      else {
        switch domain {
        case .closed(let lower, let upper): range = try ScalarInterval(lower: lower, upper: upper)
        case .periodic(let period): range = try ScalarInterval(lower: 0, upper: period)
        case .unbounded:
          // FIXME(INCOMPLETE_IMPLEMENTATION): Selected original queries cannot
          // infer complete unbounded coverage from numerical target projections.
          // A complete original range issuer is required for implicit ranges.
          throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Selected original intersection requires an explicit finite \(label) range.")
        }
      }
      guard range.lower.isFinite, range.upper.isFinite, range.lower < range.upper else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message: "Selected intersection ranges require finite ordered positive endpoints.")
      }
      return range
  }

  private func bounds(
    curve: Curve3D,
    interval: ScalarInterval,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
    if case .bSpline(let curve) = curve {
      let patches = try BSplineCurveBezierDecomposer().curvePatches(
        curve: curve,
        intersecting: interval,
        tolerance: tolerance, using: &execution
      )
      let points = try patches.flatMap { patch -> [Point3D] in
        let lower = max(interval.lower, patch.lower)
        let upper = min(interval.upper, patch.upper)
        guard upper > lower else { return [] }
        return try patch.trimmed(
          from: lower,
          to: upper,
          tolerance: tolerance
        , using: &execution).controlPoints
      }
      guard points.isEmpty == false else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          tolerance: tolerance,
          message: "B-spline curve bounds found no Bezier span intersecting the parameter cell."
        )
      }
      return try BoundingBox3D(points: points)
        .expanded(by: tolerance.distance)
    }
    if case .implicit(let curve) = curve {
      return try curve.boundingBox(
        fromNormalizedFraction: interval.lower,
        toNormalizedFraction: interval.upper,
        tolerance: tolerance
      )
    }
    if case .surfaceLift(let lift) = curve {
      return try surfaceLiftBounds(
        lift,
        interval: interval,
        tolerance: tolerance,
      using: &execution)
    }
    if case .rigidImage(let image) = curve {
      let sourceBounds = try bounds(
        curve: image.source,
        interval: interval,
        tolerance: tolerance,
      using: &execution)
      return try BoundingBox3D(
        points: boundingBoxCorners(sourceBounds).map(
          image.transform.applying(to:)
        )
      )
    }
    if case .originalAffineWord(let image) = curve {
      let sourceBounds = try bounds(curve: image.source, interval: interval, tolerance: tolerance, using: &execution)
      let original = IntervalVector3DBounds(x: .init(lower: sourceBounds.minimum.x, upper: sourceBounds.maximum.x),
        y: .init(lower: sourceBounds.minimum.y, upper: sourceBounds.maximum.y),
        z: .init(lower: sourceBounds.minimum.z, upper: sourceBounds.maximum.z))
      let mapped = try OriginalAffineWordJetTransport.position(image.preparedWord, bounds: original,
        using: &execution)
      return try .init(minimum: .init(x: mapped.x.lower, y: mapped.y.lower, z: mapped.z.lower),
        maximum: .init(x: mapped.x.upper, y: mapped.y.upper, z: mapped.z.upper))
    }
    if case .affineImage(let image) = curve {
      let sourceBounds = try bounds(
        curve: image.source,
        interval: interval,
        tolerance: tolerance,
      using: &execution)
      return try BoundingBox3D(
        points: boundingBoxCorners(sourceBounds).map(
          image.transform.applying(to:)
        )
      )
    }
    let derivativeBound: Double
    switch curve {
    case .line(let line):
      derivativeBound = line.direction.length
    case .circle(let circle):
      derivativeBound = circle.radius
    case .analytic(let curve):
      switch curve {
      case .line(_, let direction):
        derivativeBound = direction.length
      case .circle(_, _, let radius), .arc(_, _, let radius, _, _):
        derivativeBound = radius
      case .ellipse(_, _, _, let majorRadius, _):
        derivativeBound = majorRadius
      case .hyperbola(let hyperbola):
        let maximumMagnitude = max(abs(interval.lower), abs(interval.upper))
        derivativeBound = hypot(
          hyperbola.transverseRadius * sinh(maximumMagnitude),
          hyperbola.conjugateRadius * cosh(maximumMagnitude)
        )
      case .parabola(let parabola):
        let maximumMagnitude = max(abs(interval.lower), abs(interval.upper))
        derivativeBound = hypot(
          1.0,
          maximumMagnitude / (2.0 * parabola.focalLength)
        )
      case .planeTorus(let planeTorus):
        return try planeTorus.boundingBox(tolerance: tolerance)
      }
    case .certifiedIntersection(let certified):
      let differentialBounds =
        try certified
        .spatialDifferentialMagnitudeBounds(
          fromNormalizedFraction: interval.lower,
          toNormalizedFraction: interval.upper,
          tolerance: tolerance
        )
      let center = try curve.point(
        at: interval.midpoint,
        tolerance: tolerance
      )
      return try isotropicBounds(
        center: center,
        radius: differentialBounds.first
          * interval.width * 0.5
          + tolerance.distance,
        tolerance: tolerance
      )
    case .bSpline, .implicit, .surfaceLift, .rigidImage, .affineImage, .parameterImage, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "B-spline curve interval bounds failed to use the control hull."
      )
    }
    let center = try curve.point(at: interval.midpoint, tolerance: tolerance)
    return try isotropicBounds(
      center: center,
      radius: derivativeBound * interval.width * 0.5 + tolerance.distance,
      tolerance: tolerance
    )
  }

  private func boundingBoxCorners(_ box: BoundingBox3D) -> [Point3D] {
    [
      Point3D(x: box.minimum.x, y: box.minimum.y, z: box.minimum.z),
      Point3D(x: box.maximum.x, y: box.minimum.y, z: box.minimum.z),
      Point3D(x: box.minimum.x, y: box.maximum.y, z: box.minimum.z),
      Point3D(x: box.maximum.x, y: box.maximum.y, z: box.minimum.z),
      Point3D(x: box.minimum.x, y: box.minimum.y, z: box.maximum.z),
      Point3D(x: box.maximum.x, y: box.minimum.y, z: box.maximum.z),
      Point3D(x: box.minimum.x, y: box.maximum.y, z: box.maximum.z),
      Point3D(x: box.maximum.x, y: box.maximum.y, z: box.maximum.z),
    ]
  }

  private func surfaceLiftBounds(
    _ lift: SurfaceLiftCurve3D,
    interval: ScalarInterval,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
    let parameterCurve = try lift.parameterCurve.subcurve(
      fromNormalizedFraction: interval.lower,
      toNormalizedFraction: interval.upper,
      tolerance: tolerance
    )
    switch parameterCurve {
    case .originalImage, .originalAffineWord:
      return try SurfaceLiftCurve3D(surface: lift.surface, parameterCurve: parameterCurve)
        .boundingBox(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance)

    case .certifiedImplicit(let curve):
      return try curve.intersection.boundingBox(
        fromNormalizedFraction: min(curve.startFraction, curve.endFraction),
        toNormalizedFraction: max(curve.startFraction, curve.endFraction),
        tolerance: tolerance
      )
    case .certifiedAnalyticImplicit(let curve):
      return try curve.intersection.implicitCurve.boundingBox(
        fromNormalizedFraction: min(curve.startFraction, curve.endFraction),
        toNormalizedFraction: max(curve.startFraction, curve.endFraction),
        tolerance: tolerance
      )
    case .certifiedAnalyticPair(let curve):
      if curve.hasSpatialDifferentialMagnitudeBounds {
        let differentialBounds =
          try curve
          .spatialDifferentialMagnitudeBounds(
            tolerance: tolerance
          )
        let center = try curve.modelSpaceDifferential(
          atNormalizedFraction: 0.5,
          tolerance: tolerance
        ).position
        return try isotropicBounds(
          center: center,
          radius: differentialBounds.first * 0.5
            + curve.intersection.maximumResidualUpperBound
            + tolerance.distance,
          tolerance: tolerance
        )
      }
      return try curve.intersection.boundingBox(tolerance: tolerance)
    case .originalBSplineContinuation:
      break
    case .projectedAnalytic(let curve):
      return try bounds(
        curve: curve.curve,
        interval: ScalarInterval(
          lower: min(curve.startParameter, curve.endParameter),
          upper: max(curve.startParameter, curve.endParameter)
        ),
        tolerance: tolerance,
      using: &execution)
    case .sphericalGreatCircle(let cosine, let sine, let startParameter, let endParameter):
      return try sphericalGreatCircleBounds(
        surface: lift.surface,
        cosine: cosine,
        sine: sine,
        parameter: ScalarInterval(
          lower: min(startParameter, endParameter),
          upper: max(startParameter, endParameter)
        ),
        tolerance: tolerance,
      using: &execution)
    case .rigidImage(let image):
      let sourceBounds = try surfaceLiftBounds(
        image.source,
        interval: try ScalarInterval(
          lower: min(image.startFraction, image.endFraction),
          upper: max(image.startFraction, image.endFraction)
        ),
        tolerance: tolerance,
      using: &execution)
      return try BoundingBox3D(
        points: boundingBoxCorners(sourceBounds).map(image.transform.applying(to:))
      ).expanded(by: tolerance.distance)
    case .offsetSurfaceImage:
      break
    case .periodicTranslation(let base, _, _):
      return try surfaceLiftBounds(
        SurfaceLiftCurve3D(
          surface: lift.surface,
          parameterCurve: base
        ),
        interval: try ScalarInterval(lower: 0.0, upper: 1.0),
        tolerance: tolerance,
      using: &execution)
    case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
      break
    }
    if case .bSpline = lift.surface {
      guard
        let localized = try SurfaceLiftDifferentialBounder()
          .bSplineSupportBounds(
            lift: lift,
            interval: interval,
            tolerance: tolerance
          )
      else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "A B-spline surface lift requires a locally bounded parameter curve."
        )
      }
      return localized
    }
    return try surfaceBounds(
      surface: lift.surface,
      parameters: surfaceParameterBounds(
        parameterCurve,
        tolerance: tolerance,
      using: &execution),
      tolerance: tolerance
    )
  }

  private func surfaceParameterBounds(
    _ curve: SurfaceParameterCurve,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBounds {
    switch curve {
    case .originalAffineWord(let image):
      guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) else {
        throw GeometryConversionError.invalidInput("Original word surface parameter bounds lost source derivative authority.")
      }
      return SurfaceParameterBounds(u: try ScalarInterval(lower: jet.u.value.lower, upper: jet.u.value.upper),
        v: try ScalarInterval(lower: jet.v.value.lower, upper: jet.v.value.upper))
    case .originalImage(let image):
      guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) else {
        throw GeometryConversionError.invalidInput("Original image surface parameter bounds lost source derivative authority.")
      }
      return SurfaceParameterBounds(u: try ScalarInterval(lower: jet.u.value.lower, upper: jet.u.value.upper),
        v: try ScalarInterval(lower: jet.v.value.lower, upper: jet.v.value.upper))

    case .affine, .constantU, .constantV:
      let endpoints = try [0.0, 1.0].map {
        try curve.parameter(
          atNormalizedFraction: $0,
          tolerance: tolerance
        )
      }
      return try parameterBounds(points: endpoints)
    case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
      let parameter = try ScalarInterval(
        lower: min(startParameter, endParameter),
        upper: max(startParameter, endParameter)
      )
      return SurfaceParameterBounds(
        u: try added(
          constantInterval(center.x),
          trigonometricRange(
            cosineCoefficient: cosine.x,
            sineCoefficient: sine.x,
            parameter: parameter,
          using: &execution)
        ),
        v: try added(
          constantInterval(center.y),
          trigonometricRange(
            cosineCoefficient: cosine.y,
            sineCoefficient: sine.y,
            parameter: parameter,
          using: &execution)
        )
      )
    case .polyline(let points):
      return try parameterBounds(points: points)
    case .originalBSplineContinuation(let curve):
      let jet = try curve.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance)
      return SurfaceParameterBounds(u: try ScalarInterval(lower: jet.u.value.lower, upper: jet.u.value.upper),
        v: try ScalarInterval(lower: jet.v.value.lower, upper: jet.v.value.upper))
    case .bSpline(let curve):
      return try parameterBounds(
        points: curve.controlPoints.map {
          SurfaceParameter(u: $0.x, v: $0.y)
        })
    case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
      .certifiedAnalyticPair, .projectedAnalytic, .rigidImage:
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A structurally certified surface-lift curve reached generic parameter bounds."
      )
    case .offsetSurfaceImage(let image):
      return try surfaceParameterBounds(
        image.source,
        tolerance: tolerance,
      using: &execution)
    case .periodicTranslation(let base, let uShift, let vShift):
      let bounds = try surfaceParameterBounds(
        base,
        tolerance: tolerance,
      using: &execution)
      return SurfaceParameterBounds(
        u: try ScalarInterval(
          lower: (bounds.u.lower + uShift).nextDown,
          upper: (bounds.u.upper + uShift).nextUp
        ),
        v: try ScalarInterval(
          lower: (bounds.v.lower + vShift).nextDown,
          upper: (bounds.v.upper + vShift).nextUp
        )
      )
    }
  }

  private func parameterBounds(
    points: [SurfaceParameter]
  ) throws -> SurfaceParameterBounds {
    guard points.isEmpty == false else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: nil,
        message: "Surface-parameter bounds require at least one point."
      )
    }
    return SurfaceParameterBounds(
      u: try outwardInterval(points.map({ $0.u })),
      v: try outwardInterval(points.map({ $0.v }))
    )
  }

  private func surfaceBounds(
    surface: Surface3D,
    parameters: SurfaceParameterBounds,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
      of: surface,
      over: SurfaceParameterBox(u: parameters.u, v: parameters.v),
      tolerance: tolerance
    ).position
    return try BoundingBox3D(
      minimum: Point3D(
        x: enclosure.x.lower,
        y: enclosure.y.lower,
        z: enclosure.z.lower
      ),
      maximum: Point3D(
        x: enclosure.x.upper,
        y: enclosure.y.upper,
        z: enclosure.z.upper
      )
    ).expanded(by: tolerance.distance)
  }

  private func sphericalGreatCircleBounds(
    surface: Surface3D,
    cosine: Vector3D,
    sine: Vector3D,
    parameter: ScalarInterval,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
    guard case .sphere(let sphere) = CanonicalAnalyticSurface(surface) else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A spherical great-circle lift requires an analytic sphere."
      )
    }
    var coordinates: [ScalarInterval] = []
    coordinates.reserveCapacity(3)
    for index in 0..<3 {
      try execution.consumeWork(1)
      coordinates.append(
        try added(
          constantInterval(component(sphere.center, index: index)),
          scaled(
            trigonometricRange(
              cosineCoefficient: component(cosine, index: index),
              sineCoefficient: component(sine, index: index),
              parameter: parameter,
            using: &execution),
            by: sphere.radius
          )
        ))
    }
    return try BoundingBox3D(
      minimum: Point3D(
        x: coordinates[0].lower,
        y: coordinates[1].lower,
        z: coordinates[2].lower
      ),
      maximum: Point3D(
        x: coordinates[0].upper,
        y: coordinates[1].upper,
        z: coordinates[2].upper
      )
    ).expanded(by: tolerance.distance)
  }

  private func trigonometricRange(
    cosineCoefficient: Double,
    sineCoefficient: Double,
    parameter: ScalarInterval,
  using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
    let amplitude = hypot(cosineCoefficient, sineCoefficient)
    guard amplitude.isFinite else {
      throw intervalArithmeticFailure()
    }
    let period = 2.0 * Double.pi
    if parameter.width >= period
      || max(abs(parameter.lower), abs(parameter.upper)) > 1.0e12
    {
      return try ScalarInterval(
        lower: (-amplitude).nextDown,
        upper: amplitude.nextUp
      )
    }
    var values = [
      cosineCoefficient * cos(parameter.lower)
        + sineCoefficient * sin(parameter.lower),
      cosineCoefficient * cos(parameter.upper)
        + sineCoefficient * sin(parameter.upper),
    ]
    let maximumParameter = atan2(sineCoefficient, cosineCoefficient)
    for base in [maximumParameter, maximumParameter + Double.pi] {
      try execution.consumeWork(1)
      let nearest = base + round((parameter.midpoint - base) / period) * period
      for candidate in [nearest - period, nearest, nearest + period]
      where candidate >= parameter.lower && candidate <= parameter.upper {
        values.append(
          cosineCoefficient * cos(candidate)
            + sineCoefficient * sin(candidate)
        )
      }
    }
    return try outwardInterval(values)
  }

  private func constantInterval(_ value: Double) throws -> ScalarInterval {
    try ScalarInterval(lower: value, upper: value)
  }

  private func added(
    _ first: ScalarInterval,
    _ second: ScalarInterval
  ) throws -> ScalarInterval {
    try outwardInterval([
      first.lower + second.lower,
      first.upper + second.upper,
    ])
  }

  private func multiplied(
    _ first: ScalarInterval,
    _ second: ScalarInterval
  ) throws -> ScalarInterval {
    try outwardInterval([
      first.lower * second.lower,
      first.lower * second.upper,
      first.upper * second.lower,
      first.upper * second.upper,
    ])
  }

  private func scaled(
    _ interval: ScalarInterval,
    by scale: Double
  ) throws -> ScalarInterval {
    let lower = interval.lower * scale
    let upper = interval.upper * scale
    return try outwardInterval([lower, upper])
  }

  private func outwardInterval(_ values: [Double]) throws -> ScalarInterval {
    guard let lower = values.min(),
      let upper = values.max(),
      lower.isFinite,
      upper.isFinite
    else {
      throw intervalArithmeticFailure()
    }
    return try ScalarInterval(
      lower: lower.nextDown,
      upper: upper.nextUp
    )
  }

  private func intervalVector(_ bounds: BoundingBox3D) throws -> IntervalVector3 {
    try IntervalVector3(
      x: ScalarInterval(lower: bounds.minimum.x, upper: bounds.maximum.x),
      y: ScalarInterval(lower: bounds.minimum.y, upper: bounds.maximum.y),
      z: ScalarInterval(lower: bounds.minimum.z, upper: bounds.maximum.z)
    )
  }

  private func constantVector(_ point: Point3D) throws -> IntervalVector3 {
    try IntervalVector3(
      x: constantInterval(point.x),
      y: constantInterval(point.y),
      z: constantInterval(point.z)
    )
  }

  private func constantVector(_ vector: Vector3D) throws -> IntervalVector3 {
    try IntervalVector3(
      x: constantInterval(vector.x),
      y: constantInterval(vector.y),
      z: constantInterval(vector.z)
    )
  }

  private func subtracting(
    _ first: IntervalVector3,
    _ second: IntervalVector3
  ) throws -> IntervalVector3 {
    try IntervalVector3(
      x: added(first.x, scaled(second.x, by: -1.0)),
      y: added(first.y, scaled(second.y, by: -1.0)),
      z: added(first.z, scaled(second.z, by: -1.0))
    )
  }

  private func scaled(
    _ vector: IntervalVector3,
    by scale: Double
  ) throws -> IntervalVector3 {
    try IntervalVector3(
      x: scaled(vector.x, by: scale),
      y: scaled(vector.y, by: scale),
      z: scaled(vector.z, by: scale)
    )
  }

  private func scaled(
    _ vector: IntervalVector3,
    by scale: ScalarInterval
  ) throws -> IntervalVector3 {
    try IntervalVector3(
      x: multiplied(vector.x, scale),
      y: multiplied(vector.y, scale),
      z: multiplied(vector.z, scale)
    )
  }

  private func scaled(
    _ vector: Vector3D,
    by scale: ScalarInterval
  ) throws -> IntervalVector3 {
    try IntervalVector3(
      x: scaled(scale, by: vector.x),
      y: scaled(scale, by: vector.y),
      z: scaled(scale, by: vector.z)
    )
  }

  private func dot(
    _ vector: IntervalVector3,
    _ fixed: Vector3D
  ) throws -> ScalarInterval {
    try added(
      scaled(vector.x, by: fixed.x),
      added(
        scaled(vector.y, by: fixed.y),
        scaled(vector.z, by: fixed.z)
      )
    )
  }

  private func dot(
    _ first: IntervalVector3,
    _ second: IntervalVector3
  ) throws -> ScalarInterval {
    try added(
      multiplied(first.x, second.x),
      added(
        multiplied(first.y, second.y),
        multiplied(first.z, second.z)
      )
    )
  }

  private func squaredLength(_ vector: IntervalVector3) throws -> ScalarInterval {
    try dot(vector, vector)
  }

  private func divided(
    _ numerator: ScalarInterval,
    by denominator: ScalarInterval
  ) throws -> ScalarInterval {
    guard excludesZero(denominator) else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        tolerance: nil,
        message: "Interval division requires a denominator bounded away from zero."
      )
    }
    let reciprocal = try outwardInterval([
      1.0 / denominator.lower,
      1.0 / denominator.upper,
    ])
    return try multiplied(numerator, reciprocal)
  }

  private func intersection(
    _ first: ScalarInterval,
    _ second: ScalarInterval
  ) throws -> ScalarInterval? {
    let lower = max(first.lower, second.lower)
    let upper = min(first.upper, second.upper)
    guard lower <= upper else { return nil }
    return try ScalarInterval(lower: lower, upper: upper)
  }

  private func containsZero(_ interval: ScalarInterval) -> Bool {
    interval.lower <= 0.0 && interval.upper >= 0.0
  }

  private func excludesZero(_ interval: ScalarInterval) -> Bool {
    interval.upper < 0.0 || interval.lower > 0.0
  }

  private func hasStrictSameSign(
    _ first: ScalarInterval,
    _ second: ScalarInterval
  ) -> Bool {
    (first.lower > 0.0 && second.lower > 0.0)
      || (first.upper < 0.0 && second.upper < 0.0)
  }

  private func haveOppositeSigns(
    _ first: ScalarInterval,
    _ second: ScalarInterval
  ) -> Bool {
    (first.upper < 0.0 && second.lower > 0.0)
      || (first.lower > 0.0 && second.upper < 0.0)
  }

  private func intervalArithmeticFailure() -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      tolerance: nil,
      message: "Surface-lift interval arithmetic exceeded finite representation."
    )
  }

  private func component(_ point: Point3D, index: Int) -> Double {
    switch index {
    case 0: point.x
    case 1: point.y
    default: point.z
    }
  }

  private func component(_ vector: Vector3D, index: Int) -> Double {
    switch index {
    case 0: vector.x
    case 1: vector.y
    default: vector.z
    }
  }

  private func isotropicBounds(
    center: Point3D,
    radius: Double,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    guard radius.isFinite, radius >= 0.0 else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: radius,
        tolerance: tolerance,
        message: "Curve-surface interval bounds produced an invalid radius."
      )
    }
    return try BoundingBox3D(
      minimum: Point3D(x: center.x - radius, y: center.y - radius, z: center.z - radius),
      maximum: Point3D(x: center.x + radius, y: center.y + radius, z: center.z + radius)
    )
  }

  private func subdivided(
    _ cell: ParameterCell,
    root: ParameterCell,
    curveBounds: BoundingBox3D,
    curveDerivative: CurveSpatialDerivativeRange,
    surfaceBounds: BoundingBox3D
  ) throws -> [ParameterCell] {
    let tScale = cell.t.width / root.t.width
    let uScale = cell.u.width / root.u.width
    let vScale = cell.v.width / root.v.width
    if tScale >= uScale, tScale >= vScale {
      let midpoint = cell.t.midpoint
      return [
        ParameterCell(
          t: try ScalarInterval(lower: cell.t.lower, upper: midpoint),
          u: cell.u,
          v: cell.v,
          depth: cell.depth + 1,
          secondDerivativeBound: cell.secondDerivativeBound,
          surfaceBounds: surfaceBounds
        ),
        ParameterCell(
          t: try ScalarInterval(lower: midpoint, upper: cell.t.upper),
          u: cell.u,
          v: cell.v,
          depth: cell.depth + 1,
          secondDerivativeBound: cell.secondDerivativeBound,
          surfaceBounds: surfaceBounds
        ),
      ]
    }
    if uScale >= vScale {
      let midpoint = cell.u.midpoint
      return [
        ParameterCell(
          t: cell.t,
          u: try ScalarInterval(lower: cell.u.lower, upper: midpoint),
          v: cell.v,
          depth: cell.depth + 1,
          secondDerivativeBound: cell.secondDerivativeBound,
          curveBounds: curveBounds,
          curveDerivative: curveDerivative
        ),
        ParameterCell(
          t: cell.t,
          u: try ScalarInterval(lower: midpoint, upper: cell.u.upper),
          v: cell.v,
          depth: cell.depth + 1,
          secondDerivativeBound: cell.secondDerivativeBound,
          curveBounds: curveBounds,
          curveDerivative: curveDerivative
        ),
      ]
    }
    let midpoint = cell.v.midpoint
    return [
      ParameterCell(
        t: cell.t,
        u: cell.u,
        v: try ScalarInterval(lower: cell.v.lower, upper: midpoint),
        depth: cell.depth + 1,
        secondDerivativeBound: cell.secondDerivativeBound,
        curveBounds: curveBounds,
        curveDerivative: curveDerivative
      ),
      ParameterCell(
        t: cell.t,
        u: cell.u,
        v: try ScalarInterval(lower: midpoint, upper: cell.v.upper),
        depth: cell.depth + 1,
        secondDerivativeBound: cell.secondDerivativeBound,
        curveBounds: curveBounds,
        curveDerivative: curveDerivative
      ),
    ]
  }







  private func polishedAnalyticSurfaceTangency(
    seed: ParameterSeed,
    initialIterations: Int,
    curve: Curve3D,
    surface: Surface3D,
    canonicalSurface: CanonicalAnalyticSurface,
    curveRange: ScalarInterval,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
  using execution: inout OriginalQueryExecution) throws -> CurveSurfaceIntersection? {
    var parameter = seed.t
    for iteration in 0..<16 {
      try execution.consumeWork(1)
      let geometry = try curve.differentialGeometry(
        at: parameter,
        tolerance: tolerance
      )
      let implicit = try implicitDifferentialEvaluator.differential(
        at: geometry.position,
        on: canonicalSurface
      )
      let gradientMagnitude = implicit.gradient.length
      let speed = geometry.firstDerivative.length
      guard gradientMagnitude > tolerance.relative,
        speed > tolerance.distance
      else {
        return nil
      }
      let incidence = implicit.gradient.dot(geometry.firstDerivative)
      let normalizedIncidence = abs(incidence) / (gradientMagnitude * speed)
      let secondDerivative =
        try implicitDifferentialEvaluator
        .curveSecondDerivative(
          geometry: geometry,
          implicitGradient: implicit.gradient,
          surface: canonicalSurface
        )
      let distanceResidual = abs(implicit.value) / gradientMagnitude
      if distanceResidual <= tolerance.distance,
        normalizedIncidence <= tolerance.angle
      {
        return try tangentIntersectionResolver.intersection(
          curve: curve,
          surface: surface,
          parameter: parameter,
          options: options,
          iterations: initialIterations + iteration,
          tolerance: tolerance
        )
      }

      let derivativeFloor = max(
        Double.ulpOfOne * 256.0 * max(abs(incidence), 1.0),
        Double.leastNonzeroMagnitude
      )
      guard secondDerivative.isFinite,
        abs(secondDerivative) > derivativeFloor
      else {
        return nil
      }
      let parameterStep = -incidence / secondDerivative
      guard parameterStep.isFinite else { return nil }

      var stepScale = 1.0
      var acceptedParameter: Double?
      while stepScale >= 1.0 / 128.0 {
        try execution.consumeWork(1)
        let candidateParameter = clamped(
          parameter + parameterStep * stepScale,
          to: curveRange
        )
        let candidateGeometry = try curve.differentialGeometry(
          at: candidateParameter,
          tolerance: tolerance
        )
        let candidateImplicit =
          try implicitDifferentialEvaluator
          .differential(
            at: candidateGeometry.position,
            on: canonicalSurface
          )
        let candidateScale =
          candidateImplicit.gradient.length
          * candidateGeometry.firstDerivative.length
        guard candidateScale > Double.leastNonzeroMagnitude else {
          stepScale *= 0.5
          continue
        }
        let candidateIncidence =
          abs(
            candidateImplicit.gradient.dot(
              candidateGeometry.firstDerivative
            )
          ) / candidateScale
        if candidateIncidence < normalizedIncidence {
          acceptedParameter = candidateParameter
          break
        }
        if candidateParameter == parameter {
          return nil
        }
        stepScale *= 0.5
      }
      guard let acceptedParameter,
        acceptedParameter != parameter
      else {
        return nil
      }
      parameter = acceptedParameter
    }
    return nil
  }



  private func contains(_ value: Double, range: ScalarInterval?) -> Bool {
    range?.contains(value) ?? true
  }

  private func normalizedPeriodicParameter(_ parameter: Double) -> Double {
    let period = 2.0 * Double.pi
    let remainder = parameter.truncatingRemainder(dividingBy: period)
    return remainder >= 0.0 ? remainder : remainder + period
  }

  private func determinant(_ first: Vector3D, _ second: Vector3D, _ third: Vector3D) -> Double {
    first.dot(second.cross(third))
  }

  private func clamped(_ value: Double, to interval: ScalarInterval) -> Double {
    min(max(value, interval.lower), interval.upper)
  }

  private func deduplicated(
    _ intersections: [CurveSurfaceIntersection],
    tolerance: ModelingTolerance
  ) -> [CurveSurfaceIntersection] {
    let sorted = intersections.sorted { lhs, rhs in
      if lhs.curveParameter != rhs.curveParameter {
        return lhs.curveParameter < rhs.curveParameter
      }
      if lhs.surfaceU != rhs.surfaceU {
        return lhs.surfaceU < rhs.surfaceU
      }
      return lhs.surfaceV < rhs.surfaceV
    }
    var result: [CurveSurfaceIntersection] = []
    for intersection in sorted {
      if let index = result.firstIndex(where: { existing in
        (existing.point - intersection.point).length <= tolerance.distance
          && abs(existing.curveParameter - intersection.curveParameter)
            <= max(tolerance.distance, tolerance.angle)
      }) {
        if intersection.residual < result[index].residual {
          result[index] = intersection
        }
      } else {
        result.append(intersection)
      }
    }
    return result
  }

  private struct ParameterCell: Sendable {
    let t: ScalarInterval
    let u: ScalarInterval
    let v: ScalarInterval
    let depth: Int
    let curveBounds: BoundingBox3D?
    let curveDerivative: CurveSpatialDerivativeRange?
    let surfaceBounds: BoundingBox3D?
    let secondDerivativeBound: Double?

    init(
      t: ScalarInterval,
      u: ScalarInterval,
      v: ScalarInterval,
      depth: Int,
      secondDerivativeBound: Double? = nil,
      curveBounds: BoundingBox3D? = nil,
      curveDerivative: CurveSpatialDerivativeRange? = nil,
      surfaceBounds: BoundingBox3D? = nil
    ) {
      self.t = t
      self.u = u
      self.v = v
      self.depth = depth
      self.curveBounds = curveBounds
      self.curveDerivative = curveDerivative
      self.surfaceBounds = surfaceBounds
      self.secondDerivativeBound = secondDerivativeBound
    }
  }

  private struct ParameterSeed: Sendable {
    let t: Double
    let u: Double
    let v: Double
  }

  private struct AdaptiveCandidate: Sendable {
    let seed: ParameterSeed
    let t: ScalarInterval
    let u: ScalarInterval
    let v: ScalarInterval
    let depth:Int
    let curveBounds: BoundingBox3D
    let surfaceBounds: BoundingBox3D
  }

  private struct DifferenceCell: Sendable {
    let patch: RationalBezierCurveSurfaceDifferencePatch
    let depth: Int
  }

  private struct UnresolvedDifferenceCandidate: Sendable {
    let patch: RationalBezierCurveSurfaceDifferencePatch
    let residual: Double
  }
  private func reserve(count: Int, stride: Int,
    using execution: inout OriginalQueryExecution) throws {
    let bytes = count.multipliedReportingOverflow(by: stride)
    guard count >= 0, stride >= 0 else { throw ExactScalarFailure.invalidSource }
    guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
    try execution.retainStorage(bytes: bytes.partialValue)
  }
}
