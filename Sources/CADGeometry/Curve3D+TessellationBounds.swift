import CADCore
import Foundation

/// Certified geometric bounds used by derived representations. The values
/// enclose the complete curve interval, rather than only sampled points.
package struct CurveTessellationIntervalBounds: Sendable {
    package let chordDeviationUpperBound: Double
    package let arcLengthUpperBound: Double
    package let tangentDeviationUpperBound: Double
    package let speedLowerBound: Double
    package let speedUpperBound: Double
    package let secondDerivativeMagnitudeUpperBound: Double
}

package extension Curve3D {
    /// Indicates that this curve retains a derivative certificate whose
    /// restriction to a smaller interval is substantially tighter and cheaper
    /// than rebuilding the proof from its source geometry.
    var supportsEfficientLocalizedTessellationDerivativeBounds: Bool {
        switch self {
        case let .surfaceLift(lift):
            return lift.exactDerivativeCertificate != nil
        case let .rigidImage(image):
            return image.source.supportsEfficientLocalizedTessellationDerivativeBounds
        case let .affineImage(image):
            return image.source.supportsEfficientLocalizedTessellationDerivativeBounds
        case .line, .circle, .analytic, .bSpline, .implicit,
             .certifiedIntersection:
            return false
        }
    }

    func tessellationIntervalBounds(
        _ interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveTessellationIntervalBounds {
        try ValidatedCurve3D(self, tolerance: tolerance)
            .tessellationIntervalEvaluation(interval)
            .bounds
    }

    /// Reuses a second-derivative certificate that was established over a
    /// containing parameter interval. A valid upper bound remains valid for
    /// every child interval, so adaptive consumers do not need to rebuild an
    /// identical rational or procedural proof after every subdivision.
    func tessellationIntervalBounds(
        _ interval: ScalarInterval,
        usingCertifiedSecondDerivativeMagnitudeUpperBound secondDerivativeBound: Double,
        tolerance: ModelingTolerance
    ) throws -> CurveTessellationIntervalBounds {
        try ValidatedCurve3D(self, tolerance: tolerance)
            .tessellationIntervalEvaluation(
                interval,
                usingCertifiedSecondDerivativeMagnitudeUpperBound: secondDerivativeBound
            )
            .bounds
    }
}

package extension ValidatedCurve3D {
    func tessellationIntervalEvaluation(
        _ interval: ScalarInterval,
        usingCertifiedSecondDerivativeMagnitudeUpperBound inheritedBound: Double? = nil
    ) throws -> CurveTessellationIntervalEvaluation {
        guard interval.width > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve tessellation certification requires a positive parameter interval."
            )
        }
        if let inheritedBound {
            guard inheritedBound.isFinite, inheritedBound >= 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Reusable curve tessellation certification requires a finite nonnegative derivative bound."
                )
            }
        }
        let midpointPoint: Point3D
        let midpointDerivative: Vector3D
        if case let .bSpline(spline) = curve {
            let derivatives = try spline.parameterDerivativesAssumingValid(
                at: interval.midpoint,
                tolerance: tolerance
            )
            midpointPoint = derivatives.position
            midpointDerivative = derivatives.firstDerivative
        } else {
            let geometry = try curve.differentialGeometryAssumingValid(
                at: interval.midpoint,
                tolerance: tolerance
            )
            midpointPoint = geometry.position
            midpointDerivative = geometry.firstDerivative
        }
        let bounds: CurveTessellationIntervalBounds
        if case .implicit = curve {
            bounds = try curve.implicitTessellationIntervalBounds(
                interval,
                midpointDerivative: midpointDerivative,
                tolerance: tolerance
            )
        } else {
            let secondDerivativeBound: Double
            if let inheritedBound {
                secondDerivativeBound = inheritedBound
            } else {
                secondDerivativeBound = try curve.secondDerivativeMagnitudeUpperBound(
                    interval,
                    tolerance: tolerance
                )
            }
            bounds = try Curve3D.tessellationIntervalBounds(
                parameterWidth: interval.width,
                midpointDerivative: midpointDerivative,
                secondDerivativeBound: secondDerivativeBound,
                tangentDeviationOverride: curve
                    .stationaryEndpointTangentDeviationUpperBound(interval),
                tolerance: tolerance
            )
        }
        return CurveTessellationIntervalEvaluation(
            bounds: bounds,
            midpointPoint: midpointPoint
        )
    }
}

