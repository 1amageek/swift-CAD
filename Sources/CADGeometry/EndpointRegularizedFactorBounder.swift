import CADCore

struct EndpointRegularizedFactorBounder {
    struct Bounds: Hashable, Sendable {
        let lower: Double
        let upper: Double
        let first: Double
        let second: Double

        func merged(with other: Bounds) -> Bounds {
            Bounds(
                lower: min(lower, other.lower).nextDown,
                upper: max(upper, other.upper).nextUp,
                first: max(first, other.first).nextUp,
                second: max(second, other.second).nextUp
            )
        }
    }

    func bounds(
        componentLower: Double,
        componentUpper: Double,
        requestedLower: Double,
        requestedUpper: Double,
        lowerValue: Double,
        upperValue: Double,
        lowerDerivative: Double,
        upperDerivative: Double,
        firstDerivativeMagnitudeUpperBound: Double,
        secondDerivativeMagnitudeUpperBound: Double,
        thirdDerivativeMagnitudeUpperBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        guard span > tolerance.angle else {
            throw failure(
                residual: span,
                tolerance: tolerance,
                label: label,
                detail: "lost its component span"
            )
        }
        let correctionSlope = (upperValue - lowerValue) / span
        let lowerSlope = lowerDerivative - correctionSlope
        let upperSlope = -(upperDerivative - correctionSlope)
        let regularizedFirst = upperSum(
            firstDerivativeMagnitudeUpperBound,
            abs(correctionSlope)
        )
        guard requestedLower >= componentLower - tolerance.angle,
              requestedUpper <= componentUpper + tolerance.angle,
              requestedUpper > requestedLower,
              lowerSlope > arithmeticEnvelope,
              upperSlope > arithmeticEnvelope,
              regularizedFirst.isFinite,
              secondDerivativeMagnitudeUpperBound.isFinite,
              thirdDerivativeMagnitudeUpperBound.isFinite else {
            throw failure(
                residual: min(span, lowerSlope, upperSlope),
                tolerance: tolerance,
                label: label,
                detail: "lost its component span or simple endpoint-root slopes"
            )
        }
        let lowerWidth = endpointProofWidth(
            span: span,
            endpointSlope: lowerSlope,
            secondDerivativeBound:
                secondDerivativeMagnitudeUpperBound
        )
        let upperWidth = endpointProofWidth(
            span: span,
            endpointSlope: upperSlope,
            secondDerivativeBound:
                secondDerivativeMagnitudeUpperBound
        )
        var result: Bounds?
        if requestedLower < componentLower + lowerWidth {
            result = try endpointBounds(
                span: span,
                width: lowerWidth,
                endpointSlope: lowerSlope,
                firstDerivativeBound: regularizedFirst,
                secondDerivativeBound:
                    secondDerivativeMagnitudeUpperBound,
                thirdDerivativeBound:
                    thirdDerivativeMagnitudeUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                tolerance: tolerance,
                label: label
            )
        }
        if requestedUpper > componentUpper - upperWidth {
            let upper = try endpointBounds(
                span: span,
                width: upperWidth,
                endpointSlope: upperSlope,
                firstDerivativeBound: regularizedFirst,
                secondDerivativeBound:
                    secondDerivativeMagnitudeUpperBound,
                thirdDerivativeBound:
                    thirdDerivativeMagnitudeUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                tolerance: tolerance,
                label: label
            )
            result = result?.merged(with: upper) ?? upper
        }
        let interiorLower = max(
            requestedLower,
            componentLower + lowerWidth
        )
        let interiorUpper = min(
            requestedUpper,
            componentUpper - upperWidth
        )
        if interiorUpper > interiorLower {
            let interior = try interiorBounds(
                lower: interiorLower,
                upper: interiorUpper,
                componentLower: componentLower,
                componentUpper: componentUpper,
                endpointResidualMagnitude: max(
                    abs(lowerValue),
                    abs(upperValue)
                ),
                firstDerivativeBound: regularizedFirst,
                secondDerivativeBound:
                    secondDerivativeMagnitudeUpperBound,
                thirdDerivativeBound:
                    thirdDerivativeMagnitudeUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                valueRange: valueRange,
                tolerance: tolerance,
                label: label
            )
            result = result?.merged(with: interior) ?? interior
        }
        guard let result,
              result.lower > 0.0,
              result.upper.isFinite,
              result.first.isFinite,
              result.second.isFinite else {
            throw failure(
                residual: result?.lower,
                tolerance: tolerance,
                label: label,
                detail: "produced no finite positive regularized factor"
            )
        }
        return result
    }

