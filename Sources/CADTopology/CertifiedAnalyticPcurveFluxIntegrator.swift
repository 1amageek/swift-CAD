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

    struct PolynomialCylinderBounds {
        let flux: Interval
        let parameterArea: SurfaceParameterAreaBounds
    }

    fileprivate struct AnalyticPairCacheKey: Hashable {
        let intersection: CertifiedAnalyticAnalyticIntersectionCurve
        let role: SurfaceIntersectionSurfaceRole
        let lowerFraction: Double
        let upperFraction: Double
        let integrand: Integrand
        let requestedWidth: Double
        let tolerance: ModelingTolerance
    }

    final class EvaluationCache {
        fileprivate var analyticPairBounds: [AnalyticPairCacheKey: Interval] = [:]
    }

    private let maximumWorkItems: Int
    private let maximumDepth: Int
    private let evaluationCache: EvaluationCache

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

    private struct RigidImageWorkItem {
        let lowerFraction: Double
        let upperFraction: Double
        let requestedWidth: Double
        let depth: Int
    }

    private struct TensorGaussEnclosure {
        let bounds: Interval
        let lambdaError: Double
        let curveError: Double
    }

    private struct ImplicitMidpointEnclosure {
        let bounds: Interval
    }

    /// Owns the immutable Bernstein derivative nets shared by every adaptive
    /// evaluation of one rational pcurve patch. The adaptive proof changes
    /// only the evaluated fraction interval; rebuilding these nets in every
    /// Gauss cell adds no information to the enclosure.
    private struct PreparedRationalPcurvePatch {
        let source: HomogeneousPatch
        let xDerivativeControls: [[Interval]]
        let yDerivativeControls: [[Interval]]
        let weightDerivativeControls: [[Interval]]
    }

    init(
        maximumWorkItems: Int = 65_536,
        maximumDepth: Int = 48,
        evaluationCache: EvaluationCache = EvaluationCache()
    ) {
        self.maximumWorkItems = maximumWorkItems
        self.maximumDepth = maximumDepth
        self.evaluationCache = evaluationCache
    }

    func parameterEnclosures(
        for curve: SurfaceParameterCurve,
        fromNormalizedFraction lowerFraction: Double = 0.0,
        toNormalizedFraction upperFraction: Double = 1.0,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try tolerance.validate()
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction,
              maximumWidth.isFinite,
              maximumWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: upperFraction - lowerFraction,
                tolerance: tolerance,
                message: "Certified analytic pcurve enclosure requires an ordered normalized range and a finite positive width."
            )
        }
        let boundedLower = min(max(lowerFraction, 0.0), 1.0)
        let boundedUpper = min(max(upperFraction, 0.0), 1.0)
        guard boundedUpper > boundedLower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: boundedUpper - boundedLower,
                tolerance: tolerance,
                message: "Certified analytic pcurve enclosure range collapsed at its normalized domain boundary."
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
            let parameterSpan = endParameter - startParameter
            let rangeStartParameter = startParameter
                + parameterSpan * boundedLower
            let rangeEndParameter = startParameter
                + parameterSpan * boundedUpper
            let localEnclosures: [SurfaceParameterCurveEnclosure]
            if let meridian = try meridianParameterEnclosures(
                cosine: cosine,
                sine: sine,
                startParameter: rangeStartParameter,
                endParameter: rangeEndParameter
            ) {
                localEnclosures = meridian
            } else {
                localEnclosures = try adaptiveParameterEnclosures(
                    lowerFraction: 0.0,
                    upperFraction: 1.0,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                ) { fraction in
                    let parameter = Jet.constant(rangeStartParameter)
                        + Jet.constant(rangeEndParameter - rangeStartParameter) * fraction
                    return try greatCircleParameterJets(
                        cosine: cosine,
                        sine: sine,
                        parameter: parameter
                    )
                }
            }
            let aligned = try alignedSphericalEnclosures(
                localEnclosures,
                cosine: cosine,
                sine: sine,
                startParameter: rangeStartParameter,
                endParameter: rangeEndParameter
            )
            let rangeSpan = boundedUpper - boundedLower
            return aligned.map { enclosure in
                SurfaceParameterCurveEnclosure(
                    lowerFraction: boundedLower
                        + rangeSpan * enclosure.lowerFraction,
                    upperFraction: boundedLower
                        + rangeSpan * enclosure.upperFraction,
                    u: enclosure.u,
                    v: enclosure.v
                )
            }
        case let .projectedAnalytic(projected):
            return try adaptiveParameterEnclosures(
                lowerFraction: boundedLower,
                upperFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            ) { fraction in
                try projectedAnalyticParameterJets(
                    projected,
                    fraction: fraction,
                    tolerance: tolerance
                )
            }
        case let .periodicTranslation(base, uShift, vShift):
            return try parameterEnclosures(
                for: base,
                fromNormalizedFraction: boundedLower,
                toNormalizedFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            ).map { enclosure in
                SurfaceParameterCurveEnclosure(
                    lowerFraction: enclosure.lowerFraction,
                    upperFraction: enclosure.upperFraction,
                    u: try ScalarInterval(
                        lower: (enclosure.u.lower + uShift).nextDown,
                        upper: (enclosure.u.upper + uShift).nextUp
                    ),
                    v: try ScalarInterval(
                        lower: (enclosure.v.lower + vShift).nextDown,
                        upper: (enclosure.v.upper + vShift).nextUp
                    )
                )
            }
        case let .offsetSurfaceImage(image):
            return try parameterEnclosures(
                for: image.source,
                fromNormalizedFraction: boundedLower,
                toNormalizedFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .rigidImage:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "This analytic enclosure path received an incompatible pcurve representation."
            )
        }
    }

    private func alignedSphericalEnclosures(
        _ enclosures: [SurfaceParameterCurveEnclosure],
        cosine: Vector3D,
        sine: Vector3D,
        startParameter: Double,
        endParameter: Double
    ) throws -> [SurfaceParameterCurveEnclosure] {
        let period = 2.0 * Double.pi
        var referenceLongitude = sphericalEndpointLongitude(
            cosine: cosine,
            sine: sine,
            parameter: startParameter,
            approachDirection: endParameter > startParameter ? 1.0 : -1.0
        )
        var result: [SurfaceParameterCurveEnclosure] = []
        for enclosure in enclosures.sorted(by: {
            $0.lowerFraction < $1.lowerFraction
        }) {
            let shift = round(
                (referenceLongitude - enclosure.u.midpoint) / period
            ) * period
            let shiftedLowerU = enclosure.u.lower + shift
            let shiftedUpperU = enclosure.u.upper + shift
            let parameterSpan = endParameter - startParameter
            let lowerParameter = startParameter
                + parameterSpan * enclosure.lowerFraction
            let upperParameter = startParameter
                + parameterSpan * enclosure.upperFraction
            let direction = parameterSpan > 0.0 ? 1.0 : -1.0
            let lowerEndpoint = sphericalParameterEnclosureEndpoint(
                cosine: cosine,
                sine: sine,
                parameter: lowerParameter,
                approachDirection: direction,
                longitudeReference: shiftedLowerU
                    + (shiftedUpperU - shiftedLowerU) * 0.5
            )
            let upperEndpoint = sphericalParameterEnclosureEndpoint(
                cosine: cosine,
                sine: sine,
                parameter: upperParameter,
                approachDirection: -direction,
                longitudeReference: shiftedLowerU
                    + (shiftedUpperU - shiftedLowerU) * 0.5
            )
            let alignedU = try ScalarInterval(
                lower: min(
                    shiftedLowerU,
                    lowerEndpoint.u,
                    upperEndpoint.u
                ).nextDown,
                upper: max(
                    shiftedUpperU,
                    lowerEndpoint.u,
                    upperEndpoint.u
                ).nextUp
            )
            let alignedV = try ScalarInterval(
                lower: min(
                    enclosure.v.lower,
                    lowerEndpoint.v,
                    upperEndpoint.v
                ).nextDown,
                upper: max(
                    enclosure.v.upper,
                    lowerEndpoint.v,
                    upperEndpoint.v
                ).nextUp
            )
            result.append(SurfaceParameterCurveEnclosure(
                lowerFraction: enclosure.lowerFraction,
                upperFraction: enclosure.upperFraction,
                u: alignedU,
                v: alignedV
            ))
            referenceLongitude = alignedU.midpoint
        }
        return result
    }

    private func sphericalParameterEnclosureEndpoint(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        approachDirection: Double,
        longitudeReference: Double
    ) -> SurfaceParameter {
        let radial = cosine * cos(parameter) + sine * sin(parameter)
        var longitude = sphericalEndpointLongitude(
            cosine: cosine,
            sine: sine,
            parameter: parameter,
            approachDirection: approachDirection
        )
        longitude += round(
            (longitudeReference - longitude) / (2.0 * Double.pi)
        ) * (2.0 * Double.pi)
        return SurfaceParameter(
            u: longitude,
            v: asin(min(max(radial.z, -1.0), 1.0))
        )
    }

    private func meridianParameterEnclosures(
        cosine: Vector3D,
        sine: Vector3D,
        startParameter: Double,
        endParameter: Double
    ) throws -> [SurfaceParameterCurveEnclosure]? {
        let verticalRadius = hypot(cosine.z, sine.z)
        let longitudeNumerator = cosine.x * sine.y - cosine.y * sine.x
        let machineTolerance = Double.ulpOfOne * 16_384.0
        guard abs(verticalRadius - 1.0) <= machineTolerance,
              abs(longitudeNumerator) <= machineTolerance else {
            return nil
        }
        let ascendingLower = min(startParameter, endParameter)
        let ascendingUpper = max(startParameter, endParameter)
        let phase = atan2(cosine.z, sine.z)
        var ascendingBreakpoints = [ascendingLower]
        let firstIndex = Int(ceil(
            (ascendingLower + phase - Double.pi * 0.5) / Double.pi
        ))
        let lastIndex = Int(floor(
            (ascendingUpper + phase - Double.pi * 0.5) / Double.pi
        ))
        if firstIndex <= lastIndex {
            for index in firstIndex...lastIndex {
                let parameter = Double.pi * 0.5 - phase
                    + Double(index) * Double.pi
                if parameter > ascendingLower, parameter < ascendingUpper {
                    ascendingBreakpoints.append(parameter)
                }
            }
        }
        ascendingBreakpoints.append(ascendingUpper)
        ascendingBreakpoints.sort()
        let breakpoints = startParameter <= endParameter
            ? ascendingBreakpoints
            : Array(ascendingBreakpoints.reversed())
        let parameterSpan = endParameter - startParameter
        var referenceLongitude = sphericalEndpointLongitude(
            cosine: cosine,
            sine: sine,
            parameter: startParameter,
            approachDirection: parameterSpan > 0.0 ? 1.0 : -1.0
        )
        var result: [SurfaceParameterCurveEnclosure] = []
        for index in 1..<breakpoints.count {
            let first = breakpoints[index - 1]
            let second = breakpoints[index]
            let midpoint = first + (second - first) * 0.5
            let radial = cosine * cos(midpoint) + sine * sin(midpoint)
            var longitude = atan2(-radial.x, radial.y)
            if longitude < 0.0 { longitude += 2.0 * Double.pi }
            longitude += round(
                (referenceLongitude - longitude) / (2.0 * Double.pi)
            ) * (2.0 * Double.pi)
            referenceLongitude = longitude
            let firstLatitude = asin(min(max(
                cosine.z * cos(first) + sine.z * sin(first),
                -1.0
            ), 1.0))
            let secondLatitude = asin(min(max(
                cosine.z * cos(second) + sine.z * sin(second),
                -1.0
            ), 1.0))
            let firstFraction = (first - startParameter) / parameterSpan
            let secondFraction = (second - startParameter) / parameterSpan
            result.append(SurfaceParameterCurveEnclosure(
                lowerFraction: min(firstFraction, secondFraction),
                upperFraction: max(firstFraction, secondFraction),
                u: try ScalarInterval(
                    lower: longitude.nextDown,
                    upper: longitude.nextUp
                ),
                v: try ScalarInterval(
                    lower: min(firstLatitude, secondLatitude).nextDown,
                    upper: max(firstLatitude, secondLatitude).nextUp
                )
            ))
        }
        return result.sorted { $0.lowerFraction < $1.lowerFraction }
    }

    private func sphericalEndpointLongitude(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        approachDirection: Double
    ) -> Double {
        let radial = cosine * cos(parameter) + sine * sin(parameter)
        let horizontalLength = hypot(radial.x, radial.y)
        let direction: Vector3D
        if horizontalLength <= 1.0e-12 {
            let derivative = cosine * -sin(parameter) + sine * cos(parameter)
            direction = derivative * approachDirection
        } else {
            direction = radial
        }
        var longitude = atan2(-direction.x, direction.y)
        if longitude < 0.0 { longitude += 2.0 * Double.pi }
        return longitude
    }

    func bounds(
        for curve: SurfaceParameterCurve,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        if integrand.usesPeriodicBoundaryGauge {
            return try periodicBoundaryGaugeBounds(
                for: curve,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        }
        return try greenPrimitiveBounds(
            for: curve,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
    }

    private func greenPrimitiveBounds(
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
            let hasUniformWeights = spline.weights.first.map { firstWeight in
                firstWeight.isFinite
                    && firstWeight > 0.0
                    && spline.weights.allSatisfy { $0 == firstWeight }
            } ?? false
            if hasUniformWeights,
               let polynomial = try polynomialCylinderBounds(
                    for: spline,
                    integrand: integrand,
                    requestedWidth: requestedWidth,
                    tolerance: tolerance
               ) {
                return polynomial.flux
            }
            let patches = try CertifiedBSplineCurveBezierExtractor().patches(
                curve: spline,
                tolerance: tolerance
            )
            let preparedPatches = try patches.map {
                try prepareRationalPcurvePatch($0, tolerance: tolerance)
            }
            return try adaptiveJetBoundsShared(
                requestedWidth: requestedWidth,
                tolerance: tolerance,
                evaluators: preparedPatches.map { patch in
                    { fraction in
                        try self.rationalFluxJet(
                            patch: patch,
                            parameter: fraction.coefficients[0],
                            integrand: integrand,
                            tolerance: tolerance
                        )
                    }
                }
            )
        case let .certifiedAnalyticImplicit(certified):
            return try certifiedAnalyticImplicitBounds(
                curve: certified,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(certified):
            return try analyticPairFluxBounds(
                for: certified,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .constantU(u, vStart, vEnd):
            return integrand.verticalBoundaryIntegral(
                u: .exact(u),
                vStart: .exact(vStart),
                vEnd: .exact(vEnd)
            )
        case .constantV:
            return .exact(0.0)
        case .certifiedImplicit:
            // Intersection-backed pcurve flux certification is implemented by
            // the parametric-surface volume path. This analytic caller must
            // treat nil as unsupported and cannot report a successful result.
            return nil
        case let .rigidImage(image):
            return try rigidImageBounds(
                image: image,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
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
        case let .offsetSurfaceImage(image):
            return try bounds(
                for: image.source,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            let correctionBudget = (requestedWidth * 0.25).nextDown
            guard correctionBudget.isFinite, correctionBudget > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: correctionBudget,
                    tolerance: tolerance,
                    message: "Periodic analytic flux could not allocate a finite translation-correction enclosure."
                )
            }
            let baseBounds = try bounds(
                for: base,
                integrand: integrand,
                requestedWidth: (requestedWidth - correctionBudget).nextDown,
                tolerance: tolerance
            )
            guard let baseBounds else { return nil }
            let correction = try periodicTranslationFluxCorrection(
                base: base,
                uShift: uShift,
                vShift: vShift,
                integrand: integrand,
                requestedWidth: correctionBudget,
                tolerance: tolerance
            )
            let result = baseBounds + correction
            guard result.width <= requestedWidth.nextUp else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: result.width,
                    tolerance: tolerance,
                    message: "Periodic analytic flux exceeded its composed enclosure width."
                )
            }
            return result
        }
    }

    private func analyticPairFluxBounds(
        for curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let isReversed = curve.startFraction > curve.endFraction
        let key = AnalyticPairCacheKey(
            intersection: curve.intersection,
            role: curve.role,
            lowerFraction: min(curve.startFraction, curve.endFraction),
            upperFraction: max(curve.startFraction, curve.endFraction),
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        if let canonical = evaluationCache.analyticPairBounds[key] {
            return isReversed ? -canonical : canonical
        }
        let result = try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
            for: curve,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        evaluationCache.analyticPairBounds[key] = isReversed ? -result : result
        return result
    }

    private func periodicBoundaryGaugeBounds(
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
                message: "Periodic analytic flux requires a finite positive enclosure width."
            )
        }
        switch curve {
        case let .certifiedAnalyticPair(certified):
            return try analyticPairFluxBounds(
                for: certified,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(image):
            return try periodicBoundaryGaugeBounds(
                for: image.source,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            let period = 2.0 * Double.pi
            let turns = uShift / period
            guard uShift.isFinite,
                  vShift.isFinite,
                  abs(turns - turns.rounded()) <= tolerance.relative else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: max(abs(uShift), abs(vShift)),
                    tolerance: tolerance,
                    message: "A periodic analytic pcurve translation must preserve its whole-turn U chart."
                )
            }
            if vShift != 0.0 {
                let vTurns = vShift / period
                guard case .torus = integrand,
                      abs(vTurns - vTurns.rounded()) <= tolerance.relative else {
                    throw KernelError(
                        phase: .topology,
                        code: .invalidInput,
                        residual: vShift,
                        tolerance: tolerance,
                        message: "Only a torus pcurve can receive a whole-turn V translation."
                    )
                }
            }
            let correctionBudget = (requestedWidth * 0.25).nextDown
            let baseBounds = try periodicBoundaryGaugeBounds(
                for: base,
                integrand: integrand,
                requestedWidth: (requestedWidth - correctionBudget).nextDown,
                tolerance: tolerance
            )
            guard let baseBounds else { return nil }
            let correction = try periodicBoundaryTranslationFluxCorrection(
                base: base,
                uShift: uShift,
                vShift: vShift,
                integrand: integrand,
                requestedWidth: correctionBudget,
                tolerance: tolerance
            )
            let result = baseBounds + correction
            guard result.width <= requestedWidth.nextUp else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: result.width,
                    tolerance: tolerance,
                    message: "Periodic analytic flux exceeded its composed enclosure width."
                )
            }
            return result
        default:
            let correction = try periodicBoundaryGaugeCorrection(
                for: curve,
                integrand: integrand,
                tolerance: tolerance
            )
            let remainingWidth = (requestedWidth - correction.width).nextDown
            guard remainingWidth.isFinite, remainingWidth > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: correction.width,
                    tolerance: tolerance,
                    message: "Periodic analytic flux exhausted its enclosure width in the exact boundary-gauge correction."
                )
            }
            guard let primitiveBounds = try greenPrimitiveBounds(
                for: curve,
                integrand: integrand,
                requestedWidth: remainingWidth,
                tolerance: tolerance
            ) else {
                return nil
            }
            let result = primitiveBounds + correction
            guard result.width <= requestedWidth.nextUp else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: result.width,
                    tolerance: tolerance,
                    message: "Periodic analytic flux exceeded its composed enclosure width."
                )
            }
            return result
        }
    }

    private func periodicBoundaryGaugeCorrection(
        for curve: SurfaceParameterCurve,
        integrand: Integrand,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let start = try curve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let end = try curve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        )
        let startPotential = integrand.periodicBoundaryGaugePotential(
            u: .floating(start.u),
            v: .floating(start.v)
        )
        let endPotential = integrand.periodicBoundaryGaugePotential(
            u: .floating(end.u),
            v: .floating(end.v)
        )
        return endPotential - startPotential
    }

    private func periodicBoundaryTranslationFluxCorrection(
        base: SurfaceParameterCurve,
        uShift: Double,
        vShift: Double,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        if abs(uShift) <= tolerance.relative {
            return .exact(0.0)
        }
        guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Periodic analytic flux requires a finite positive translation-correction width."
            )
        }
        var maximumEndpointWidth = min(
            1.0e-3,
            requestedWidth / max(abs(uShift), 1.0)
        )
        for _ in 0..<16 {
            let endpoints = try continuousEndpointVEnclosures(
                for: base,
                maximumWidth: maximumEndpointWidth,
                tolerance: tolerance
            )
            let shiftedStartV = Interval(
                lower: (endpoints.start.lower + vShift).nextDown,
                upper: (endpoints.start.upper + vShift).nextUp
            )
            let shiftedEndV = Interval(
                lower: (endpoints.end.lower + vShift).nextDown,
                upper: (endpoints.end.upper + vShift).nextUp
            )
            let correction = integrand.periodicBoundaryVerticalIntegral(
                u: .floating(uShift),
                vStart: shiftedStartV,
                vEnd: shiftedEndV
            ) - integrand.periodicBoundaryVerticalIntegral(
                u: .exact(0.0),
                vStart: shiftedStartV,
                vEnd: shiftedEndV
            )
            if correction.width <= requestedWidth.nextUp {
                return correction
            }
            maximumEndpointWidth *= 0.25
        }
        throw KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            residual: maximumEndpointWidth,
            tolerance: tolerance,
            message: "Periodic analytic flux could not certify translated endpoint lifts within its correction budget."
        )
    }

    /// Certifies `integral u dv` directly from outward-rounded homogeneous
    /// Bezier patches. This is the proof boundary used by rational revolution
    /// moments; materializing nominal Euclidean control points here would lose
    /// the extraction and Bernstein-product rounding enclosure.
    func parameterAreaBounds(
        for patches: [HomogeneousPatch],
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        try tolerance.validate()
        guard patches.isEmpty == false,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified rational parameter-area integration requires patches and a finite positive width."
            )
        }
        let preparedPatches = try patches.map {
            try prepareRationalPcurvePatch($0, tolerance: tolerance)
        }
        let area = try adaptiveJetBoundsShared(
            requestedWidth: requestedWidth,
            tolerance: tolerance,
            evaluators: preparedPatches.map { patch in
                { fraction in
                    try self.rationalFluxJet(
                        patch: patch,
                        parameter: fraction.coefficients[0],
                        integrand: .plane(volumeScale: .exact(1.0)),
                        tolerance: tolerance
                    )
                }
            }
        )
        return SurfaceParameterAreaBounds(lower: area.lower, upper: area.upper)
    }

    private func rigidImageBounds(
        image: RigidImageSurfaceParameterCurve,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        var remainingItems = maximumWorkItems
        var stack = [RigidImageWorkItem(
            lowerFraction: 0.0,
            upperFraction: 1.0,
            requestedWidth: requestedWidth,
            depth: 0
        )]
        var result = Interval.exact(0.0)
        while let item = stack.popLast() {
            guard remainingItems > 0 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rigid-image analytic flux integration exceeded its work-item budget."
                )
            }
            remainingItems -= 1
            let localImage = try image.subcurve(
                fromNormalizedFraction: item.lowerFraction,
                toNormalizedFraction: item.upperFraction,
                tolerance: tolerance
            )
            let enclosures = try CertifiedSurfaceParameterCurveEncloser()
                .enclosures(
                    for: .rigidImage(localImage),
                    maximumWidth: 0.25,
                    tolerance: tolerance
                )
            if enclosures.count != 1 {
                guard item.depth < maximumDepth,
                      enclosures.isEmpty == false else {
                    throw KernelError(
                        phase: .topology,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Rigid-image analytic flux subdivision did not converge to one certified chart cell."
                    )
                }
                for enclosure in enclosures.reversed() {
                    let span = item.upperFraction - item.lowerFraction
                    let lower = item.lowerFraction
                        + span * enclosure.lowerFraction
                    let upper = item.lowerFraction
                        + span * enclosure.upperFraction
                    stack.append(RigidImageWorkItem(
                        lowerFraction: lower,
                        upperFraction: upper,
                        requestedWidth: item.requestedWidth
                            * (enclosure.upperFraction - enclosure.lowerFraction),
                        depth: item.depth + 1
                    ))
                }
                continue
            }
            let enclosure = enclosures[0]
            let lower = item.lowerFraction
            let upper = item.upperFraction
            let midpoint = lower + (upper - lower) * 0.5
            guard let derivativeBound = try image
                .modelSpaceFirstDerivativeMagnitude(
                    fromNormalizedFraction: lower,
                    toNormalizedFraction: upper,
                    tolerance: tolerance
                ), let metricLower = minimumMetricScale(
                    surface: image.targetSurface,
                    enclosure: enclosure
                ), metricLower > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Rigid-image analytic flux reached a singular target parameter chart."
                )
            }
            let middleParameter = try image.parameter(
                atNormalizedFraction: midpoint,
                tolerance: tolerance
            )
            let startParameter = try image.parameter(
                atNormalizedFraction: lower,
                tolerance: tolerance
            )
            let endParameter = try image.parameter(
                atNormalizedFraction: upper,
                tolerance: tolerance
            )
            let qBounds = integrand.greenPrimitive(
                u: Interval(
                    lower: enclosure.u.lower,
                    upper: enclosure.u.upper
                ),
                v: Interval(
                    lower: enclosure.v.lower,
                    upper: enclosure.v.upper
                )
            )
            let qMiddle = integrand.greenPrimitive(
                u: .exact(middleParameter.u),
                v: .exact(middleParameter.v)
            )
            let deltaV = Interval.floating(
                endParameter.v - startParameter.v
            )
            let central = qMiddle * deltaV
            let qDeviation = max(
                abs(qBounds.lower - qMiddle.upper),
                abs(qBounds.upper - qMiddle.lower)
            ).nextUp
            let parameterVariation = (
                derivativeBound / metricLower * (upper - lower)
            ).nextUp
            let error = (qDeviation * parameterVariation).nextUp
            let contribution = central + Interval(
                lower: (-error).nextDown,
                upper: error.nextUp
            )
            if contribution.width <= item.requestedWidth {
                result = result + contribution
                continue
            }
            guard item.depth < maximumDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: contribution.width,
                    tolerance: tolerance,
                    message: "Rigid-image analytic flux exceeded its subdivision depth before reaching the requested enclosure width."
                )
            }
            let split = midpoint
            stack.append(RigidImageWorkItem(
                lowerFraction: split,
                upperFraction: upper,
                requestedWidth: item.requestedWidth * 0.5,
                depth: item.depth + 1
            ))
            stack.append(RigidImageWorkItem(
                lowerFraction: lower,
                upperFraction: split,
                requestedWidth: item.requestedWidth * 0.5,
                depth: item.depth + 1
            ))
        }
        return result
    }

    private func minimumMetricScale(
        surface: Surface3D,
        enclosure: SurfaceParameterCurveEnclosure
    ) -> Double? {
        switch surface {
        case .plane, .analytic(.plane):
            return 1.0
        case let .cylinder(cylinder):
            return min(cylinder.radius, 1.0).nextDown
        case let .analytic(.cylinder(_, _, radius)):
            return min(radius, 1.0).nextDown
        case let .analytic(.cone(_, _, halfAngle)):
            let minimumAbsoluteV: Double
            if enclosure.v.lower <= 0.0, enclosure.v.upper >= 0.0 {
                minimumAbsoluteV = 0.0
            } else {
                minimumAbsoluteV = min(
                    abs(enclosure.v.lower),
                    abs(enclosure.v.upper)
                )
            }
            return min(
                1.0,
                minimumAbsoluteV * abs(sin(halfAngle))
            ).nextDown
        case let .analytic(.sphere(_, radius)):
            let maximumAbsoluteV = max(
                abs(enclosure.v.lower),
                abs(enclosure.v.upper)
            )
            return (radius * max(0.0, cos(min(
                maximumAbsoluteV,
                Double.pi * 0.5
            )))).nextDown
        case let .analytic(.torus(_, _, majorRadius, minorRadius)):
            return min(
                minorRadius,
                majorRadius - minorRadius
            ).nextDown
        case .analytic, .bSpline, .procedural:
            return nil
        }
    }

    private func periodicTranslationFluxCorrection(
        base: SurfaceParameterCurve,
        uShift: Double,
        vShift: Double,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let period = 2.0 * Double.pi
        func isWholePeriod(_ shift: Double) -> Bool {
            guard shift.isFinite else { return false }
            let turns = shift / period
            return abs(turns - turns.rounded()) <= tolerance.relative
        }
        guard uShift == 0.0 || isWholePeriod(uShift) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: uShift,
                tolerance: tolerance,
                message: "Analytic flux received a non-periodic U translation."
            )
        }
        if vShift != 0.0 {
            guard case .torus = integrand, isWholePeriod(vShift) else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: vShift,
                    tolerance: tolerance,
                    message: "Analytic flux received a non-periodic V translation."
                )
            }
        }
        if uShift == 0.0 { return .exact(0.0) }
        guard case .plane = integrand else {
            guard requestedWidth.isFinite, requestedWidth > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    residual: requestedWidth,
                    tolerance: tolerance,
                    message: "Periodic analytic flux requires a finite positive correction width."
                )
            }
            var maximumEndpointWidth = min(
                1.0e-3,
                requestedWidth / max(abs(uShift), 1.0)
            )
            for _ in 0..<16 {
                let endpoints = try continuousEndpointVEnclosures(
                    for: base,
                    maximumWidth: maximumEndpointWidth,
                    tolerance: tolerance
                )
                let shiftedStartV = Interval(
                    lower: (endpoints.start.lower + vShift).nextDown,
                    upper: (endpoints.start.upper + vShift).nextUp
                )
                let shiftedEndV = Interval(
                    lower: (endpoints.end.lower + vShift).nextDown,
                    upper: (endpoints.end.upper + vShift).nextUp
                )
                let correction = integrand.verticalBoundaryIntegral(
                    u: .exact(uShift),
                    vStart: shiftedStartV,
                    vEnd: shiftedEndV
                ) - integrand.verticalBoundaryIntegral(
                    u: .exact(0.0),
                    vStart: shiftedStartV,
                    vEnd: shiftedEndV
                )
                if correction.width <= requestedWidth.nextUp {
                    return correction
                }
                maximumEndpointWidth *= 0.25
            }
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: maximumEndpointWidth,
                tolerance: tolerance,
                message: "Periodic analytic flux could not certify continuous endpoint lifts within its correction budget."
            )
        }
        throw KernelError(
            phase: .topology,
            code: .invalidInput,
            residual: uShift,
            tolerance: tolerance,
            message: "A planar analytic flux cannot receive a periodic U translation."
        )
    }

    /// Returns endpoint V coordinates in the curve's certified continuous
    /// universal-cover chart. Direct endpoint evaluation is intentionally not
    /// used: periodic analytic pcurves report principal representatives, and
    /// a seam endpoint can therefore differ from the traversed lift by one
    /// whole period. Borrowed endpoint neighborhoods retain the geometric
    /// proof sheet without constructing tolerance-sized topology curves.
    private func continuousEndpointVEnclosures(
        for curve: SurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> (start: ScalarInterval, end: ScalarInterval) {
        let minimumSpan = Double.ulpOfOne * 64.0
        let endpointSpan = min(
            1.0e-6,
            max(maximumEndpointSpan(maximumWidth), minimumSpan)
        )
        guard endpointSpan < 1.0,
              1.0 - endpointSpan < 1.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: endpointSpan,
                tolerance: tolerance,
                message: "Periodic analytic flux reached normalized endpoint resolution."
            )
        }
        let encloser = CertifiedSurfaceParameterCurveEncloser()
        let startEnclosures = try encloser.vEnclosures(
            for: curve,
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: endpointSpan,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        )
        let endEnclosures = try encloser.vEnclosures(
            for: curve,
            fromNormalizedFraction: 1.0 - endpointSpan,
            toNormalizedFraction: 1.0,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        )
        guard let start = startEnclosures.first,
              let end = endEnclosures.last,
              abs(start.lowerFraction) <= tolerance.relative,
              abs(end.upperFraction - 1.0) <= tolerance.relative else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Periodic analytic flux received incomplete endpoint lift certificates."
            )
        }
        return (start.v, end.v)
    }

    private func maximumEndpointSpan(_ maximumWidth: Double) -> Double {
        (maximumWidth * 0.01).nextDown
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
                let preparedPatch = try prepareRationalPcurvePatch(
                    patch,
                    tolerance: tolerance
                )
                result = result + (try adaptiveJetBounds(
                    requestedWidth: patchWidth,
                    tolerance: tolerance
                ) { fraction in
                    let parameters = try rationalPcurveJets(
                        patch: preparedPatch,
                        parameter: fraction.coefficients[0],
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
             .projectedAnalytic,
             .rigidImage:
            return nil
        case let .offsetSurfaceImage(image):
            return try polynomialBounds(
                for: image.source,
                primitive: primitive,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            guard uShift == 0.0, vShift == 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A polynomial surface flux cannot consume a nonzero periodic parameter translation."
                )
            }
            return try polynomialBounds(
                for: base,
                primitive: primitive,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
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
                let preparedPatch = try prepareRationalPcurvePatch(
                    patch,
                    tolerance: tolerance
                )
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
                        patch: preparedPatch,
                        parameter: fraction.coefficients[0],
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
        case let .rigidImage(image):
            guard try image.affineParameterTransform(tolerance: tolerance)
                    == .identity else {
                return nil
            }
            return try rationalSurfaceBounds(
                for: image.sourceParameterCurve(tolerance: tolerance),
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(image):
            return try rationalSurfaceBounds(
                for: image.source,
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            guard uShift == 0.0, vShift == 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A rational surface flux cannot consume a nonzero periodic parameter translation."
                )
            }
            return try rationalSurfaceBounds(
                for: base,
                field: field,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        }
    }

    func proceduralSurfaceBounds(
        for curve: SurfaceParameterCurve,
        surface: Surface3D,
        reference: Point3D,
        uBase: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        try tolerance.validate()
        guard case .procedural = surface,
              uBase.isFinite,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Certified procedural pcurve flux requires a procedural surface, finite base, and positive enclosure width."
            )
        }
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return try proceduralSurfaceExplicitBounds(
                surface: surface,
                reference: reference,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
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
            return try proceduralSurfaceExplicitBounds(
                surface: surface,
                reference: reference,
                uBase: uBase,
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
            return try proceduralSurfaceExplicitBounds(
                surface: surface,
                reference: reference,
                uBase: uBase,
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
                    message: "Certified procedural polyline flux requires at least two points."
                )
            }
            let segmentWidth = requestedWidth / Double(points.count - 1)
            var result = Interval.exact(0.0)
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                result = result + (try proceduralSurfaceExplicitBounds(
                    surface: surface,
                    reference: reference,
                    uBase: uBase,
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
            guard patches.isEmpty == false else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified procedural B-spline flux found no active Bezier span."
                )
            }
            let patchWidth = requestedWidth / Double(patches.count)
            var result = Interval.exact(0.0)
            for patch in patches {
                let prepared = try prepareRationalPcurvePatch(
                    patch,
                    tolerance: tolerance
                )
                result = result + (try proceduralSurfaceExplicitBounds(
                    surface: surface,
                    reference: reference,
                    uBase: uBase,
                    requestedWidth: patchWidth,
                    tolerance: tolerance
                ) { fraction in
                    try rationalPcurveJets(
                        patch: prepared,
                        parameter: fraction.coefficients[0],
                        tolerance: tolerance
                    )
                })
            }
            return result
        case let .rigidImage(image):
            guard try image.affineParameterTransform(tolerance: tolerance)
                    == .identity else {
                return nil
            }
            return try proceduralSurfaceBounds(
                for: image.sourceParameterCurve(tolerance: tolerance),
                surface: surface,
                reference: reference,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(image):
            return try proceduralSurfaceBounds(
                for: image.source,
                surface: surface,
                reference: reference,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            let materialized = curve.materializingPeriodicTranslation()
            if materialized == curve,
               case let .rigidImage(image) = base,
               try image.affineParameterTransform(tolerance: tolerance) == .identity {
                let sourceCurve = try image.sourceParameterCurve(tolerance: tolerance)
                let untranslated = SurfaceParameterCurve.periodicTranslation(
                    base: sourceCurve,
                    uShift: uShift,
                    vShift: vShift
                )
                let translatedSource = untranslated.materializingPeriodicTranslation()
                guard translatedSource != untranslated else {
                    return nil
                }
                return try proceduralSurfaceBounds(
                    for: translatedSource,
                    surface: surface,
                    reference: reference,
                    uBase: uBase,
                    requestedWidth: requestedWidth,
                    tolerance: tolerance
                )
            }
            guard materialized != curve else { return nil }
            return try proceduralSurfaceBounds(
                for: materialized,
                surface: surface,
                reference: reference,
                uBase: uBase,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
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
                let preparedPatch = try prepareRationalPcurvePatch(
                    patch,
                    tolerance: tolerance
                )
                result = result + (try rationalPlanarExplicitBounds(
                    field: field,
                    projection: projection,
                    requestedWidth: patchWidth,
                    tolerance: tolerance
                ) { fraction in
                    try rationalPcurveJets(
                        patch: preparedPatch,
                        parameter: fraction.coefficients[0],
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
        case let .rigidImage(image):
            guard try image.affineParameterTransform(tolerance: tolerance)
                    == .identity else {
                return nil
            }
            return try rationalPlanarAreaBounds(
                for: image.sourceParameterCurve(tolerance: tolerance),
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(image):
            return try rationalPlanarAreaBounds(
                for: image.source,
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            guard uShift == 0.0, vShift == 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A rational planar area integral cannot consume a nonzero periodic parameter translation."
                )
            }
            return try rationalPlanarAreaBounds(
                for: base,
                field: field,
                projection: projection,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
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

    private func proceduralSurfaceExplicitBounds(
        surface: Surface3D,
        reference: Point3D,
        uBase: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance,
        parameterEvaluator: (Jet) throws -> (u: Jet, v: Jet)
    ) throws -> Interval {
        struct WorkItem {
            let lambdaLower: Double
            let lambdaUpper: Double
            let curveLower: Double
            let curveUpper: Double
            let depth: Int
            let enclosure: Interval
            let lambdaError: Double
            let curveError: Double

            var width: Double { enclosure.width }
        }

        func positiveScalarInterval(
            _ source: Interval,
            domain: ParameterDomain,
            tolerance: ModelingTolerance
        ) throws -> ScalarInterval {
            var lower = source.lower
            var upper = source.upper
            if case let .closed(domainLower, domainUpper) = domain {
                let scale = max(
                    abs(domainLower),
                    abs(domainUpper),
                    abs(lower),
                    abs(upper),
                    1.0
                )
                let slack = max(
                    tolerance.relative * scale,
                    Double.ulpOfOne * scale * 4_096.0
                )
                guard lower >= domainLower - slack,
                      upper <= domainUpper + slack else {
                    throw KernelError(
                        phase: .topology,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Certified procedural pcurve flux midpoint left the surface parameter domain."
                    )
                }
                lower = max(lower, domainLower)
                upper = min(upper, domainUpper)
                if lower == upper {
                    if upper < domainUpper {
                        upper = min(domainUpper, upper.nextUp)
                    } else if lower > domainLower {
                        lower = max(domainLower, lower.nextDown)
                    }
                }
            } else if lower == upper {
                lower = lower.nextDown
                upper = upper.nextUp
            }
            guard lower.isFinite,
                  upper.isFinite,
                  upper > lower else {
                throw resourceFailure(
                    residual: upper - lower,
                    tolerance: tolerance,
                    message: "Certified procedural pcurve flux midpoint requires a positive finite parameter interval."
                )
            }
            return try ScalarInterval(lower: lower, upper: upper)
        }

        func enclosed(
            lambdaLower: Double,
            lambdaUpper: Double,
            curveLower: Double,
            curveUpper: Double,
            depth: Int
        ) throws -> WorkItem {
            let curve = try parameterEvaluator(.variable(Interval(
                lower: curveLower,
                upper: curveUpper
            )))
            let u = curve.u.coefficients[0]
            let v = curve.v.coefficients[0]
            let vDerivative = curve.v.derivative().coefficients[0]
            let deltaU = u - .exact(uBase)
            if deltaU.lower == 0.0, deltaU.upper == 0.0 {
                return WorkItem(
                    lambdaLower: lambdaLower,
                    lambdaUpper: lambdaUpper,
                    curveLower: curveLower,
                    curveUpper: curveUpper,
                    depth: depth,
                    enclosure: .exact(0.0),
                    lambdaError: 0.0,
                    curveError: 0.0
                )
            }
            if vDerivative.lower == 0.0, vDerivative.upper == 0.0 {
                return WorkItem(
                    lambdaLower: lambdaLower,
                    lambdaUpper: lambdaUpper,
                    curveLower: curveLower,
                    curveUpper: curveUpper,
                    depth: depth,
                    enclosure: .exact(0.0),
                    lambdaError: 0.0,
                    curveError: 0.0
                )
            }
            let lambda = Interval(
                lower: lambdaLower,
                upper: lambdaUpper
            )
            let mappedU = Interval.exact(uBase) + lambda * deltaU
            guard mappedU.width > 0.0, v.width > 0.0 else {
                throw resourceFailure(
                    residual: max(mappedU.width, v.width),
                    tolerance: tolerance,
                    message: "Certified procedural pcurve flux could not form a positive parameter cell."
                )
            }
            let differential = try SurfaceFluxDifferentialEncloser().enclosure(
                of: surface,
                over: SurfaceParameterBox(
                    u: try positiveScalarInterval(
                        mappedU,
                        domain: surface.uDomain,
                        tolerance: tolerance
                    ),
                    v: try positiveScalarInterval(
                        v,
                        domain: surface.vDomain,
                        tolerance: tolerance
                    )
                ),
                relativeTo: reference,
                tolerance: tolerance
            )
            let cellArea = (lambdaUpper - lambdaLower)
                * (curveUpper - curveLower)
            let flux = Interval(
                lower: differential.value.lower,
                upper: differential.value.upper
            )
            let rangeContribution = flux * deltaU * vDerivative
                * .floating(cellArea)
            let firstU = Interval(
                lower: differential.firstDerivativeU.lower,
                upper: differential.firstDerivativeU.upper
            )
            let firstV = Interval(
                lower: differential.firstDerivativeV.lower,
                upper: differential.firstDerivativeV.upper
            )
            let secondUU = Interval(
                lower: differential.secondDerivativeUU.lower,
                upper: differential.secondDerivativeUU.upper
            )
            let secondUV = Interval(
                lower: differential.secondDerivativeUV.lower,
                upper: differential.secondDerivativeUV.upper
            )
            let secondVV = Interval(
                lower: differential.secondDerivativeVV.lower,
                upper: differential.secondDerivativeVV.upper
            )
            let uFirst = curve.u.derivative().coefficients[0]
            let uSecond = curve.u.derivative().derivative().coefficients[0]
            let vSecond = curve.v.derivative().derivative().coefficients[0]
            let vThird = curve.v.derivative().derivative().derivative()
                .coefficients[0]
            let xFirst = lambda * uFirst
            let xSecond = lambda * uSecond
            let fluxFirst = firstU * xFirst + firstV * vDerivative
            let fluxSecond = secondUU * xFirst * xFirst
                + .floating(2.0) * secondUV * xFirst * vDerivative
                + secondVV * vDerivative * vDerivative
                + firstU * xSecond
                + firstV * vSecond
            let boundaryFactor = deltaU * vDerivative
            let boundaryFactorFirst = uFirst * vDerivative
                + deltaU * vSecond
            let boundaryFactorSecond = uSecond * vDerivative
                + .floating(2.0) * uFirst * vSecond
                + deltaU * vThird
            let secondCurve = fluxSecond * boundaryFactor
                + .floating(2.0) * fluxFirst * boundaryFactorFirst
                + flux * boundaryFactorSecond
            let secondLambda = secondUU * deltaU * deltaU * deltaU
                * vDerivative
            let lambdaSpan = lambdaUpper - lambdaLower
            let curveSpan = curveUpper - curveLower
            let lambdaError = (cellArea * secondLambda.maximumAbsolute
                * lambdaSpan * lambdaSpan / 24.0).nextUp
            let curveError = (cellArea * secondCurve.maximumAbsolute
                * curveSpan * curveSpan / 24.0).nextUp
            let totalError = (lambdaError + curveError).nextUp

            let lambdaMidpoint = lambdaLower + lambdaSpan * 0.5
            let curveMidpoint = curveLower + curveSpan * 0.5
            let midpointCurve = try parameterEvaluator(
                .variable(.floating(curveMidpoint))
            )
            let midpointDeltaU = midpointCurve.u.coefficients[0]
                - .exact(uBase)
            let midpointMappedU = Interval.exact(uBase)
                + .floating(lambdaMidpoint) * midpointDeltaU
            let midpointV = midpointCurve.v.coefficients[0]
            let midpointFlux = try SurfaceFluxDifferentialEncloser().enclosure(
                of: surface,
                over: SurfaceParameterBox(
                    u: try positiveScalarInterval(
                        midpointMappedU,
                        domain: surface.uDomain,
                        tolerance: tolerance
                    ),
                    v: try positiveScalarInterval(
                        midpointV,
                        domain: surface.vDomain,
                        tolerance: tolerance
                    )
                ),
                relativeTo: reference,
                tolerance: tolerance
            ).value
            let midpointEstimate = Interval(
                lower: midpointFlux.lower,
                upper: midpointFlux.upper
            ) * midpointDeltaU
                * midpointCurve.v.derivative().coefficients[0]
                * .floating(cellArea)
            let midpointContribution = midpointEstimate + Interval(
                lower: (-totalError).nextDown,
                upper: totalError.nextUp
            )
            let lower = max(
                rangeContribution.lower,
                midpointContribution.lower
            )
            let upper = min(
                rangeContribution.upper,
                midpointContribution.upper
            )
            guard lower <= upper else {
                throw resourceFailure(
                    residual: lower - upper,
                    tolerance: tolerance,
                    message: "Certified procedural pcurve flux produced inconsistent independent enclosures."
                )
            }
            let contribution = Interval(lower: lower, upper: upper)
            guard contribution.lower.isFinite,
                  contribution.upper.isFinite else {
                throw resourceFailure(
                    residual: contribution.width,
                    tolerance: tolerance,
                    message: "Certified procedural pcurve flux exceeded finite interval arithmetic."
                )
            }
            return WorkItem(
                lambdaLower: lambdaLower,
                lambdaUpper: lambdaUpper,
                curveLower: curveLower,
                curveUpper: curveUpper,
                depth: depth,
                enclosure: contribution,
                lambdaError: lambdaError,
                curveError: curveError
            )
        }

        guard maximumWorkItems > 0 else {
            throw resourceFailure(
                residual: Double(maximumWorkItems),
                tolerance: tolerance,
                message: "Certified procedural pcurve flux has no subdivision budget."
            )
        }
        var heap: [WorkItem] = []
        func push(_ item: WorkItem) {
            heap.append(item)
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard heap[index].width > heap[parent].width else { break }
                heap.swapAt(index, parent)
                index = parent
            }
        }
        func popMaximum() -> WorkItem? {
            guard heap.isEmpty == false else { return nil }
            if heap.count == 1 { return heap.removeLast() }
            let result = heap[0]
            heap[0] = heap.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var largest = index
                if left < heap.count, heap[left].width > heap[largest].width {
                    largest = left
                }
                if right < heap.count, heap[right].width > heap[largest].width {
                    largest = right
                }
                guard largest != index else { break }
                heap.swapAt(index, largest)
                index = largest
            }
            return result
        }
        func accumulated() -> Interval {
            heap.reduce(.exact(0.0)) { $0 + $1.enclosure }
        }

        push(try enclosed(
            lambdaLower: 0.0,
            lambdaUpper: 1.0,
            curveLower: 0.0,
            curveUpper: 1.0,
            depth: 0
        ))
        var evaluatedCellCount = 1
        while accumulated().width > requestedWidth {
            guard let item = popMaximum() else {
                throw resourceFailure(
                    residual: requestedWidth,
                    tolerance: tolerance,
                    message: "Certified procedural pcurve flux lost its active subdivision cells."
                )
            }
            guard item.depth < maximumDepth,
                  evaluatedCellCount + 2 <= maximumWorkItems else {
                throw resourceFailure(
                    residual: accumulated().width + item.width,
                    tolerance: tolerance,
                    message: "Certified procedural pcurve flux exhausted its adaptive subdivision budget."
                )
            }
            let childDepth = item.depth + 1
            if item.curveError >= item.lambdaError {
                let middle = item.curveLower
                    + (item.curveUpper - item.curveLower) * 0.5
                push(try enclosed(
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    curveLower: item.curveLower,
                    curveUpper: middle,
                    depth: childDepth
                ))
                push(try enclosed(
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    curveLower: middle,
                    curveUpper: item.curveUpper,
                    depth: childDepth
                ))
            } else {
                let middle = item.lambdaLower
                    + (item.lambdaUpper - item.lambdaLower) * 0.5
                push(try enclosed(
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: middle,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    depth: childDepth
                ))
                push(try enclosed(
                    lambdaLower: middle,
                    lambdaUpper: item.lambdaUpper,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    depth: childDepth
                ))
            }
            evaluatedCellCount += 2
        }
        return accumulated()
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
        if let planar = try field.exactPlanarAffineFluxTraversal(for: curve) {
            let scale = Interval(
                lower: planar.fluxScale.lower,
                upper: planar.fluxScale.upper
            )
            let scaleMagnitude = scale.maximumAbsolute
            guard scaleMagnitude.isFinite else {
                throw resourceFailure(
                    residual: scaleMagnitude,
                    tolerance: tolerance,
                    message: "Certified planar affine flux lost its finite scale."
                )
            }
            let patches = planar.patches.map { patch in
                HomogeneousPatch(
                    controls: patch.controls.map { control in
                        HomogeneousPatch.HomogeneousPoint(
                            x: ScalarBounds(
                                lower: control.x.lower,
                                upper: control.x.upper
                            ),
                            y: ScalarBounds(
                                lower: control.y.lower,
                                upper: control.y.upper
                            ),
                            weight: ScalarBounds(
                                lower: control.weight.lower,
                                upper: control.weight.upper
                            )
                        )
                    },
                    lower: 0.0,
                    upper: 1.0
                )
            }
            let areaWidth = requestedWidth / max(scaleMagnitude * 4.0, 1.0)
            let area = try parameterAreaBounds(
                for: patches,
                requestedWidth: areaWidth,
                tolerance: tolerance
            )
            let result = scale * Interval(
                lower: area.lower,
                upper: area.upper
            )
            guard result.width <= requestedWidth else {
                throw resourceFailure(
                    residual: result.width,
                    tolerance: tolerance,
                    message: "Certified planar affine flux exceeded its requested enclosure width."
                )
            }
            return result
        }
        let uCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstU
            : .secondU
        let vCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstV
            : .secondV
        let traversalSegments = try curve.canonicalTraversalSegments(
            tolerance: tolerance
        )
        let requestedSpan = abs(curve.endFraction - curve.startFraction)
        guard !implicit.cells.isEmpty,
              requestedSpan > tolerance.relative else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified implicit rational pcurve flux requires a nonempty graph traversal."
            )
        }
        let implicitJetEncloser = try ImplicitCurveIntervalJetEncloser(
            intersection: implicit,
            tolerance: tolerance
        )
        struct WorkItem {
            let cell: CertifiedImplicitIntersectionGraphCell
            let cellIndex: Int
            let curveLower: Double
            let curveUpper: Double
            let lambdaLower: Double
            let lambdaUpper: Double
            let orientationMultiplier: Double
            let depth: Int
            let enclosure: Interval
            let rangeWidth: Double
            let midpointWidth: Double?

            var width: Double { enclosure.width }
        }
        let cellCount = implicit.cells.count
        func makeItem(
            cell: CertifiedImplicitIntersectionGraphCell,
            cellIndex: Int,
            curveLower: Double,
            curveUpper: Double,
            lambdaLower: Double,
            lambdaUpper: Double,
            orientationMultiplier: Double,
            depth: Int
        ) throws -> WorkItem {
            let subcell = try implicitJetEncloser.restrictedBounds(
                of: implicit,
                cellIndex: cellIndex,
                fromNormalizedFraction: curveLower,
                toNormalizedFraction: curveUpper,
                tolerance: tolerance
            )
            let u = interval(subcell.parameterBox.interval(for: uCoordinate))
            let v = interval(subcell.parameterBox.interval(for: vCoordinate))
            let vDerivative = interval(
                subcell.parameterDerivativeBounds[vCoordinate.rawValue]
            )
            let deltaU = u - .exact(uBase)
            let lambda = Interval(
                lower: lambdaLower,
                upper: lambdaUpper
            )
            let mappedU = Interval.exact(uBase) + lambda * deltaU
            let flux = try field.bounds(
                uLower: mappedU.lower,
                uUpper: mappedU.upper,
                vLower: v.lower,
                vUpper: v.upper
            )
            let rangeEnclosure = Interval(lower: flux.lower, upper: flux.upper)
                * deltaU * vDerivative
                * .floating(
                    (lambdaUpper - lambdaLower) * orientationMultiplier
            )
            let enclosure: Interval
            let midpointWidth: Double?
            let midpointEnclosure = try implicitRationalMidpointEnclosure(
                intersection: implicit,
                cellIndex: cellIndex,
                curveLower: curveLower,
                curveUpper: curveUpper,
                lambdaLower: lambdaLower,
                lambdaUpper: lambdaUpper,
                orientationMultiplier: orientationMultiplier,
                uCoordinate: uCoordinate,
                vCoordinate: vCoordinate,
                field: field,
                uBase: uBase,
                curveJetEncloser: implicitJetEncloser,
                tolerance: tolerance
            )
            if let midpointEnclosure {
                let lower = max(
                    rangeEnclosure.lower,
                    midpointEnclosure.bounds.lower
                )
                let upper = min(
                    rangeEnclosure.upper,
                    midpointEnclosure.bounds.upper
                )
                guard lower <= upper else {
                    throw resourceFailure(
                        residual: lower - upper,
                        tolerance: tolerance,
                        message: "Certified implicit rational pcurve flux produced inconsistent independent enclosures."
                    )
                }
                enclosure = Interval(lower: lower, upper: upper)
                midpointWidth = midpointEnclosure.bounds.width
            } else {
                enclosure = rangeEnclosure
                midpointWidth = nil
            }
            guard enclosure.lower.isFinite, enclosure.upper.isFinite else {
                throw resourceFailure(
                    residual: enclosure.width,
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux exceeded finite interval arithmetic."
                )
            }
            return WorkItem(
                cell: cell,
                cellIndex: cellIndex,
                curveLower: curveLower,
                curveUpper: curveUpper,
                lambdaLower: lambdaLower,
                lambdaUpper: lambdaUpper,
                orientationMultiplier: orientationMultiplier,
                depth: depth,
                enclosure: enclosure,
                rangeWidth: rangeEnclosure.width,
                midpointWidth: midpointWidth
            )
        }

        var heap: [WorkItem] = []
        func push(_ item: WorkItem) {
            heap.append(item)
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard heap[index].width > heap[parent].width else { break }
                heap.swapAt(index, parent)
                index = parent
            }
        }
        func popMaximum() -> WorkItem? {
            guard !heap.isEmpty else { return nil }
            if heap.count == 1 { return heap.removeLast() }
            let result = heap[0]
            heap[0] = heap.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var largest = index
                if left < heap.count, heap[left].width > heap[largest].width {
                    largest = left
                }
                if right < heap.count, heap[right].width > heap[largest].width {
                    largest = right
                }
                guard largest != index else { break }
                heap.swapAt(index, largest)
                index = largest
            }
            return result
        }
        func accumulatedBounds() -> Interval {
            heap.reduce(Interval.exact(0.0)) { $0 + $1.enclosure }
        }

        for traversal in traversalSegments {
            for (index, cell) in implicit.cells.enumerated() {
                let cellStart = Double(index) / Double(cellCount)
                let cellEnd = Double(index + 1) / Double(cellCount)
                let overlapStart = max(traversal.canonicalLowerFraction, cellStart)
                let overlapEnd = min(traversal.canonicalUpperFraction, cellEnd)
                guard overlapEnd > overlapStart else { continue }
                push(try makeItem(
                    cell: cell,
                    cellIndex: index,
                    curveLower: (overlapStart - cellStart) * Double(cellCount),
                    curveUpper: (overlapEnd - cellStart) * Double(cellCount),
                    lambdaLower: 0.0,
                    lambdaUpper: 1.0,
                    orientationMultiplier: traversal.orientationMultiplier,
                    depth: 0
                ))
            }
        }
        guard !heap.isEmpty else {
            throw resourceFailure(
                residual: 0.0,
                tolerance: tolerance,
                message: "Certified implicit rational pcurve flux found no active traversal cell."
            )
        }

        var workItemCount = heap.count
        var activeWidth = heap.reduce(0.0) {
            ($0 + $1.enclosure.width).nextUp
        }
        while true {
            if activeWidth <= requestedWidth {
                let result = accumulatedBounds()
                if result.width <= requestedWidth {
                    return result
                }
                activeWidth = result.width
            }
            guard let item = popMaximum() else {
                throw resourceFailure(
                    residual: nil,
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux lost its active proof cells."
                )
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: item.enclosure.width,
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux exceeded its proof depth."
                )
            }
            workItemCount += 2
            guard workItemCount <= maximumWorkItems else {
                throw resourceFailure(
                    residual: activeWidth,
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux exhausted its \(maximumWorkItems)-cell budget; widest cell index \(item.cellIndex), local curve [\(item.curveLower), \(item.curveUpper)], depth \(item.depth), lambda [\(item.lambdaLower), \(item.lambdaUpper)], width \(item.width), range width \(item.rangeWidth), midpoint width \(String(describing: item.midpointWidth))."
                )
            }
            let curveSpan = item.curveUpper - item.curveLower
            let lambdaSpan = item.lambdaUpper - item.lambdaLower
            let canSplitCurve = curveSpan > tolerance.relative * 2.0
                && item.curveLower + curveSpan * 0.5 > item.curveLower
                && item.curveLower + curveSpan * 0.5 < item.curveUpper
            let canSplitLambda = lambdaSpan > tolerance.relative * 2.0
                && item.lambdaLower + lambdaSpan * 0.5 > item.lambdaLower
                && item.lambdaLower + lambdaSpan * 0.5 < item.lambdaUpper
            guard canSplitCurve || canSplitLambda else {
                throw resourceFailure(
                    residual: item.enclosure.width,
                    tolerance: tolerance,
                    message: "Certified implicit rational pcurve flux subdivision reached parameter resolution."
                )
            }
            if canSplitCurve,
               item.depth.isMultiple(of: 2) || !canSplitLambda {
                let middle = item.curveLower + curveSpan * 0.5
                let upper = try makeItem(
                    cell: item.cell,
                    cellIndex: item.cellIndex,
                    curveLower: middle,
                    curveUpper: item.curveUpper,
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    orientationMultiplier: item.orientationMultiplier,
                    depth: item.depth + 1
                )
                let lower = try makeItem(
                    cell: item.cell,
                    cellIndex: item.cellIndex,
                    curveLower: item.curveLower,
                    curveUpper: middle,
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: item.lambdaUpper,
                    orientationMultiplier: item.orientationMultiplier,
                    depth: item.depth + 1
                )
                push(upper)
                push(lower)
                activeWidth = max(0.0, activeWidth - item.width)
                activeWidth = (
                    activeWidth + upper.width + lower.width
                ).nextUp
            } else {
                let middle = item.lambdaLower
                    + lambdaSpan * 0.5
                let upper = try makeItem(
                    cell: item.cell,
                    cellIndex: item.cellIndex,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    lambdaLower: middle,
                    lambdaUpper: item.lambdaUpper,
                    orientationMultiplier: item.orientationMultiplier,
                    depth: item.depth + 1
                )
                let lower = try makeItem(
                    cell: item.cell,
                    cellIndex: item.cellIndex,
                    curveLower: item.curveLower,
                    curveUpper: item.curveUpper,
                    lambdaLower: item.lambdaLower,
                    lambdaUpper: middle,
                    orientationMultiplier: item.orientationMultiplier,
                    depth: item.depth + 1
                )
                push(upper)
                push(lower)
                activeWidth = max(0.0, activeWidth - item.width)
                activeWidth = (
                    activeWidth + upper.width + lower.width
                ).nextUp
            }
        }
    }

    private func implicitRationalMidpointEnclosure(
        intersection: CertifiedImplicitIntersectionCurve,
        cellIndex: Int,
        curveLower: Double,
        curveUpper: Double,
        lambdaLower: Double,
        lambdaUpper: Double,
        orientationMultiplier: Double,
        uCoordinate: SurfaceIntersectionParameterCoordinate,
        vCoordinate: SurfaceIntersectionParameterCoordinate,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        uBase: Double,
        curveJetEncloser: ImplicitCurveIntervalJetEncloser,
        tolerance: ModelingTolerance
    ) throws -> ImplicitMidpointEnclosure? {
        let cellCount = Double(intersection.cells.count)
        let localSpan = curveUpper - curveLower
        let lambdaSpan = lambdaUpper - lambdaLower
        guard cellCount > 0.0,
              localSpan > tolerance.relative * 4.0,
              localSpan <= 1.0 / 16.0,
              lambdaSpan > 0.0 else {
            return nil
        }
        let globalLower = (Double(cellIndex) + curveLower) / cellCount
        let globalUpper = (Double(cellIndex) + curveUpper) / cellCount
        let globalSpan = globalUpper - globalLower
        let globalInterval = try ScalarInterval(
            lower: globalLower,
            upper: globalUpper
        )
        let parameterJet = try curveJetEncloser.parameterIntervalJet(
            of: intersection,
            over: globalInterval,
            tolerance: tolerance
        )
        let uCoordinateJet = parameterJet[uCoordinate]
        let vCoordinateJet = parameterJet[vCoordinate]
        let u = interval(uCoordinateJet.value)
        let uFirst = interval(uCoordinateJet.firstDerivative)
        let uSecond = interval(uCoordinateJet.secondDerivative)
        let v = interval(vCoordinateJet.value)
        let vFirst = interval(vCoordinateJet.firstDerivative)
        let vSecond = interval(vCoordinateJet.secondDerivative)
        let vThird = interval(vCoordinateJet.thirdDerivative)
        let deltaU = u - .exact(uBase)
        let lambda = Interval(lower: lambdaLower, upper: lambdaUpper)
        let mappedU = Interval.exact(uBase) + lambda * deltaU
        guard let uSpan = field.containingUSpan(mappedU),
              let vSpan = field.containingVSpan(v) else {
            return nil
        }
        let partials = try field.secondOrderBounds(
            u: mappedU,
            v: v,
            uSpan: uSpan,
            vSpan: vSpan
        )
        let two = Interval.exact(2.0)
        let mappedUFirst = lambda * uFirst
        let mappedUSecond = lambda * uSecond
        let fluxFirst = partials.derivativeU * mappedUFirst
            + partials.derivativeV * vFirst
        let fluxSecond = partials.secondDerivativeUU
            * mappedUFirst * mappedUFirst
            + two * partials.secondDerivativeUV * mappedUFirst * vFirst
            + partials.secondDerivativeVV * vFirst * vFirst
            + partials.derivativeU * mappedUSecond
            + partials.derivativeV * vSecond
        let curveIntegrandSecond = fluxSecond * deltaU * vFirst
            + partials.value * uSecond * vFirst
            + partials.value * deltaU * vThird
            + two * fluxFirst * uFirst * vFirst
            + two * fluxFirst * deltaU * vSecond
            + two * partials.value * uFirst * vSecond
        let lambdaIntegrandSecond = partials.secondDerivativeUU
            * deltaU * deltaU * deltaU * vFirst
        let lambdaSecond = lambdaIntegrandSecond.maximumAbsolute
        let curveSecond = curveIntegrandSecond.maximumAbsolute
        let lambdaError = outwardProduct(
            outwardProduct(lambdaSecond, pow(lambdaSpan, 3.0)),
            globalSpan / 24.0
        )
        let curveError = outwardProduct(
            outwardProduct(curveSecond, pow(globalSpan, 3.0)),
            lambdaSpan / 24.0
        )
        let error = (lambdaError + curveError).nextUp
        guard error.isFinite else {
            throw resourceFailure(
                residual: error,
                tolerance: tolerance,
                message: "Certified implicit rational pcurve midpoint error exceeded finite arithmetic."
            )
        }

        let localMidpoint = curveLower + localSpan * 0.5
        let minimumHalfWidth = max(
            tolerance.relative * 2.0,
            Double.ulpOfOne * max(1.0, abs(localMidpoint)) * 4_096.0
        )
        let sampleHalfWidth = min(localSpan * 0.25, minimumHalfWidth)
        let sampleGlobalInterval = try ScalarInterval(
            lower: (Double(cellIndex) + localMidpoint - sampleHalfWidth) / cellCount,
            upper: (Double(cellIndex) + localMidpoint + sampleHalfWidth) / cellCount
        )
        let sampleJet = try curveJetEncloser.parameterIntervalJet(
            of: intersection,
            over: sampleGlobalInterval,
            tolerance: tolerance
        )
        let sampleU = interval(sampleJet[uCoordinate].value)
        let sampleV = interval(sampleJet[vCoordinate].value)
        let derivativeOffset = localSpan * 0.125
        let derivativeOffsetGlobal = derivativeOffset / cellCount
        let lowerDerivativeSample = try curveJetEncloser.parameterIntervalJet(
            of: intersection,
            over: try ScalarInterval(
                lower: (
                    Double(cellIndex) + localMidpoint - derivativeOffset
                        - sampleHalfWidth
                ) / cellCount,
                upper: (
                    Double(cellIndex) + localMidpoint - derivativeOffset
                        + sampleHalfWidth
                ) / cellCount
            ),
            tolerance: tolerance
        )
        let upperDerivativeSample = try curveJetEncloser.parameterIntervalJet(
            of: intersection,
            over: try ScalarInterval(
                lower: (
                    Double(cellIndex) + localMidpoint + derivativeOffset
                        - sampleHalfWidth
                ) / cellCount,
                upper: (
                    Double(cellIndex) + localMidpoint + derivativeOffset
                        + sampleHalfWidth
                ) / cellCount
            ),
            tolerance: tolerance
        )
        let derivativeSecant = (
            interval(upperDerivativeSample[vCoordinate].value)
                - interval(lowerDerivativeSample[vCoordinate].value)
        ) / .floating(2.0 * derivativeOffsetGlobal)
        let derivativeRemainder = outwardProduct(
            vThird.maximumAbsolute,
            derivativeOffsetGlobal * derivativeOffsetGlobal / 6.0
        )
        let sampleVDerivative = derivativeSecant + Interval(
            lower: (-derivativeRemainder).nextDown,
            upper: derivativeRemainder.nextUp
        )
        let sampleDeltaU = sampleU - .exact(uBase)
        let lambdaMidpoint = lambdaLower + lambdaSpan * 0.5
        let sampleMappedU = Interval.exact(uBase)
            + .floating(lambdaMidpoint) * sampleDeltaU
        let sampleFlux = try field.bounds(
            uLower: sampleMappedU.lower,
            uUpper: sampleMappedU.upper,
            vLower: sampleV.lower,
            vUpper: sampleV.upper
        )
        let estimate = Interval(
            lower: sampleFlux.lower,
            upper: sampleFlux.upper
        ) * sampleDeltaU * sampleVDerivative
            * .floating(lambdaSpan * globalSpan * orientationMultiplier)
        return ImplicitMidpointEnclosure(
            bounds: Interval(
                lower: (estimate.lower - error).nextDown,
                upper: (estimate.upper + error).nextUp
            )
        )
    }

    private func adaptiveJetBounds(
        requestedWidth: Double,
        tolerance: ModelingTolerance,
        evaluator: (Jet) throws -> Jet
    ) throws -> Interval {
        try withoutActuallyEscaping(evaluator) { escapableEvaluator in
            try adaptiveJetBoundsShared(
                requestedWidth: requestedWidth,
                tolerance: tolerance,
                evaluators: [escapableEvaluator]
            )
        }
    }

    // Equal per-segment width splits starve segments whose integrand sits on
    // a square-root shoulder while tame segments waste their share, so all
    // segments refine against one shared width budget.
    private func adaptiveJetBoundsShared(
        requestedWidth: Double,
        tolerance: ModelingTolerance,
        evaluators: [(Jet) throws -> Jet]
    ) throws -> Interval {
        struct WorkItem {
            let segment: Int
            let lower: Double
            let upper: Double
            let depth: Int
            let enclosure: Interval?

            var width: Double {
                enclosure?.width ?? .infinity
            }
        }
        // Per-cell halving budgets shrink faster than a square-root
        // shoulder can converge, so the proof refines the globally widest
        // cell (singular cells first) until the summed enclosure width
        // meets the request.
        func makeItem(
            segment: Int,
            lower: Double,
            upper: Double,
            depth: Int
        ) throws -> WorkItem {
            let enclosure = try gaussEnclosure(
                lower: lower,
                upper: upper,
                evaluator: evaluators[segment],
                tolerance: tolerance
            )
            if let enclosure {
                guard enclosure.lower.isFinite, enclosure.upper.isFinite else {
                    throw resourceFailure(
                        residual: enclosure.width,
                        tolerance: tolerance,
                        message: "Certified analytic pcurve flux exceeded finite interval arithmetic."
                    )
                }
            }
            return WorkItem(
                segment: segment,
                lower: lower,
                upper: upper,
                depth: depth,
                enclosure: enclosure
            )
        }
        var heap: [WorkItem] = []
        func push(_ item: WorkItem) {
            heap.append(item)
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard heap[index].width > heap[parent].width else { break }
                heap.swapAt(index, parent)
                index = parent
            }
        }
        func popMaximum() -> WorkItem? {
            guard heap.isEmpty == false else { return nil }
            if heap.count == 1 { return heap.removeLast() }
            let top = heap[0]
            heap[0] = heap.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var largest = index
                if left < heap.count, heap[left].width > heap[largest].width {
                    largest = left
                }
                if right < heap.count, heap[right].width > heap[largest].width {
                    largest = right
                }
                guard largest != index else { break }
                heap.swapAt(index, largest)
                index = largest
            }
            return top
        }
        for segment in evaluators.indices {
            push(try makeItem(
                segment: segment,
                lower: 0.0,
                upper: 1.0,
                depth: 0
            ))
        }
        var workItemCount = evaluators.count
        func recomputeTotals() -> (finite: Double, singular: Int) {
            var total = 0.0
            var singular = 0
            for item in heap {
                if let enclosure = item.enclosure {
                    total = (total + enclosure.width).nextUp
                } else {
                    singular += 1
                }
            }
            return (total, singular)
        }
        var totals = recomputeTotals()
        var subdivisionCount = 0
        while totals.singular > 0 || totals.finite > requestedWidth {
            guard let item = popMaximum() else {
                throw resourceFailure(
                    residual: totals.finite,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux lost its active proof cells."
                )
            }
            guard item.depth < maximumDepth else {
                throw resourceFailure(
                    residual: item.enclosure?.width,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux exceeded its maximum proof depth."
                )
            }
            workItemCount += 2
            guard workItemCount <= max(maximumWorkItems, 1_048_576) else {
                let widest = heap.max { lhs, rhs in
                    (lhs.enclosure?.width ?? Double.infinity)
                        < (rhs.enclosure?.width ?? Double.infinity)
                }
                throw resourceFailure(
                    residual: Double(workItemCount),
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux exhausted its subdivision budget. Finite width \(totals.finite) versus requested \(requestedWidth), singular cells \(totals.singular), widest cell segment \(String(describing: widest?.segment)) range [\(String(describing: widest?.lower)), \(String(describing: widest?.upper))] depth \(String(describing: widest?.depth)) enclosure width \(String(describing: widest?.enclosure?.width)), current item segment \(item.segment) range [\(item.lower), \(item.upper)] depth \(item.depth) enclosure \(String(describing: item.enclosure?.width))."
                )
            }
            let middle = item.lower + (item.upper - item.lower) * 0.5
            guard middle > item.lower, middle < item.upper else {
                throw resourceFailure(
                    residual: item.enclosure?.width,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux subdivision reached floating-point resolution."
                )
            }
            let left = try makeItem(
                segment: item.segment,
                lower: item.lower,
                upper: middle,
                depth: item.depth + 1
            )
            let right = try makeItem(
                segment: item.segment,
                lower: middle,
                upper: item.upper,
                depth: item.depth + 1
            )
            push(left)
            push(right)
            subdivisionCount += 1
            if subdivisionCount.isMultiple(of: 128) {
                totals = recomputeTotals()
            } else {
                if let popped = item.enclosure {
                    totals.finite -= popped.width
                } else {
                    totals.singular -= 1
                }
                for child in [left, right] {
                    if let enclosure = child.enclosure {
                        totals.finite = (totals.finite + enclosure.width).nextUp
                    } else {
                        totals.singular += 1
                    }
                }
                totals.finite = max(totals.finite, 0.0)
            }
        }
        var result = Interval.exact(0.0)
        for item in heap {
            guard let enclosure = item.enclosure else {
                throw resourceFailure(
                    residual: nil,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve flux retained an unresolved singular cell."
                )
            }
            result = result + enclosure
        }
        // Heap refinement order varies with traversal direction, so the
        // bounds are quantized outward onto a shared magnitude grid; this
        // keeps forward and reversed enclosures mutually containing while
        // only ever widening the certified result.
        // The ulp of a binade is a fixed power of two, so the grid is a
        // shared absolute step for every same-magnitude enclosure rather
        // than a magnitude-proportional step that quantization cancels.
        let grid = max(
            result.lower.ulp,
            result.upper.ulp,
            Double.leastNormalMagnitude
        ) * 64.0
        return Interval(
            lower: (result.lower / grid).rounded(.down) * grid,
            upper: (result.upper / grid).rounded(.up) * grid
        )
    }

    private func adaptiveParameterEnclosures(
        lowerFraction: Double,
        upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance,
        evaluator: (Jet) throws -> (u: Jet, v: Jet)
    ) throws -> [SurfaceParameterCurveEnclosure] {
        struct WorkItem {
            let lower: Double
            let upper: Double
            let depth: Int
        }
        var pending = [WorkItem(
            lower: lowerFraction,
            upper: upperFraction,
            depth: 0
        )]
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
    ) throws -> Interval? {
        let midpoint = lower + (upper - lower) * 0.5
        let halfSpan = (upper - lower) * 0.5
        let root = sqrt(3.0 / 5.0)
        let nodes = [midpoint - halfSpan * root, midpoint, midpoint + halfSpan * root]
        let weights = [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
        var estimate = Interval.exact(0.0)
        for index in nodes.indices {
            let evaluated: Jet
            do {
                evaluated = try evaluator(.variable(.exact(nodes[index])))
            } catch LocalProofFailure.intervalSingularity {
                return nil
            }
            let value = evaluated.coefficients[0]
            estimate = estimate + value * .floating(weights[index])
        }
        estimate = estimate * .floating(halfSpan)

        let domainJet: Jet
        do {
            domainJet = try evaluator(.variable(Interval(
                lower: lower,
                upper: upper
            )))
        } catch LocalProofFailure.intervalSingularity {
            return nil
        }
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
        let gauss = Interval(
            lower: (estimate.lower - error).nextDown,
            upper: (estimate.upper + error).nextUp
        )
        // The value-range envelope needs no derivatives, so it stays tame
        // on square-root shoulders where high-order interval jets inflate;
        // both enclosures certify the same integral, so their overlap does
        // too.
        let envelope = domainJet.coefficients[0] * .floating(upper - lower)
        guard envelope.lower.isFinite, envelope.upper.isFinite else {
            return gauss
        }
        let overlapLower = max(gauss.lower, envelope.lower)
        let overlapUpper = min(gauss.upper, envelope.upper)
        guard overlapLower <= overlapUpper else {
            return gauss.width <= envelope.width ? gauss : envelope
        }
        return Interval(lower: overlapLower, upper: overlapUpper)
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
                curve: curve,
                subcell: subcell,
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
        curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        subcell: CertifiedImplicitIntersectionGraphSubcell,
        integrand: Integrand,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let enclosure = try curve.parameterEnclosure(
            for: subcell,
            tolerance: tolerance
        )
        return integrand.greenPrimitive(
            u: Interval(lower: enclosure.u.lower, upper: enclosure.u.upper),
            v: Interval(lower: enclosure.v.lower, upper: enclosure.v.upper)
        ) * Interval(
            lower: enclosure.vDerivative.lower,
            upper: enclosure.vDerivative.upper
        )
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
        case .cylinder, .analytic, .bSpline, .procedural:
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
        case .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .rigidImage, .affineImage:
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
        patch: PreparedRationalPcurvePatch,
        parameter: Interval,
        integrand: Integrand,
        tolerance: ModelingTolerance
    ) throws -> Jet {
        let parameters = try rationalPcurveJets(
            patch: patch,
            parameter: parameter,
            tolerance: tolerance
        )
        return greenPrimitive(
            integrand: integrand,
            u: parameters.u,
            v: parameters.v
        ) * parameters.v.derivative()
    }

    func polynomialCylinderBounds(
        for curve: BSplineCurve2D,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> PolynomialCylinderBounds? {
        guard case let .cylinder(radius, offsetU, offsetV) = integrand,
              let firstWeight = curve.weights.first,
              firstWeight.isFinite,
              firstWeight > 0.0,
              curve.weights.allSatisfy({ $0 == firstWeight }) else {
            return nil
        }
        let patches = try curve.rationalBezierPatches(tolerance: tolerance)
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Polynomial cylinder flux produced no Bezier spans."
            )
        }
        let patchWidth = requestedWidth / Double(patches.count)
        var result = Interval.exact(0.0)
        var parameterArea = Interval.exact(0.0)
        for patch in patches {
            guard patch.degree >= 1,
                  patch.controlPoints.count == patch.weights.count,
                  let firstWeight = patch.weights.first,
                  firstWeight.isFinite,
                  firstWeight > 0.0,
                  patch.weights.allSatisfy({ $0 == firstWeight }) else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Polynomial cylinder flux requires finite certified Bezier controls."
                )
            }
            let uControls = patch.controlPoints.map { Interval.floating($0.x) }
            let vControls = patch.controlPoints.map { Interval.floating($0.y) }
            let u = powerCoefficients(bernsteinControls: uControls)
            let v = powerCoefficients(bernsteinControls: vControls)
            let vDerivative = derivativeCoefficients(v)
            let uvIntegral = integratedProduct(u, vDerivative)
            parameterArea = parameterArea + uvIntegral
            let lowerU = uControls.map(\.lower).min() ?? -.infinity
            let upperU = uControls.map(\.upper).max() ?? .infinity
            let center = lowerU + (upperU - lowerU) * 0.5
            guard center.isFinite else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Polynomial cylinder flux lost a finite angular center."
                )
            }
            let deltaControls = uControls.map { $0 - .floating(center) }
            let delta = powerCoefficients(bernsteinControls: deltaControls)
            let maximumDelta = max(abs(lowerU - center), abs(upperU - center)).nextUp
            let maximumVDerivative = derivativeBernsteinControls(vControls)
                .map(\.maximumAbsolute)
                .max() ?? .infinity
            let trigonometric = try polynomialTrigonometricMoments(
                delta: delta,
                vDerivative: vDerivative,
                center: center,
                maximumDelta: maximumDelta,
                maximumVDerivative: maximumVDerivative,
                tolerance: tolerance
            )
            let contribution = radius / .exact(3.0) * (
                offsetU * trigonometric.sine
                    - offsetV * trigonometric.cosine
                    + radius * uvIntegral
            )
            guard contribution.width <= patchWidth else {
                throw resourceFailure(
                    residual: contribution.width,
                    tolerance: tolerance,
                    message: "Polynomial cylinder flux exceeded its Bezier-span enclosure budget."
                )
            }
            result = result + contribution
        }
        return PolynomialCylinderBounds(
            flux: result,
            parameterArea: SurfaceParameterAreaBounds(
                lower: parameterArea.lower,
                upper: parameterArea.upper
            )
        )
    }

    private func polynomialTrigonometricMoments(
        delta: [Interval],
        vDerivative: [Interval],
        center: Double,
        maximumDelta: Double,
        maximumVDerivative: Double,
        tolerance: ModelingTolerance
    ) throws -> (sine: Interval, cosine: Interval) {
        let maximumOrder = 10
        var deltaPower = [Interval.exact(1.0)]
        var sine = Interval.exact(0.0)
        var cosine = Interval.exact(0.0)
        var factorial = 1.0
        for order in 0...maximumOrder {
            if order > 0 {
                factorial *= Double(order)
                deltaPower = convolved(deltaPower, delta)
            }
            let moment = integratedProduct(deltaPower, vDerivative)
            let phase = center + Double(order) * Double.pi * 0.5
            sine = sine + .floating(sin(phase) / factorial) * moment
            cosine = cosine + .floating(cos(phase) / factorial) * moment
        }
        let nextFactorial = factorial * Double(maximumOrder + 1)
        var remainder = pow(maximumDelta, Double(maximumOrder + 1))
            / nextFactorial * maximumVDerivative
        for _ in 0..<16 { remainder = remainder.nextUp }
        guard remainder.isFinite else {
            throw resourceFailure(
                residual: remainder,
                tolerance: tolerance,
                message: "Polynomial cylinder flux Taylor remainder exceeded finite arithmetic."
            )
        }
        let enclosedSine = Interval(
            lower: (sine.lower - remainder).nextDown,
            upper: (sine.upper + remainder).nextUp
        )
        let enclosedCosine = Interval(
            lower: (cosine.lower - remainder).nextDown,
            upper: (cosine.upper + remainder).nextUp
        )
        return (enclosedSine, enclosedCosine)
    }

    private func powerCoefficients(
        bernsteinControls: [Interval]
    ) -> [Interval] {
        let degree = bernsteinControls.count - 1
        return (0...degree).map { power in
            var coefficient = Interval.exact(0.0)
            for index in 0...power {
                let sign = (power - index).isMultiple(of: 2) ? 1.0 : -1.0
                let scale = sign
                    * binomial(degree, power)
                    * binomial(power, index)
                coefficient = coefficient
                    + bernsteinControls[index] * .floating(scale)
            }
            return coefficient
        }
    }

    private func derivativeCoefficients(_ coefficients: [Interval]) -> [Interval] {
        guard coefficients.count >= 2 else { return [.exact(0.0)] }
        return (1..<coefficients.count).map { index in
            coefficients[index] * .floating(Double(index))
        }
    }

    private func derivativeBernsteinControls(
        _ controls: [Interval]
    ) -> [Interval] {
        let degree = controls.count - 1
        guard degree > 0 else { return [.exact(0.0)] }
        return (0..<degree).map { index in
            (controls[index + 1] - controls[index]) * .floating(Double(degree))
        }
    }

    private func convolved(
        _ first: [Interval],
        _ second: [Interval]
    ) -> [Interval] {
        var result = Array(
            repeating: Interval.exact(0.0),
            count: first.count + second.count - 1
        )
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                let index = firstIndex + secondIndex
                result[index] = result[index]
                    + first[firstIndex] * second[secondIndex]
            }
        }
        return result
    }

    private func integratedProduct(
        _ first: [Interval],
        _ second: [Interval]
    ) -> Interval {
        let product = convolved(first, second)
        return product.indices.reduce(Interval.exact(0.0)) { result, index in
            result + product[index] / .floating(Double(index + 1))
        }
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        guard k > 0, k < n else { return 1.0 }
        let reduced = min(k, n - k)
        return (1...reduced).reduce(1.0) { result, index in
            result * Double(n - reduced + index) / Double(index)
        }
    }

    private func rationalPcurveJets(
        patch: PreparedRationalPcurvePatch,
        parameter: Interval,
        tolerance: ModelingTolerance
    ) throws -> (u: Jet, v: Jet) {
        let x = bezierVariableJet(
            derivativeControls: patch.xDerivativeControls,
            parameter: parameter
        )
        let y = bezierVariableJet(
            derivativeControls: patch.yDerivativeControls,
            parameter: parameter
        )
        let weight = bezierVariableJet(
            derivativeControls: patch.weightDerivativeControls,
            parameter: parameter
        )
        var u = try x.divided(by: weight)
        var v = try y.divided(by: weight)
        let restrictedControls = try patch.source.restrictedControls(
            fractionLower: parameter.lower,
            fractionUpper: parameter.upper,
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

    private func prepareRationalPcurvePatch(
        _ patch: HomogeneousPatch,
        tolerance: ModelingTolerance
    ) throws -> PreparedRationalPcurvePatch {
        guard patch.degree >= 1,
              patch.controls.allSatisfy(\.isFiniteAndPositiveWeight) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified rational pcurve flux requires valid homogeneous controls."
            )
        }
        return PreparedRationalPcurvePatch(
            source: patch,
            xDerivativeControls: bezierDerivativeControlLevels(
                patch.controls.map { interval($0.x) }
            ),
            yDerivativeControls: bezierDerivativeControlLevels(
                patch.controls.map { interval($0.y) }
            ),
            weightDerivativeControls: bezierDerivativeControlLevels(
                patch.controls.map { interval($0.weight) }
            )
        )
    }

    private func bezierDerivativeControlLevels(
        _ controls: [Interval]
    ) -> [[Interval]] {
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append(derivativeBernsteinControls(previous))
        }
        return levels
    }

    /// Builds the Taylor jet of a Bernstein polynomial for the independent
    /// variable used by the Gauss proof. Each coefficient is the certified
    /// range of the corresponding derivative divided by its factorial.
    private func bezierVariableJet(
        derivativeControls: [[Interval]],
        parameter: Interval
    ) -> Jet {
        var coefficients = Array(
            repeating: Interval.exact(0.0),
            count: Jet.order + 1
        )
        var factorial = 1.0
        for derivativeOrder in 0..<min(
            derivativeControls.count,
            Jet.order + 1
        ) {
            if derivativeOrder > 1 {
                factorial *= Double(derivativeOrder)
            }
            coefficients[derivativeOrder] = bezierRange(
                controls: derivativeControls[derivativeOrder],
                parameter: parameter
            ) / .exact(factorial)
        }
        return Jet(coefficients: coefficients)
    }

    private func bezierRange(
        controls: [Interval],
        parameter: Interval
    ) -> Interval {
        var level = controls
        let complement = Interval.exact(1.0) - parameter
        while level.count > 1 {
            for index in 0..<(level.count - 1) {
                level[index] = level[index] * complement
                    + level[index + 1] * parameter
            }
            level.removeLast()
        }
        return level[0]
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