fileprivate extension Curve3D {
    func stationaryEndpointTangentDeviationUpperBound(
        _ interval: ScalarInterval
    ) -> Double? {
        guard case let .bSpline(curve) = self,
              curve.degree == 3,
              curve.controlPointCount == 4,
              curve.isRational == false,
              case let .closed(domainLower, domainUpper) = curve.domain,
              curve.knots == [
                  domainLower, domainLower, domainLower, domainLower,
                  domainUpper, domainUpper, domainUpper, domainUpper,
              ] else {
            return nil
        }
        let domainWidth = domainUpper - domainLower
        guard domainWidth.isFinite, domainWidth > 0.0 else {
            return nil
        }
        let normalizedLower = (interval.lower - domainLower) / domainWidth
        let normalizedUpper = (interval.upper - domainLower) / domainWidth
        let normalizedMiddle = (normalizedLower + normalizedUpper) * 0.5
        let normalizedHalfWidth = (normalizedUpper - normalizedLower) * 0.5
        let directionCenter: Vector3D
        let directionRadius: Double
        if interval.lower == domainLower,
           curve.controlPoints[0] == curve.controlPoints[1] {
            let first = curve.controlPoints[2] - curve.controlPoints[1]
            let second = curve.controlPoints[3] - curve.controlPoints[2]
            directionCenter = first * (2.0 * (1.0 - normalizedMiddle))
                + second * normalizedMiddle
            directionRadius = (second - first * 2.0).length
                * normalizedHalfWidth
        } else if interval.upper == domainUpper,
                  curve.controlPoints[2] == curve.controlPoints[3] {
            let first = curve.controlPoints[1] - curve.controlPoints[0]
            let second = curve.controlPoints[2] - curve.controlPoints[1]
            directionCenter = first * (1.0 - normalizedMiddle)
                + second * (2.0 * normalizedMiddle)
            directionRadius = (second * 2.0 - first).length
                * normalizedHalfWidth
        } else {
            return nil
        }
        let centerLength = directionCenter.length
        guard centerLength.isFinite,
              directionRadius.isFinite,
              centerLength > directionRadius else {
            return .infinity
        }
        return (2.0 * asin(min(1.0, directionRadius / centerLength))).nextUp
    }

    func implicitTessellationIntervalBounds(
        _ interval: ScalarInterval,
        midpointDerivative: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> CurveTessellationIntervalBounds {
        guard let derivativeRange = try DefaultCurveSpatialDerivativeRangeResolver()
            .derivativeRange(
                curve: self,
                interval: interval,
                tolerance: tolerance
            ) else {
            throw certificationFailure(
                tolerance: tolerance,
                message: "The implicit curve has no certified spatial derivative enclosure."
            )
        }
        let maximumDerivative = Vector3D(
            x: max(abs(derivativeRange.x.lower), abs(derivativeRange.x.upper)),
            y: max(abs(derivativeRange.y.lower), abs(derivativeRange.y.upper)),
            z: max(abs(derivativeRange.z.lower), abs(derivativeRange.z.upper))
        ).length.nextUp
        let minimumDerivative = Vector3D(
            x: Self.minimumAbsoluteValue(in: derivativeRange.x),
            y: Self.minimumAbsoluteValue(in: derivativeRange.y),
            z: Self.minimumAbsoluteValue(in: derivativeRange.z)
        ).length.nextDown
        let derivativeWidth = Vector3D(
            x: derivativeRange.x.width,
            y: derivativeRange.y.width,
            z: derivativeRange.z.width
        ).length.nextUp
        let midpointUncertainty = Vector3D(
            x: max(
                abs(derivativeRange.x.lower - midpointDerivative.x),
                abs(derivativeRange.x.upper - midpointDerivative.x)
            ),
            y: max(
                abs(derivativeRange.y.lower - midpointDerivative.y),
                abs(derivativeRange.y.upper - midpointDerivative.y)
            ),
            z: max(
                abs(derivativeRange.z.lower - midpointDerivative.z),
                abs(derivativeRange.z.upper - midpointDerivative.z)
            )
        ).length.nextUp
        let chordDeviation = (
            interval.width * derivativeWidth * 0.5
        ).nextUp
        let arcLength = (
            interval.width * maximumDerivative
        ).nextUp
        let tangentDeviation: Double
        let midpointSpeed = midpointDerivative.length.nextDown
        if midpointSpeed > midpointUncertainty {
            tangentDeviation = (
                2.0 * asin(min(1.0, midpointUncertainty / midpointSpeed))
            ).nextUp
        } else {
            tangentDeviation = .infinity
        }
        return try Self.validatedTessellationBounds(
            chordDeviation: chordDeviation,
            arcLength: arcLength,
            tangentDeviation: tangentDeviation,
            speedLowerBound: max(0.0, minimumDerivative),
            speedUpperBound: maximumDerivative,
            secondDerivativeMagnitudeUpperBound: .infinity,
            tolerance: tolerance
        )
    }

    func secondDerivativeMagnitudeUpperBound(
        _ interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double {
        switch self {
        case .line, .analytic(.line):
            return 0.0
        case let .circle(circle):
            return circle.radius.nextUp
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            return radius.nextUp
        case let .analytic(.ellipse(_, _, _, majorRadius, minorRadius)):
            return max(majorRadius, minorRadius).nextUp
        case let .analytic(.hyperbola(curve)):
            let parameter = max(abs(interval.lower), abs(interval.upper))
            let value = hypot(
                curve.transverseRadius * cosh(parameter),
                curve.conjugateRadius * sinh(parameter)
            )
            guard value.isFinite else {
                throw arithmeticFailure(
                    tolerance: tolerance,
                    message: "Hyperbola tessellation certification exceeded finite arithmetic."
                )
            }
            return value.nextUp
        case let .analytic(.parabola(curve)):
            return (1.0 / (2.0 * curve.focalLength)).nextUp
        case let .analytic(.planeTorus(curve)):
            return try curve.spatialDifferentialMagnitudeBounds(
                fromParameter: interval.lower,
                toParameter: interval.upper,
                tolerance: tolerance
            ).second
        case let .bSpline(curve):
            if let exactBound = cubicPolynomialSecondDerivativeMagnitudeUpperBound(
                curve,
                interval: interval
            ) {
                return exactBound
            }
            let patches = try BSplineCurveBezierDecomposer().curvePatches(
                curve: curve,
                intersecting: interval,
                tolerance: tolerance
            )
            guard patches.isEmpty == false else {
                throw certificationFailure(
                    tolerance: tolerance,
                    message: "B-spline tessellation interval has no rational Bezier span."
                )
            }
            var maximum = 0.0
            for sourcePatch in patches {
                let lower = max(interval.lower, sourcePatch.lower)
                let upper = min(interval.upper, sourcePatch.upper)
                guard upper > lower else { continue }
                let patch = lower == sourcePatch.lower && upper == sourcePatch.upper
                    ? sourcePatch
                    : try sourcePatch.trimmed(
                        from: lower,
                        to: upper,
                        tolerance: tolerance
                    )
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map(\.x),
                        patch.controlPoints.map(\.y),
                        patch.controlPoints.map(\.z),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                maximum = max(
                    maximum,
                    hypot(
                        hypot(bound.second[0], bound.second[1]),
                        bound.second[2]
                    ).nextUp
                )
            }
            return maximum
        case let .surfaceLift(lift):
            guard let value = try SurfaceLiftDifferentialBounder()
                .secondDerivativeMagnitude(
                    lift: lift,
                    interval: interval,
                    tolerance: tolerance
                ) else {
                throw certificationFailure(
                    tolerance: tolerance,
                    message: "Surface-lift tessellation has no certified second-derivative bound."
                )
            }
            return value
        case let .certifiedIntersection(curve):
            return try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: interval.lower,
                toNormalizedFraction: interval.upper,
                tolerance: tolerance
            ).second
        case let .rigidImage(image):
            return try image.source.secondDerivativeMagnitudeUpperBound(
                interval,
                tolerance: tolerance
            )
        case let .affineImage(image):
            let sourceBound = try image.source.secondDerivativeMagnitudeUpperBound(
                interval,
                tolerance: tolerance
            )
            let transformedBound = (
                sourceBound * image.transform.linearMagnitudeUpperBound
            ).nextUp
            guard transformedBound.isFinite else {
                throw arithmeticFailure(
                    tolerance: tolerance,
                    message: "Affine-image tessellation certification exceeded finite arithmetic."
                )
            }
            return transformedBound
        case .implicit:
            throw certificationFailure(
                tolerance: tolerance,
                message: "Implicit curves use a spatial derivative-range certificate."
            )
        }
    }

    func cubicPolynomialSecondDerivativeMagnitudeUpperBound(
        _ curve: BSplineCurve3D,
        interval: ScalarInterval
    ) -> Double? {
        guard curve.degree == 3,
              curve.controlPointCount == 4,
              curve.isRational == false,
              case let .closed(lower, upper) = curve.domain,
              curve.knots == [
                  lower, lower, lower, lower,
                  upper, upper, upper, upper,
              ] else {
            return nil
        }
        let parameterWidth = upper - lower
        guard parameterWidth.isFinite, parameterWidth > 0.0 else {
            return nil
        }
        let firstDifference = (curve.controlPoints[2] - curve.controlPoints[1])
            - (curve.controlPoints[1] - curve.controlPoints[0])
        let secondDifference = (curve.controlPoints[3] - curve.controlPoints[2])
            - (curve.controlPoints[2] - curve.controlPoints[1])
        let normalizedLower = min(max(
            (interval.lower - lower) / parameterWidth,
            0.0
        ), 1.0)
        let normalizedUpper = min(max(
            (interval.upper - lower) / parameterWidth,
            0.0
        ), 1.0)
        let scale = 6.0 / (parameterWidth * parameterWidth)
        let lowerDerivative = (
            firstDifference * (1.0 - normalizedLower)
                + secondDifference * normalizedLower
        ) * scale
        let upperDerivative = (
            firstDifference * (1.0 - normalizedUpper)
                + secondDifference * normalizedUpper
        ) * scale
        return max(lowerDerivative.length, upperDerivative.length).nextUp
    }

    static func tessellationIntervalBounds(
        parameterWidth: Double,
        midpointDerivative: Vector3D,
        secondDerivativeBound: Double,
        tangentDeviationOverride: Double? = nil,
        tolerance: ModelingTolerance
    ) throws -> CurveTessellationIntervalBounds {
        let halfWidth = parameterWidth * 0.5
        let derivativeRadius = (secondDerivativeBound * halfWidth).nextUp
        let speedUpper = (midpointDerivative.length + derivativeRadius).nextUp
        let speedLower = (midpointDerivative.length - derivativeRadius).nextDown
        let chordDeviation = (
            secondDerivativeBound * parameterWidth * parameterWidth * 0.125
        ).nextUp
        let arcLength = (speedUpper * parameterWidth).nextUp
        let tangentDeviation = tangentDeviationOverride ?? (
            speedLower > 0.0
                ? (secondDerivativeBound * parameterWidth / speedLower).nextUp
                : .infinity
        )
        return try validatedTessellationBounds(
            chordDeviation: chordDeviation,
            arcLength: arcLength,
            tangentDeviation: tangentDeviation,
            speedLowerBound: max(0.0, speedLower),
            speedUpperBound: speedUpper,
            secondDerivativeMagnitudeUpperBound: secondDerivativeBound,
            tolerance: tolerance
        )
    }

    static func validatedTessellationBounds(
        chordDeviation: Double,
        arcLength: Double,
        tangentDeviation: Double,
        speedLowerBound: Double,
        speedUpperBound: Double,
        secondDerivativeMagnitudeUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> CurveTessellationIntervalBounds {
        guard chordDeviation.isFinite,
              chordDeviation >= 0.0,
              arcLength.isFinite,
              arcLength >= 0.0,
              tangentDeviation >= 0.0,
              speedLowerBound.isFinite,
              speedLowerBound >= 0.0,
              speedUpperBound.isFinite,
              speedUpperBound >= speedLowerBound,
              secondDerivativeMagnitudeUpperBound >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Curve tessellation certification exceeded finite interval arithmetic."
            )
        }
        return CurveTessellationIntervalBounds(
            chordDeviationUpperBound: chordDeviation,
            arcLengthUpperBound: arcLength,
            tangentDeviationUpperBound: tangentDeviation,
            speedLowerBound: speedLowerBound,
            speedUpperBound: speedUpperBound,
            secondDerivativeMagnitudeUpperBound: secondDerivativeMagnitudeUpperBound
        )
    }

    static func minimumAbsoluteValue(
        in interval: ScalarInterval
    ) -> Double {
        if interval.lower <= 0.0, interval.upper >= 0.0 {
            return 0.0
        }
        return min(abs(interval.lower), abs(interval.upper))
    }

    func certificationFailure(
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

    func arithmeticFailure(
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