    private func endpointProofWidth(
        span: Double,
        endpointSlope: Double,
        secondDerivativeBound: Double
    ) -> Double {
        guard secondDerivativeBound > Double.leastNonzeroMagnitude else {
            return (span * 0.25).nextDown
        }
        return min(
            (span * 0.25).nextDown,
            (endpointSlope / (secondDerivativeBound * 4.0)).nextDown
        )
    }

    private func endpointBounds(
        span: Double,
        width: Double,
        endpointSlope: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let denominatorLower = (span - width).nextDown
        let averagedSlopeLower = (
            endpointSlope
                - upperProduct(secondDerivativeBound, width)
                - arithmeticEnvelope
        ).nextDown
        guard width > 0.0,
              denominatorLower > 0.0,
              averagedSlopeLower > 0.0 else {
            throw failure(
                residual: min(width, denominatorLower, averagedSlopeLower),
                tolerance: tolerance,
                label: label,
                detail: "lost its endpoint divided-difference margin"
            )
        }
        let denominatorSquared = lowerProduct(
            denominatorLower,
            denominatorLower
        )
        let denominatorCubed = lowerProduct(
            denominatorSquared,
            denominatorLower
        )
        return Bounds(
            lower: (averagedSlopeLower / span.nextUp).nextDown,
            upper: (firstDerivativeBound / denominatorLower).nextUp,
            first: upperSum(
                (
                    (secondDerivativeBound * 0.5).nextUp
                        / denominatorLower
                ).nextUp,
                (firstDerivativeBound / denominatorSquared).nextUp
            ),
            second: upperSum(
                (
                    (thirdDerivativeBound / 3.0).nextUp
                        / denominatorLower
                ).nextUp,
                upperSum(
                    (secondDerivativeBound / denominatorSquared).nextUp,
                    (
                        upperProduct(2.0, firstDerivativeBound)
                            / denominatorCubed
                    ).nextUp
                )
            )
        )
    }

    private func derivativeEndpointBounds(
        span: Double,
        width: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double
    ) -> Bounds? {
        let denominatorLower = (span - width).nextDown
        guard width >= 0.0, denominatorLower > 0.0 else {
            return nil
        }
        let denominatorSquared = lowerProduct(
            denominatorLower,
            denominatorLower
        )
        let denominatorCubed = lowerProduct(
            denominatorSquared,
            denominatorLower
        )
        return Bounds(
            lower: .infinity,
            upper: (firstDerivativeBound / denominatorLower).nextUp,
            first: upperSum(
                (
                    (secondDerivativeBound * 0.5).nextUp
                        / denominatorLower
                ).nextUp,
                (firstDerivativeBound / denominatorSquared).nextUp
            ),
            second: upperSum(
                (
                    (thirdDerivativeBound / 3.0).nextUp
                        / denominatorLower
                ).nextUp,
                upperSum(
                    (secondDerivativeBound / denominatorSquared).nextUp,
                    (
                        upperProduct(2.0, firstDerivativeBound)
                            / denominatorCubed
                    ).nextUp
                )
            )
        )
    }

    private func interiorBounds(
        lower: Double,
        upper: Double,
        componentLower: Double,
        componentUpper: Double,
        endpointResidualMagnitude: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        var cellLower = lower
        var result: Bounds?
        var remainingCells = 2_048
        while cellLower < upper {
            guard remainingCells > 0 else {
                throw failure(
                    residual: upper - cellLower,
                    tolerance: tolerance,
                    label: label,
                    detail: "exceeded its interior subdivision budget"
                )
            }
            remainingCells -= 1
            let offset = cellLower - componentLower
            let endpointDistance = min(offset, span - offset)
            let step = max(
                endpointDistance * 0.25,
                Double.ulpOfOne * max(span, 1.0) * 4_096.0
            )
            let cellUpper = min(cellLower + step, upper)
            let cell = try interiorCellBounds(
                lower: cellLower,
                upper: cellUpper,
                componentLower: componentLower,
                componentUpper: componentUpper,
                endpointResidualMagnitude: endpointResidualMagnitude,
                firstDerivativeBound: firstDerivativeBound,
                secondDerivativeBound: secondDerivativeBound,
                thirdDerivativeBound: thirdDerivativeBound,
                arithmeticEnvelope: arithmeticEnvelope,
                valueRange: valueRange,
                tolerance: tolerance,
                label: label
            )
            result = result?.merged(with: cell) ?? cell
            cellLower = cellUpper
        }
        guard let result else {
            throw failure(
                residual: upper - lower,
                tolerance: tolerance,
                label: label,
                detail: "produced no interior cells"
            )
        }
        return result
    }

