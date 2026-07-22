import CADCore
import CADGeometry
import Foundation

/// Certifies the Green boundary integral `integral Q(u, v) dv` for explicit
/// pcurves on analytic surfaces. Adaptive subdivision is bounded and returns a
/// typed resource failure instead of accepting an enclosure wider than asked.
struct CertifiedAnalyticPcurveFluxIntegrator {
    typealias Integrand = TrimmedAnalyticSurfaceVolumeEvaluator.Integrand
    typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    typealias HomogeneousPatch = CertifiedHomogeneousBezierCurvePatch
    typealias ScalarBounds = HomogeneousPatch.ScalarBounds

    private let maximumWorkItems: Int
    private let maximumDepth: Int

    private enum LocalProofFailure: Error {
        case intervalSingularity
    }

    private enum PiecewiseRationalEnclosure {
        case enclosed(TensorGaussEnclosure)
        case seamEnclosed(SeamEnclosure)
    }

    private enum SeamSplitLocation {
        case lower
        case upper
        case balanced
    }

    private struct SeamEnclosure {
        let bounds: Interval
        let splitLocation: SeamSplitLocation
    }

    private struct RationalSeamRootCell {
        let differences: [ScalarBounds]
        let weights: [ScalarBounds]
        let lower: Double
        let upper: Double
        let depth: Int
    }

    private struct TensorGaussEnclosure {
        let bounds: Interval
        let lambdaError: Double
        let curveError: Double
    }

    init(maximumWorkItems: Int = 65_536, maximumDepth: Int = 48) {
        self.maximumWorkItems = maximumWorkItems
        self.maximumDepth = maximumDepth
    }

