import Foundation
import CADCore

public struct DefaultCurveSurfaceIntersector: CurveSurfaceIntersecting {
    private let certifiedIntersectionCoincidenceResolver:
        any CertifiedIntersectionCoincidenceResolving
    private let certifiedIntersectionReductionIntersector:
        any CertifiedIntersectionReductionIntersecting
    private let certifiedIntersectionReductionResolver:
        any CertifiedIntersectionReductionResolving
    private let certifiedIntersectionSpatialDisjointnessResolver:
        any CertifiedIntersectionSpatialDisjointnessResolving
    private let parallelTorusTorusPlaneIntersector:
        any ParallelTorusTorusPlaneIntersecting
    private let coneCylinderSphereIntersector:
        any ConeCylinderSphereIntersecting
    private let coneCylinderConeIntersector:
        any ConeCylinderConeIntersecting
    private let coneHostedQuadricIntersector:
        any ConeHostedQuadricIntersecting
    private let cylinderCylinderReductionEligibility:
        any CertifiedCylinderCylinderReductionEligibility
    private let tangentIntersectionResolver:
        any SurfaceLiftTangentIntersectionResolving
    private let surfaceNormalResolver: any SurfaceNormalResolving

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
            VerifiedSurfaceLiftTangentIntersectionResolver()
        surfaceNormalResolver = DefaultSurfaceNormalResolver()
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
            any SurfaceLiftTangentIntersectionResolving,
        surfaceNormalResolver:
            any SurfaceNormalResolving = DefaultSurfaceNormalResolver()
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
    }

    public func intersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        try options.validate(tolerance: tolerance)
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)

        if case let .certifiedIntersection(certifiedCurve) = curve {
            if try certifiedIntersectionCoincidenceResolver.isSourceSurface(
                surface,
                of: certifiedCurve,
                tolerance: tolerance
            ) {
                throw KernelError(
                    phase: .geometry,
                    code: .nonDiscreteIntersection,
                    tolerance: tolerance,
                    message: "A certified intersection curve is continuously coincident with its source surface."
                )
            }
            let canonicalTarget = CanonicalAnalyticSurface(surface)
            if try certifiedIntersectionSpatialDisjointnessResolver.areDisjoint(
                curve: certifiedCurve,
                target: canonicalTarget,
                tolerance: tolerance
            ) {
                return []
            }
            if try supportsCertifiedReduction(
                curve: certifiedCurve,
                target: canonicalTarget,
                tolerance: tolerance
            ), let reduction = certifiedIntersectionReductionResolver
                .reduction(
                    for: certifiedCurve,
                    target: canonicalTarget
                ) {
                return try certifiedIntersectionReductionIntersector.intersections(
                    curve: certifiedCurve,
                    targetSurface: surface,
                    reduction: reduction,
                    options: options,
                    tolerance: tolerance,
                    sectionCurveIntersector: self
                )
            }
            if case .sphere = canonicalTarget,
               case let .coneCylinder(coneCylinderCurve) = certifiedCurve {
                return try coneCylinderSphereIntersector.intersections(
                    curve: coneCylinderCurve,
                    sphereSurface: surface,
                    options: options,
                    tolerance: tolerance
                )
            }
            if case .cone = canonicalTarget,
               case let .coneCylinder(coneCylinderCurve) = certifiedCurve,
               try coneCylinderConeIntersector.supports(
                    curve: coneCylinderCurve,
                    coneSurface: surface,
                    tolerance: tolerance
               ) {
                return try coneCylinderConeIntersector.intersections(
                    curve: coneCylinderCurve,
                    coneSurface: surface,
                    options: options,
                    tolerance: tolerance
                )
            }
            if try coneHostedQuadricIntersector.supports(
                curve: certifiedCurve,
                targetSurface: surface,
                tolerance: tolerance
            ) {
                return try coneHostedQuadricIntersector.intersections(
                    curve: certifiedCurve,
                    targetSurface: surface,
                    options: options,
                    tolerance: tolerance
                )
            }
            if case .plane = canonicalTarget,
               case let .parallelTorusTorus(parallelCurve) = certifiedCurve {
                return try parallelTorusTorusPlaneIntersector.intersections(
                    curve: parallelCurve,
                    planeSurface: surface,
                    options: options,
                    tolerance: tolerance
                )
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Certified intersection curve and
            // third-surface pairs outside the registered plane reductions,
            // sphere-cone/sphere or exact-cylinder reductions,
            // non-degenerate cone-cylinder/cone elimination,
            // non-degenerate cone-hosted quadric elimination,
            // cone-cylinder/sphere elimination, parallel-cylinder reduction, or
            // root-free skew-cylinder reduction, and
            // parallel-torus/plane elimination, unless conservative spatial bounds
            // prove separation from a bounded target, still lack complete
            // pair-specific algebraic reductions or interval-local bounds. The
            // production intersections(curve:surface:options:tolerance:) path reaches
            // this branch, and it must not report success until complete
            // transverse/tangent root isolation and parameter recovery are verified.
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "This certified intersection curve and third-surface pair lacks a complete certified reduction."
            )
        }

        if let intersections = try closedFormEllipticPlanarIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        if let intersections = try closedFormCircularPlanarIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        if case let .bSpline(bSplineCurve) = curve {
            let canonicalSurface = CanonicalAnalyticSurface(surface)
            switch canonicalSurface {
            case .unsupported:
                break
            case let supportedSurface:
                return try BSplineCurveAnalyticSurfaceIntersector().intersections(
                    curve: bSplineCurve,
                    surface: surface,
                    canonicalSurface: supportedSurface,
                    options: options,
                    tolerance: tolerance
                )
            }
        }

        if case let .surfaceLift(lift) = curve {
            let canonicalSurface = CanonicalAnalyticSurface(surface)
            if case .unsupported = canonicalSurface {
                // The rational-surface path performs its own exact source-locus reduction.
            } else {
                let curveRange = try resolvedInterval(
                    domain: curve.parameterDomain,
                    explicit: options.curveRange,
                    label: "curve",
                    tolerance: tolerance
                )
                if let exactCurve = try AnalyticCurveBSplineBuilder().boundedCurve(
                    curve: curve,
                    interval: curveRange,
                    maximumSpanCount: options.maximumCandidateCount,
                    tolerance: tolerance
                ) {
                    return try BSplineCurveAnalyticSurfaceIntersector().intersections(
                        curve: exactCurve,
                        surface: surface,
                        canonicalSurface: canonicalSurface,
                        options: options,
                        tolerance: tolerance
                    )
                }
                return try certifiedSurfaceLiftAnalyticIntersections(
                    lift: lift,
                    curve: curve,
                    surface: surface,
                    canonicalSurface: canonicalSurface,
                    curveRange: curveRange,
                    options: options,
                    tolerance: tolerance
                )
            }
        }

        if let line = lineGeometry(curve) {
            if let coefficients = try implicitPolynomial(
                line: line,
                surface: surface,
                tolerance: tolerance
            ) {
                return try closedFormLineIntersections(
                    line: line,
                    curve: curve,
                    surface: surface,
                    coefficients: coefficients,
                    options: options,
                    tolerance: tolerance
                )
            }
        }

        if let intersections = try closedFormUnboundedConicAnalyticIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        if let intersections = try closedFormHarmonicAnalyticIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        return try adaptiveIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        )
    }

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
        case let .cylinder(targetCylinder):
            switch curve {
            case .sphereCone:
                return true
            case .coneCone:
                return true
            case let .coneCylinder(coneCylinderCurve):
                guard case let .cylinder(sourceCylinder) =
                    CanonicalAnalyticSurface(
                        coneCylinderCurve.cylinderSurface
                    ) else {
                    return false
                }
                if AnalyticAxisRelation.areParallel(
                    targetCylinder.axis,
                    sourceCylinder.axis,
                    tolerance: tolerance
                ) {
                    return true
                }
                return try cylinderCylinderReductionEligibility
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
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        guard case let .analytic(.ellipse(
            center,
            normal,
            majorAxis,
            majorRadius,
            minorRadius
        )) = curve,
              let plane = planarGeometry(surface) else {
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
                    message: "Elliptic curve and plane are coincident; the intersection is not a discrete point set."
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
        let first = normalizedPeriodicParameter(phase - angularOffset)
        let second = normalizedPeriodicParameter(phase + angularOffset)
        let parameters = abs(sin(angularOffset)) <= tolerance.angle
            ? [first]
            : [first, second]

        var intersections: [CurveSurfaceIntersection] = []
        for parameter in parameters {
            guard contains(parameter, range: options.curveRange),
                  try curve.parameterDomain.contains(parameter, tolerance: tolerance) else {
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
                  contains(surfaceProjection.v, range: options.surfaceVRange) else {
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
            intersections.append(try CurveSurfaceIntersection(
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
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        guard let harmonic = try harmonicCurveGeometry(
            curve,
            tolerance: tolerance
        ),
        let coefficients = harmonicImplicitPolynomial(
            center: harmonic.center,
            cosine: harmonic.cosine,
            sine: harmonic.sine,
            surface: surface
        ) else {
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
        var parameters = try solver.realRoots(coefficients: coefficients).compactMap {
            resolvedCurveParameter(
                normalizedPeriodicParameter(2.0 * atan($0)),
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
                where error.code == .intersectionFailure {
                // The tan-half-angle pole is not an intersection.
            }
        }

        var intersections: [CurveSurfaceIntersection] = []
        for parameter in parameters {
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
                  contains(surfaceProjection.v, range: options.surfaceVRange) else {
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
                tolerance: tolerance
            )
            intersections.append(try CurveSurfaceIntersection(
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
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        let coefficients: [Double]
        let parameterForRoot: (Double) -> Double?
        switch curve {
        case let .analytic(.hyperbola(hyperbola)):
            let conjugateAxis = try hyperbola.normal
                .cross(hyperbola.transverseAxis)
                .normalized(tolerance: tolerance.distance)
            let transverse = hyperbola.transverseAxis * hyperbola.transverseRadius
            let conjugate = conjugateAxis * hyperbola.conjugateRadius
            let denominator = [0.0, 1.0]
            guard let polynomial = rationalCurveImplicitPolynomial(
                relativeNumerator: { origin in
                    [
                        (transverse - conjugate) * 0.5,
                        hyperbola.center - origin,
                        (transverse + conjugate) * 0.5,
                    ]
                },
                denominator: denominator,
                surface: surface
            ) else {
                return nil
            }
            coefficients = polynomial
            parameterForRoot = { root in
                guard root.isFinite, root > 0.0 else { return nil }
                let parameter = log(root)
                return parameter.isFinite ? parameter : nil
            }
        case let .analytic(.parabola(parabola)):
            let transverseAxis = try parabola.normal
                .cross(parabola.axis)
                .normalized(tolerance: tolerance.distance)
            guard let polynomial = rationalCurveImplicitPolynomial(
                relativeNumerator: { origin in
                    [
                        parabola.vertex - origin,
                        transverseAxis,
                        parabola.axis * (1.0 / (4.0 * parabola.focalLength)),
                    ]
                },
                denominator: [1.0],
                surface: surface
            ) else {
                return nil
            }
            coefficients = polynomial
            parameterForRoot = { root in root.isFinite ? root : nil }
        case .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
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
        let parameters = try solver.realRoots(coefficients: coefficients)
            .compactMap(parameterForRoot)
            .filter { parameter in
                options.curveRange?.contains(parameter) ?? true
            }
        return try verifiedConicIntersections(
            parameters: parameters,
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        )
    }

    private func verifiedConicIntersections(
        parameters: [Double],
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        var result: [CurveSurfaceIntersection] = []
        for parameter in parameters {
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
                  try surface.vDomain.contains(projection.v, tolerance: tolerance) else {
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
                tolerance: tolerance
            )
            result.append(try CurveSurfaceIntersection(
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
        case let .circle(circle):
            let normal = try circle.normal.normalized(
                tolerance: tolerance.distance
            )
            let helper = abs(normal.z) < 0.9
                ? Vector3D.unitZ
                : Vector3D.unitY
            let cosine = try helper.cross(normal).normalized(
                tolerance: tolerance.distance
            ) * circle.radius
            return (
                circle.center,
                cosine,
                normal.cross(cosine)
            )
        case let .analytic(analytic):
            switch analytic {
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                let basis = try analyticOrthonormalBasis(
                    normal,
                    tolerance: tolerance
                )
                return (center, basis.u * radius, basis.v * radius)
            case let .ellipse(
                center,
                normal,
                majorAxis,
                majorRadius,
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
        case .line, .bSpline, .implicit, .surfaceLift, .certifiedIntersection:
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
        case let .plane(plane):
            return relativeNumerator(plane.origin).map { $0.dot(plane.normal) }
        case let .cylinder(value):
            return cylinder(
                origin: value.origin,
                axis: value.axis,
                radius: value.radius
            )
        case let .analytic(analytic):
            switch analytic {
            case let .plane(origin, normal):
                return relativeNumerator(origin).map { $0.dot(normal) }
            case let .cylinder(origin, axis, radius):
                return cylinder(origin: origin, axis: axis, radius: radius)
            case let .cone(apex, axis, halfAngle):
                return cone(apex: apex, axis: axis, halfAngle: halfAngle)
            case let .sphere(center, radius):
                return sphere(center: center, radius: radius)
            case let .torus(center, axis, majorRadius, minorRadius):
                return torus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
            }
        case .bSpline:
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
        case let .periodic(period):
            guard let range else { return canonical }
            let cycle = ceil((range.lower - canonical - tolerance.angle) / period)
            let candidate = canonical + cycle * period
            return candidate <= range.upper + tolerance.angle ? candidate : nil
        case let .closed(lower, upper):
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
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        guard let circle = circularGeometry(curve),
              let plane = planarGeometry(surface) else {
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
                    message: "Circular curve and plane are coincident; the intersection is not a discrete point set."
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
        let lineAnchor = circle.center
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
                  contains(surfaceProjection.v, range: options.surfaceVRange) else {
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
            intersections.append(try CurveSurfaceIntersection(
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
        case let .circle(circle):
            return (circle.center, circle.normal, circle.radius)
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            return (center, normal, radius)
        case .line, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }

    private func planarGeometry(
        _ surface: Surface3D
    ) -> (origin: Point3D, normal: Vector3D)? {
        switch surface {
        case let .plane(plane):
            return (plane.origin, plane.normal)
        case let .analytic(.plane(origin, normal)):
            return (origin, normal)
        case .cylinder, .analytic, .bSpline:
            return nil
        }
    }

    private func lineGeometry(_ curve: Curve3D) -> Line3D? {
        switch curve {
        case let .line(line):
            return line
        case let .analytic(.line(origin, direction)):
            return Line3D(origin: origin, direction: direction)
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }

    private func implicitPolynomial(
        line: Line3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [Double]? {
        switch surface {
        case let .plane(plane):
            return try planePolynomial(line: line, origin: plane.origin, normal: plane.normal, tolerance: tolerance)
        case let .cylinder(cylinder):
            return cylinderPolynomial(
                line: line,
                origin: cylinder.origin,
                axis: cylinder.axis,
                radius: cylinder.radius
            )
        case let .analytic(surface):
            switch surface {
            case let .plane(origin, normal):
                return try planePolynomial(line: line, origin: origin, normal: normal, tolerance: tolerance)
            case let .cylinder(origin, axis, radius):
                return cylinderPolynomial(line: line, origin: origin, axis: axis, radius: radius)
            case let .cone(apex, axis, halfAngle):
                return conePolynomial(line: line, apex: apex, axis: axis, halfAngle: halfAngle)
            case let .sphere(center, radius):
                let offset = line.origin - center
                return [
                    offset.dot(offset) - radius * radius,
                    2.0 * offset.dot(line.direction),
                    line.direction.dot(line.direction),
                ]
            case let .torus(center, axis, majorRadius, minorRadius):
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
           abs(linear) <= tolerance.angle {
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
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
        if coefficients.allSatisfy({ abs($0) <= coefficientScale * tolerance.angle }) {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "Curve and surface share a continuous intersection; a discrete point set cannot represent it."
            )
        }
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.distance * 0.001, Double.ulpOfOne * 64.0),
            residualTolerance: max(tolerance.angle * 0.001, Double.ulpOfOne * 64.0)
        )
        let roots = try solver.realRoots(coefficients: coefficients)
        var results: [CurveSurfaceIntersection] = []
        for parameter in roots {
            if let range = options.curveRange,
               range.contains(parameter) == false {
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
                  try surface.vDomain.contains(surfaceParameter.v, tolerance: tolerance) else {
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
                tolerance: tolerance
            )
            let kind: CurveSurfaceIntersectionKind = abs(line.direction.dot(normal)) <= tolerance.angle
                ? .tangent
                : .transverse
            results.append(try CurveSurfaceIntersection(
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
        lift: SurfaceLiftCurve3D,
        curve: Curve3D,
        surface: Surface3D,
        canonicalSurface: CanonicalAnalyticSurface,
        curveRange: ScalarInterval,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let supportSurface = CanonicalAnalyticSurface(lift.surface)
        guard lift.surface != surface,
              try representDifferentLoci(
                supportSurface,
                canonicalSurface,
                tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "A surface-lift curve lies continuously on its target support surface."
            )
        }
        let bounder = SurfaceLiftDifferentialBounder()
        let breaks = try bounder.breakParameters(
            lift: lift,
            within: curveRange,
            tolerance: tolerance
        )
        let partition = [curveRange.lower] + breaks + [curveRange.upper]
        var pending: [ScalarRootCell] = []
        for index in 1..<partition.count {
            let interval = try ScalarInterval(
                lower: partition[index - 1],
                upper: partition[index]
            )
            guard let secondDerivativeBound = try bounder
                .secondDerivativeMagnitude(
                    lift: lift,
                    interval: interval,
                    tolerance: tolerance
                ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "A certified surface-lift representation requires its structural curve root solver."
                )
            }
            pending.append(ScalarRootCell(
                interval: interval,
                depth: 0,
                secondDerivativeBound: secondDerivativeBound
            ))
        }
        var remainingCells = options.maximumSubdivisionCells
        var intersections: [CurveSurfaceIntersection] = []
        var unresolved: [UnresolvedScalarRootCandidate] = []
        while let cell = pending.popLast() {
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
                > max(tolerance.angle, tolerance.distance) {
                curveBounds = try bounds(
                    curve: curve,
                    interval: cell.interval,
                    tolerance: tolerance
                )
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
            case let .unique(rootInterval):
                guard let intersection = try refinedAnalyticSurfaceIntersection(
                    curve: curve,
                    surface: surface,
                    canonicalSurface: canonicalSurface,
                    rootInterval: rootInterval,
                    options: options,
                    tolerance: tolerance
                ) else { continue }
                intersections.append(intersection)
            case .unresolved:
                guard cell.depth < options.maximumSubdivisionDepth else {
                    let stationary = try refinedStationaryParameter(
                        curve: curve,
                        surface: canonicalSurface,
                        interval: cell.interval,
                        maximumIterations: options.maximumIterations,
                        tolerance: tolerance
                    )
                    let geometry = try curve.differentialGeometry(
                        at: stationary.parameter,
                        tolerance: tolerance
                    )
                    let implicit = try implicitValueAndGradient(
                        point: geometry.position,
                        surface: canonicalSurface
                    )
                    let incidence = abs(
                        implicit.gradient.dot(geometry.firstDerivative)
                    )
                    let scale = max(
                        implicit.gradient.length * geometry.firstDerivative.length,
                        Double.leastNonzeroMagnitude
                    )
                    let distanceResidual = abs(implicit.value) / max(
                        implicit.gradient.length,
                        Double.leastNonzeroMagnitude
                    )
                    if distanceResidual <= tolerance.distance,
                       incidence <= tolerance.angle * scale {
                        if let intersection = try tangentIntersectionResolver
                            .intersection(
                                curve: curve,
                                surface: surface,
                                parameter: stationary.parameter,
                                options: options,
                                iterations: stationary.iterations,
                                tolerance: tolerance
                            ) {
                            intersections.append(intersection)
                        }
                        continue
                    }
                    unresolved.append(UnresolvedScalarRootCandidate(
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
                pending.append(ScalarRootCell(
                    interval: try ScalarInterval(
                        lower: midpoint,
                        upper: cell.interval.upper
                    ),
                    depth: cell.depth + 1,
                    secondDerivativeBound: cell.secondDerivativeBound
                ))
                pending.append(ScalarRootCell(
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
            Double.ulpOfOne * max(
                max(abs(curveRange.lower), abs(curveRange.upper)),
                1.0
            ) * 256.0
        )
        var unaccounted: [UnresolvedScalarRootCandidate] = []
        for candidate in unresolved {
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
            let spatialRadius = (
                centerGeometry.firstDerivative.length * halfWidth
                    + 0.5 * candidate.secondDerivativeBound
                        * halfWidth * halfWidth
            ).nextUp
            let spatiallyAccounted = result.contains { intersection in
                guard intersection.kind == .tangent else { return false }
                return (
                    (centerGeometry.position - intersection.point).length
                        + spatialRadius
                ).nextUp <= tolerance.distance
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
        interval: ScalarInterval,
        secondDerivativeBound: Double,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let geometry = try curve.differentialGeometry(
            at: interval.midpoint,
            tolerance: tolerance
        )
        let halfWidth = (interval.width * 0.5).nextUp
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * max(
                    (geometry.position - .origin).length,
                    geometry.firstDerivative.length,
                    secondDerivativeBound,
                    1.0
                )
                * 65_536.0
        ).nextUp
        let radius = (
            geometry.firstDerivative.length * halfWidth
                + 0.5 * secondDerivativeBound * halfWidth * halfWidth
                + arithmeticEnvelope
        ).nextUp
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
        if case let .plane(plane) = surface {
            let geometry = try curve.differentialGeometry(
                at: interval.midpoint,
                tolerance: tolerance
            )
            let relative = geometry.position - plane.origin
            let centerValue = relative.dot(plane.normal)
            let centerDerivative = geometry.firstDerivative.dot(plane.normal)
            let halfWidth = (interval.width * 0.5).nextUp
            let normalLength = plane.normal.length.nextUp
            let derivativeRadius = (
                normalLength * secondDerivativeBound * halfWidth
            ).nextUp
            let arithmeticEnvelope = (
                Double.ulpOfOne
                    * max(
                        abs(centerValue),
                        (geometry.position - .origin).length * normalLength,
                        1.0
                    )
                    * 65_536.0
            ).nextUp
            let valueRadius = (
                abs(centerDerivative) * halfWidth
                    + 0.5 * normalLength * secondDerivativeBound
                        * halfWidth * halfWidth
                    + arithmeticEnvelope
            ).nextUp
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
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int) {
        var parameter = interval.midpoint
        var iterations = 0
        for iteration in 0..<maximumIterations {
            iterations = iteration + 1
            let geometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let implicit = try implicitValueAndGradient(
                point: geometry.position,
                surface: surface
            )
            let firstDerivative = implicit.gradient.dot(
                geometry.firstDerivative
            )
            let secondDerivative = try implicitCurveSecondDerivative(
                geometry: geometry,
                implicitGradient: implicit.gradient,
                surface: surface
            )
            let derivativeFloor = max(
                Double.ulpOfOne * 256.0 * max(abs(firstDerivative), 1.0),
                Double.leastNonzeroMagnitude
            )
            guard secondDerivative.isFinite,
                  abs(secondDerivative) > derivativeFloor else {
                break
            }
            let candidate = min(
                max(
                    parameter - firstDerivative / secondDerivative,
                    interval.lower
                ),
                interval.upper
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

    private func implicitCurveSecondDerivative(
        geometry: Curve3D.DifferentialGeometry,
        implicitGradient: Vector3D,
        surface: CanonicalAnalyticSurface
    ) throws -> Double {
        let tangent = geometry.firstDerivative
        let tangentSquared = tangent.dot(tangent)
        let directionalHessian: Double
        switch surface {
        case .plane:
            directionalHessian = 0.0
        case let .cylinder(cylinder):
            let axial = cylinder.axis.dot(tangent)
            directionalHessian = 2.0 * (tangentSquared - axial * axial)
        case let .cone(cone):
            let axial = cone.axis.dot(tangent)
            directionalHessian = 2.0 * (
                tangentSquared
                    - axial * axial
                    - axial * axial * pow(tan(cone.halfAngle), 2.0)
            )
        case .sphere:
            directionalHessian = 2.0 * tangentSquared
        case let .torus(torus):
            let relative = geometry.position - torus.center
            let axialTangent = torus.axis.dot(tangent)
            let radialTangentSquared = tangentSquared
                - axialTangent * axialTangent
            let quadratic = relative.dot(relative)
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            directionalHessian = 8.0 * pow(relative.dot(tangent), 2.0)
                + 4.0 * quadratic * tangentSquared
                - 8.0 * torus.majorRadius * torus.majorRadius
                    * radialTangentSquared
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Implicit second derivatives require an analytic target surface."
            )
        }
        let result = directionalHessian
            + implicitGradient.dot(geometry.secondDerivative)
        guard result.isFinite else {
            throw intervalArithmeticFailure()
        }
        return result
    }

    private func representDifferentLoci(
        _ first: CanonicalAnalyticSurface,
        _ second: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        switch (first, second) {
        case let (.plane(lhs), .plane(rhs)):
            let lhsNormal = try lhs.normal.normalized(
                tolerance: tolerance.distance
            )
            let rhsNormal = try rhs.normal.normalized(
                tolerance: tolerance.distance
            )
            let parallel = abs(lhsNormal.dot(rhsNormal))
                >= 1.0 - tolerance.angle
            let separation = abs((rhs.origin - lhs.origin).dot(lhsNormal))
            return parallel == false || separation > tolerance.distance
        case let (.cylinder(lhs), .cylinder(rhs)):
            return try axesRepresentDifferentLines(
                lhsOrigin: lhs.origin,
                lhsAxis: lhs.axis,
                rhsOrigin: rhs.origin,
                rhsAxis: rhs.axis,
                tolerance: tolerance
            ) || abs(lhs.radius - rhs.radius) > tolerance.distance
        case let (.cone(lhs), .cone(rhs)):
            let lhsAxis = try lhs.axis.normalized(tolerance: tolerance.distance)
            let rhsAxis = try rhs.axis.normalized(tolerance: tolerance.distance)
            return lhs.apex.isApproximatelyEqual(
                to: rhs.apex,
                tolerance: tolerance.distance
            ) == false
                || abs(lhsAxis.dot(rhsAxis)) < 1.0 - tolerance.angle
                || abs(lhs.halfAngle - rhs.halfAngle) > tolerance.angle
        case let (.sphere(lhs), .sphere(rhs)):
            return lhs.center.isApproximatelyEqual(
                to: rhs.center,
                tolerance: tolerance.distance
            ) == false
                || abs(lhs.radius - rhs.radius) > tolerance.distance
        case let (.torus(lhs), .torus(rhs)):
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
        let lowerValue = try implicitValueAndGradient(
            point: curve.point(at: interval.lower, tolerance: tolerance),
            surface: surface
        ).value
        let upperValue = try implicitValueAndGradient(
            point: curve.point(at: interval.upper, tolerance: tolerance),
            surface: surface
        ).value
        let lowerRange = try constantInterval(lowerValue)
        let upperRange = try constantInterval(upperValue)
        if hasStrictSameSign(lowerRange, upperRange) {
            return .excluded
        }
        if containsZero(lowerRange) || containsZero(upperRange)
            || haveOppositeSigns(lowerRange, upperRange) {
            return .unique(interval)
        }
        let midpointValue = try implicitValueAndGradient(
            point: curve.point(at: interval.midpoint, tolerance: tolerance),
            surface: surface
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
           contraction.upper < interval.upper - margin {
            return .unique(contraction)
        }
        return .unresolved
    }

    private func refinedAnalyticSurfaceIntersection(
        curve: Curve3D,
        surface: Surface3D,
        canonicalSurface: CanonicalAnalyticSurface,
        rootInterval: ScalarInterval,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        var parameter = rootInterval.midpoint
        var iterations = 0
        for iteration in 0..<options.maximumIterations {
            iterations = iteration + 1
            let geometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let implicit = try implicitValueAndGradient(
                point: geometry.position,
                surface: canonicalSurface
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
            if abs(next - parameter) <= max(
                tolerance.relative,
                Double.ulpOfOne * max(abs(parameter), 1.0) * 256.0
            ) {
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
        guard let surfaceU = rangeResolver.resolvedParameter(
            projection.u,
            domain: surface.uDomain,
            requestedRange: options.surfaceURange,
            tolerance: tolerance
        ), let surfaceV = rangeResolver.resolvedParameter(
            projection.v,
            domain: surface.vDomain,
            requestedRange: options.surfaceVRange,
            tolerance: tolerance
        ) else { return nil }
        let surfaceGeometry = try surface.differentialGeometry(
            atU: surfaceU,
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
        return try CurveSurfaceIntersection(
            point: curveGeometry.position,
            curveParameter: parameter,
            surfaceU: surfaceU,
            surfaceV: surfaceV,
            kind: abs(curveGeometry.tangent.dot(surfaceGeometry.normal)) <= tolerance.angle
                ? .tangent
                : .transverse,
            residual: projection.residual,
            iterations: iterations
        )
    }

    private func curveDerivativeRange(
        curve: Curve3D,
        interval: ScalarInterval,
        secondDerivativeBound: Double,
        tolerance: ModelingTolerance
    ) throws -> IntervalVector3 {
        let derivative = try curve.differentialGeometry(
            at: interval.midpoint,
            tolerance: tolerance
        ).firstDerivative
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
        case let .plane(plane):
            return try dot(
                subtracting(position, constantVector(plane.origin)),
                plane.normal
            )
        case let .cylinder(cylinder):
            let relative = try subtracting(position, constantVector(cylinder.origin))
            let axial = try dot(relative, cylinder.axis)
            let radial = try subtracting(relative, scaled(cylinder.axis, by: axial))
            return try added(
                squaredLength(radial),
                constantInterval(-cylinder.radius * cylinder.radius)
            )
        case let .cone(cone):
            let relative = try subtracting(position, constantVector(cone.apex))
            let axial = try dot(relative, cone.axis)
            let radial = try subtracting(relative, scaled(cone.axis, by: axial))
            return try added(
                squaredLength(radial),
                scaled(multiplied(axial, axial), by: -pow(tan(cone.halfAngle), 2.0))
            )
        case let .sphere(sphere):
            let relative = try subtracting(position, constantVector(sphere.center))
            return try added(
                squaredLength(relative),
                constantInterval(-sphere.radius * sphere.radius)
            )
        case let .torus(torus):
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
        case let .plane(plane):
            return try constantVector(plane.normal)
        case let .cylinder(cylinder):
            let relative = try subtracting(position, constantVector(cylinder.origin))
            let axial = try dot(relative, cylinder.axis)
            let radial = try subtracting(relative, scaled(cylinder.axis, by: axial))
            return try scaled(radial, by: 2.0)
        case let .cone(cone):
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
        case let .sphere(sphere):
            return try scaled(
                subtracting(position, constantVector(sphere.center)),
                by: 2.0
            )
        case let .torus(torus):
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

    private func implicitValueAndGradient(
        point: Point3D,
        surface: CanonicalAnalyticSurface
    ) throws -> (value: Double, gradient: Vector3D) {
        switch surface {
        case let .plane(plane):
            let relative = point - plane.origin
            return (relative.dot(plane.normal), plane.normal)
        case let .cylinder(cylinder):
            let relative = point - cylinder.origin
            let radial = relative - cylinder.axis * relative.dot(cylinder.axis)
            return (
                radial.dot(radial) - cylinder.radius * cylinder.radius,
                radial * 2.0
            )
        case let .cone(cone):
            let relative = point - cone.apex
            let axial = relative.dot(cone.axis)
            let radial = relative - cone.axis * axial
            let tangentSquared = pow(tan(cone.halfAngle), 2.0)
            return (
                radial.dot(radial) - axial * axial * tangentSquared,
                radial * 2.0 - cone.axis * (2.0 * axial * tangentSquared)
            )
        case let .sphere(sphere):
            let relative = point - sphere.center
            return (
                relative.dot(relative) - sphere.radius * sphere.radius,
                relative * 2.0
            )
        case let .torus(torus):
            let relative = point - torus.center
            let axial = relative.dot(torus.axis)
            let radial = relative - torus.axis * axial
            let distanceSquared = relative.dot(relative)
            let quadratic = distanceSquared
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            return (
                quadratic * quadratic
                    - 4.0 * torus.majorRadius * torus.majorRadius
                        * radial.dot(radial),
                relative * (4.0 * quadratic)
                    - radial * (8.0 * torus.majorRadius * torus.majorRadius)
            )
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Implicit evaluation requires an analytic target surface."
            )
        }
    }

    private func adaptiveIntersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let curveRange = try resolvedInterval(
            domain: curve.parameterDomain,
            explicit: options.curveRange,
            label: "curve",
            tolerance: tolerance
        )
        let uRange = try resolvedInterval(
            domain: surface.uDomain,
            explicit: options.surfaceURange,
            label: "surface U",
            tolerance: tolerance
        )
        let vRange = try resolvedInterval(
            domain: surface.vDomain,
            explicit: options.surfaceVRange,
            label: "surface V",
            tolerance: tolerance
        )
        if case let .bSpline(bSplineSurface) = surface {
            let exactCurve: BSplineCurve3D?
            let requiresSourceParameterRecovery: Bool
            if case let .bSpline(bSplineCurve) = curve {
                exactCurve = bSplineCurve
                requiresSourceParameterRecovery = false
            } else {
                exactCurve = try AnalyticCurveBSplineBuilder().boundedCurve(
                    curve: curve,
                    interval: curveRange,
                    maximumSpanCount: options.maximumCandidateCount,
                    tolerance: tolerance
                )
                requiresSourceParameterRecovery = exactCurve != nil
            }
            if let exactCurve {
                let intersections = try rationalBSplineIntersections(
                    curve: exactCurve,
                    surface: bSplineSurface,
                    curveRange: curveRange,
                    uRange: uRange,
                    vRange: vRange,
                    options: options,
                    tolerance: tolerance
                )
                guard requiresSourceParameterRecovery else {
                    return intersections
                }
                return try recoveredAnalyticCurveParameters(
                    intersections,
                    sourceCurve: curve,
                    exactCurve: exactCurve,
                    surface: surface,
                    options: options,
                    tolerance: tolerance
                )
            }
        }
        let rootCell = ParameterCell(t: curveRange, u: uRange, v: vRange, depth: 0)
        var pending = [rootCell]
        var candidates: [AdaptiveCandidate] = []
        var remainingCells = options.maximumSubdivisionCells
        while let cell = pending.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Curve-surface adaptive subdivision exceeded its cell budget."
                )
            }
            remainingCells -= 1
            let curveBounds = try bounds(curve: curve, interval: cell.t, tolerance: tolerance)
            let surfaceBounds = try bounds(
                surface: surface,
                uInterval: cell.u,
                vInterval: cell.v,
                tolerance: tolerance
            )
            guard curveBounds.intersects(surfaceBounds, tolerance: tolerance.distance) else {
                continue
            }
            if cell.depth >= options.maximumSubdivisionDepth {
                guard candidates.count < options.maximumCandidateCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Curve-surface adaptive subdivision exceeded its candidate budget."
                    )
                }
                candidates.append(AdaptiveCandidate(
                    seed: ParameterSeed(
                        t: cell.t.midpoint,
                        u: cell.u.midpoint,
                        v: cell.v.midpoint
                    ),
                    curveBounds: curveBounds,
                    surfaceBounds: surfaceBounds
                ))
                continue
            }
            let children = try subdivided(cell, root: rootCell)
            pending.append(contentsOf: children.reversed())
        }

        var intersections: [CurveSurfaceIntersection] = []
        var unresolvedResidual: Double?
        for candidate in candidates {
            if let intersection = try refinedIntersection(
                seed: candidate.seed,
                curve: curve,
                surface: surface,
                curveRange: curveRange,
                uRange: uRange,
                vRange: vRange,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            ) {
                intersections.append(intersection)
                unresolvedResidual = min(
                    unresolvedResidual ?? intersection.residual,
                    intersection.residual
                )
                continue
            }
            let curvePoint = try curve.point(
                at: candidate.seed.t,
                tolerance: tolerance
            )
            let surfacePoint = try surface.point(
                u: candidate.seed.u,
                v: candidate.seed.v,
                tolerance: tolerance
            )
            let witnessResidual = (curvePoint - surfacePoint).length.nextUp
            let variationUpperBound = (
                boundingBoxDiameterUpperBound(candidate.curveBounds)
                    + boundingBoxDiameterUpperBound(candidate.surfaceBounds)
            ).nextUp
            if (witnessResidual - variationUpperBound).nextDown
                <= tolerance.distance {
                unresolvedResidual = min(
                    unresolvedResidual ?? witnessResidual,
                    witnessResidual
                )
            }
        }
        if let unresolvedResidual {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: unresolvedResidual,
                tolerance: tolerance,
                message: "Curve-surface subdivision could not certify uniqueness and completeness for every remaining non-rational candidate."
            )
        }
        return deduplicated(intersections, tolerance: tolerance)
    }

    private func recoveredAnalyticCurveParameters(
        _ intersections: [CurveSurfaceIntersection],
        sourceCurve: Curve3D,
        exactCurve: BSplineCurve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        var result: [CurveSurfaceIntersection] = []
        result.reserveCapacity(intersections.count)
        for intersection in intersections {
            let localRange = try exactSpan(
                containing: intersection.curveParameter,
                curve: exactCurve,
                tolerance: tolerance
            )
            let sourceProjection = try sourceCurve.parameterProjection(
                of: intersection.point,
                options: CurveParameterProjectionOptions(
                    parameterRange: localRange,
                    maximumIterations: options.maximumIterations,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    maximumSubdivisionCells: options.maximumSubdivisionCells,
                    maximumCandidateCount: options.maximumCandidateCount
                ),
                tolerance: tolerance
            )
            let curveGeometry = try sourceCurve.differentialGeometry(
                at: sourceProjection.parameter,
                tolerance: tolerance
            )
            let surfaceGeometry = try surface.differentialGeometry(
                atU: intersection.surfaceU,
                v: intersection.surfaceV,
                tolerance: tolerance
            )
            let surfacePoint = try surface.point(
                u: intersection.surfaceU,
                v: intersection.surfaceV,
                tolerance: tolerance
            )
            let residual = max(
                sourceProjection.residual,
                (curveGeometry.position - surfacePoint).length.nextUp
            )
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Recovered analytic curve parameter failed exact intersection verification."
                )
            }
            result.append(try CurveSurfaceIntersection(
                point: curveGeometry.position,
                curveParameter: sourceProjection.parameter,
                surfaceU: intersection.surfaceU,
                surfaceV: intersection.surfaceV,
                kind: abs(curveGeometry.tangent.dot(surfaceGeometry.normal)) <= tolerance.angle
                    ? .tangent
                    : .transverse,
                residual: residual,
                iterations: intersection.iterations + sourceProjection.iterations
            ))
        }
        return deduplicated(result, tolerance: tolerance)
    }

    private func exactSpan(
        containing parameter: Double,
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .closed(domainLower, domainUpper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic parameter recovery requires a bounded exact curve."
            )
        }
        let resolution = curve.domain.parameterResolution(tolerance: tolerance)
        var breaks = [domainLower]
        for knot in curve.knots where knot > domainLower && knot < domainUpper {
            if abs(knot - (breaks.last ?? domainLower)) > resolution {
                breaks.append(knot)
            }
        }
        breaks.append(domainUpper)
        for index in 0..<(breaks.count - 1) where
            parameter >= breaks[index] - resolution
                && parameter <= breaks[index + 1] + resolution {
            return try ScalarInterval(
                lower: breaks[index],
                upper: breaks[index + 1]
            )
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: parameter,
            tolerance: tolerance,
            message: "Exact rational curve parameter is outside every source conic span."
        )
    }

    private func rationalBSplineIntersections(
        curve: BSplineCurve3D,
        surface: BSplineSurface3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let boundedCurve = try curve.trimmed(
            from: curveRange.lower,
            to: curveRange.upper,
            tolerance: tolerance
        )
        let boundedSurface = try surface.trimmed(
            uFrom: uRange.lower,
            uTo: uRange.upper,
            vFrom: vRange.lower,
            vTo: vRange.upper,
            tolerance: tolerance
        )
        let curvePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: boundedCurve,
            tolerance: tolerance
        )
        let surfacePatches = try BSplineSurfaceBezierDecomposer().surfacePatches(
            surface: boundedSurface,
            tolerance: tolerance
        )
        var pending: [DifferenceCell] = []
        for curvePatch in curvePatches.reversed() {
            for surfacePatch in surfacePatches.reversed() {
                pending.append(DifferenceCell(
                    patch: try RationalBezierCurveSurfaceDifferencePatch(
                        curve: curvePatch,
                        surface: surfacePatch,
                        tolerance: tolerance
                    ),
                    depth: 0
                ))
            }
        }
        var remainingCells = options.maximumSubdivisionCells
        var remainingCandidates = options.maximumCandidateCount
        var intersections: [CurveSurfaceIntersection] = []
        var unresolved: [UnresolvedDifferenceCandidate] = []
        while let cell = pending.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational B-spline curve-surface intersection exceeded its difference-cell budget."
                )
            }
            remainingCells -= 1
            let rootCertificate = cell.patch.rootCertificate()
            guard rootCertificate != .excluded else { continue }
            if rootCertificate == .unique {
                guard remainingCandidates > 0 else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Rational B-spline curve-surface intersection exceeded its certified-root refinement budget."
                    )
                }
                remainingCandidates -= 1
                let refinement = try refinedDifferenceIntersection(
                    patch: cell.patch,
                    curve: boundedCurve,
                    surface: boundedSurface,
                    curveRange: curveRange,
                    uRange: uRange,
                    vRange: vRange,
                    maximumIterations: options.maximumIterations,
                    tolerance: tolerance
                )
                guard let intersection = refinement.intersection else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        residual: refinement.residual,
                        tolerance: tolerance,
                        message: "Interval Krawczyk certified a unique root that numerical refinement did not resolve."
                    )
                }
                intersections.append(intersection)
                continue
            }
            if cell.depth < options.maximumSubdivisionDepth {
                let direction: RationalBezierCurveSurfaceDifferencePatch.SplitDirection
                switch cell.depth % 3 {
                case 0:
                    direction = .curve
                case 1:
                    direction = .surfaceU
                default:
                    direction = .surfaceV
                }
                for child in cell.patch.subdivided(direction: direction).reversed() {
                    pending.append(DifferenceCell(
                        patch: child,
                        depth: cell.depth + 1
                    ))
                }
                continue
            }
            guard remainingCandidates > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational B-spline curve-surface intersection exceeded its difference-candidate budget."
                )
            }
            remainingCandidates -= 1
            let refinement = try refinedDifferenceIntersection(
                patch: cell.patch,
                curve: boundedCurve,
                surface: boundedSurface,
                curveRange: curveRange,
                uRange: uRange,
                vRange: vRange,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            )
            if let intersection = refinement.intersection {
                intersections.append(intersection)
            } else {
                unresolved.append(UnresolvedDifferenceCandidate(
                    patch: cell.patch,
                    residual: refinement.residual
                ))
            }
        }
        let result = deduplicated(intersections, tolerance: tolerance)
        let parameterTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let unaccounted = unresolved.filter { candidate in
            result.contains { intersection in
                contains(
                    intersection.curveParameter,
                    lower: candidate.patch.curveLower,
                    upper: candidate.patch.curveUpper,
                    tolerance: parameterTolerance
                ) && contains(
                    intersection.surfaceU,
                    lower: candidate.patch.surfaceULower,
                    upper: candidate.patch.surfaceUUpper,
                    tolerance: parameterTolerance
                ) && contains(
                    intersection.surfaceV,
                    lower: candidate.patch.surfaceVLower,
                    upper: candidate.patch.surfaceVUpper,
                    tolerance: parameterTolerance
                )
            } == false
        }
        if let residual = unaccounted.map(\.residual).min() {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: residual,
                tolerance: tolerance,
                message: "Rational B-spline curve-surface intersection left an unresolved homogeneous difference candidate."
            )
        }
        return result
    }

    private func refinedDifferenceIntersection(
        patch: RationalBezierCurveSurfaceDifferencePatch,
        curve: BSplineCurve3D,
        surface: BSplineSurface3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> (intersection: CurveSurfaceIntersection?, residual: Double) {
        let seed = ParameterSeed(
            t: midpoint(patch.curveLower, patch.curveUpper),
            u: midpoint(patch.surfaceULower, patch.surfaceUUpper),
            v: midpoint(patch.surfaceVLower, patch.surfaceVUpper)
        )
        let curvePoint = try curve.point(at: seed.t, tolerance: tolerance)
        let surfacePoint = try surface.point(
            u: seed.u,
            v: seed.v,
            tolerance: tolerance
        )
        return try (
            refinedIntersection(
                seed: seed,
                curve: .bSpline(curve),
                surface: .bSpline(surface),
                curveRange: curveRange,
                uRange: uRange,
                vRange: vRange,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            ),
            (curvePoint - surfacePoint).length.nextUp
        )
    }

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func contains(
        _ value: Double,
        lower: Double,
        upper: Double,
        tolerance: Double
    ) -> Bool {
        value >= lower - tolerance && value <= upper + tolerance
    }

    private func boundingBoxDiameterUpperBound(_ box: BoundingBox3D) -> Double {
        let size = box.size
        let x = abs(size.x).nextUp
        let y = abs(size.y).nextUp
        let z = abs(size.z).nextUp
        return sqrt((x * x + y * y + z * z).nextUp).nextUp
    }

    private func resolvedInterval(
        domain: ParameterDomain,
        explicit: ScalarInterval?,
        label: String,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let explicit {
            guard explicit.width > max(tolerance.angle, Double.ulpOfOne) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "The explicit \(label) intersection range is degenerate."
                )
            }
            return explicit
        }
        switch domain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Adaptive intersection requires an explicit finite \(label) range."
            )
        }
    }

    private func bounds(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        if case let .bSpline(curve) = curve {
            let boundedCurve: BSplineCurve3D
            if interval.width > tolerance.distance {
                boundedCurve = try curve.trimmed(
                    from: interval.lower,
                    to: interval.upper,
                    tolerance: tolerance
                )
            } else {
                boundedCurve = curve
            }
            return try BoundingBox3D(points: boundedCurve.controlPoints)
                .expanded(by: tolerance.distance)
        }
        if case let .implicit(curve) = curve {
            return try curve.boundingBox(
                fromNormalizedFraction: interval.lower,
                toNormalizedFraction: interval.upper,
                tolerance: tolerance
            )
        }
        if case let .surfaceLift(lift) = curve {
            return try surfaceLiftBounds(
                lift,
                interval: interval,
                tolerance: tolerance
            )
        }
        let derivativeBound: Double
        switch curve {
        case let .line(line):
            derivativeBound = line.direction.length
        case let .circle(circle):
            derivativeBound = circle.radius
        case let .analytic(curve):
            switch curve {
            case let .line(_, direction):
                derivativeBound = direction.length
            case let .circle(_, _, radius), let .arc(_, _, radius, _, _):
                derivativeBound = radius
            case let .ellipse(_, _, _, majorRadius, _):
                derivativeBound = majorRadius
            case let .hyperbola(hyperbola):
                let maximumMagnitude = max(abs(interval.lower), abs(interval.upper))
                derivativeBound = hypot(
                    hyperbola.transverseRadius * sinh(maximumMagnitude),
                    hyperbola.conjugateRadius * cosh(maximumMagnitude)
                )
            case let .parabola(parabola):
                let maximumMagnitude = max(abs(interval.lower), abs(interval.upper))
                derivativeBound = hypot(
                    1.0,
                    maximumMagnitude / (2.0 * parabola.focalLength)
                )
            case let .planeTorus(planeTorus):
                return try planeTorus.boundingBox(tolerance: tolerance)
            }
        case .bSpline, .implicit, .surfaceLift, .certifiedIntersection:
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

    private func surfaceLiftBounds(
        _ lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let parameterCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: interval.lower,
            toNormalizedFraction: interval.upper,
            tolerance: tolerance
        )
        switch parameterCurve {
        case let .certifiedImplicit(curve):
            return try curve.intersection.boundingBox(
                fromNormalizedFraction: min(curve.startFraction, curve.endFraction),
                toNormalizedFraction: max(curve.startFraction, curve.endFraction),
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(curve):
            return try curve.intersection.implicitCurve.boundingBox(
                fromNormalizedFraction: min(curve.startFraction, curve.endFraction),
                toNormalizedFraction: max(curve.startFraction, curve.endFraction),
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(curve):
            if curve.hasSpatialDifferentialMagnitudeBounds {
                let differentialBounds = try curve
                    .spatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
                let parameter = try curve.parameter(
                    atNormalizedFraction: 0.5,
                    tolerance: tolerance
                )
                let center = try lift.surface.point(
                    u: parameter.u,
                    v: parameter.v,
                    tolerance: tolerance
                )
                return try isotropicBounds(
                    center: center,
                    radius: differentialBounds.first * 0.5
                        + curve.intersection.maximumResidualUpperBound
                        + tolerance.distance,
                    tolerance: tolerance
                )
            }
            return try curve.intersection.boundingBox(tolerance: tolerance)
        case let .projectedAnalytic(curve):
            return try bounds(
                curve: curve.curve,
                interval: ScalarInterval(
                    lower: min(curve.startParameter, curve.endParameter),
                    upper: max(curve.startParameter, curve.endParameter)
                ),
                tolerance: tolerance
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return try sphericalGreatCircleBounds(
                surface: lift.surface,
                cosine: cosine,
                sine: sine,
                parameter: ScalarInterval(
                    lower: min(startParameter, endParameter),
                    upper: max(startParameter, endParameter)
                ),
                tolerance: tolerance
            )
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
            break
        }
        if case .bSpline = lift.surface {
            guard let localized = try SurfaceLiftDifferentialBounder()
                .bSplineSupportBounds(
                    lift: lift,
                    interval: interval,
                    tolerance: tolerance
                ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A B-spline surface lift requires a locally bounded parameter curve."
                )
            }
            return localized
        }
        return try analyticSurfaceBounds(
            surface: lift.surface,
            parameters: surfaceParameterBounds(
                parameterCurve,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
    }

    private func surfaceParameterBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBounds {
        switch curve {
        case .affine, .constantU, .constantV:
            let endpoints = try [0.0, 1.0].map {
                try curve.parameter(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                )
            }
            return try parameterBounds(points: endpoints)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
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
                        parameter: parameter
                    )
                ),
                v: try added(
                    constantInterval(center.y),
                    trigonometricRange(
                        cosineCoefficient: cosine.y,
                        sineCoefficient: sine.y,
                        parameter: parameter
                    )
                )
            )
        case let .polyline(points):
            return try parameterBounds(points: points)
        case let .bSpline(curve):
            return try parameterBounds(points: curve.controlPoints.map {
                SurfaceParameter(u: $0.x, v: $0.y)
            })
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A structurally certified surface-lift curve reached generic parameter bounds."
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
            u: try outwardInterval(points.map(\.u)),
            v: try outwardInterval(points.map(\.v))
        )
    }

    private func analyticSurfaceBounds(
        surface: Surface3D,
        parameters: SurfaceParameterBounds,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let canonical = CanonicalAnalyticSurface(surface)
        var coordinates: [ScalarInterval] = []
        coordinates.reserveCapacity(3)
        for index in 0..<3 {
            let coordinate: ScalarInterval
            switch canonical {
            case let .plane(plane):
                let basis = try analyticOrthonormalBasis(
                    plane.normal,
                    tolerance: tolerance
                )
                coordinate = try added(
                    constantInterval(component(plane.origin, index: index)),
                    added(
                        scaled(parameters.u, by: component(basis.u, index: index)),
                        scaled(parameters.v, by: component(basis.v, index: index))
                    )
                )
            case let .cylinder(cylinder):
                let basis = try analyticOrthonormalBasis(
                    cylinder.axis,
                    tolerance: tolerance
                )
                let radial = try trigonometricRange(
                    cosineCoefficient: component(basis.u, index: index) * cylinder.radius,
                    sineCoefficient: component(basis.v, index: index) * cylinder.radius,
                    parameter: parameters.u
                )
                coordinate = try added(
                    constantInterval(component(cylinder.origin, index: index)),
                    added(
                        radial,
                        scaled(parameters.v, by: component(cylinder.axis, index: index))
                    )
                )
            case let .cone(cone):
                let basis = try analyticOrthonormalBasis(
                    cone.axis,
                    tolerance: tolerance
                )
                let radialDirection = try trigonometricRange(
                    cosineCoefficient: component(basis.u, index: index),
                    sineCoefficient: component(basis.v, index: index),
                    parameter: parameters.u
                )
                let axial = try scaled(
                    parameters.v,
                    by: component(cone.axis, index: index) * cos(cone.halfAngle)
                )
                let radial = try scaled(
                    multiplied(parameters.v, radialDirection),
                    by: sin(cone.halfAngle)
                )
                coordinate = try added(
                    constantInterval(component(cone.apex, index: index)),
                    added(axial, radial)
                )
            case let .sphere(sphere):
                let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
                let radial = try trigonometricRange(
                    cosineCoefficient: component(basis.u, index: index),
                    sineCoefficient: component(basis.v, index: index),
                    parameter: parameters.u
                )
                let cosineV = try trigonometricRange(
                    cosineCoefficient: 1.0,
                    sineCoefficient: 0.0,
                    parameter: parameters.v
                )
                let sineV = try trigonometricRange(
                    cosineCoefficient: 0.0,
                    sineCoefficient: 1.0,
                    parameter: parameters.v
                )
                let direction = try added(
                    multiplied(radial, cosineV),
                    scaled(sineV, by: component(Vector3D.unitZ, index: index))
                )
                coordinate = try added(
                    constantInterval(component(sphere.center, index: index)),
                    scaled(direction, by: sphere.radius)
                )
            case let .torus(torus):
                let basis = try analyticOrthonormalBasis(
                    torus.axis,
                    tolerance: tolerance
                )
                let radial = try trigonometricRange(
                    cosineCoefficient: component(basis.u, index: index),
                    sineCoefficient: component(basis.v, index: index),
                    parameter: parameters.u
                )
                let cosineV = try trigonometricRange(
                    cosineCoefficient: 1.0,
                    sineCoefficient: 0.0,
                    parameter: parameters.v
                )
                let sineV = try trigonometricRange(
                    cosineCoefficient: 0.0,
                    sineCoefficient: 1.0,
                    parameter: parameters.v
                )
                let radialDistance = try added(
                    constantInterval(torus.majorRadius),
                    scaled(cosineV, by: torus.minorRadius)
                )
                coordinate = try added(
                    constantInterval(component(torus.center, index: index)),
                    added(
                        multiplied(radial, radialDistance),
                        scaled(
                            sineV,
                            by: component(torus.axis, index: index) * torus.minorRadius
                        )
                    )
                )
            case .unsupported:
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Analytic surface-lift bounds received a non-analytic surface."
                )
            }
            coordinates.append(coordinate)
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

    private func sphericalGreatCircleBounds(
        surface: Surface3D,
        cosine: Vector3D,
        sine: Vector3D,
        parameter: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        guard case let .sphere(sphere) = CanonicalAnalyticSurface(surface) else {
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
            coordinates.append(try added(
                constantInterval(component(sphere.center, index: index)),
                scaled(
                    trigonometricRange(
                        cosineCoefficient: component(cosine, index: index),
                        sineCoefficient: component(sine, index: index),
                        parameter: parameter
                    ),
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
        parameter: ScalarInterval
    ) throws -> ScalarInterval {
        let amplitude = hypot(cosineCoefficient, sineCoefficient)
        guard amplitude.isFinite else {
            throw intervalArithmeticFailure()
        }
        let period = 2.0 * Double.pi
        if parameter.width >= period
            || max(abs(parameter.lower), abs(parameter.upper)) > 1.0e12 {
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
              upper.isFinite else {
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

    private func bounds(
        surface: Surface3D,
        uInterval: ScalarInterval,
        vInterval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        if case let .bSpline(surface) = surface {
            let boundedSurface: BSplineSurface3D
            if uInterval.width > tolerance.distance,
               vInterval.width > tolerance.distance {
                boundedSurface = try surface.trimmed(
                    uFrom: uInterval.lower,
                    uTo: uInterval.upper,
                    vFrom: vInterval.lower,
                    vTo: vInterval.upper,
                    tolerance: tolerance
                )
            } else {
                boundedSurface = surface
            }
            return try BoundingBox3D(
                points: boundedSurface.controlPoints.flatMap { $0 }
            )
                .expanded(by: tolerance.distance)
        }
        let derivativeBounds: (u: Double, v: Double)
        switch surface {
        case .plane:
            derivativeBounds = (1.0, 1.0)
        case let .cylinder(cylinder):
            derivativeBounds = (cylinder.radius, 1.0)
        case let .analytic(surface):
            switch surface {
            case .plane:
                derivativeBounds = (1.0, 1.0)
            case let .cylinder(_, _, radius):
                derivativeBounds = (radius, 1.0)
            case let .cone(_, _, halfAngle):
                let maximumAbsoluteV = max(abs(vInterval.lower), abs(vInterval.upper))
                derivativeBounds = (maximumAbsoluteV * sin(halfAngle), 1.0)
            case let .sphere(_, radius):
                derivativeBounds = (radius, radius)
            case let .torus(_, _, majorRadius, minorRadius):
                derivativeBounds = (majorRadius + minorRadius, minorRadius)
            }
        case .bSpline:
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline surface interval bounds failed to use the control hull."
            )
        }
        let center = try surface.point(
            u: uInterval.midpoint,
            v: vInterval.midpoint,
            tolerance: tolerance
        )
        let radius = derivativeBounds.u * uInterval.width * 0.5
            + derivativeBounds.v * vInterval.width * 0.5
            + tolerance.distance
        return try isotropicBounds(center: center, radius: radius, tolerance: tolerance)
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
        root: ParameterCell
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
                    depth: cell.depth + 1
                ),
                ParameterCell(
                    t: try ScalarInterval(lower: midpoint, upper: cell.t.upper),
                    u: cell.u,
                    v: cell.v,
                    depth: cell.depth + 1
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
                    depth: cell.depth + 1
                ),
                ParameterCell(
                    t: cell.t,
                    u: try ScalarInterval(lower: midpoint, upper: cell.u.upper),
                    v: cell.v,
                    depth: cell.depth + 1
                ),
            ]
        }
        let midpoint = cell.v.midpoint
        return [
            ParameterCell(
                t: cell.t,
                u: cell.u,
                v: try ScalarInterval(lower: cell.v.lower, upper: midpoint),
                depth: cell.depth + 1
            ),
            ParameterCell(
                t: cell.t,
                u: cell.u,
                v: try ScalarInterval(lower: midpoint, upper: cell.v.upper),
                depth: cell.depth + 1
            ),
        ]
    }

    private func refinedIntersection(
        seed: ParameterSeed,
        curve: Curve3D,
        surface: Surface3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        var current = seed
        var verifiedIntersection: CurveSurfaceIntersection?
        for iteration in 0...maximumIterations {
            let curveGeometry = try curve.differentialGeometry(at: current.t, tolerance: tolerance)
            let surfaceGeometry = try surface.differentialGeometry(
                atU: current.u,
                v: current.v,
                tolerance: tolerance
            )
            let residualVector = curveGeometry.position - surfaceGeometry.position
            let residual = residualVector.length
            if residual <= tolerance.distance {
                let kind: CurveSurfaceIntersectionKind = abs(
                    curveGeometry.tangent.dot(surfaceGeometry.normal)
                ) <= tolerance.angle ? .tangent : .transverse
                verifiedIntersection = try CurveSurfaceIntersection(
                    point: curveGeometry.position,
                    curveParameter: current.t,
                    surfaceU: current.u,
                    surfaceV: current.v,
                    kind: kind,
                    residual: residual,
                    iterations: iteration
                )
            }
            guard iteration < maximumIterations else {
                return try finalizedIntersection(
                    verifiedIntersection,
                    curve: curve,
                    surface: surface,
                    curveRange: curveRange,
                    uRange: uRange,
                    vRange: vRange,
                    tolerance: tolerance
                )
            }
            let columnT = curveGeometry.firstDerivative
            let columnU = -surfaceGeometry.tangentU
            let columnV = -surfaceGeometry.tangentV
            let jacobianDeterminant = determinant(columnT, columnU, columnV)
            let rightHandSide = -residualVector
            let delta: ParameterSeed
            if abs(jacobianDeterminant) > max(
                Double.ulpOfOne,
                tolerance.angle * tolerance.angle
            ) {
                delta = ParameterSeed(
                    t: determinant(rightHandSide, columnU, columnV) / jacobianDeterminant,
                    u: determinant(columnT, rightHandSide, columnV) / jacobianDeterminant,
                    v: determinant(columnT, columnU, rightHandSide) / jacobianDeterminant
                )
            } else {
                guard let leastSquaresDelta = dampedLeastSquaresDelta(
                    columnT: columnT,
                    columnU: columnU,
                    columnV: columnV,
                    residual: residualVector,
                    curveRange: curveRange,
                    uRange: uRange,
                    vRange: vRange,
                    tolerance: tolerance
                ) else {
                    return try finalizedIntersection(
                        verifiedIntersection,
                        curve: curve,
                        surface: surface,
                        curveRange: curveRange,
                        uRange: uRange,
                        vRange: vRange,
                        tolerance: tolerance
                    )
                }
                delta = leastSquaresDelta
            }
            guard delta.t.isFinite, delta.u.isFinite, delta.v.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Curve-surface Newton refinement produced a non-finite step."
                )
            }
            let normalizedStep = max(
                abs(delta.t) / curveRange.width,
                max(
                    abs(delta.u) / uRange.width,
                    abs(delta.v) / vRange.width
                )
            )
            let stepTolerance = max(
                tolerance.angle * 0.01,
                Double.ulpOfOne * 256.0
            )
            if let verifiedIntersection,
               normalizedStep <= stepTolerance {
                return try finalizedIntersection(
                    verifiedIntersection,
                    curve: curve,
                    surface: surface,
                    curveRange: curveRange,
                    uRange: uRange,
                    vRange: vRange,
                    tolerance: tolerance
                )
            }
            var stepScale = 1.0
            var accepted: ParameterSeed?
            while stepScale >= 1.0 / 128.0 {
                let candidate = ParameterSeed(
                    t: clamped(current.t + delta.t * stepScale, to: curveRange),
                    u: clamped(current.u + delta.u * stepScale, to: uRange),
                    v: clamped(current.v + delta.v * stepScale, to: vRange)
                )
                let curvePoint = try curve.point(at: candidate.t, tolerance: tolerance)
                let surfacePoint = try surface.point(
                    u: candidate.u,
                    v: candidate.v,
                    tolerance: tolerance
                )
                if (curvePoint - surfacePoint).length < residual {
                    accepted = candidate
                    break
                }
                stepScale *= 0.5
            }
            guard let accepted else {
                return try finalizedIntersection(
                    verifiedIntersection,
                    curve: curve,
                    surface: surface,
                    curveRange: curveRange,
                    uRange: uRange,
                    vRange: vRange,
                    tolerance: tolerance
                )
            }
            current = accepted
        }
        return nil
    }

    private func finalizedIntersection(
        _ verified: CurveSurfaceIntersection?,
        curve: Curve3D,
        surface: Surface3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        guard let verified, verified.kind != .tangent else { return verified }
        return try polishedTangency(
            seed: ParameterSeed(
                t: verified.curveParameter,
                u: verified.surfaceU,
                v: verified.surfaceV
            ),
            initialIterations: verified.iterations,
            curve: curve,
            surface: surface,
            curveRange: curveRange,
            uRange: uRange,
            vRange: vRange,
            tolerance: tolerance
        ) ?? verified
    }

    private func polishedTangency(
        seed: ParameterSeed,
        initialIterations: Int,
        curve: Curve3D,
        surface: Surface3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        var current = seed
        for iteration in 0..<16 {
            let curveGeometry = try curve.differentialGeometry(
                at: current.t,
                tolerance: tolerance
            )
            let surfaceGeometry = try surface.differentialGeometry(
                atU: current.u,
                v: current.v,
                tolerance: tolerance
            )
            let residual = (
                curveGeometry.position - surfaceGeometry.position
            ).length
            let normalizedIncidence = abs(
                curveGeometry.tangent.dot(surfaceGeometry.normal)
            )
            if residual <= tolerance.distance,
               normalizedIncidence <= tolerance.angle {
                return try CurveSurfaceIntersection(
                    point: curveGeometry.position,
                    curveParameter: current.t,
                    surfaceU: current.u,
                    surfaceV: current.v,
                    kind: .tangent,
                    residual: residual,
                    iterations: initialIterations + iteration
                )
            }

            let tangentU = surfaceGeometry.tangentU
            let tangentV = surfaceGeometry.tangentV
            let firstMetric = tangentU.dot(tangentU)
            let mixedMetric = tangentU.dot(tangentV)
            let secondMetric = tangentV.dot(tangentV)
            let metricDeterminant = firstMetric * secondMetric
                - mixedMetric * mixedMetric
            let metricScale = max(
                firstMetric * secondMetric,
                mixedMetric * mixedMetric
            )
            guard metricDeterminant > max(
                metricScale * tolerance.relative,
                Double.ulpOfOne * 256.0
            ) else {
                return nil
            }
            let projectedU = curveGeometry.firstDerivative.dot(tangentU)
            let projectedV = curveGeometry.firstDerivative.dot(tangentV)
            let derivativeU = (
                secondMetric * projectedU - mixedMetric * projectedV
            ) / metricDeterminant
            let derivativeV = (
                firstMetric * projectedV - mixedMetric * projectedU
            ) / metricDeterminant
            let surfaceAcceleration = surfaceGeometry.secondDerivativeUU
                * (derivativeU * derivativeU)
                + surfaceGeometry.secondDerivativeUV
                * (2.0 * derivativeU * derivativeV)
                + surfaceGeometry.secondDerivativeVV
                * (derivativeV * derivativeV)
            let relativeAcceleration = curveGeometry.secondDerivative
                - surfaceAcceleration
            let normalAcceleration = relativeAcceleration.dot(
                surfaceGeometry.normal
            )
            let accelerationScale = max(
                relativeAcceleration.length,
                curveGeometry.firstDerivative.length
            )
            guard abs(normalAcceleration) > max(
                accelerationScale * tolerance.relative,
                Double.ulpOfOne * 256.0
            ) else {
                return nil
            }
            let incidence = curveGeometry.firstDerivative.dot(
                surfaceGeometry.normal
            )
            let parameterStep = -incidence / normalAcceleration
            guard parameterStep.isFinite else { return nil }

            var stepScale = 1.0
            var accepted: ParameterSeed?
            while stepScale >= 1.0 / 128.0 {
                let scaledStep = parameterStep * stepScale
                let candidate = ParameterSeed(
                    t: clamped(current.t + scaledStep, to: curveRange),
                    u: clamped(
                        current.u + derivativeU * scaledStep,
                        to: uRange
                    ),
                    v: clamped(
                        current.v + derivativeV * scaledStep,
                        to: vRange
                    )
                )
                let candidateCurve = try curve.differentialGeometry(
                    at: candidate.t,
                    tolerance: tolerance
                )
                let candidateSurface = try surface.differentialGeometry(
                    atU: candidate.u,
                    v: candidate.v,
                    tolerance: tolerance
                )
                let candidateResidual = (
                    candidateCurve.position - candidateSurface.position
                ).length
                let candidateIncidence = abs(
                    candidateCurve.tangent.dot(candidateSurface.normal)
                )
                if candidateResidual <= tolerance.distance,
                   candidateIncidence < normalizedIncidence {
                    accepted = candidate
                    break
                }
                stepScale *= 0.5
            }
            guard let accepted else { return nil }
            current = accepted
        }
        return nil
    }

    private func dampedLeastSquaresDelta(
        columnT: Vector3D,
        columnU: Vector3D,
        columnV: Vector3D,
        residual: Vector3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) -> ParameterSeed? {
        let tScale = curveRange.width
        let uScale = uRange.width
        let vScale = vRange.width
        guard tScale.isFinite, tScale > 0.0,
              uScale.isFinite, uScale > 0.0,
              vScale.isFinite, vScale > 0.0 else {
            return nil
        }
        let scaledT = columnT * tScale
        let scaledU = columnU * uScale
        let scaledV = columnV * vScale
        let diagonalT = scaledT.dot(scaledT)
        let diagonalU = scaledU.dot(scaledU)
        let diagonalV = scaledV.dot(scaledV)
        let matrixScale = max(diagonalT, max(diagonalU, diagonalV))
        guard matrixScale.isFinite, matrixScale > 0.0 else { return nil }
        let damping = max(
            matrixScale * tolerance.relative,
            matrixScale * Double.ulpOfOne * 256.0
        )
        let crossTU = scaledT.dot(scaledU)
        let crossTV = scaledT.dot(scaledV)
        let crossUV = scaledU.dot(scaledV)
        let firstColumn = Vector3D(
            x: diagonalT + damping,
            y: crossTU,
            z: crossTV
        )
        let secondColumn = Vector3D(
            x: crossTU,
            y: diagonalU + damping,
            z: crossUV
        )
        let thirdColumn = Vector3D(
            x: crossTV,
            y: crossUV,
            z: diagonalV + damping
        )
        let rightHandSide = Vector3D(
            x: -scaledT.dot(residual),
            y: -scaledU.dot(residual),
            z: -scaledV.dot(residual)
        )
        let systemDeterminant = determinant(
            firstColumn,
            secondColumn,
            thirdColumn
        )
        let determinantFloor = max(
            pow(matrixScale, 3.0) * Double.ulpOfOne * 256.0,
            Double.leastNonzeroMagnitude
        )
        guard systemDeterminant.isFinite,
              abs(systemDeterminant) > determinantFloor else {
            return nil
        }
        let fractionT = determinant(
            rightHandSide,
            secondColumn,
            thirdColumn
        ) / systemDeterminant
        let fractionU = determinant(
            firstColumn,
            rightHandSide,
            thirdColumn
        ) / systemDeterminant
        let fractionV = determinant(
            firstColumn,
            secondColumn,
            rightHandSide
        ) / systemDeterminant
        let delta = ParameterSeed(
            t: fractionT * tScale,
            u: fractionU * uScale,
            v: fractionV * vScale
        )
        guard delta.t.isFinite, delta.u.isFinite, delta.v.isFinite else {
            return nil
        }
        return delta
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
                (existing.point - intersection.point).length <= tolerance.distance &&
                    abs(existing.curveParameter - intersection.curveParameter) <= max(tolerance.distance, tolerance.angle)
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
    }

    private struct ParameterSeed: Sendable {
        let t: Double
        let u: Double
        let v: Double
    }

    private struct AdaptiveCandidate: Sendable {
        let seed: ParameterSeed
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
}