    private func interiorCellBounds(
        lower: Double,
        upper: Double,
        componentLower: Double,
        componentUpper: Double,
        endpointResidualMagnitude: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        let lowerOffset = lower - componentLower
        let upperOffset = upper - componentLower
        let lowerDenominator = lowerProduct(
            lowerOffset,
            span - lowerOffset
        )
        let upperDenominator = lowerProduct(
            upperOffset,
            span - upperOffset
        )
        let denominatorLower = min(
            lowerDenominator,
            upperDenominator
        ).nextDown
        let denominatorUpper: Double
        if lowerOffset <= span * 0.5, upperOffset >= span * 0.5 {
            denominatorUpper = (
                upperProduct(span, span) * 0.25
            ).nextUp
        } else {
            denominatorUpper = max(
                lowerOffset * (span - lowerOffset),
                upperOffset * (span - upperOffset)
            ).nextUp
        }
        let raw = try valueRange(lower, upper)
        let rawLower = (
            raw.lower
                - endpointResidualMagnitude
                - arithmeticEnvelope
        ).nextDown
        guard denominatorLower > 0.0,
              denominatorUpper > 0.0,
              rawLower > 0.0 else {
            throw failure(
                residual: min(
                    denominatorLower,
                    denominatorUpper,
                    rawLower
                ),
                tolerance: tolerance,
                label: label,
                detail: "lost its positive interior factor margin"
            )
        }
        let valueUpper = upperSum(
            upperSum(raw.upper, endpointResidualMagnitude),
            arithmeticEnvelope
        )
        let denominatorSquared = lowerProduct(
            denominatorLower,
            denominatorLower
        )
        let denominatorCubed = lowerProduct(
            denominatorSquared,
            denominatorLower
        )
        let direct = Bounds(
            lower: (rawLower / denominatorUpper).nextDown,
            upper: (valueUpper / denominatorLower).nextUp,
            first: upperSum(
                (firstDerivativeBound / denominatorLower).nextUp,
                (
                    upperProduct(valueUpper, span)
                        / denominatorSquared
                ).nextUp
            ),
            second: upperSum(
                (secondDerivativeBound / denominatorLower).nextUp,
                upperSum(
                    (
                        upperProduct(2.0, valueUpper)
                            / denominatorSquared
                    ).nextUp,
                    upperSum(
                        (
                            upperProduct(
                                2.0,
                                upperProduct(firstDerivativeBound, span)
                            ) / denominatorSquared
                        ).nextUp,
                        (
                            upperProduct(
                                2.0,
                                upperProduct(
                                    valueUpper,
                                    upperProduct(span, span)
                                )
                            ) / denominatorCubed
                        ).nextUp
                    )
                )
            )
        )
        let derivativeCertificates = [
            derivativeEndpointBounds(
                span: span,
                width: upperOffset,
                firstDerivativeBound: firstDerivativeBound,
                secondDerivativeBound: secondDerivativeBound,
                thirdDerivativeBound: thirdDerivativeBound
            ),
            derivativeEndpointBounds(
                span: span,
                width: span - lowerOffset,
                firstDerivativeBound: firstDerivativeBound,
                secondDerivativeBound: secondDerivativeBound,
                thirdDerivativeBound: thirdDerivativeBound
            ),
        ].compactMap { $0 }
        return Bounds(
            lower: direct.lower,
            upper: derivativeCertificates.reduce(direct.upper) {
                min($0, $1.upper)
            }.nextUp,
            first: derivativeCertificates.reduce(direct.first) {
                min($0, $1.first)
            }.nextUp,
            second: derivativeCertificates.reduce(direct.second) {
                min($0, $1.second)
            }.nextUp
        )
    }

    private func failure(
        residual: Double?,
        tolerance: ModelingTolerance,
        label: String,
        detail: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: "\(label) \(detail)."
        )
    }

    private func upperSum(_ first: Double, _ second: Double) -> Double {
        (first + second).nextUp
    }

    private func upperProduct(_ first: Double, _ second: Double) -> Double {
        (first * second).nextUp
    }

    private func lowerProduct(_ first: Double, _ second: Double) -> Double {
        (first * second).nextDown
    }
}