    func parameterEnclosures(
        for curve: SurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try tolerance.validate()
        guard maximumWidth.isFinite, maximumWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: maximumWidth,
                tolerance: tolerance,
                message: "Certified analytic pcurve enclosure requires a finite positive width."
            )
        }
        switch curve {
        case let .sphericalGreatCircle(
            cosine,
            sine,
            startParameter,
            endParameter
        ):
            try cosine.validateUnitLength(tolerance: tolerance)
            try sine.validateUnitLength(tolerance: tolerance)
            guard abs(cosine.dot(sine)) <= tolerance.angle else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: abs(cosine.dot(sine)),
                    tolerance: tolerance,
                    message: "A spherical pcurve enclosure requires an orthonormal great-circle frame."
                )
            }
            return try adaptiveParameterEnclosures(
                maximumWidth: maximumWidth,
                tolerance: tolerance
            ) { fraction in
                let parameter = Jet.constant(startParameter)
                    + Jet.constant(endParameter - startParameter) * fraction
                return try greatCircleParameterJets(
                    cosine: cosine,
                    sine: sine,
                    parameter: parameter
                )
            }
        case let .projectedAnalytic(projected):
            return try adaptiveParameterEnclosures(
                maximumWidth: maximumWidth,
                tolerance: tolerance
            ) { fraction in
                try projectedAnalyticParameterJets(
                    projected,
                    fraction: fraction,
                    tolerance: tolerance
                )
            }
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "This analytic enclosure path received an incompatible pcurve representation."
            )
        }
    }

    func bounds(
        for curve: SurfaceParameterCurve,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        try tolerance.validate()
        guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified analytic pcurve flux requires a finite positive enclosure width."
            )
        }
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return try adaptiveJetBounds(
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let parameterSpan = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + parameterSpan * fraction
                let u = Jet.constant(origin.x) + Jet.constant(direction.x) * parameter
                let v = Jet.constant(origin.y) + Jet.constant(direction.y) * parameter
                let derivativeV = Jet.constant(direction.y) * parameterSpan
                return greenPrimitive(
                    integrand: integrand,
                    u: u,
                    v: v
                ) * derivativeV
            }
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return try adaptiveJetBounds(
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let parameterSpan = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + parameterSpan * fraction
                let values = parameter.sineAndCosine()
                let u = Jet.constant(center.x)
                    + Jet.constant(cosine.x) * values.cosine
                    + Jet.constant(sine.x) * values.sine
                let v = Jet.constant(center.y)
                    + Jet.constant(cosine.y) * values.cosine
                    + Jet.constant(sine.y) * values.sine
                let derivativeV = (
                    -Jet.constant(cosine.y) * values.sine
                        + Jet.constant(sine.y) * values.cosine
                ) * parameterSpan
                return greenPrimitive(
                    integrand: integrand,
                    u: u,
                    v: v
                ) * derivativeV
            }
        case let .polyline(points):
            guard points.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: Double(points.count),
                    tolerance: tolerance,
                    message: "Certified analytic polyline flux requires at least two points."
                )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                let deltaU = Interval.exact(end.u) - .exact(start.u)
                let deltaV = Interval.exact(end.v) - .exact(start.v)
                result = result + (try adaptiveJetBounds(
                    requestedWidth: segmentWidth,
                    tolerance: tolerance
                ) { fraction in
                    let u = Jet.constant(start.u) + Jet.constant(deltaU) * fraction
                    let v = Jet.constant(start.v) + Jet.constant(deltaV) * fraction
                    return greenPrimitive(
                        integrand: integrand,
                        u: u,
                        v: v
                    ) * Jet.constant(deltaV)
                })
            }
            return result
        case let .sphericalGreatCircle(
            cosine,
            sine,
            startParameter,
            endParameter
        ):
            return try sphericalGreatCircleBounds(
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .bSpline(spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
                curve: spline,
                tolerance: tolerance
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
                result = result + (try adaptiveJetBounds(
                    requestedWidth: patchWidth,
                    tolerance: tolerance
                ) { fraction in
                    try rationalFluxJet(
                        patch: patch,
                        fraction: fraction,
                        integrand: integrand,
                        tolerance: tolerance
                    )
                })
            }
            return result
        case let .certifiedAnalyticImplicit(certified):
            return try certifiedAnalyticImplicitBounds(
                curve: certified,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(certified):
            return try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
                for: certified,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case .constantU, .constantV:
            preconditionFailure("Coordinate pcurves must use the closed-form boundary path.")
        case .certifiedImplicit:
            // Intersection-backed pcurve flux certification is implemented by
            // the parametric-surface volume path. This analytic caller must
            // treat nil as unsupported and cannot report a successful result.
            return nil
        case let .projectedAnalytic(projected):
            return try adaptiveJetBounds(
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let parameters = try projectedAnalyticParameterJets(
                    projected,
                    fraction: fraction,
                    tolerance: tolerance
                )
                return greenPrimitive(
                    integrand: integrand,
                    u: parameters.u,
                    v: parameters.v
                ) * parameters.v.derivative()
            }
        }
    }

    func projectedParameterAreaBounds(
        for curve: ProjectedAnalyticSurfaceParameterCurve,
        uShift: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        try curve.validate(on: curve.surface, tolerance: tolerance)
        guard uShift.isFinite,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified projected pcurve area requires finite positive options."
            )
        }
        return try adaptiveJetBounds(
            requestedWidth: requestedWidth,
            tolerance: tolerance
        ) { fraction in
            let parameters = try projectedAnalyticParameterJets(
                curve,
                fraction: fraction,
                tolerance: tolerance
            )
            return (parameters.u + .constant(uShift)) * parameters.v.derivative()
        }
    }

    func polynomialBounds(
        for curve: SurfaceParameterCurve,
        primitive: CertifiedPolynomialSurfaceFluxPrimitive,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        try tolerance.validate()
        guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified polynomial pcurve flux requires a finite positive enclosure width."
            )
        }
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return try adaptiveJetBounds(
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let v = Jet.constant(vStart)
                    + Jet.constant(Interval.exact(vEnd) - .exact(vStart)) * fraction
                return try polynomialFluxJet(
                    primitive: primitive,
                    u: .constant(u),
                    v: v,
                    tolerance: tolerance
                )
            }
        case .constantV:
            return .exact(0.0)
        case let .affine(origin, direction, startParameter, endParameter):
            return try adaptiveJetBounds(
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let parameterSpan = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + parameterSpan * fraction
                let u = Jet.constant(origin.x) + Jet.constant(direction.x) * parameter
                let v = Jet.constant(origin.y) + Jet.constant(direction.y) * parameter
                return try polynomialFluxJet(
                    primitive: primitive,
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
            }
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return try adaptiveJetBounds(
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let parameterSpan = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + parameterSpan * fraction
                let values = parameter.sineAndCosine()
                let u = Jet.constant(center.x)
                    + Jet.constant(cosine.x) * values.cosine
                    + Jet.constant(sine.x) * values.sine
                let v = Jet.constant(center.y)
                    + Jet.constant(cosine.y) * values.cosine
                    + Jet.constant(sine.y) * values.sine
                return try polynomialFluxJet(
                    primitive: primitive,
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
            }
        case let .polyline(points):
            guard points.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: Double(points.count),
                    tolerance: tolerance,
                    message: "Certified polynomial polyline flux requires at least two points."
                )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                result = result + (try adaptiveJetBounds(
                    requestedWidth: segmentWidth,
                    tolerance: tolerance
                ) { fraction in
                    let u = Jet.constant(start.u)
                        + Jet.constant(Interval.exact(end.u) - .exact(start.u)) * fraction
                    let v = Jet.constant(start.v)
                        + Jet.constant(Interval.exact(end.v) - .exact(start.v)) * fraction
                    return try polynomialFluxJet(
                        primitive: primitive,
                        u: u,
                        v: v,
                        tolerance: tolerance
                    )
                })
            }
            return result
        case let .bSpline(spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
                curve: spline,
                tolerance: tolerance
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
                result = result + (try adaptiveJetBounds(
                    requestedWidth: patchWidth,
                    tolerance: tolerance
                ) { fraction in
                    let parameters = try rationalPcurveJets(
                        patch: patch,
                        fraction: fraction,
                        tolerance: tolerance
                    )
                    return try polynomialFluxJet(
                        primitive: primitive,
                        u: parameters.u,
                        v: parameters.v,
                        tolerance: tolerance
                    )
                })
            }
            return result
        case .sphericalGreatCircle,
             .certifiedImplicit,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        }
    }

    func rationalSurfaceBounds(
        for curve: SurfaceParameterCurve,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        try tolerance.validate()
        guard uBase.isFinite,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified rational pcurve flux requires a finite base and positive enclosure width."
            )
        }
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return try rationalSurfaceExplicitBounds(
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance,
                curveBreaks: linearSurfaceSpanBreaks(
                    uStart: u,
                    uEnd: u,
                    vStart: vStart,
                    vEnd: vEnd,
                    field: field
                )
            ) { fraction in
                (
                    .constant(u),
                    .constant(vStart)
                        + .constant(Interval.exact(vEnd) - .exact(vStart)) * fraction
                )
            }
        case .constantV:
            return .exact(0.0)
        case let .affine(origin, direction, startParameter, endParameter):
            let uStart = origin.x + direction.x * startParameter
            let uEnd = origin.x + direction.x * endParameter
            let vStart = origin.y + direction.y * startParameter
            let vEnd = origin.y + direction.y * endParameter
            return try rationalSurfaceExplicitBounds(
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance,
                curveBreaks: linearSurfaceSpanBreaks(
                    uStart: uStart,
                    uEnd: uEnd,
                    vStart: vStart,
                    vEnd: vEnd,
                    field: field
                )
            ) { fraction in
                let span = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + span * fraction
                return (
                    Jet.constant(origin.x) + Jet.constant(direction.x) * parameter,
                    Jet.constant(origin.y) + Jet.constant(direction.y) * parameter
                )
            }
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return try rationalSurfaceExplicitBounds(
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance,
                curveBreaks: try harmonicSurfaceSpanBreaks(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    field: field,
                    tolerance: tolerance
                )
            ) { fraction in
                let span = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + span * fraction
                let values = parameter.sineAndCosine()
                return (
                    Jet.constant(center.x)
                        + Jet.constant(cosine.x) * values.cosine
                        + Jet.constant(sine.x) * values.sine,
                    Jet.constant(center.y)
                        + Jet.constant(cosine.y) * values.cosine
                        + Jet.constant(sine.y) * values.sine
                )
            }
        case let .polyline(points):
            guard points.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: Double(points.count),
                    tolerance: tolerance,
                    message: "Certified rational polyline flux requires at least two points."
                )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                result = result + (try rationalSurfaceExplicitBounds(
                    field: field,
                    uBase: uBase,
                    requestedWidth: segmentWidth,
                    tolerance: tolerance,
                    curveBreaks: linearSurfaceSpanBreaks(
                        uStart: start.u,
                        uEnd: end.u,
                        vStart: start.v,
                        vEnd: end.v,
                        field: field
                    )
                ) { fraction in
                    (
                        .constant(start.u)
                            + .constant(Interval.exact(end.u) - .exact(start.u)) * fraction,
                        .constant(start.v)
                            + .constant(Interval.exact(end.v) - .exact(start.v)) * fraction
                    )
                })
            }
            return result
        case let .bSpline(spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
                curve: spline,
                tolerance: tolerance
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
                result = result + (try rationalSurfaceExplicitBounds(
                    field: field,
                    uBase: uBase,
                    requestedWidth: patchWidth,
                    tolerance: tolerance,
                    curveBreaks: try rationalPcurveSurfaceSpanBreaks(
                        patch: patch,
                        field: field,
                        tolerance: tolerance
                    )
                ) { fraction in
                    try rationalPcurveJets(
                        patch: patch,
                        fraction: fraction,
                        tolerance: tolerance
                    )
                })
            }
            return result
        case let .certifiedImplicit(certified):
            return try rationalSurfaceImplicitBounds(
                curve: certified,
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case .sphericalGreatCircle,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        }
    }

    func rationalPlanarAreaBounds(
        for curve: SurfaceParameterCurve,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        try tolerance.validate()
        guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified rational planar area requires a positive enclosure width."
            )
        }
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return try rationalPlanarExplicitBounds(
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                (
                    .constant(u),
                    .constant(vStart)
                        + .constant(Interval.exact(vEnd) - .exact(vStart)) * fraction
                )
            }
        case let .constantV(v, uStart, uEnd):
            return try rationalPlanarExplicitBounds(
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                (
                    .constant(uStart)
                        + .constant(Interval.exact(uEnd) - .exact(uStart)) * fraction,
                    .constant(v)
                )
            }
        case let .affine(origin, direction, startParameter, endParameter):
            return try rationalPlanarExplicitBounds(
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let span = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + span * fraction
                return (
                    Jet.constant(origin.x) + Jet.constant(direction.x) * parameter,
                    Jet.constant(origin.y) + Jet.constant(direction.y) * parameter
                )
            }
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return try rationalPlanarExplicitBounds(
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            ) { fraction in
                let span = Jet.constant(
                    Interval.exact(endParameter) - .exact(startParameter)
                )
                let parameter = Jet.constant(startParameter) + span * fraction
                let values = parameter.sineAndCosine()
                return (
                    Jet.constant(center.x)
                        + Jet.constant(cosine.x) * values.cosine
                        + Jet.constant(sine.x) * values.sine,
                    Jet.constant(center.y)
                        + Jet.constant(cosine.y) * values.cosine
                        + Jet.constant(sine.y) * values.sine
                )
            }
        case let .polyline(points):
            guard points.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: Double(points.count),
                    tolerance: tolerance,
                    message: "Certified rational planar polyline requires at least two points."
                )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                result = result + (try rationalPlanarExplicitBounds(
                    field: field,
                    projection: projection,
                    requestedWidth: segmentWidth,
                    tolerance: tolerance
                ) { fraction in
                    (
                        .constant(start.u)
                            + .constant(Interval.exact(end.u) - .exact(start.u)) * fraction,
                        .constant(start.v)
                            + .constant(Interval.exact(end.v) - .exact(start.v)) * fraction
                    )
                })
            }
            return result
        case let .bSpline(spline):
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
                curve: spline,
                tolerance: tolerance
            )
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
                result = result + (try rationalPlanarExplicitBounds(
                    field: field,
                    projection: projection,
                    requestedWidth: patchWidth,
                    tolerance: tolerance
                ) { fraction in
                    try rationalPcurveJets(
                        patch: patch,
                        fraction: fraction,
                        tolerance: tolerance
                    )
                })
            }
            return result
        case .sphericalGreatCircle,
             .certifiedImplicit,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        }
    }

    private func rationalPlanarExplicitBounds(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
        requestedWidth: Double,
        tolerance: ModelingTolerance,
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet)
    ) throws -> Interval {
        struct WorkItem {
            let lower: Double
            let upper: Double
            let widthBudget: Double
            let depth: Int
        }
        var pending = [WorkItem(
            lower: 0.0,
            upper: 1.0,
            widthBudget: requestedWidth,
            depth: 0
        )]
        var result = Interval.exact(0.0)
        var workItemCount = 0
        while let item = pending.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified rational planar area exhausted its curve-cell budget."
                )
            }
            let curve = try parameterEvaluator(
                .variable(Interval(lower: item.lower, upper: item.upper))
            )
            let uSpan = field.containingUSpan(curve.u.coefficients[0])
            let vSpan = field.containingVSpan(curve.v.coefficients[0])
            let enclosure: Interval?
            if let uSpan, let vSpan {
                enclosure = try rationalPlanarGaussEnclosure(
                    field: field,
                    projection: projection,
                    uSpan: uSpan,
                    vSpan: vSpan,
                    lower: item.lower,
                    upper: item.upper,
                    parameterEvaluator: parameterEvaluator,
                    tolerance: tolerance
                )
            } else {
                let range = try field.projectedBoundaryAreaRange(
                    u: certifiedJet(curve.u),
                    v: certifiedJet(curve.v),
                    projection: projection
                )
                enclosure = Interval(
                    lower: range.lower,
                    upper: range.upper
                ) * .floating(item.upper - item.lower)
            }
            if let enclosure, enclosure.width <= item.widthBudget {
                result = result + enclosure
                continue
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: enclosure?.width,
                    tolerance: tolerance,
                    message: "Certified rational planar area exceeded its proof depth."
                )
            }
            let middle = item.lower + (item.upper - item.lower) * 0.5
            let halfBudget = item.widthBudget * 0.5
            pending.append(WorkItem(
                lower: middle,
                upper: item.upper,
                widthBudget: halfBudget,
                depth: item.depth + 1
            ))
            pending.append(WorkItem(
                lower: item.lower,
                upper: middle,
                widthBudget: halfBudget,
                depth: item.depth + 1
            ))
        }
        return result
    }

    private func rationalPlanarGaussEnclosure(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection,
        uSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
        vSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
        lower: Double,
        upper: Double,
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet),
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let midpoint = lower + (upper - lower) * 0.5
        let halfSpan = (upper - lower) * 0.5
        let root = sqrt(3.0 / 5.0)
        let nodes = [midpoint - halfSpan * root, midpoint, midpoint + halfSpan * root]
        let weights = [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
        var estimate = Interval.exact(0.0)
        for index in nodes.indices {
            let curve = try parameterEvaluator(.variable(.exact(nodes[index])))
            let value = try field.projectedBoundaryAreaJet(
                u: certifiedJet(curve.u),
                v: certifiedJet(curve.v),
                projection: projection,
                uSpan: uSpan,
                vSpan: vSpan
            ).coefficients[0]
            estimate = estimate + value * .floating(weights[index])
        }
        estimate = estimate * .floating(halfSpan)

        let curve = try parameterEvaluator(
            .variable(Interval(lower: lower, upper: upper))
        )
        let integrand = try field.projectedBoundaryAreaJet(
            u: certifiedJet(curve.u),
            v: certifiedJet(curve.v),
            projection: projection,
            uSpan: uSpan,
            vSpan: vSpan
        )
        let sixthCoefficient = integrand.coefficients[6].maximumAbsolute
        let sixthDerivative = outwardProduct(sixthCoefficient, 720.0)
        let gaussConstant = 1_296.0 / (7.0 * 720.0 * 720.0 * 720.0)
        var error = outwardProduct(
            outwardProduct(sixthDerivative, gaussConstant),
            pow(upper - lower, 7.0)
        )
        for _ in 0..<8 { error = error.nextUp }
        guard estimate.lower.isFinite,
              estimate.upper.isFinite,
              error.isFinite else {
            throw resourceFailure(
                residual: error,
                tolerance: tolerance,
                message: "Certified rational planar area exceeded finite arithmetic."
            )
        }
        return Interval(
            lower: (estimate.lower - error).nextDown,
            upper: (estimate.upper + error).nextUp
        )
    }

    private func certifiedJet(
        _ jet: Jet
    ) -> CertifiedUnivariateTaylorJet {
        CertifiedUnivariateTaylorJet.series(
            jet.coefficients.map {
                CertifiedUnivariateTaylorJet.Interval(
                    lower: $0.lower,
                    upper: $0.upper
                )
            }
        )
    }

    private func rationalSurfaceExplicitBounds(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance,
        curveBreaks: [Double] = [0.0, 1.0],
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet)
    ) throws -> Interval {
        struct WorkItem {
            let lambdaLower: Double
            let lambdaUpper: Double
            let curveLower: Double
            let curveUpper: Double
            let widthBudget: Double
            let depth: Int
        }
        let orderedBreaks = Array(Set(curveBreaks + [0.0, 1.0]))
            .filter { $0 >= 0.0 && $0 <= 1.0 }
            .sorted()
        guard orderedBreaks.count >= 2 else {
            throw resourceFailure(
                residual: Double(orderedBreaks.count),
                tolerance: tolerance,
                message: "Certified rational pcurve flux found no bounded curve partition."
            )
        }
        guard maximumWorkItems > 0 else {
            throw resourceFailure(
                residual: Double(maximumWorkItems),
                tolerance: tolerance,
                message: "Certified rational pcurve flux has no two-dimensional cell budget."
            )
        }
        let activeIntervals = (1..<orderedBreaks.count).compactMap { index
            -> (lower: Double, upper: Double)? in
            let lower = orderedBreaks[index - 1]
            let upper = orderedBreaks[index]
            return upper > lower ? (lower, upper) : nil
        }
        guard !activeIntervals.isEmpty else {
            throw resourceFailure(
                residual: 0.0,
                tolerance: tolerance,
                message: "Certified rational pcurve flux found no positive curve partition."
            )
        }
        let hierarchicalBudget = requestedWidth * 0.5
        let intervalBudget = hierarchicalBudget / Double(activeIntervals.count)
        let leafRoundoffBudget = requestedWidth
            * 0.5
            / Double(maximumWorkItems)
        var pending: [WorkItem] = []
        pending.reserveCapacity(activeIntervals.count)
        for interval in activeIntervals {
            pending.append(WorkItem(
                lambdaLower: 0.0,
                lambdaUpper: 1.0,
                curveLower: interval.lower,
                curveUpper: interval.upper,
                widthBudget: intervalBudget,
                depth: 0
            ))
        }
        var result = Interval.exact(0.0)
        var workItemCount = 0
        while let item = pending.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified rational pcurve flux exhausted its two-dimensional cell budget."
                )
            }
            let piecewise = try piecewiseRationalSurfaceGaussEnclosure(
                field: field,
                uBase: uBase,
                lambdaLower: item.lambdaLower,
                lambdaUpper: item.lambdaUpper,
                curveLower: item.curveLower,
                curveUpper: item.curveUpper,
                parameterEvaluator: parameterEvaluator,
                tolerance: tolerance
            )
            let enclosure: Interval
            let preferredCurveSplit: Bool
            let seamSplitLocation: SeamSplitLocation?
            let directionalErrors: (lambda: Double, curve: Double)?
            switch piecewise {
            case let .enclosed(value):
                enclosure = value.bounds
                preferredCurveSplit = value.curveError >= value.lambdaError
                seamSplitLocation = nil
                directionalErrors = (value.lambdaError, value.curveError)
            case let .seamEnclosed(value):
                enclosure = value.bounds
                preferredCurveSplit = true
                seamSplitLocation = value.splitLocation
                directionalErrors = nil
            }
            if enclosure.width <= (item.widthBudget + leafRoundoffBudget).nextUp {
                result = result + enclosure
                continue
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: enclosure.width,
                    tolerance: tolerance,
                    message: directionalErrors.map {
                        "Certified rational pcurve flux exceeded its two-dimensional proof depth (lambda remainder: \($0.lambda), curve remainder: \($0.curve))."
                    } ?? "Certified rational pcurve flux exceeded its two-dimensional proof depth while isolating a surface-span crossing."
                )
            }
            let halfBudget = item.widthBudget * 0.5
            if preferredCurveSplit {
                let middle = item.curveLower
                    + (item.curveUpper - item.curveLower) * 0.5
                let lowerBudget: Double
                let upperBudget: Double
                switch seamSplitLocation {
                case .lower:
                    lowerBudget = item.widthBudget * 0.75
                    upperBudget = item.widthBudget * 0.25
                case .upper:
                    lowerBudget = item.widthBudget * 0.25
                    upperBudget = item.widthBudget * 0.75
                case .balanced, nil:
                    lowerBudget = halfBudget
                    upperBudget = halfBudget
                }
                pending.append(WorkItem(
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    curveLower: middle,
                    curveUpper: item.curveUpper,
                    widthBudget: upperBudget,
                    depth: item.depth + 1
                ))
                pending.append(WorkItem(
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    curveLower: item.curveLower,
                    curveUpper: middle,
                    widthBudget: lowerBudget,
                    depth: item.depth + 1
                ))
            } else {
                let middle = item.lambdaLower
                    + (item.lambdaUpper - item.lambdaLower) * 0.5
                pending.append(WorkItem(
                    lambdaLower: middle,
                    lambdaUpper: item.lambdaUpper,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    widthBudget: halfBudget,
                    depth: item.depth + 1
                ))
                pending.append(WorkItem(
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: middle,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    widthBudget: halfBudget,
                    depth: item.depth + 1
                ))
            }
        }
        return result
    }

    private func linearSurfaceSpanBreaks(
        uStart: Double,
        uEnd: Double,
        vStart: Double,
        vEnd: Double,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField
    ) -> [Double] {
        var breaks = [0.0, 1.0]
        appendLinearSeamBreaks(
            start: uStart,
            end: uEnd,
            seams: interiorSeams(field.uSpans),
            to: &breaks
        )
        appendLinearSeamBreaks(
            start: vStart,
            end: vEnd,
            seams: interiorSeams(field.vSpans),
            to: &breaks
        )
        return Array(Set(breaks)).sorted()
    }

    private func appendLinearSeamBreaks(
        start: Double,
        end: Double,
        seams: [Double],
        to breaks: inout [Double]
    ) {
        let displacement = end - start
        guard displacement.isFinite, displacement != 0.0 else { return }
        for seam in seams {
            let fraction = (seam - start) / displacement
            if fraction > 0.0, fraction < 1.0, fraction.isFinite {
                breaks.append(fraction)
            }
        }
    }

    private func harmonicSurfaceSpanBreaks(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let values = [
            center.x, center.y,
            cosine.x, cosine.y,
            sine.x, sine.y,
            startParameter, endParameter,
        ]
        guard values.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified rational harmonic pcurve seam isolation requires finite coefficients and parameters."
            )
        }
        var breaks = [0.0, 1.0]
        try appendHarmonicSeamBreaks(
            center: center.x,
            cosine: cosine.x,
            sine: sine.x,
            startParameter: startParameter,
            endParameter: endParameter,
            seams: interiorSeams(field.uSpans),
            to: &breaks,
            tolerance: tolerance
        )
        try appendHarmonicSeamBreaks(
            center: center.y,
            cosine: cosine.y,
            sine: sine.y,
            startParameter: startParameter,
            endParameter: endParameter,
            seams: interiorSeams(field.vSpans),
            to: &breaks,
            tolerance: tolerance
        )
        return sortedUniqueFractions(breaks)
    }

    private func appendHarmonicSeamBreaks(
        center: Double,
        cosine: Double,
        sine: Double,
        startParameter: Double,
        endParameter: Double,
        seams: [Double],
        to breaks: inout [Double],
        tolerance: ModelingTolerance
    ) throws {
        let parameterSpan = endParameter - startParameter
        guard parameterSpan != 0.0 else { return }
        let amplitude = hypot(cosine, sine)
        guard amplitude > 0.0 else { return }
        let phase = atan2(sine, cosine)
        let parameterLower = min(startParameter, endParameter)
        let parameterUpper = max(startParameter, endParameter)
        let twoPi = 2.0 * Double.pi
        for seam in seams {
            let normalized = (seam - center) / amplitude
            let scale = max(1.0, abs(seam), abs(center), amplitude)
            let normalizedSlack = Double.ulpOfOne * scale / amplitude * 512.0
            guard normalized >= -1.0 - normalizedSlack,
                  normalized <= 1.0 + normalizedSlack else {
                continue
            }
            let angle = acos(min(1.0, max(-1.0, normalized)))
            for base in [phase - angle, phase + angle] {
                let lowerIndex = ceil((parameterLower - base) / twoPi)
                let upperIndex = floor((parameterUpper - base) / twoPi)
                guard lowerIndex.isFinite, upperIndex.isFinite else {
                    throw resourceFailure(
                        residual: nil,
                        tolerance: tolerance,
                        message: "Certified rational harmonic pcurve seam isolation exceeded finite turn indexing."
                    )
                }
                guard upperIndex >= lowerIndex else { continue }
                let rootCount = upperIndex - lowerIndex + 1.0
                guard breaks.count <= maximumWorkItems else {
                    throw resourceFailure(
                        residual: Double(breaks.count),
                        tolerance: tolerance,
                        message: "Certified rational harmonic pcurve seam isolation exhausted its root budget."
                    )
                }
                let remainingCapacity = maximumWorkItems - breaks.count
                guard rootCount <= Double(remainingCapacity) else {
                    throw resourceFailure(
                        residual: rootCount,
                        tolerance: tolerance,
                        message: "Certified rational harmonic pcurve seam isolation exhausted its root budget."
                    )
                }
                var index = lowerIndex
                while index <= upperIndex {
                    let parameter = base + twoPi * index
                    let fraction = (parameter - startParameter) / parameterSpan
                    if fraction > 0.0, fraction < 1.0, fraction.isFinite {
                        breaks.append(fraction)
                    }
                    index += 1.0
                }
            }
        }
    }

    private func rationalPcurveSurfaceSpanBreaks(
        patch: HomogeneousPatch,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard patch.degree >= 1,
              patch.controls.allSatisfy(\.isFiniteAndPositiveWeight) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified rational pcurve seam isolation requires valid homogeneous controls."
            )
        }
        var breaks = [0.0, 1.0]
        var workItemCount = 0
        for seam in interiorSeams(field.uSpans) {
            try appendRationalBezierSeamBreaks(
                coordinateControls: patch.controls.map(\.x),
                weightControls: patch.controls.map(\.weight),
                seam: seam,
                to: &breaks,
                workItemCount: &workItemCount,
                tolerance: tolerance
            )
        }
        for seam in interiorSeams(field.vSpans) {
            try appendRationalBezierSeamBreaks(
                coordinateControls: patch.controls.map(\.y),
                weightControls: patch.controls.map(\.weight),
                seam: seam,
                to: &breaks,
                workItemCount: &workItemCount,
                tolerance: tolerance
            )
        }
        return sortedUniqueFractions(breaks)
    }

    private func appendRationalBezierSeamBreaks(
        coordinateControls: [ScalarBounds],
        weightControls: [ScalarBounds],
        seam: Double,
        to breaks: inout [Double],
        workItemCount: inout Int,
        tolerance: ModelingTolerance
    ) throws {
        let differences = coordinateControls.indices.map { index in
            coordinateControls[index]
                - ScalarBounds.exact(seam) * weightControls[index]
        }
        let coordinateSlack = Double.ulpOfOne
            * max(1.0, abs(seam))
            * 128.0
        if rationalCoordinateResidual(
            differences: differences,
            weights: weightControls
        ) <= coordinateSlack {
            return
        }
        var pending = [RationalSeamRootCell(
            differences: differences,
            weights: weightControls,
            lower: 0.0,
            upper: 1.0,
            depth: 0
        )]
        while let cell = pending.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified rational pcurve seam isolation exhausted its Bernstein-cell budget."
                )
            }
            let hullLower = cell.differences.map(\.lower).min() ?? -.infinity
            let hullUpper = cell.differences.map(\.upper).max() ?? .infinity
            if hullLower > 0.0 || hullUpper < 0.0 {
                continue
            }
            let residual = rationalCoordinateResidual(
                differences: cell.differences,
                weights: cell.weights
            )
            if residual <= coordinateSlack {
                if cell.lower > 0.0 { breaks.append(cell.lower) }
                if cell.upper < 1.0 { breaks.append(cell.upper) }
                continue
            }
            guard cell.depth < maximumDepth else {
                throw resourceFailure(
                    residual: residual,
                    tolerance: tolerance,
                    message: "Certified rational pcurve seam isolation exceeded its Bernstein proof depth."
                )
            }
            let differenceChildren = subdividedBernsteinControls(cell.differences)
            let weightChildren = subdividedBernsteinControls(cell.weights)
            let middle = cell.lower + (cell.upper - cell.lower) * 0.5
            pending.append(RationalSeamRootCell(
                differences: differenceChildren.upper,
                weights: weightChildren.upper,
                lower: middle,
                upper: cell.upper,
                depth: cell.depth + 1
            ))
            pending.append(RationalSeamRootCell(
                differences: differenceChildren.lower,
                weights: weightChildren.lower,
                lower: cell.lower,
                upper: middle,
                depth: cell.depth + 1
            ))
        }
    }

    private func rationalCoordinateResidual(
        differences: [ScalarBounds],
        weights: [ScalarBounds]
    ) -> Double {
        let numerator = differences.reduce(0.0) { partial, value in
            max(partial, abs(value.lower), abs(value.upper))
        }
        let denominator = weights.map(\.lower).min() ?? 0.0
        guard numerator.isFinite,
              denominator.isFinite,
              denominator > 0.0 else {
            return .infinity
        }
        return (numerator / denominator).nextUp
    }

    private func subdividedBernsteinControls(
        _ controls: [ScalarBounds]
    ) -> (lower: [ScalarBounds], upper: [ScalarBounds]) {
        var levels = [controls]
        let half = ScalarBounds.exact(0.5)
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index] * half + previous[index + 1] * half
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func sortedUniqueFractions(_ fractions: [Double]) -> [Double] {
        let ordered = fractions.sorted()
        var result: [Double] = []
        result.reserveCapacity(ordered.count)
        for fraction in ordered {
            if result.last != fraction {
                result.append(fraction)
            }
        }
        return result
    }

    private func interiorSeams(
        _ spans: [CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan]
    ) -> [Double] {
        guard let lower = spans.map(\.lower).min(),
              let upper = spans.map(\.upper).max() else {
            return []
        }
        return Array(Set(spans.flatMap { [$0.lower, $0.upper] }))
            .filter { $0 > lower && $0 < upper }
            .sorted()
    }

    private func piecewiseRationalSurfaceGaussEnclosure(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        lambdaLower: Double,
        lambdaUpper: Double,
        curveLower: Double,
        curveUpper: Double,
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet),
        tolerance: ModelingTolerance
    ) throws -> PiecewiseRationalEnclosure {
        let curve = try parameterEvaluator(
            .variable(Interval(lower: curveLower, upper: curveUpper))
        )
        guard let vSpan = field.strictlyContainingVSpan(
            curve.v.coefficients[0]
        ) else {
            return .seamEnclosed(try rationalSurfaceSeamEnclosure(
                field: field,
                uBase: uBase,
                lambdaLower: lambdaLower,
                lambdaUpper: lambdaUpper,
                curveLower: curveLower,
                curveUpper: curveUpper,
                curve: curve,
                parameterEvaluator: parameterEvaluator,
                tolerance: tolerance
            ))
        }
        let uRange = curve.u.coefficients[0]
        var result = Interval.exact(0.0)
        var lambdaError = 0.0
        var curveError = 0.0
        for uSpan in field.uSpans where uSpan.upper > uBase {
            let localLower = max(uBase, uSpan.lower)
            guard uSpan.upper > localLower else { continue }
            if uRange.upper <= localLower {
                continue
            }
            let isFull = uRange.lower >= uSpan.upper
            let isPartial = uRange.lower >= localLower
                && uRange.upper <= uSpan.upper
            guard isFull || isPartial else {
                return .seamEnclosed(try rationalSurfaceSeamEnclosure(
                    field: field,
                    uBase: uBase,
                    lambdaLower: lambdaLower,
                    lambdaUpper: lambdaUpper,
                    curveLower: curveLower,
                    curveUpper: curveUpper,
                    curve: curve,
                    parameterEvaluator: parameterEvaluator,
                    tolerance: tolerance
                ))
            }
            let enclosure = try rationalSurfaceGaussEnclosure(
                field: field,
                uBase: localLower,
                surfaceUSpan: uSpan,
                surfaceVSpan: vSpan,
                lambdaLower: lambdaLower,
                lambdaUpper: lambdaUpper,
                curveLower: curveLower,
                curveUpper: curveUpper,
                parameterEvaluator: { fraction in
                    let parameters = try parameterEvaluator(fraction)
                    return (
                        isFull ? .constant(uSpan.upper) : parameters.u,
                        parameters.v
                    )
                },
                tolerance: tolerance
            )
            result = result + enclosure.bounds
            lambdaError = (lambdaError + enclosure.lambdaError).nextUp
            curveError = (curveError + enclosure.curveError).nextUp
        }
        return .enclosed(TensorGaussEnclosure(
            bounds: result,
            lambdaError: lambdaError,
            curveError: curveError
        ))
    }

    private func rationalSurfaceSeamEnclosure(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        lambdaLower: Double,
        lambdaUpper: Double,
        curveLower: Double,
        curveUpper: Double,
        curve: (u: Jet, v: Jet),
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet),
        tolerance: ModelingTolerance
    ) throws -> SeamEnclosure {
        guard let uLower = field.uSpans.map(\.lower).min(),
              let uUpper = field.uSpans.map(\.upper).max(),
              let vLower = field.vSpans.map(\.lower).min(),
              let vUpper = field.vSpans.map(\.upper).max() else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified rational pcurve seam enclosure found no extracted surface span."
            )
        }
        let rawURange = curve.u.coefficients[0]
        let rawVRange = curve.v.coefficients[0]
        let uScale = max(1.0, abs(uLower), abs(uUpper))
        let vScale = max(1.0, abs(vLower), abs(vUpper))
        let uSlack = Double.ulpOfOne * uScale * 4_096.0
        let vSlack = Double.ulpOfOne * vScale * 4_096.0
        guard rawURange.lower >= uLower - uSlack,
              rawURange.upper <= uUpper + uSlack,
              rawVRange.lower >= vLower - vSlack,
              rawVRange.upper <= vUpper + vSlack,
              uBase >= uLower,
              uBase <= uUpper else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified rational pcurve seam enclosure left the extracted surface domain."
            )
        }
        let uRange = Interval(
            lower: max(uLower, rawURange.lower),
            upper: min(uUpper, rawURange.upper)
        )
        let vRange = Interval(
            lower: max(vLower, rawVRange.lower),
            upper: min(vUpper, rawVRange.upper)
        )
        let lambda = Interval(
            lower: lambdaLower,
            upper: lambdaUpper
        )
        let derivativeV = curve.v.derivative().coefficients[0]
        var integrand = Interval.exact(0.0)
        for uSpan in field.uSpans where uSpan.upper > uBase {
            let localLower = max(uBase, uSpan.lower)
            guard uSpan.upper > localLower else { continue }
            let endpointLower = min(
                uSpan.upper,
                max(localLower, uRange.lower)
            )
            let endpointUpper = min(
                uSpan.upper,
                max(localLower, uRange.upper)
            )
            let deltaU = Interval(
                lower: endpointLower,
                upper: endpointUpper
            ) - .exact(localLower)
            guard deltaU.upper > 0.0 else { continue }
            let mappedU = Interval.exact(localLower) + lambda * deltaU
            let flux = try field.bounds(
                uLower: mappedU.lower,
                uUpper: mappedU.upper,
                vLower: vRange.lower,
                vUpper: vRange.upper
            )
            integrand = integrand
                + Interval(lower: flux.lower, upper: flux.upper)
                    * deltaU
                    * derivativeV
        }
        let measure = Interval.floating(lambdaUpper - lambdaLower)
            * .floating(curveUpper - curveLower)
        let result = integrand * measure
        guard result.lower.isFinite, result.upper.isFinite else {
            throw resourceFailure(
                residual: result.width,
                tolerance: tolerance,
                message: "Certified rational pcurve seam enclosure exceeded finite arithmetic."
            )
        }
        return SeamEnclosure(
            bounds: result,
            splitLocation: try seamSplitLocation(
                field: field,
                curveLower: curveLower,
                curveUpper: curveUpper,
                parameterEvaluator: parameterEvaluator
            )
        )
    }

    private func seamSplitLocation(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        curveLower: Double,
        curveUpper: Double,
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet)
    ) throws -> SeamSplitLocation {
        let lower = try parameterEvaluator(.variable(.exact(curveLower)))
        let upper = try parameterEvaluator(.variable(.exact(curveUpper)))
        let uSeams = interiorSeams(field.uSpans)
        let vSeams = interiorSeams(field.vSpans)
        let lowerDistance = minimumSeamDistance(
            u: lower.u.coefficients[0],
            v: lower.v.coefficients[0],
            uSeams: uSeams,
            vSeams: vSeams
        )
        let upperDistance = minimumSeamDistance(
            u: upper.u.coefficients[0],
            v: upper.v.coefficients[0],
            uSeams: uSeams,
            vSeams: vSeams
        )
        if lowerDistance < upperDistance * 0.5 { return .lower }
        if upperDistance < lowerDistance * 0.5 { return .upper }
        return .balanced
    }

    private func minimumSeamDistance(
        u: Interval,
        v: Interval,
        uSeams: [Double],
        vSeams: [Double]
    ) -> Double {
        let uDistance = uSeams.map { intervalDistance(u, to: $0) }.min()
            ?? .infinity
        let vDistance = vSeams.map { intervalDistance(v, to: $0) }.min()
            ?? .infinity
        return min(uDistance, vDistance)
    }

    private func intervalDistance(_ interval: Interval, to value: Double) -> Double {
        if interval.lower <= value, interval.upper >= value { return 0.0 }
        return min(abs(interval.lower - value), abs(interval.upper - value))
    }

    private func rationalSurfaceGaussEnclosure(
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        surfaceUSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
        surfaceVSpan: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan,
        lambdaLower: Double,
        lambdaUpper: Double,
        curveLower: Double,
        curveUpper: Double,
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet),
        tolerance: ModelingTolerance
    ) throws -> TensorGaussEnclosure {
        let lambdaMidpoint = lambdaLower + (lambdaUpper - lambdaLower) * 0.5
        let curveMidpoint = curveLower + (curveUpper - curveLower) * 0.5
        let lambdaHalfSpan = (lambdaUpper - lambdaLower) * 0.5
        let curveHalfSpan = (curveUpper - curveLower) * 0.5
        let root = sqrt(3.0 / 5.0)
        let displacements = [-root, 0.0, root]
        let weights = [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
        var estimate = Interval.exact(0.0)
        for lambdaIndex in displacements.indices {
            let lambda = lambdaMidpoint
                + lambdaHalfSpan * displacements[lambdaIndex]
            for curveIndex in displacements.indices {
                let curveParameter = curveMidpoint
                    + curveHalfSpan * displacements[curveIndex]
                let curve = try parameterEvaluator(.variable(.exact(curveParameter)))
                let u = curve.u.coefficients[0]
                let v = curve.v.coefficients[0]
                let deltaU = u - .exact(uBase)
                let mappedU = Interval.exact(uBase) + .floating(lambda) * deltaU
                let flux = try field.bounds(
                    u: mappedU,
                    v: v,
                    uSpan: surfaceUSpan,
                    vSpan: surfaceVSpan
                )
                estimate = estimate
                    + Interval(lower: flux.lower, upper: flux.upper)
                        * deltaU
                        * curve.v.derivative().coefficients[0]
                        * .floating(weights[lambdaIndex] * weights[curveIndex])
            }
        }
        estimate = estimate * .floating(lambdaHalfSpan * curveHalfSpan)

        let curve = try parameterEvaluator(
            .variable(Interval(lower: curveLower, upper: curveUpper))
        )
        let lambdaSurfaceFlux: CertifiedUnivariateTaylorJet
        let curveSurfaceFlux: CertifiedUnivariateTaylorJet
        let lambdaDeltaU = CertifiedUnivariateTaylorJet.constant(
            curve.u.coefficients[0] - .exact(uBase)
        )
        let lambdaJet = CertifiedUnivariateTaylorJet.variable(
            Interval(lower: lambdaLower, upper: lambdaUpper)
        )
        let lambdaMappedU = CertifiedUnivariateTaylorJet.constant(uBase)
            + lambdaJet * lambdaDeltaU
        let constantV = CertifiedUnivariateTaylorJet.constant(curve.v.coefficients[0])
        let curveU = CertifiedUnivariateTaylorJet.series(curve.u.coefficients)
        let curveV = CertifiedUnivariateTaylorJet.series(curve.v.coefficients)
        let curveDeltaU = curveU - .constant(uBase)
        let curveMappedU = CertifiedUnivariateTaylorJet.constant(uBase)
            + CertifiedUnivariateTaylorJet.constant(
                Interval(lower: lambdaLower, upper: lambdaUpper)
            ) * curveDeltaU
        do {
            let certifiedLambda = try field.directionalFluxJet(
                u: lambdaMappedU,
                v: constantV,
                uSpan: surfaceUSpan,
                vSpan: surfaceVSpan
            )
            let certifiedCurve = try field.directionalFluxJet(
                u: curveMappedU,
                v: curveV,
                uSpan: surfaceUSpan,
                vSpan: surfaceVSpan
            )
            lambdaSurfaceFlux = certifiedLambda
            curveSurfaceFlux = certifiedCurve
        } catch let error as KernelError where error.code == .singularSystem {
            throw error
        }
        let lambdaIntegrand = lambdaSurfaceFlux
            * lambdaDeltaU
            * .constant(curve.v.derivative().coefficients[0])
        let curveIntegrand = curveSurfaceFlux
            * curveDeltaU
            * curveV.derivative()
        let lambdaSixthCoefficient = lambdaIntegrand.coefficients[6].maximumAbsolute
        let curveSixthCoefficient = curveIntegrand.coefficients[6].maximumAbsolute
        let lambdaSixthDerivative = outwardProduct(lambdaSixthCoefficient, 720.0)
        let curveSixthDerivative = outwardProduct(curveSixthCoefficient, 720.0)
        let gaussConstant = 1_296.0 / (7.0 * 720.0 * 720.0 * 720.0)
        let lambdaSpan = lambdaUpper - lambdaLower
        let curveSpan = curveUpper - curveLower
        let lambdaError = outwardProduct(
            outwardProduct(lambdaSixthDerivative, gaussConstant),
            pow(lambdaSpan, 7.0) * curveSpan
        )
        let curveError = outwardProduct(
            outwardProduct(curveSixthDerivative, gaussConstant),
            pow(curveSpan, 7.0) * lambdaSpan
        )
        var error = (lambdaError + curveError).nextUp
        for _ in 0..<8 { error = error.nextUp }
        guard estimate.lower.isFinite,
              estimate.upper.isFinite,
              error.isFinite else {
            throw resourceFailure(
                residual: error,
                tolerance: tolerance,
                message: "Certified rational pcurve tensor-Gauss enclosure exceeded finite arithmetic."
            )
        }
        return TensorGaussEnclosure(
            bounds: Interval(
                lower: (estimate.lower - error).nextDown,
                upper: (estimate.upper + error).nextUp
            ),
            lambdaError: lambdaError,
            curveError: curveError
        )
    }

    private func rationalSurfaceImplicitBounds(
        curve: CertifiedImplicitSurfaceParameterCurve,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let implicit = curve.intersection
        try implicit.validate(tolerance: tolerance)
        let uCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstU
            : .secondU
        let vCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstV
            : .secondV
        let ascendingStart = min(curve.startFraction, curve.endFraction)
        let ascendingEnd = max(curve.startFraction, curve.endFraction)
        let requestedSpan = ascendingEnd - ascendingStart
        guard !implicit.cells.isEmpty,
              requestedSpan > tolerance.relative else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified implicit rational pcurve flux requires a nonempty graph traversal."
            )
        }
        struct WorkItem {
            let cell: CertifiedImplicitIntersectionGraphCell
            let curveLower: Double
            let curveUpper: Double
            let lambdaLower: Double
            let lambdaUpper: Double
            let widthBudget: Double
            let depth: Int
        }
        let cellCount = implicit.cells.count
        var pending: [WorkItem] = []
        for (index, cell) in implicit.cells.enumerated() {
            let cellStart = Double(index) / Double(cellCount)
            let cellEnd = Double(index + 1) / Double(cellCount)
            let overlapStart = max(ascendingStart, cellStart)
            let overlapEnd = min(ascendingEnd, cellEnd)
            guard overlapEnd - overlapStart > tolerance.relative else { continue }
            pending.append(WorkItem(
                cell: cell,
                curveLower: (overlapStart - cellStart) * Double(cellCount),
                curveUpper: (overlapEnd - cellStart) * Double(cellCount),
                lambdaLower: 0.0,
                lambdaUpper: 1.0,
                widthBudget: requestedWidth * (overlapEnd - overlapStart) / requestedSpan,
                depth: 0
            ))
        }
        var result = Interval.exact(0.0)
        var workItemCount = 0
        while let item = pending.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux exhausted its cell budget."
                )
            }
            let subcell = try item.cell.restrictedBounds(
                fromNormalizedFraction: item.curveLower,
                toNormalizedFraction: item.curveUpper,
                firstSurface: implicit.firstSurface,
                secondSurface: implicit.secondSurface,
                tolerance: tolerance
            )
            let u = interval(subcell.parameterBox.interval(for: uCoordinate))
            let v = interval(subcell.parameterBox.interval(for: vCoordinate))
            let vDerivative = interval(
                subcell.parameterDerivativeBounds[vCoordinate.rawValue]
            )
            let deltaU = u - .exact(uBase)
            let lambda = Interval(
                lower: item.lambdaLower,
                upper: item.lambdaUpper
            )
            let mappedU = Interval.exact(uBase) + lambda * deltaU
            let flux = try field.bounds(
                uLower: mappedU.lower,
                uUpper: mappedU.upper,
                vLower: v.lower,
                vUpper: v.upper
            )
            let enclosure = Interval(lower: flux.lower, upper: flux.upper)
                * deltaU * vDerivative
                * .floating(item.lambdaUpper - item.lambdaLower)
            if enclosure.width <= item.widthBudget {
                result = result + enclosure
                continue
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: enclosure.width,
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux exceeded its proof depth."
                )
            }
            let halfBudget = item.widthBudget * 0.5
            let curveSpan = item.curveUpper - item.curveLower
            if item.depth.isMultiple(of: 2),
               curveSpan > tolerance.relative * 2.0 {
                let middle = item.curveLower + curveSpan * 0.5
                pending.append(WorkItem(
                    cell: item.cell,
                    curveLower: middle,
                    curveUpper: item.curveUpper,
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    widthBudget: halfBudget,
                    depth: item.depth + 1
                ))
                pending.append(WorkItem(
                    cell: item.cell,
                    curveLower: item.curveLower,
                    curveUpper: middle,
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    widthBudget: halfBudget,
                    depth: item.depth + 1
                ))
            } else {
                let middle = item.lambdaLower
                    + (item.lambdaUpper - item.lambdaLower) * 0.5
                pending.append(WorkItem(
                    cell: item.cell,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    lambdaLower: middle,
                    lambdaUpper: item.lambdaUpper,
                    widthBudget: halfBudget,
                    depth: item.depth + 1
                ))
                pending.append(WorkItem(
                    cell: item.cell,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: middle,
                    widthBudget: halfBudget,
                    depth: item.depth + 1
                ))
            }
        }
        return curve.startFraction <= curve.endFraction ? result : -result
    }

    private func adaptiveJetBounds(
        requestedWidth: Double,
        tolerance: ModelingTolerance,
        evaluator: (Jet) throws -> Jet
    ) throws -> Interval {
        struct WorkItem {
            let lower: Double
            let upper: Double
            let depth: Int
            let widthBudget: Double
        }
        var stack = [WorkItem(lower: 0.0, upper: 1.0, depth: 0, widthBudget: requestedWidth)]
        var result = Interval.exact(0.0)
        var workItemCount = 0
        while let item = stack.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux exhausted its subdivision budget."
                )
            }
            let enclosure: Interval?
            do {
                enclosure = try gaussEnclosure(
                    lower: item.lower,
                    upper: item.upper,
                    evaluator: evaluator,
                    tolerance: tolerance
                )
            } catch LocalProofFailure.intervalSingularity {
                enclosure = nil
            }
            if let enclosure {
                guard enclosure.lower.isFinite, enclosure.upper.isFinite else {
                    throw resourceFailure(
                        residual: enclosure.width,
                        tolerance: tolerance,
                        message: "Certified analytic pcurve flux exceeded finite interval arithmetic."
                    )
                }
                if enclosure.width <= item.widthBudget {
                    result = result + enclosure
                    continue
                }
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: enclosure?.width,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux exceeded its maximum proof depth."
                )
            }
            let middle = item.lower + (item.upper - item.lower) * 0.5
            let halfBudget = item.widthBudget * 0.5
            stack.append(WorkItem(
                lower: middle,
                upper: item.upper,
                depth: item.depth + 1,
                widthBudget: halfBudget
            ))
            stack.append(WorkItem(
                lower: item.lower,
                upper: middle,
                depth: item.depth + 1,
                widthBudget: halfBudget
            ))
        }
        return result
    }

    private func adaptiveParameterEnclosures(
        maximumWidth: Double,
        tolerance: ModelingTolerance,
        evaluator: (Jet) throws -> (u: Jet, v: Jet)
    ) throws -> [SurfaceParameterCurveEnclosure] {
        struct WorkItem {
            let lower: Double
            let upper: Double
            let depth: Int
        }
        var pending = [WorkItem(lower: 0.0, upper: 1.0, depth: 0)]
        var result: [SurfaceParameterCurveEnclosure] = []
        var workItemCount = 0
        while let item = pending.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified analytic pcurve enclosure exhausted its cell budget."
                )
            }
            let ranges: (u: Interval, v: Interval)?
            do {
                let parameters = try evaluator(.variable(Interval(
                    lower: item.lower,
                    upper: item.upper
                )))
                ranges = (
                    parameters.u.coefficients[0],
                    parameters.v.coefficients[0]
                )
            } catch LocalProofFailure.intervalSingularity {
                ranges = nil
            }
            if let ranges,
               ranges.u.lower.isFinite,
               ranges.u.upper.isFinite,
               ranges.v.lower.isFinite,
               ranges.v.upper.isFinite,
               max(ranges.u.width, ranges.v.width) <= maximumWidth {
                result.append(SurfaceParameterCurveEnclosure(
                    lowerFraction: item.lower,
                    upperFraction: item.upper,
                    u: try ScalarInterval(
                        lower: ranges.u.lower,
                        upper: ranges.u.upper
                    ),
                    v: try ScalarInterval(
                        lower: ranges.v.lower,
                        upper: ranges.v.upper
                    )
                ))
                continue
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: ranges.map { max($0.u.width, $0.v.width) },
                    tolerance: tolerance,
                    message: "Certified analytic pcurve enclosure exceeded its proof depth."
                )
            }
            let middle = item.lower + (item.upper - item.lower) * 0.5
            guard middle > item.lower, middle < item.upper else {
                throw resourceFailure(
                    residual: nil,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve enclosure reached floating-point resolution."
                )
            }
            pending.append(WorkItem(
                lower: middle,
                upper: item.upper,
                depth: item.depth + 1
            ))
            pending.append(WorkItem(
                lower: item.lower,
                upper: middle,
                depth: item.depth + 1
            ))
        }
        return result.sorted { $0.lowerFraction < $1.lowerFraction }
    }

    private func gaussEnclosure(
        lower: Double,
        upper: Double,
        evaluator: (Jet) throws -> Jet,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let midpoint = lower + (upper - lower) * 0.5
        let halfSpan = (upper - lower) * 0.5
        let root = sqrt(3.0 / 5.0)
        let nodes = [midpoint - halfSpan * root, midpoint, midpoint + halfSpan * root]
        let weights = [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
        var estimate = Interval.exact(0.0)
        for index in nodes.indices {
            let value = try evaluator(.variable(.exact(nodes[index]))).coefficients[0]
            estimate = estimate + value * .floating(weights[index])
        }
        estimate = estimate * .floating(halfSpan)

        let domainJet = try evaluator(.variable(Interval(lower: lower, upper: upper)))
        let sixthCoefficient = domainJet.coefficients[6].maximumAbsolute
        let sixthDerivative = outwardProduct(sixthCoefficient, 720.0)
        let gaussConstant = 1_296.0 / (7.0 * 720.0 * 720.0 * 720.0)
        let spanPower = pow(upper - lower, 7.0)
        var error = outwardProduct(
            outwardProduct(sixthDerivative, gaussConstant),
            spanPower
        )
        for _ in 0..<8 { error = error.nextUp }
        guard estimate.lower.isFinite,
              estimate.upper.isFinite,
              error.isFinite else {
            throw resourceFailure(
                residual: error,
                tolerance: tolerance,
                message: "Certified analytic pcurve Gauss enclosure exceeded finite arithmetic."
            )
        }
        return Interval(
            lower: (estimate.lower - error).nextDown,
            upper: (estimate.upper + error).nextUp
        )
    }

    private func sphericalGreatCircleBounds(
        cosine: Vector3D,
        sine: Vector3D,
        startParameter: Double,
        endParameter: Double,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        try cosine.validateUnitLength(tolerance: tolerance)
        try sine.validateUnitLength(tolerance: tolerance)
        guard abs(cosine.dot(sine)) <= tolerance.angle,
              startParameter.isFinite,
              endParameter.isFinite,
              abs(endParameter - startParameter) > tolerance.angle,
              abs(endParameter - startParameter) <= 2.0 * Double.pi + tolerance.angle else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified great-circle flux requires one finite nondegenerate turn or less."
            )
        }
        let ascendingLower = min(startParameter, endParameter)
        let ascendingUpper = max(startParameter, endParameter)
        if let meridian = meridianFluxBounds(
            cosine: cosine,
            sine: sine,
            lower: ascendingLower,
            upper: ascendingUpper,
            integrand: integrand
        ) {
            return startParameter <= endParameter ? meridian : -meridian
        }
        let breakpoints = [ascendingLower]
            + greatCircleSeamParameters(
                cosine: cosine,
                sine: sine,
                lower: ascendingLower,
                upper: ascendingUpper,
                tolerance: tolerance
            )
            + [ascendingUpper]
        let totalSpan = ascendingUpper - ascendingLower
        var result = Interval.exact(0.0)
        for index in 1..<breakpoints.count {
            let lower = breakpoints[index - 1]
            let upper = breakpoints[index]
            guard upper > lower else { continue }
            let segmentWidth = requestedWidth * (upper - lower) / totalSpan
            result = result + (try adaptiveJetBounds(
                requestedWidth: segmentWidth,
                tolerance: tolerance
            ) { fraction in
                let parameter = Jet.constant(lower)
                    + Jet.constant(upper - lower) * fraction
                let geometry = try greatCircleParameterJets(
                    cosine: cosine,
                    sine: sine,
                    parameter: parameter
                )
                return greenPrimitive(
                    integrand: integrand,
                    u: geometry.u,
                    v: geometry.v
                ) * geometry.v.derivative()
            })
        }
        return startParameter <= endParameter ? result : -result
    }

    private func certifiedAnalyticImplicitBounds(
        curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let intersection = curve.intersection
        try intersection.validate(tolerance: tolerance)
        let implicit = intersection.implicitCurve
        let analyticU: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstU
            : .secondU
        let analyticV: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstV
            : .secondV
        guard !implicit.cells.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified analytic pcurve flux requires at least one graph cell."
            )
        }
        let ascendingStart = min(curve.startFraction, curve.endFraction)
        let ascendingEnd = max(curve.startFraction, curve.endFraction)
        struct WorkItem {
            let cell: CertifiedImplicitIntersectionGraphCell
            let lowerFraction: Double
            let upperFraction: Double
            let widthBudget: Double
            let depth: Int
        }
        let cellCount = implicit.cells.count
        let requestedSpan = ascendingEnd - ascendingStart
        var pending: [WorkItem] = []
        var result = Interval.exact(0.0)
        for (index, cell) in implicit.cells.enumerated() {
            let cellStart = Double(index) / Double(cellCount)
            let cellEnd = Double(index + 1) / Double(cellCount)
            let overlapStart = max(ascendingStart, cellStart)
            let overlapEnd = min(ascendingEnd, cellEnd)
            guard overlapEnd - overlapStart > tolerance.relative else { continue }
            let localLower = (overlapStart - cellStart) * Double(cellCount)
            let localUpper = (overlapEnd - cellStart) * Double(cellCount)
            pending.append(WorkItem(
                cell: cell,
                lowerFraction: localLower,
                upperFraction: localUpper,
                widthBudget: requestedWidth * (overlapEnd - overlapStart) / requestedSpan,
                depth: 0
            ))
        }
        var workItemCount = 0
        while let item = pending.popLast() {
            workItemCount += 1
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified analytic implicit pcurve flux exhausted its subcell budget."
                )
            }
            let subcell = try item.cell.restrictedBounds(
                fromNormalizedFraction: item.lowerFraction,
                toNormalizedFraction: item.upperFraction,
                firstSurface: implicit.firstSurface,
                secondSurface: implicit.secondSurface,
                tolerance: tolerance
            )
            let contribution = try certifiedAnalyticImplicitSubcellBounds(
                subcell: subcell,
                analyticSurface: intersection.analyticSurface,
                analyticU: analyticU,
                analyticV: analyticV,
                periodicSeamOffset: intersection.periodicSeamOffset,
                integrand: integrand,
                tolerance: tolerance
            )
            if contribution.width <= item.widthBudget {
                result = result + contribution
                continue
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: contribution.width,
                    tolerance: tolerance,
                    message: "Certified analytic implicit pcurve flux exceeded its proof depth."
                )
            }
            let middle = item.lowerFraction
                + (item.upperFraction - item.lowerFraction) * 0.5
            let halfBudget = item.widthBudget * 0.5
            pending.append(WorkItem(
                cell: item.cell,
                lowerFraction: middle,
                upperFraction: item.upperFraction,
                widthBudget: halfBudget,
                depth: item.depth + 1
            ))
            pending.append(WorkItem(
                cell: item.cell,
                lowerFraction: item.lowerFraction,
                upperFraction: middle,
                widthBudget: halfBudget,
                depth: item.depth + 1
            ))
        }
        if curve.startFraction > curve.endFraction { result = -result }
        return result
    }

    private func certifiedAnalyticImplicitSubcellBounds(
        subcell: CertifiedImplicitIntersectionGraphSubcell,
        analyticSurface: Surface3D,
        analyticU: SurfaceIntersectionParameterCoordinate,
        analyticV: SurfaceIntersectionParameterCoordinate,
        periodicSeamOffset: Double,
        integrand: Integrand,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let u = try analyticCircleAngleBounds(
            subcell.parameterBox.interval(for: analyticU),
            offset: periodicSeamOffset,
            parameterUpperBound: 4.0,
            tolerance: tolerance
        )
        let v: Interval
        let vDerivative: Interval
        switch analyticSurface {
        case .cylinder, .analytic(.cylinder), .analytic(.cone):
            v = interval(subcell.parameterBox.interval(for: analyticV))
            vDerivative = interval(subcell.parameterDerivativeBounds[analyticV.rawValue])
        case .analytic(.sphere):
            v = try analyticCircleAngleBounds(
                subcell.parameterBox.interval(for: analyticV),
                offset: -Double.pi * 0.5,
                parameterUpperBound: 2.0,
                tolerance: tolerance
            )
            vDerivative = try analyticCircleAngleDerivativeBounds(
                subcell.parameterDerivativeBounds[analyticV.rawValue]
            )
        case .analytic(.torus):
            v = try analyticCircleAngleBounds(
                subcell.parameterBox.interval(for: analyticV),
                offset: periodicSeamOffset,
                parameterUpperBound: 4.0,
                tolerance: tolerance
            )
            vDerivative = try analyticCircleAngleDerivativeBounds(
                subcell.parameterDerivativeBounds[analyticV.rawValue]
            )
        case .plane, .analytic(.plane), .bSpline:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified analytic pcurve flux received a non-periodic analytic source."
            )
        }
        return integrand.greenPrimitive(u: u, v: v) * vDerivative
    }

    private func analyticCircleAngleBounds(
        _ parameter: ScalarInterval,
        offset: Double,
        parameterUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        guard parameter.lower >= -tolerance.relative,
              parameter.upper <= parameterUpperBound + tolerance.relative else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic NURBS circle parameter left its certified conversion domain."
            )
        }
        let lower = analyticCircleAngle(
            at: min(max(parameter.lower, 0.0), parameterUpperBound)
        ) + offset
        let upper = analyticCircleAngle(
            at: min(max(parameter.upper, 0.0), parameterUpperBound)
        ) + offset
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "An analytic NURBS circle parameter lost monotone angle order."
            )
        }
        return Interval(lower: lower.nextDown, upper: upper.nextUp)
    }

    private func analyticCircleAngle(at parameter: Double) -> Double {
        if parameter >= 4.0 { return 2.0 * Double.pi }
        let segment = min(max(Int(floor(parameter)), 0), 3)
        let local = parameter - Double(segment)
        let complement = 1.0 - local
        let diagonalWeight = sqrt(0.5)
        let x = complement * complement
            + 2.0 * diagonalWeight * local * complement
        let y = 2.0 * diagonalWeight * local * complement + local * local
        return Double(segment) * Double.pi * 0.5 + atan2(y, x)
    }

    private func analyticCircleAngleDerivativeBounds(
        _ derivative: ScalarInterval
    ) throws -> Interval {
        let scale = Interval(lower: 1.0.nextDown, upper: 2.0.nextUp)
        return interval(derivative) * scale
    }

    private func interval(_ bounds: ScalarInterval) -> Interval {
        Interval(lower: bounds.lower, upper: bounds.upper)
    }

    private func meridianFluxBounds(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        integrand: Integrand
    ) -> Interval? {
        let verticalRadius = hypot(cosine.z, sine.z)
        let longitudeNumerator = cosine.x * sine.y - cosine.y * sine.x
        let machineTolerance = Double.ulpOfOne * 16_384.0
        guard abs(verticalRadius - 1.0) <= machineTolerance,
              abs(longitudeNumerator) <= machineTolerance else {
            return nil
        }
        let phase = atan2(cosine.z, sine.z)
        var breakpoints = [lower]
        let firstIndex = Int(ceil(
            (lower + phase - Double.pi * 0.5) / Double.pi
        ))
        let lastIndex = Int(floor(
            (upper + phase - Double.pi * 0.5) / Double.pi
        ))
        if firstIndex <= lastIndex {
            for index in firstIndex...lastIndex {
                let parameter = Double.pi * 0.5 - phase + Double(index) * Double.pi
                if parameter > lower, parameter < upper {
                    breakpoints.append(parameter)
                }
            }
        }
        breakpoints.append(upper)
        breakpoints.sort()
        var result = Interval.exact(0.0)
        for index in 1..<breakpoints.count {
            let segmentLower = breakpoints[index - 1]
            let segmentUpper = breakpoints[index]
            let midpoint = segmentLower + (segmentUpper - segmentLower) * 0.5
            let radial = cosine * cos(midpoint) + sine * sin(midpoint)
            var longitude = atan2(-radial.x, radial.y)
            if longitude < 0.0 { longitude += 2.0 * Double.pi }
            let lowerLatitude = asin(min(max(
                cosine.z * cos(segmentLower) + sine.z * sin(segmentLower),
                -1.0
            ), 1.0))
            let upperLatitude = asin(min(max(
                cosine.z * cos(segmentUpper) + sine.z * sin(segmentUpper),
                -1.0
            ), 1.0))
            result = result + integrand.verticalBoundaryIntegral(
                u: .floating(longitude),
                vStart: .floating(lowerLatitude),
                vEnd: .floating(upperLatitude)
            )
        }
        return result
    }

    private func greatCircleSeamParameters(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let horizontalScale = hypot(cosine.x, sine.x)
        guard horizontalScale > tolerance.angle else { return [] }
        let base = atan2(-cosine.x, sine.x)
        let firstIndex = Int(ceil((lower - base) / Double.pi))
        let lastIndex = Int(floor((upper - base) / Double.pi))
        guard firstIndex <= lastIndex else { return [] }
        var result: [Double] = []
        for index in firstIndex...lastIndex {
            let parameter = base + Double(index) * Double.pi
            guard parameter > lower + tolerance.angle,
                  parameter < upper - tolerance.angle else {
                continue
            }
            let y = cosine.y * cos(parameter) + sine.y * sin(parameter)
            if y > tolerance.angle { result.append(parameter) }
        }
        return result.sorted()
    }

    private func greatCircleParameterJets(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Jet
    ) throws -> (u: Jet, v: Jet) {
        let values = parameter.sineAndCosine()
        let x = Jet.constant(cosine.x) * values.cosine
            + Jet.constant(sine.x) * values.sine
        let y = Jet.constant(cosine.y) * values.cosine
            + Jet.constant(sine.y) * values.sine
        let z = Jet.constant(cosine.z) * values.cosine
            + Jet.constant(sine.z) * values.sine
        let horizontalSquared = x * x + y * y
        let longitudeDerivative = try Jet.constant(
            cosine.x * sine.y - cosine.y * sine.x
        ).divided(by: horizontalSquared)
        let parameterBounds = parameter.coefficients[0]
        let midpoint = parameterBounds.lower
            + (parameterBounds.upper - parameterBounds.lower) * 0.5
        let radial = cosine * cos(midpoint) + sine * sin(midpoint)
        var midpointLongitude = atan2(-radial.x, radial.y)
        if midpointLongitude < 0.0 { midpointLongitude += 2.0 * Double.pi }
        let longitudeRadius = longitudeDerivative.coefficients[0].maximumAbsolute
            * (parameterBounds.upper - parameterBounds.lower) * 0.5
        let longitude = Jet.antiderivative(
            constant: Interval(
                lower: (midpointLongitude - longitudeRadius).nextDown,
                upper: (midpointLongitude + longitudeRadius).nextUp
            ),
            derivative: longitudeDerivative
        )

        let latitudeDenominator = try (
            Jet.constant(1.0) - z * z
        ).squareRoot()
        let latitudeDerivative = try z.derivative().divided(by: latitudeDenominator)
        let zBounds = z.coefficients[0]
        guard zBounds.lower >= -1.0 - Double.ulpOfOne * 4_096.0,
              zBounds.upper <= 1.0 + Double.ulpOfOne * 4_096.0 else {
            throw LocalProofFailure.intervalSingularity
        }
        let latitude = Jet.antiderivative(
            constant: Interval(
                lower: asin(min(max(zBounds.lower, -1.0), 1.0)).nextDown,
                upper: asin(min(max(zBounds.upper, -1.0), 1.0)).nextUp
            ),
            derivative: latitudeDerivative
        )
        return (longitude, latitude)
    }

    private func projectedAnalyticParameterJets(
        _ projected: ProjectedAnalyticSurfaceParameterCurve,
        fraction: Jet,
        tolerance: ModelingTolerance
    ) throws -> (u: Jet, v: Jet) {
        try projected.validate(on: projected.surface, tolerance: tolerance)
        let parameter = Jet.constant(projected.startParameter)
            + Jet.constant(projected.endParameter - projected.startParameter) * fraction
        let point = try projectedAnalyticPointJets(
            projected.curve,
            parameter: parameter,
            tolerance: tolerance
        )
        switch projected.surface {
        case let .plane(plane):
            return try planarParameterJets(
                point: point,
                origin: plane.origin,
                normal: plane.normal,
                tolerance: tolerance
            )
        case let .analytic(.plane(origin, normal)):
            return try planarParameterJets(
                point: point,
                origin: origin,
                normal: normal,
                tolerance: tolerance
            )
        case let .analytic(.cone(apex, axis, halfAngle)):
            return try conicalParameterJets(
                point: point,
                apex: apex,
                axis: axis,
                halfAngle: halfAngle,
                projected: projected,
                fraction: fraction,
                tolerance: tolerance
            )
        case .cylinder, .analytic, .bSpline:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified projected pcurve integration requires a plane or cone support."
            )
        }
    }

    private func projectedAnalyticPointJets(
        _ curve: Curve3D,
        parameter: Jet,
        tolerance: ModelingTolerance
    ) throws -> (x: Jet, y: Jet, z: Jet) {
        switch curve {
        case let .analytic(.hyperbola(hyperbola)):
            try hyperbola.validate(tolerance: tolerance)
            let conjugateAxis = try hyperbola.normal
                .cross(hyperbola.transverseAxis)
                .normalized(tolerance: tolerance.distance)
            let values = parameter.hyperbolicSineAndCosine()
            return (
                .constant(hyperbola.center.x)
                    + .constant(hyperbola.transverseAxis.x * hyperbola.transverseRadius)
                        * values.cosine
                    + .constant(conjugateAxis.x * hyperbola.conjugateRadius)
                        * values.sine,
                .constant(hyperbola.center.y)
                    + .constant(hyperbola.transverseAxis.y * hyperbola.transverseRadius)
                        * values.cosine
                    + .constant(conjugateAxis.y * hyperbola.conjugateRadius)
                        * values.sine,
                .constant(hyperbola.center.z)
                    + .constant(hyperbola.transverseAxis.z * hyperbola.transverseRadius)
                        * values.cosine
                    + .constant(conjugateAxis.z * hyperbola.conjugateRadius)
                        * values.sine
            )
        case let .analytic(.parabola(parabola)):
            try parabola.validate(tolerance: tolerance)
            let transverseAxis = try parabola.normal
                .cross(parabola.axis)
                .normalized(tolerance: tolerance.distance)
            let squared = parameter * parameter
            let inverseFourFocalLength = 1.0 / (4.0 * parabola.focalLength)
            return (
                .constant(parabola.vertex.x)
                    + .constant(transverseAxis.x) * parameter
                    + .constant(parabola.axis.x * inverseFourFocalLength) * squared,
                .constant(parabola.vertex.y)
                    + .constant(transverseAxis.y) * parameter
                    + .constant(parabola.axis.y * inverseFourFocalLength) * squared,
                .constant(parabola.vertex.z)
                    + .constant(transverseAxis.z) * parameter
                    + .constant(parabola.axis.z * inverseFourFocalLength) * squared
            )
        case .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified projected pcurve integration requires a hyperbola or parabola."
            )
        }
    }

    private func planarParameterJets(
        point: (x: Jet, y: Jet, z: Jet),
        origin: Point3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Jet, v: Jet) {
        let basis = try projectedAnalyticBasis(normal, tolerance: tolerance)
        let offset = (
            x: point.x - .constant(origin.x),
            y: point.y - .constant(origin.y),
            z: point.z - .constant(origin.z)
        )
        return (
            projectedAnalyticDot(offset, basis.u),
            projectedAnalyticDot(offset, basis.v)
        )
    }

    private func conicalParameterJets(
        point: (x: Jet, y: Jet, z: Jet),
        apex: Point3D,
        axis: Vector3D,
        halfAngle: Double,
        projected: ProjectedAnalyticSurfaceParameterCurve,
        fraction: Jet,
        tolerance: ModelingTolerance
    ) throws -> (u: Jet, v: Jet) {
        let basis = try projectedAnalyticBasis(axis, tolerance: tolerance)
        let offset = (
            x: point.x - .constant(apex.x),
            y: point.y - .constant(apex.y),
            z: point.z - .constant(apex.z)
        )
        let axial = projectedAnalyticDot(offset, axis)
        let cosine = cos(halfAngle)
        guard cosine.isFinite, abs(cosine) > tolerance.angle else {
            throw KernelError(
                phase: .topology,
                code: .singularGeometry,
                residual: abs(cosine),
                tolerance: tolerance,
                message: "Certified projected cone pcurve has a singular half angle."
            )
        }
        let v = axial * .constant(1.0 / cosine)
        let vRange = v.coefficients[0]
        guard vRange.lower > 0.0 || vRange.upper < 0.0 else {
            throw LocalProofFailure.intervalSingularity
        }
        let sign = vRange.lower > 0.0 ? 1.0 : -1.0
        let x = projectedAnalyticDot(offset, basis.u) * .constant(sign)
        let y = projectedAnalyticDot(offset, basis.v) * .constant(sign)
        let denominator = x * x + y * y
        let angleDerivative = try (
            x * y.derivative() - y * x.derivative()
        ).divided(by: denominator)

        let fractionBounds = fraction.coefficients[0]
        let middleFraction = fractionBounds.lower
            + (fractionBounds.upper - fractionBounds.lower) * 0.5
        let reference = try projected.parameter(
            atNormalizedFraction: 0.5,
            tolerance: tolerance
        ).u
        let middle = try projected.parameter(
            atNormalizedFraction: middleFraction,
            tolerance: tolerance
        ).u
        let unwrappedMiddle = middle
            + 2.0 * Double.pi * ((reference - middle) / (2.0 * Double.pi)).rounded()
        let angleRadius = angleDerivative.coefficients[0].maximumAbsolute
            * (fractionBounds.upper - fractionBounds.lower) * 0.5
        guard angleRadius.isFinite,
              angleRadius < Double.pi - tolerance.angle else {
            throw LocalProofFailure.intervalSingularity
        }
        let u = Jet.antiderivative(
            constant: Interval(
                lower: (unwrappedMiddle - angleRadius).nextDown,
                upper: (unwrappedMiddle + angleRadius).nextUp
            ),
            derivative: angleDerivative
        )
        return (u, v)
    }

    private func projectedAnalyticBasis(
        _ normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let reference = abs(normal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
        let u = try normal.cross(reference).normalized(tolerance: tolerance.distance)
        let v = try normal.cross(u).normalized(tolerance: tolerance.distance)
        return (u, v)
    }

    private func projectedAnalyticDot(
        _ point: (x: Jet, y: Jet, z: Jet),
        _ vector: Vector3D
    ) -> Jet {
        point.x * .constant(vector.x)
            + point.y * .constant(vector.y)
            + point.z * .constant(vector.z)
    }

    private func rationalFluxJet(
        patch: HomogeneousPatch,
        fraction: Jet,
        integrand: Integrand,
        tolerance: ModelingTolerance
    ) throws -> Jet {
        let parameters = try rationalPcurveJets(
            patch: patch,
            fraction: fraction,
            tolerance: tolerance
        )
        return greenPrimitive(
            integrand: integrand,
            u: parameters.u,
            v: parameters.v
        ) * parameters.v.derivative()
    }

    private func rationalPcurveJets(
        patch: HomogeneousPatch,
        fraction: Jet,
        tolerance: ModelingTolerance
    ) throws -> (u: Jet, v: Jet) {
        guard patch.degree >= 1,
              patch.controls.allSatisfy(\.isFiniteAndPositiveWeight) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified rational pcurve flux requires valid homogeneous controls."
            )
        }
        let x = bezierJet(controls: patch.controls.map(\.x), fraction: fraction)
        let y = bezierJet(controls: patch.controls.map(\.y), fraction: fraction)
        let weight = bezierJet(controls: patch.controls.map(\.weight), fraction: fraction)
        var u = try x.divided(by: weight)
        var v = try y.divided(by: weight)
        let fractionRange = fraction.coefficients[0]
        let restrictedControls = try patch.restrictedControls(
            fractionLower: fractionRange.lower,
            fractionUpper: fractionRange.upper,
            tolerance: tolerance
        )
        let uControls = restrictedControls.map { $0.x / $0.weight }
        let vControls = restrictedControls.map { $0.y / $0.weight }
        u.coefficients[0] = Interval(
            lower: uControls.map(\.lower).min() ?? -.infinity,
            upper: uControls.map(\.upper).max() ?? .infinity
        )
        v.coefficients[0] = Interval(
            lower: vControls.map(\.lower).min() ?? -.infinity,
            upper: vControls.map(\.upper).max() ?? .infinity
        )
        return (u, v)
    }

    private func polynomialFluxJet(
        primitive: CertifiedPolynomialSurfaceFluxPrimitive,
        u: Jet,
        v: Jet,
        tolerance: ModelingTolerance
    ) throws -> Jet {
        let normalizedU = try normalizedParameterJet(
            u,
            domain: primitive.uDomain,
            tolerance: tolerance
        )
        let normalizedV = try normalizedParameterJet(
            v,
            domain: primitive.vDomain,
            tolerance: tolerance
        )
        let rows = primitive.coefficients.map {
            bernsteinJet(coefficients: $0, parameter: normalizedU)
        }
        let value = bernsteinJet(coefficients: rows, parameter: normalizedV)
        return value * normalizedV.derivative()
    }

    private func normalizedParameterJet(
        _ parameter: Jet,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Jet {
        guard case let .closed(lower, upper) = domain,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified polynomial pcurve flux requires a positive bounded source domain."
            )
        }
        return try (parameter - .constant(lower)).divided(
            by: .constant(Interval.exact(upper) - .exact(lower))
        )
    }

    private func bernsteinJet(
        coefficients: [Interval],
        parameter: Jet
    ) -> Jet {
        var level = coefficients.map(Jet.constant)
        let complement = Jet.constant(1.0) - parameter
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index] * complement + level[index + 1] * parameter
            }
        }
        return level[0]
    }

    private func bernsteinJet(
        coefficients: [Jet],
        parameter: Jet
    ) -> Jet {
        var level = coefficients
        let complement = Jet.constant(1.0) - parameter
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index] * complement + level[index + 1] * parameter
            }
        }
        return level[0]
    }

    private func bezierJet(controls: [ScalarBounds], fraction: Jet) -> Jet {
        var level = controls.map { Jet.constant(interval($0)) }
        let complement = Jet.constant(1.0) - fraction
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index] * complement + level[index + 1] * fraction
            }
        }
        return level[0]
    }

    private func interval(_ bounds: ScalarBounds) -> Interval {
        Interval(lower: bounds.lower, upper: bounds.upper)
    }

    private func outwardProduct(_ lhs: Double, _ rhs: Double) -> Double {
        var result = lhs * rhs
        for _ in 0..<4 { result = result.nextUp }
        return result
    }

    private func greenPrimitive(
        integrand: Integrand,
        u: Jet,
        v: Jet
    ) -> Jet {
        switch integrand {
        case let .plane(volumeScale):
            return Jet.constant(volumeScale) * u
        case let .cylinder(radius, offsetU, offsetV):
            return Jet.constant(radius / .exact(3.0)) * (
                azimuthPrimitive(u: u, offsetU: offsetU, offsetV: offsetV)
                    + Jet.constant(radius) * u
            )
        case let .cone(
            sine,
            cosine,
            radialOffsetU,
            radialOffsetV,
            axialOffset
        ):
            return Jet.constant(sine / .exact(3.0)) * (
                Jet.constant(cosine) * azimuthPrimitive(
                    u: u,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                ) - Jet.constant(sine * axialOffset) * u
            ) * v
        case let .sphere(
            radius,
            radialOffsetU,
            radialOffsetV,
            axialOffset
        ):
            let values = v.sineAndCosine()
            return Jet.constant(radius * radius / .exact(3.0)) * (
                azimuthPrimitive(
                    u: u,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                ) * values.cosine * values.cosine
                    + u * (
                        Jet.constant(axialOffset) * values.cosine * values.sine
                            + Jet.constant(radius) * values.cosine
                    )
            )
        case let .torus(
            majorRadius,
            minorRadius,
            radialOffsetU,
            radialOffsetV,
            axialOffset
        ):
            let values = v.sineAndCosine()
            let azimuthTerm = azimuthPrimitive(
                u: u,
                offsetU: radialOffsetU,
                offsetV: radialOffsetV
            ) * (
                Jet.constant(majorRadius) * values.cosine
                    + Jet.constant(minorRadius) * values.cosine * values.cosine
            )
            let axialTerm = u * (
                Jet.constant(axialOffset * majorRadius) * values.sine
                    + Jet.constant(axialOffset * minorRadius)
                        * values.cosine * values.sine
                    + Jet.constant(majorRadius * majorRadius) * values.cosine
                    + Jet.constant(majorRadius * minorRadius)
                        * values.cosine * values.cosine
                    + Jet.constant(minorRadius * majorRadius)
                    + Jet.constant(minorRadius * minorRadius) * values.cosine
            )
            return Jet.constant(minorRadius / .exact(3.0)) * (azimuthTerm + axialTerm)
        }
    }

    private func azimuthPrimitive(
        u: Jet,
        offsetU: Interval,
        offsetV: Interval
    ) -> Jet {
        let values = u.sineAndCosine()
        return Jet.constant(offsetU) * values.sine
            - Jet.constant(offsetV) * values.cosine
    }

    private struct Jet {
        // The sixth derivative of a line integrand containing `v'` depends on
        // the seventh Taylor coefficient of the underlying pcurve.
        static let order = 7
        var coefficients: [Interval]

        static func variable(_ interval: Interval) -> Jet {
            var coefficients = Array(repeating: Interval.exact(0.0), count: order + 1)
            coefficients[0] = interval
            coefficients[1] = .exact(1.0)
            return Jet(coefficients: coefficients)
        }

        static func constant(_ value: Double) -> Jet {
            constant(.exact(value))
        }

        static func constant(_ value: Interval) -> Jet {
            var coefficients = Array(repeating: Interval.exact(0.0), count: order + 1)
            coefficients[0] = value
            return Jet(coefficients: coefficients)
        }

        static func antiderivative(
            constant: Interval,
            derivative: Jet
        ) -> Jet {
            var coefficients = Array(repeating: Interval.exact(0.0), count: order + 1)
            coefficients[0] = constant
            for degree in 1...order {
                coefficients[degree] = derivative.coefficients[degree - 1]
                    / .exact(Double(degree))
            }
            return Jet(coefficients: coefficients)
        }

        static prefix func - (value: Jet) -> Jet {
            Jet(coefficients: value.coefficients.map { -$0 })
        }

        static func + (lhs: Jet, rhs: Jet) -> Jet {
            Jet(coefficients: zip(lhs.coefficients, rhs.coefficients).map {
                $0 + $1
            })
        }

        static func - (lhs: Jet, rhs: Jet) -> Jet {
            lhs + (-rhs)
        }

        static func * (lhs: Jet, rhs: Jet) -> Jet {
            var result = Array(repeating: Interval.exact(0.0), count: order + 1)
            for degree in 0...order {
                for index in 0...degree {
                    result[degree] = result[degree]
                        + lhs.coefficients[index] * rhs.coefficients[degree - index]
                }
            }
            return Jet(coefficients: result)
        }

        func divided(by denominator: Jet) throws -> Jet {
            self * (try denominator.reciprocal())
        }

        func reciprocal() throws -> Jet {
            let constant = coefficients[0]
            guard constant.lower > 0.0 || constant.upper < 0.0 else {
                throw LocalProofFailure.intervalSingularity
            }
            let inverse = Interval.exact(1.0) / constant
            var result = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            result[0] = inverse
            for degree in 1...Self.order {
                var sum = Interval.exact(0.0)
                for index in 1...degree {
                    sum = sum + coefficients[index] * result[degree - index]
                }
                result[degree] = -inverse * sum
            }
            return Jet(coefficients: result)
        }

        func derivative() -> Jet {
            var result = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            for degree in 0..<Self.order {
                result[degree] = coefficients[degree + 1] * .exact(Double(degree + 1))
            }
            return Jet(coefficients: result)
        }

        func squareRoot() throws -> Jet {
            let constant = coefficients[0]
            guard constant.lower > 0.0 else {
                throw LocalProofFailure.intervalSingularity
            }
            let root = Interval(
                lower: sqrt(constant.lower).nextDown,
                upper: sqrt(constant.upper).nextUp
            )
            var result = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            result[0] = root
            let denominator = root * .exact(2.0)
            for degree in 1...Self.order {
                var crossTerms = Interval.exact(0.0)
                if degree > 1 {
                    for index in 1..<degree {
                        crossTerms = crossTerms + result[index] * result[degree - index]
                    }
                }
                result[degree] = (coefficients[degree] - crossTerms) / denominator
            }
            return Jet(coefficients: result)
        }

        func sineAndCosine() -> (sine: Jet, cosine: Jet) {
            var sine = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            var cosine = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            sine[0] = .sine(coefficients[0])
            cosine[0] = .cosine(coefficients[0])
            for degree in 1...Self.order {
                var sineSum = Interval.exact(0.0)
                var cosineSum = Interval.exact(0.0)
                for index in 1...degree {
                    let derivativeCoefficient = coefficients[index]
                        * .exact(Double(index))
                    sineSum = sineSum
                        + derivativeCoefficient * cosine[degree - index]
                    cosineSum = cosineSum
                        + derivativeCoefficient * sine[degree - index]
                }
                sine[degree] = sineSum / .exact(Double(degree))
                cosine[degree] = -cosineSum / .exact(Double(degree))
            }
            return (
                sine: Jet(coefficients: sine),
                cosine: Jet(coefficients: cosine)
            )
        }

        func hyperbolicSineAndCosine() -> (sine: Jet, cosine: Jet) {
            var sine = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            var cosine = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
            sine[0] = .hyperbolicSine(coefficients[0])
            cosine[0] = .hyperbolicCosine(coefficients[0])
            for degree in 1...Self.order {
                var sineSum = Interval.exact(0.0)
                var cosineSum = Interval.exact(0.0)
                for index in 1...degree {
                    let derivativeCoefficient = coefficients[index]
                        * .exact(Double(index))
                    sineSum = sineSum
                        + derivativeCoefficient * cosine[degree - index]
                    cosineSum = cosineSum
                        + derivativeCoefficient * sine[degree - index]
                }
                sine[degree] = sineSum / .exact(Double(degree))
                cosine[degree] = cosineSum / .exact(Double(degree))
            }
            return (
                sine: Jet(coefficients: sine),
                cosine: Jet(coefficients: cosine)
            )
        }
    }

    private func resourceFailure(
        residual: Double?,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}

private extension TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
    static func hyperbolicSine(
        _ value: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    ) -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
        var lower = sinh(value.lower)
        var upper = sinh(value.upper)
        for _ in 0..<16 {
            lower = lower.nextDown
            upper = upper.nextUp
        }
        return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
            lower: lower,
            upper: upper
        )
    }

    static func hyperbolicCosine(
        _ value: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    ) -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
        let lower: Double
        if value.lower <= 0.0, value.upper >= 0.0 {
            lower = 1.0
        } else {
            lower = min(cosh(value.lower), cosh(value.upper))
        }
        var outwardLower = lower
        var outwardUpper = max(cosh(value.lower), cosh(value.upper))
        for _ in 0..<16 {
            outwardLower = outwardLower.nextDown
            outwardUpper = outwardUpper.nextUp
        }
        return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
            lower: max(1.0, outwardLower),
            upper: outwardUpper
        )
    }
}
