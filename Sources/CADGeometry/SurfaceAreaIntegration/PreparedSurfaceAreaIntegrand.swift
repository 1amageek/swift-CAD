import CADCore
import Foundation

/// Integral-specific fields; derivative coordinates are boundary fraction and radial fraction.
package struct SurfaceAreaIntegrandBounds: Sendable {
    package let value: OutwardScalarInterval
    package let derivativeU: OutwardScalarInterval
    package let derivativeV: OutwardScalarInterval
    package let secondUU: OutwardScalarInterval?
    package let secondUV: OutwardScalarInterval?
    package let secondVV: OutwardScalarInterval?
}

/// Immutable exact geometry preparation for signed boundary-fan integration.
package struct PreparedSurfaceAreaIntegrand: Sendable {
    private indirect enum Storage: Sendable {
        case spline(BSplineSurface3D, [RationalBezierSurfaceJetEncloser.PreparedPatch])
        case offset(OffsetSurface3D, PreparedSurfaceAreaIntegrand)
        case direct(PreparedSurfaceDifferentialEncloser)
        case translatedRollingBall(SurfaceAreaTranslatedRollingBallJet)
    }
    package let surface: Surface3D
    private let storage: Storage
    private let derivativeOrder: Int
    package let translationDirection: SurfaceAreaTranslationCertificate?

    package init(surface: Surface3D, tolerance: ModelingTolerance, maximumControlPointCount: Int = 65_536) throws {
        try Self.admitDimensions(surface, limit: maximumControlPointCount, tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        self.surface = surface
        translationDirection = SurfaceAreaTranslationCertificate.direction(of: surface)
        switch surface {
        case .bSpline(let spline):
            let encloser = RationalBezierSurfaceJetEncloser()
            storage = .spline(spline, try BSplineSurfaceBezierDecomposer().surfacePatches(
                surface: spline, tolerance: tolerance
            ).map { try encloser.prepare($0, tolerance: tolerance) })
            func continuity(_ knots: [Double], _ degree: Int) -> Int {
                let unique = Array(Set(knots)).sorted()
                return unique.dropFirst().dropLast().map { knot in
                    degree - knots.filter { $0 == knot }.count
                }.min() ?? 3
            }
            derivativeOrder = min(3, continuity(spline.uKnots, spline.uDegree) + 1,
                                  continuity(spline.vKnots, spline.vDegree) + 1)
            // FIXME(INCOMPLETE_IMPLEMENTATION): C0 interior support knots have an unintegrated
            // density discontinuity on the production face-area/centroid path. Complete only
            // after exact span/domain partitioning and successful discontinuous-density fixtures.
            guard derivativeOrder >= 2 else {
                throw Self.failure(.unsupportedCapability, tolerance,
                    "Area density integration requires C1 support across interior B-spline knots.")
            }
        case .procedural(.offset(let offset)):
            if let exact = try offset.exactChartPreservingSurface(tolerance: tolerance) {
                let prepared = try PreparedSurfaceAreaIntegrand(surface: exact, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount)
                storage = prepared.storage
                derivativeOrder = prepared.derivativeOrder
            } else {
                let source = try PreparedSurfaceAreaIntegrand(surface: offset.source, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Sources below third order, including
                // uncertified nested offsets, lack derivatives for production face-area/centroid integration.
                // Complete only after higher source interval jets and offset integral fixtures certify.
                guard source.derivativeOrder >= 3 else {
                    throw Self.failure(.unsupportedCapability, tolerance,
                        "Offset area density gradients require certified third source derivatives.")
                }
                storage = .offset(offset, source)
                // OffsetSurface3D's actual interval path zeroes third tangent jets.
                // Those are fourth source derivatives: use density Hessians only
                // when structural polynomial authority proves every one is zero.
                derivativeOrder = SurfaceAreaTranslationCertificate.fourthDerivativesAreExactlyZero(of: offset.source) ? 3 : 2
            }
        case .procedural(.ruled(let ruled)):
            derivativeOrder = min(try Self.curveOrder(ruled.startBoundary, tolerance: tolerance),
                                  try Self.curveOrder(ruled.endBoundary, tolerance: tolerance))
            // FIXME(INCOMPLETE_IMPLEMENTATION): Ruled supports with non-C1 boundary curves lack
            // density derivative admission on production face-area/centroid queries. Complete
            // only after piecewise boundary partitioning and successful/failure integral fixtures.
            guard derivativeOrder >= 2 else {
                throw Self.failure(.unsupportedCapability, tolerance, "Ruled area derivatives require C1 boundary geometry.")
            }
            storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
        case .procedural(.rollingBall(let blend)):
            if case .bSpline(let spine) = blend.centerSpine,
               spine.controlPoints.count > maximumControlPointCount {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Area center-spine admission limit exceeded.")
            }
            derivativeOrder = min(try Self.curveOrder(blend.centerSpine, tolerance: tolerance),
                                  try Self.curveOrder(blend.firstContact, tolerance: tolerance),
                                  try Self.curveOrder(blend.secondContact, tolerance: tolerance))
            // FIXME(INCOMPLETE_IMPLEMENTATION): Non-C1 rolling-ball spine/rails cannot certify
            // density derivatives on production face-area/centroid queries. Complete only after
            // piecewise blend integration and exact integral/error fixtures admit these sources.
            guard derivativeOrder >= 2 else {
                throw Self.failure(.unsupportedCapability, tolerance, "Rolling-ball area derivatives require C1 spine and rails.")
            }
            if let translated = try SurfaceAreaTranslatedRollingBallJet(blend) {
                storage = .translatedRollingBall(translated)
            } else {
                storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
            }
        default:
            storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
            derivativeOrder = 3
        }
    }

    /// Bounds exact density and three reference-centered moments over a fan square.
    package func bounds(
        curve: SurfaceParameterCurve, anchor: SurfaceParameter, reference: Point3D,
        boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceAreaIntegrandBounds] {
        guard let chart = try SurfaceParameterIntervalJet.enclose(
            curve, over: boundaryFraction, tolerance: tolerance
        ) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Certified intersection and rigid-image trims
            // lack integral-specific fan derivative jets on this production face-area path.
            // Complete only when those exact chart derivatives and integral fixtures certify.
            throw Self.failure(.unsupportedCapability, tolerance,
                "Face area fan integration has no certified derivatives for this trim chart.")
        }
        let r = SurfaceIntervalJet.parameterV(radialFraction)
        let du = chart.u - .constant(anchor.u)
        let dv = chart.v - .constant(anchor.v)
        let u: SurfaceIntervalJet = .constant(anchor.u) + du * r
        let v: SurfaceIntervalJet = .constant(anchor.v) + dv * r
        let parameters = SurfaceParameterBox(
            u: try clipped(u.value, to: surface.uDomain, tolerance: tolerance),
            v: try clipped(v.value, to: surface.vDomain, tolerance: tolerance))
        let jet = try surfaceJet(over: parameters, tolerance: tolerance)
        let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
        guard let density = cross.dot(cross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance,
                "Surface area integrand cannot certify a nonzero area element on this box.")
        }
        let jacobian = r * (du * chart.v.differentiatedUThroughSecondOrder()
                           - dv * chart.u.differentiatedUThroughSecondOrder())
        let coordinates = [jet.x - .constant(reference.x), jet.y - .constant(reference.y),
                           jet.z - .constant(reference.z)]
        return ([density] + coordinates.map { $0 * density }).map { field in
            let composed = compose(field, u: u, v: v) * jacobian
            return SurfaceAreaIntegrandBounds(
                value: composed.value, derivativeU: composed.derivativeU, derivativeV: composed.derivativeV,
                secondUU: derivativeOrder >= 3 ? composed.secondDerivativeUU : nil,
                secondUV: derivativeOrder >= 3 ? composed.secondDerivativeUV : nil,
                secondVV: derivativeOrder >= 3 ? composed.secondDerivativeVV : nil)
        }
    }

    /// Structural affine authority permits exact radial integration for every numeric trim.
    package var radialIntegrationIsExact: Bool { surface.hasExactAffineParameterization }

    package func boundaryBounds(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                reference: Point3D, boundaryFraction: ScalarInterval,
                                tolerance: ModelingTolerance) throws -> [SurfaceAreaIntegrandBounds] {
        guard radialIntegrationIsExact,
              let chart = try SurfaceParameterIntervalJet.enclose(curve, over: boundaryFraction,
                                                                 tolerance: tolerance) else {
            throw Self.failure(.unsupportedCapability, tolerance, "Exact radial area requires an affine support and numeric chart.")
        }
        // Prove the exact boundary fan remains within the original support domain.
        let fullR = SurfaceIntervalJet.parameterV(try ScalarInterval(lower: 0, upper: 1))
        let du = chart.u - .constant(anchor.u), dv = chart.v - .constant(anchor.v)
        let fanU: SurfaceIntervalJet = .constant(anchor.u) + du * fullR
        let fanV: SurfaceIntervalJet = .constant(anchor.v) + dv * fullR
        _ = try clipped(fanU.value, to: surface.uDomain, tolerance: tolerance)
        _ = try clipped(fanV.value, to: surface.vDomain, tolerance: tolerance)
        let pointBox = SurfaceParameterBox(
            u: try clipped(.exact(anchor.u), to: surface.uDomain, tolerance: tolerance),
            v: try clipped(.exact(anchor.v), to: surface.vDomain, tolerance: tolerance))
        let map = try surfaceJet(over: pointBox, tolerance: tolerance)
        let areaCross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
        guard let nativeDensity = areaCross.dot(areaCross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance, "Affine area element is unresolved.")
        }
        func constant(_ interval: OutwardScalarInterval) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value: interval, derivativeU: zero, derivativeV: zero,
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let density = constant(nativeDensity.value)
        let determinant = du * chart.v.differentiatedUThroughSecondOrder()
            - dv * chart.u.differentiatedUThroughSecondOrder()
        let area = density * determinant * .constant(0.5)
        let point = [map.x, map.y, map.z]
        let origins = [reference.x, reference.y, reference.z]
        var fields = [area]
        for index in 0..<3 {
            let native = point[index]
            let offset = constant(native.value - .exact(origins[index]))
            let displacement = constant(native.derivativeU) * du + constant(native.derivativeV) * dv
            // Integral r dr = 1/2; integral r^2 dr = 1/3 exactly.
            fields.append(offset * area + displacement * density * determinant * .constant(1.0 / 3))
        }
        return fields.map { field in
            SurfaceAreaIntegrandBounds(value: field.value, derivativeU: field.derivativeU,
                derivativeV: field.derivativeV, secondUU: field.secondDerivativeUU,
                secondUV: field.secondDerivativeUV, secondVV: field.secondDerivativeVV)
        }
    }

    /// Integrates a proved translation coordinate exactly over one rectangular trim.
    /// Density is independent of that coordinate and position is affine in it.
    package func rectangularTranslationBounds(
        rectangle: SurfaceParameterBox, fraction: ScalarInterval, reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceAreaIntegrandBounds] {
        guard let direction = translationDirection else {
            throw Self.failure(.unsupportedCapability, tolerance, "A surface translation certificate is required.")
        }
        // Exact elimination must preserve admission of the entire original band,
        // including endpoints that are absent from the midpoint evaluation box.
        _ = try clipped(OutwardScalarInterval(lower: rectangle.u.lower, upper: rectangle.u.upper),
                        to: surface.uDomain, tolerance: tolerance)
        _ = try clipped(OutwardScalarInterval(lower: rectangle.v.lower, upper: rectangle.v.upper),
                        to: surface.vDomain, tolerance: tolerance)
        func constant(_ interval: OutwardScalarInterval) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value: interval, derivativeU: zero, derivativeV: zero,
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let varying = direction == .v ? rectangle.u : rectangle.v
        let integrated = direction == .v ? rectangle.v : rectangle.u
        let width = OutwardScalarInterval.exact(varying.upper) - .exact(varying.lower)
        let bandWidth = OutwardScalarInterval.exact(integrated.upper) - .exact(integrated.lower)
        let midpoint = (OutwardScalarInterval.exact(integrated.lower) + .exact(integrated.upper)) * .exact(0.5)
        let t = SurfaceIntervalJet.parameterU(fraction)
        let native = constant(.exact(varying.lower)) + constant(width) * t
        let middle = constant(midpoint)
        let u = direction == .v ? native : middle
        let v = direction == .v ? middle : native
        let box = SurfaceParameterBox(u: try clipped(u.value, to: surface.uDomain, tolerance: tolerance),
                                      v: try clipped(v.value, to: surface.vDomain, tolerance: tolerance))
        let jet = try surfaceJet(over: box, tolerance: tolerance)
        let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
        guard let density = cross.dot(cross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance, "Translation area density is unresolved on this interval.")
        }
        let measure = constant(width * bandWidth)
        let fields = [density, (jet.x - .constant(reference.x)) * density,
                      (jet.y - .constant(reference.y)) * density,
                      (jet.z - .constant(reference.z)) * density]
        return fields.map { field in
            let f = compose(field, u: u, v: v) * measure
            return SurfaceAreaIntegrandBounds(value: f.value, derivativeU: f.derivativeU, derivativeV: .exact(0),
                secondUU: derivativeOrder >= 3 ? f.secondDerivativeUU : nil,
                secondUV: derivativeOrder >= 3 ? .exact(0) : nil,
                secondVV: derivativeOrder >= 3 ? .exact(0) : nil)
        }
    }

    private func surfaceJet(over box: SurfaceParameterBox,
                            tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        switch storage {
        case .translatedRollingBall(let prepared): return try prepared.intervalJet(over:box,tolerance:tolerance)
        case .direct(let prepared): return try prepared.intervalJet(over: box, tolerance: tolerance)
        case .offset(let offset, let source):
            return try offset.intervalJet(fromValidatedSourceJet: source.surfaceJet(over: box, tolerance: tolerance),
                                          tolerance: tolerance)
        case .spline(let spline, let patches):
            var result: SurfaceIntervalVectorJet?
            let us = try spline.enclosureIntervals(box.u, direction: .u, tolerance: tolerance)
            let vs = try spline.enclosureIntervals(box.v, direction: .v, tolerance: tolerance)
            // Conservative base-chart normalization covers every requested cycle,
            // including negative representatives and both sides of a seam.
            for u in us {
                for v in vs {
                    for patch in patches {
                        guard !Task.isCancelled else {
                            throw Self.failure(.cancelled, tolerance, "Surface area enclosure was cancelled.")
                        }
                        let lowU = max(u.lower, patch.uLower), highU = min(u.upper, patch.uUpper)
                        let lowV = max(v.lower, patch.vLower), highV = min(v.upper, patch.vUpper)
                        guard lowU <= highU, lowV <= highV else { continue }
                        let jet = try RationalBezierSurfaceJetEncloser().enclosure(of: patch,
                            u: ScalarInterval(lower: lowU, upper: highU),
                            v: ScalarInterval(lower: lowV, upper: highV), tolerance: tolerance)
                        result = result.map { $0.union(jet) } ?? jet
                    }
                }
            }
            guard let result else {
                throw Self.failure(.classificationFailure, tolerance, "Area parameter box misses all exact spline spans.")
            }
            return result
        }
    }

    private func clipped(_ interval: OutwardScalarInterval, to domain: ParameterDomain,
                         tolerance: ModelingTolerance) throws -> ScalarInterval {
        var lower = interval.lower, upper = interval.upper
        if case let .closed(a, b) = domain {
            let slack = Double.ulpOfOne * max(1, abs(a), abs(b)) * 64
            guard lower >= a - slack, upper <= b + slack else {
                throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
            }
            lower = max(lower, a); upper = min(upper, b)
        }
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw Self.failure(.classificationFailure, tolerance, "Area integrand bounds are nonfinite or disjoint.")
        }
        // A degenerate chart coordinate is enlarged solely to obtain a containing surface box.
        if lower == upper {
            lower = lower.nextDown; upper = upper.nextUp
            if case let .closed(a, b) = domain { lower = max(lower, a); upper = min(upper, b) }
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func compose(_ f: SurfaceIntervalJet, u: SurfaceIntervalJet,
                         v: SurfaceIntervalJet) -> SurfaceIntervalJet {
        let two = OutwardScalarInterval.exact(2)
        func second(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval,
                    _ c: OutwardScalarInterval, _ d: OutwardScalarInterval) -> OutwardScalarInterval {
            f.secondDerivativeUU * a * a + two * f.secondDerivativeUV * a * b
                + f.secondDerivativeVV * b * b + f.derivativeU * c + f.derivativeV * d
        }
        let zero = OutwardScalarInterval.exact(0)
        return SurfaceIntervalJet(value: f.value,
            derivativeU: f.derivativeU * u.derivativeU + f.derivativeV * v.derivativeU,
            derivativeV: f.derivativeU * u.derivativeV + f.derivativeV * v.derivativeV,
            secondDerivativeUU: second(u.derivativeU, v.derivativeU, u.secondDerivativeUU, v.secondDerivativeUU),
            secondDerivativeUV: f.secondDerivativeUU * u.derivativeU * u.derivativeV
                + f.secondDerivativeUV * (u.derivativeU * v.derivativeV + u.derivativeV * v.derivativeU)
                + f.secondDerivativeVV * v.derivativeU * v.derivativeV
                + f.derivativeU * u.secondDerivativeUV + f.derivativeV * v.secondDerivativeUV,
            secondDerivativeVV: second(u.derivativeV, v.derivativeV, u.secondDerivativeVV, v.secondDerivativeVV),
            thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }

    private static func admitDimensions(_ surface: Surface3D, limit: Int,
                                        tolerance: ModelingTolerance, depth: Int = 0) throws {
        guard limit > 0, limit <= 1_048_576, depth <= 16 else {
            throw failure(.resourceLimitExceeded, tolerance, "Area geometry admission exceeds finite dimensions or nesting.")
        }
        func chart(_ value: SurfaceParameterCurve, chartDepth: Int = 0) throws {
            guard chartDepth <= 16 else {
                throw failure(.resourceLimitExceeded, tolerance, "Area rail chart nesting admission exceeded.")
            }
            switch value {
            case .bSpline(let spline):
                guard spline.controlPoints.count <= limit, spline.weights.count <= limit,
                      spline.knots.count <= 2 * limit + 1 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area rail chart dimension admission exceeded.")
                }
                guard spline.degree >= 1, spline.degree < spline.controlPoints.count,
                      spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                      spline.weights.count == spline.controlPoints.count else {
                    throw failure(.invalidInput, tolerance, "Area rail chart spline dimensions are inconsistent.")
                }
            case .periodicTranslation(let base, _, _): try chart(base, chartDepth: chartDepth + 1)
            case .offsetSurfaceImage(let image): try chart(image.source, chartDepth: chartDepth + 1)
            case .affine, .constantU, .constantV, .harmonic: break
            default:
                throw failure(.unsupportedCapability, tolerance, "Area rail chart has no certified derivative admission.")
            }
        }
        func curve(_ value: Curve3D) throws {
            switch value {
            case .bSpline(let spline):
                guard spline.controlPoints.count <= limit, spline.weights.count <= limit,
                      spline.knots.count <= 2 * limit + 1 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area curve dimension admission exceeded.")
                }
                guard spline.degree >= 1, spline.degree < spline.controlPoints.count,
                      spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                      spline.weights.count == spline.controlPoints.count else {
                    throw failure(.invalidInput, tolerance, "Area curve spline dimensions are inconsistent.")
                }
            case .surfaceLift(let lift):
                try chart(lift.parameterCurve)
                try admitDimensions(lift.surface, limit: limit, tolerance: tolerance, depth: depth + 1)
            default: break
            }
        }
        switch surface {
        case .bSpline(let spline):
            let uCount = spline.controlPoints.first?.count ?? 0
            let vCount = spline.controlPoints.count
            guard vCount <= limit, spline.controlPoints.allSatisfy({ $0.count <= limit }),
                  spline.weights.count <= limit, spline.weights.allSatisfy({ $0.count <= limit }),
                  spline.uKnots.count <= 2 * limit + 1, spline.vKnots.count <= 2 * limit + 1 else {
                throw failure(.resourceLimitExceeded, tolerance, "Area surface dimension admission exceeded.")
            }
            guard uCount > 0, vCount > 0, spline.uDegree >= 1, spline.uDegree < uCount,
                  spline.vDegree >= 1, spline.vDegree < vCount,
                  spline.uKnots.count == uCount + spline.uDegree + 1,
                  spline.vKnots.count == vCount + spline.vDegree + 1,
                  spline.weights.count == vCount,
                  spline.controlPoints.allSatisfy({ $0.count == uCount }),
                  spline.weights.allSatisfy({ $0.count == uCount }) else {
                throw failure(.invalidInput, tolerance, "Area surface spline dimensions are inconsistent.")
            }
        case .procedural(.offset(let offset)):
            try admitDimensions(offset.source, limit: limit, tolerance: tolerance, depth: depth + 1)
        case .procedural(.ruled(let ruled)):
            try curve(ruled.startBoundary); try curve(ruled.endBoundary)
        case .procedural(.rollingBall(let blend)):
            try curve(blend.centerSpine); try curve(blend.firstContact); try curve(blend.secondContact)
        default: break
        }
    }

    private static func curveOrder(_ curve: Curve3D, tolerance: ModelingTolerance) throws -> Int {
        switch curve {
        case .bSpline(let spline):
            let internalKnots = Array(Set(spline.knots)).sorted().dropFirst().dropLast()
            return min(3, (internalKnots.map { knot in
                spline.degree - spline.knots.filter { $0 == knot }.count
            }.min() ?? 3) + 1)
        case .surfaceLift(let lift):
            guard try SurfaceParameterIntervalJet.enclose(lift.parameterCurve,
                over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) != nil else {
                throw failure(.unsupportedCapability, tolerance,
                    "Area rail derivatives require certified numeric parameter charts.")
            }
            return try PreparedSurfaceAreaIntegrand(surface: lift.surface, tolerance: tolerance).derivativeOrder
        case .line, .circle, .analytic: return 3
        default:
            throw failure(.unsupportedCapability, tolerance,
                "Area procedural support has no certified derivative-order admission for its source curve.")
        }
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
