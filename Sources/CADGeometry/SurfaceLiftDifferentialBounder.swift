import CADCore
import Foundation

struct SurfaceLiftDifferentialBounder {
    struct ParameterBounds {
        let u: ScalarInterval
        let v: ScalarInterval
    }

    private struct ParameterDerivativeBounds {
        let firstU: Double
        let firstV: Double
        let secondU: Double
        let secondV: Double
    }

    private struct SurfaceDerivativeBounds {
        let firstU: Double
        let firstV: Double
        let secondUU: Double
        let secondUV: Double
        let secondVV: Double
    }

    func secondDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard interval.width > tolerance.relative else {
            throw GeometryError.invalidDistance(interval.width)
        }
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: interval.lower,
            toNormalizedFraction: interval.upper,
            tolerance: tolerance
        )
        if case let .certifiedAnalyticPair(curve) = localCurve,
           curve.hasCylinderSpatialBounds {
            let localBounds = try curve
                .cylinderSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let intervalScaleSquared = (
                interval.width.nextDown * interval.width.nextDown
            ).nextDown
            guard intervalScaleSquared > 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair interval scaling collapsed."
                )
            }
            let globalBound = localBounds.second
                / intervalScaleSquared
            guard globalBound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair spatial differentiation exceeded finite arithmetic."
                )
            }
            return globalBound.nextUp
        }
        guard let parameterDerivatives = try parameterDerivativeBounds(
            localCurve,
            tolerance: tolerance
        ), let parameterBounds = try parameterBounds(
            localCurve,
            tolerance: tolerance
        ) else {
            return nil
        }
        let surfaceDerivatives = try surfaceDerivativeBounds(
            surface: lift.surface,
            parameters: parameterBounds,
            tolerance: tolerance
        )
        let localBound = upperSum(
            upperSum(
                upperProduct(
                    surfaceDerivatives.secondUU,
                    upperProduct(
                        parameterDerivatives.firstU,
                        parameterDerivatives.firstU
                    )
                ),
                upperProduct(
                    2.0 * surfaceDerivatives.secondUV,
                    upperProduct(
                        parameterDerivatives.firstU,
                        parameterDerivatives.firstV
                    )
                )
            ),
            upperSum(
                upperProduct(
                    surfaceDerivatives.secondVV,
                    upperProduct(
                        parameterDerivatives.firstV,
                        parameterDerivatives.firstV
                    )
                ),
                upperSum(
                    upperProduct(
                        surfaceDerivatives.firstU,
                        parameterDerivatives.secondU
                    ),
                    upperProduct(
                        surfaceDerivatives.firstV,
                        parameterDerivatives.secondV
                    )
                )
            )
        )
        let globalBound = localBound / (interval.width * interval.width)
        guard globalBound.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Surface-lift second-derivative certification exceeded finite arithmetic."
            )
        }
        return globalBound.nextUp
    }

    func breakParameters(
        lift: SurfaceLiftCurve3D,
        within interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let normalizedBreaks: [Double]
        switch lift.parameterCurve {
        case let .polyline(points):
            var lengths: [Double] = []
            var totalLength = 0.0
            for index in 1..<points.count {
                let length = hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                )
                lengths.append(length)
                totalLength = upperSum(totalLength, length)
            }
            guard totalLength > tolerance.relative else {
                throw GeometryError.invalidDistance(totalLength)
            }
            var accumulated = 0.0
            normalizedBreaks = lengths.dropLast().map { length in
                accumulated += length
                return accumulated / totalLength
            }
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A surface-lift B-spline pcurve requires a bounded domain."
                )
            }
            let width = upper - lower
            var result: [Double] = []
            for knot in curve.knots where knot > lower && knot < upper {
                let value = (knot - lower) / width
                if let last = result.last,
                   abs(value - last) <= tolerance.relative {
                    continue
                }
                result.append(value)
            }
            normalizedBreaks = result
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            normalizedBreaks = []
        }
        return normalizedBreaks.filter {
            $0 > interval.lower + tolerance.relative
                && $0 < interval.upper - tolerance.relative
        }
    }

    func parameterBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> ParameterBounds? {
        switch curve {
        case .affine, .constantU, .constantV:
            let endpoints = try [0.0, 1.0].map {
                try curve.parameter(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                )
            }
            return try bounds(points: endpoints)
        case let .harmonic(center, cosine, sine, _, _):
            let uAmplitude = hypot(cosine.x, sine.x)
            let vAmplitude = hypot(cosine.y, sine.y)
            return ParameterBounds(
                u: try ScalarInterval(
                    lower: (center.x - uAmplitude).nextDown,
                    upper: (center.x + uAmplitude).nextUp
                ),
                v: try ScalarInterval(
                    lower: (center.y - vAmplitude).nextDown,
                    upper: (center.y + vAmplitude).nextUp
                )
            )
        case let .polyline(points):
            return try bounds(points: points)
        case let .bSpline(curve):
            return try bounds(points: curve.controlPoints.map {
                SurfaceParameter(u: $0.x, v: $0.y)
            })
        // FIXME(INCOMPLETE_IMPLEMENTATION): Certified analytic-pair definitions other
        // than cylinder-cylinder curves do not yet expose interval parameter
        // enclosures. Direct surface-lift curve intersection reaches this branch,
        // and it must not return a successful structural bound until every registered
        // definition supplies seam-aware interval parameter bounds.
        case .certifiedAnalyticPair:
            return nil
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .projectedAnalytic:
            return nil
        }
    }

    func bSplineSupportBounds(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D? {
        guard case let .bSpline(surface) = lift.surface else { return nil }
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: interval.lower,
            toNormalizedFraction: interval.upper,
            tolerance: tolerance
        )
        guard let parameters = try parameterBounds(
            localCurve,
            tolerance: tolerance
        ) else {
            return nil
        }
        let uRange = try nondegenerateRange(
            parameters.u,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let vRange = try nondegenerateRange(
            parameters.v,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        let trimmed = try surface.trimmed(
            uFrom: uRange.lower,
            uTo: uRange.upper,
            vFrom: vRange.lower,
            vTo: vRange.upper,
            tolerance: tolerance
        )
        return try BoundingBox3D(
            points: trimmed.controlPoints.flatMap { $0 }
        ).expanded(by: tolerance.distance)
    }

    private func parameterDerivativeBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> ParameterDerivativeBounds? {
        switch curve {
        case let .affine(_, direction, start, end):
            let scale = abs(end - start)
            return ParameterDerivativeBounds(
                firstU: upperProduct(abs(direction.x), scale),
                firstV: upperProduct(abs(direction.y), scale),
                secondU: 0.0,
                secondV: 0.0
            )
        case let .constantU(_, vStart, vEnd):
            return ParameterDerivativeBounds(
                firstU: 0.0,
                firstV: abs(vEnd - vStart).nextUp,
                secondU: 0.0,
                secondV: 0.0
            )
        case let .constantV(_, uStart, uEnd):
            return ParameterDerivativeBounds(
                firstU: abs(uEnd - uStart).nextUp,
                firstV: 0.0,
                secondU: 0.0,
                secondV: 0.0
            )
        case let .harmonic(_, cosine, sine, start, end):
            let scale = abs(end - start)
            let scaleSquared = upperProduct(scale, scale)
            let uAmplitude = hypot(cosine.x, sine.x).nextUp
            let vAmplitude = hypot(cosine.y, sine.y).nextUp
            return ParameterDerivativeBounds(
                firstU: upperProduct(scale, uAmplitude),
                firstV: upperProduct(scale, vAmplitude),
                secondU: upperProduct(scaleSquared, uAmplitude),
                secondV: upperProduct(scaleSquared, vAmplitude)
            )
        case let .polyline(points):
            guard points.count == 2 else { return nil }
            return ParameterDerivativeBounds(
                firstU: abs(points[1].u - points[0].u).nextUp,
                firstV: abs(points[1].v - points[0].v).nextUp,
                secondU: 0.0,
                secondV: 0.0
            )
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(tolerance: tolerance)
            guard case let .closed(lower, upper) = curve.domain,
                  patches.isEmpty == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A surface-lift B-spline pcurve requires a bounded non-empty domain."
                )
            }
            let domainWidth = upper - lower
            let domainWidthSquared = upperProduct(domainWidth, domainWidth)
            var result = ParameterDerivativeBounds(
                firstU: 0.0,
                firstV: 0.0,
                secondU: 0.0,
                secondV: 0.0
            )
            for patch in patches {
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map(\.x),
                        patch.controlPoints.map(\.y),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                result = ParameterDerivativeBounds(
                    firstU: max(result.firstU, upperProduct(bound.first[0], domainWidth)),
                    firstV: max(result.firstV, upperProduct(bound.first[1], domainWidth)),
                    secondU: max(
                        result.secondU,
                        upperProduct(bound.second[0], domainWidthSquared)
                    ),
                    secondV: max(
                        result.secondV,
                        upperProduct(bound.second[1], domainWidthSquared)
                    )
                )
            }
            return result
        // FIXME(INCOMPLETE_IMPLEMENTATION): Certified analytic-pair definitions other
        // than cylinder-cylinder curves do not yet expose interval first- and
        // second-derivative bounds. The production surface-lift root solver reaches
        // this branch, and it must not report success until every registered
        // definition supplies certified interval differential bounds.
        case .certifiedAnalyticPair:
            return nil
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .projectedAnalytic:
            return nil
        }
    }

    private func surfaceDerivativeBounds(
        surface: Surface3D,
        parameters: ParameterBounds,
        tolerance: ModelingTolerance
    ) throws -> SurfaceDerivativeBounds {
        switch CanonicalAnalyticSurface(surface) {
        case .plane:
            return SurfaceDerivativeBounds(
                firstU: 1.0,
                firstV: 1.0,
                secondUU: 0.0,
                secondUV: 0.0,
                secondVV: 0.0
            )
        case let .cylinder(cylinder):
            return SurfaceDerivativeBounds(
                firstU: cylinder.radius.nextUp,
                firstV: 1.0,
                secondUU: cylinder.radius.nextUp,
                secondUV: 0.0,
                secondVV: 0.0
            )
        case let .cone(cone):
            let radial = upperProduct(
                max(abs(parameters.v.lower), abs(parameters.v.upper)),
                abs(sin(cone.halfAngle))
            )
            return SurfaceDerivativeBounds(
                firstU: radial,
                firstV: 1.0,
                secondUU: radial,
                secondUV: abs(sin(cone.halfAngle)).nextUp,
                secondVV: 0.0
            )
        case let .sphere(sphere):
            let radius = sphere.radius.nextUp
            return SurfaceDerivativeBounds(
                firstU: radius,
                firstV: radius,
                secondUU: radius,
                secondUV: radius,
                secondVV: radius
            )
        case let .torus(torus):
            let radial = (torus.majorRadius + torus.minorRadius).nextUp
            let minor = torus.minorRadius.nextUp
            return SurfaceDerivativeBounds(
                firstU: radial,
                firstV: minor,
                secondUU: radial,
                secondUV: minor,
                secondVV: minor
            )
        case .unsupported:
            guard case let .bSpline(surface) = surface else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Surface-lift derivative bounds received an unknown support surface."
                )
            }
            let uRange = try nondegenerateRange(
                parameters.u,
                domain: surface.uDomain,
                tolerance: tolerance
            )
            let vRange = try nondegenerateRange(
                parameters.v,
                domain: surface.vDomain,
                tolerance: tolerance
            )
            let trimmed = try surface.trimmed(
                uFrom: uRange.lower,
                uTo: uRange.upper,
                vFrom: vRange.lower,
                vTo: vRange.upper,
                tolerance: tolerance
            )
            let bound = try CubicSurfaceResidualCertifier.SurfaceDerivativeBounds(
                surface: trimmed,
                tolerance: tolerance
            )
            return SurfaceDerivativeBounds(
                firstU: bound.tangentU,
                firstV: bound.tangentV,
                secondUU: bound.secondUU,
                secondUV: bound.secondUV,
                secondVV: bound.secondVV
            )
        }
    }

    private func bounds(points: [SurfaceParameter]) throws -> ParameterBounds {
        guard points.isEmpty == false,
              let minimumU = points.map(\.u).min(),
              let maximumU = points.map(\.u).max(),
              let minimumV = points.map(\.v).min(),
              let maximumV = points.map(\.v).max() else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Surface-lift parameter bounds require at least one finite point."
            )
        }
        return ParameterBounds(
            u: try ScalarInterval(
                lower: minimumU.nextDown,
                upper: maximumU.nextUp
            ),
            v: try ScalarInterval(
                lower: minimumV.nextDown,
                upper: maximumV.nextUp
            )
        )
    }

    private func nondegenerateRange(
        _ interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .closed(domainLower, domainUpper) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A B-spline support surface requires finite parameter domains."
            )
        }
        let lower = max(interval.lower, domainLower)
        let upper = min(interval.upper, domainUpper)
        guard lower <= upper else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A surface-lift parameter enclosure leaves its support domain."
            )
        }
        let minimumWidth = max(
            tolerance.relative * (domainUpper - domainLower),
            Double.ulpOfOne * max(max(abs(lower), abs(upper)), 1.0) * 256.0
        )
        if upper - lower > minimumWidth {
            return try ScalarInterval(lower: lower, upper: upper)
        }
        let midpoint = min(max(interval.midpoint, domainLower), domainUpper)
        let expandedLower = max(domainLower, midpoint - minimumWidth)
        let expandedUpper = min(domainUpper, midpoint + minimumWidth)
        guard expandedUpper > expandedLower else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A surface-lift parameter enclosure collapsed at a support boundary."
            )
        }
        return try ScalarInterval(
            lower: expandedLower,
            upper: expandedUpper
        )
    }

    private func upperSum(_ first: Double, _ second: Double) -> Double {
        (first + second).nextUp
    }

    private func upperProduct(_ first: Double, _ second: Double) -> Double {
        (first * second).nextUp
    }

    private func resourceFailure(
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
