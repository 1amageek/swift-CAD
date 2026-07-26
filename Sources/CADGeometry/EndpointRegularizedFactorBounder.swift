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

    func oneSidedBounds(
        componentLower: Double,
        componentUpper: Double,
        requestedLower: Double,
        requestedUpper: Double,
        rootAtLower: Bool,
        endpointValue: Double,
        endpointDerivative: Double,
        firstDerivativeMagnitudeUpperBound: Double,
        secondDerivativeMagnitudeUpperBound: Double,
        thirdDerivativeMagnitudeUpperBound: Double,
        arithmeticEnvelope: Double,
        orientedValueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        let endpointSlope = rootAtLower
            ? endpointDerivative
            : -endpointDerivative
        guard span > tolerance.angle,
              requestedLower >= componentLower - tolerance.angle,
              requestedUpper <= componentUpper + tolerance.angle,
              requestedUpper > requestedLower,
              endpointSlope > arithmeticEnvelope,
              firstDerivativeMagnitudeUpperBound.isFinite,
              secondDerivativeMagnitudeUpperBound.isFinite,
              thirdDerivativeMagnitudeUpperBound.isFinite else {
            throw failure(
                residual: min(span, endpointSlope),
                tolerance: tolerance,
                label: label,
                detail: "lost its one-sided component span or simple endpoint-root slope"
            )
        }
        let endpointWidth = endpointProofWidth(
            span: span,
            endpointSlope: endpointSlope,
            secondDerivativeBound: secondDerivativeMagnitudeUpperBound
        )
        let endpointBoundary = rootAtLower
            ? componentLower + endpointWidth
            : componentUpper - endpointWidth
        var result: Bounds?
        let reachesEndpoint = rootAtLower
            ? requestedLower < endpointBoundary
            : requestedUpper > endpointBoundary
        if reachesEndpoint {
            let lower = (
                endpointSlope
                    - upperProduct(
                        secondDerivativeMagnitudeUpperBound,
                        endpointWidth
                    )
                    - arithmeticEnvelope
            ).nextDown
            guard endpointWidth > 0.0, lower > 0.0 else {
                throw failure(
                    residual: min(endpointWidth, lower),
                    tolerance: tolerance,
                    label: label,
                    detail: "lost its one-sided endpoint divided-difference margin"
                )
            }
            result = Bounds(
                lower: lower,
                upper: upperSum(
                    firstDerivativeMagnitudeUpperBound,
                    arithmeticEnvelope
                ),
                first: (
                    secondDerivativeMagnitudeUpperBound * 0.5
                ).nextUp,
                second: (
                    thirdDerivativeMagnitudeUpperBound / 3.0
                ).nextUp
            )
        }
        let interiorLower = rootAtLower
            ? max(requestedLower, endpointBoundary)
            : requestedLower
        let interiorUpper = rootAtLower
            ? requestedUpper
            : min(requestedUpper, endpointBoundary)
        if interiorUpper > interiorLower {
            let interior = try oneSidedInteriorBounds(
                lower: interiorLower,
                upper: interiorUpper,
                componentLower: componentLower,
                componentUpper: componentUpper,
                rootAtLower: rootAtLower,
                endpointResidualMagnitude: abs(endpointValue),
                firstDerivativeBound:
                    firstDerivativeMagnitudeUpperBound,
                secondDerivativeBound:
                    secondDerivativeMagnitudeUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                orientedValueRange: orientedValueRange,
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
                detail: "produced no finite positive one-sided factor"
            )
        }
        return result
    }

    func oneSidedDoubleRootBounds(
        componentLower: Double,
        componentUpper: Double,
        requestedLower: Double,
        requestedUpper: Double,
        rootAtLower: Bool,
        endpointValue: Double,
        endpointDerivative: Double,
        endpointSecondDerivative: Double,
        firstDerivativeMagnitudeUpperBound: Double,
        secondDerivativeMagnitudeUpperBound: Double,
        thirdDerivativeMagnitudeUpperBound: Double,
        fourthDerivativeMagnitudeUpperBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        let endpointFactor = endpointSecondDerivative * 0.5
        let factorFirstBound = (
            thirdDerivativeMagnitudeUpperBound / 6.0
        ).nextUp
        let factorSecondBound = (
            fourthDerivativeMagnitudeUpperBound / 12.0
        ).nextUp
        guard span > tolerance.angle,
              requestedLower >= componentLower - tolerance.angle,
              requestedUpper <= componentUpper + tolerance.angle,
              requestedUpper > requestedLower,
              endpointFactor > arithmeticEnvelope,
              factorFirstBound.isFinite,
              factorSecondBound.isFinite else {
            throw failure(
                residual: min(span, endpointFactor),
                tolerance: tolerance,
                label: label,
                detail: "lost its one-sided double-root curvature"
            )
        }
        let endpointWidth: Double
        if factorFirstBound > Double.leastNonzeroMagnitude {
            endpointWidth = min(
                (span * 0.25).nextDown,
                (
                    endpointFactor / (factorFirstBound * 4.0)
                ).nextDown
            )
        } else {
            endpointWidth = (span * 0.25).nextDown
        }
        let endpointBoundary = rootAtLower
            ? componentLower + endpointWidth
            : componentUpper - endpointWidth
        var result: Bounds?
        let reachesEndpoint = rootAtLower
            ? requestedLower < endpointBoundary
            : requestedUpper > endpointBoundary
        if reachesEndpoint {
            let lower = (
                endpointFactor
                    - upperProduct(factorFirstBound, endpointWidth)
                    - arithmeticEnvelope
            ).nextDown
            guard endpointWidth > 0.0, lower > 0.0 else {
                throw failure(
                    residual: min(endpointWidth, lower),
                    tolerance: tolerance,
                    label: label,
                    detail: "lost its double-root endpoint factor margin"
                )
            }
            result = Bounds(
                lower: lower,
                upper: upperSum(
                    upperSum(
                        endpointFactor,
                        upperProduct(factorFirstBound, endpointWidth)
                    ),
                    arithmeticEnvelope
                ),
                first: factorFirstBound,
                second: factorSecondBound
            )
        }
        let interiorLower = rootAtLower
            ? max(requestedLower, endpointBoundary)
            : requestedLower
        let interiorUpper = rootAtLower
            ? requestedUpper
            : min(requestedUpper, endpointBoundary)
        if interiorUpper > interiorLower {
            let interior = try doubleRootInteriorBounds(
                lower: interiorLower,
                upper: interiorUpper,
                componentLower: componentLower,
                componentUpper: componentUpper,
                rootAtLower: rootAtLower,
                endpointValue: endpointValue,
                endpointDerivative: endpointDerivative,
                firstDerivativeBound:
                    firstDerivativeMagnitudeUpperBound,
                secondDerivativeBound:
                    secondDerivativeMagnitudeUpperBound,
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
                detail: "produced no finite positive double-root factor"
            )
        }
        return result
    }

    func mixedDoubleSimpleBounds(
        componentLower: Double,
        componentUpper: Double,
        requestedLower: Double,
        requestedUpper: Double,
        doubleRootAtLower: Bool,
        doubleRootValue: Double,
        doubleRootFirstDerivative: Double,
        doubleRootSecondDerivative: Double,
        simpleRootValue: Double,
        simpleRootFirstDerivative: Double,
        firstDerivativeMagnitudeUpperBound: Double,
        secondDerivativeMagnitudeUpperBound: Double,
        fourthDerivativeMagnitudeUpperBound: Double,
        fifthDerivativeMagnitudeUpperBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        guard span > tolerance.angle,
              requestedLower >= componentLower - tolerance.angle,
              requestedUpper <= componentUpper + tolerance.angle,
              requestedUpper > requestedLower,
              fourthDerivativeMagnitudeUpperBound.isFinite,
              fifthDerivativeMagnitudeUpperBound.isFinite else {
            throw failure(
                residual: span,
                tolerance: tolerance,
                label: label,
                detail: "lost its mixed-root component span"
            )
        }
        let orientedDoubleFirst = doubleRootAtLower
            ? doubleRootFirstDerivative
            : -doubleRootFirstDerivative
        let orientedSimpleFirst = doubleRootAtLower
            ? simpleRootFirstDerivative
            : -simpleRootFirstDerivative
        let correctionQuadratic = (
            simpleRootValue
                - doubleRootValue
                - orientedDoubleFirst * span
        ) / (span * span)
        let doubleFactor = (
            doubleRootSecondDerivative * 0.5
                - correctionQuadratic
        ) / span
        let correctedSimpleFirst = orientedSimpleFirst
            - orientedDoubleFirst
            - 2.0 * correctionQuadratic * span
        let simpleFactor = -correctedSimpleFirst / (span * span)
        let firstBound = (
            fourthDerivativeMagnitudeUpperBound / 24.0
        ).nextUp
        let secondBound = (
            fifthDerivativeMagnitudeUpperBound / 60.0
        ).nextUp
        guard doubleFactor > arithmeticEnvelope,
              simpleFactor > arithmeticEnvelope,
              firstDerivativeMagnitudeUpperBound.isFinite,
              secondDerivativeMagnitudeUpperBound.isFinite,
              firstBound.isFinite,
              secondBound.isFinite else {
            throw failure(
                residual: min(doubleFactor, simpleFactor),
                tolerance: tolerance,
                label: label,
                detail: "lost its positive mixed double/simple divided-difference factor"
            )
        }
        let doubleWidth = firstBound > Double.leastNonzeroMagnitude
            ? min(
                (span * 0.125).nextDown,
                (
                    doubleFactor / (firstBound * 4.0)
                ).nextDown
            )
            : (span * 0.125).nextDown
        let simpleWidth = firstBound > Double.leastNonzeroMagnitude
            ? min(
                (span * 0.125).nextDown,
                (
                    simpleFactor / (firstBound * 4.0)
                ).nextDown
            )
            : (span * 0.125).nextDown
        guard doubleWidth > 0.0, simpleWidth > 0.0 else {
            throw failure(
                residual: min(doubleWidth, simpleWidth),
                tolerance: tolerance,
                label: label,
                detail: "lost its mixed-root endpoint proof widths"
            )
        }
        let requestedCoordinateLower = doubleRootAtLower
            ? requestedLower - componentLower
            : componentUpper - requestedUpper
        let requestedCoordinateUpper = doubleRootAtLower
            ? requestedUpper - componentLower
            : componentUpper - requestedLower
        var result: Bounds?
        if requestedCoordinateLower < doubleWidth {
            result = Bounds(
                lower: (
                    doubleFactor - firstBound * doubleWidth
                        - arithmeticEnvelope
                ).nextDown,
                upper: (
                    doubleFactor + firstBound * doubleWidth
                        + arithmeticEnvelope
                ).nextUp,
                first: firstBound,
                second: secondBound
            )
        }
        if requestedCoordinateUpper > span - simpleWidth {
            let simple = Bounds(
                lower: (
                    simpleFactor - firstBound * simpleWidth
                        - arithmeticEnvelope
                ).nextDown,
                upper: (
                    simpleFactor + firstBound * simpleWidth
                        + arithmeticEnvelope
                ).nextUp,
                first: firstBound,
                second: secondBound
            )
            result = result?.merged(with: simple) ?? simple
        }
        let correctionMagnitude = (
            abs(doubleRootValue)
                + abs(orientedDoubleFirst) * span
                + abs(correctionQuadratic) * span * span
                + arithmeticEnvelope
        ).nextUp
        let correctionFirstMagnitude = (
            abs(orientedDoubleFirst)
                + 2.0 * abs(correctionQuadratic) * span
        ).nextUp
        let correctionSecondMagnitude = (
            2.0 * abs(correctionQuadratic)
        ).nextUp
        var coordinateLower = max(
            requestedCoordinateLower,
            doubleWidth
        )
        let coordinateUpper = min(
            requestedCoordinateUpper,
            span - simpleWidth
        )
        var remainingCells = 4_096
        while coordinateLower < coordinateUpper {
            guard remainingCells > 0 else {
                throw failure(
                    residual: coordinateUpper - coordinateLower,
                    tolerance: tolerance,
                    label: label,
                    detail: "exceeded its mixed-root interior subdivision budget"
                )
            }
            remainingCells -= 1
            let simpleDistance = span - coordinateLower
            let step = max(
                min(coordinateLower, simpleDistance) * 0.25,
                Double.ulpOfOne * max(span, 1.0) * 4_096.0
            )
            let coordinateCellUpper = min(
                coordinateLower + step,
                coordinateUpper
            )
            let xLower = coordinateLower.nextDown
            let xUpper = coordinateCellUpper.nextUp
            let yLower = (span - coordinateCellUpper).nextDown
            let yUpper = (span - coordinateLower).nextUp
            let denominatorLower = lowerProduct(
                lowerProduct(xLower, xLower),
                yLower
            )
            let denominatorUpper = upperProduct(
                upperProduct(xUpper, xUpper),
                yUpper
            )
            let angleLower: Double
            let angleUpper: Double
            if doubleRootAtLower {
                angleLower = componentLower + coordinateLower
                angleUpper = componentLower + coordinateCellUpper
            } else {
                angleLower = componentUpper - coordinateCellUpper
                angleUpper = componentUpper - coordinateLower
            }
            let raw = try valueRange(angleLower, angleUpper)
            let numeratorLower = (
                raw.lower - correctionMagnitude
            ).nextDown
            let numeratorUpper = (
                raw.upper + correctionMagnitude
            ).nextUp
            guard denominatorLower > 0.0,
                  numeratorLower > 0.0 else {
                throw failure(
                    residual: min(denominatorLower, numeratorLower),
                    tolerance: tolerance,
                    label: label,
                    detail: "lost its positive mixed-root interior quotient"
                )
            }
            let denominatorFirst = (
                2.0 * span * xUpper + 3.0 * xUpper * xUpper
            ).nextUp
            let denominatorSecond = (
                2.0 * span + 6.0 * xUpper
            ).nextUp
            let denominatorSquaredLower = lowerProduct(
                denominatorLower,
                denominatorLower
            )
            let denominatorCubedLower = lowerProduct(
                denominatorSquaredLower,
                denominatorLower
            )
            let inverse = (1.0 / denominatorLower).nextUp
            let inverseFirst = (
                denominatorFirst / denominatorSquaredLower
            ).nextUp
            let inverseSecond = (
                2.0 * denominatorFirst * denominatorFirst
                    / denominatorCubedLower
                    + denominatorSecond / denominatorSquaredLower
            ).nextUp
            let numeratorFirst = upperSum(
                firstDerivativeMagnitudeUpperBound,
                correctionFirstMagnitude
            )
            let numeratorSecond = upperSum(
                secondDerivativeMagnitudeUpperBound,
                correctionSecondMagnitude
            )
            let cell = Bounds(
                lower: (numeratorLower / denominatorUpper).nextDown,
                upper: (numeratorUpper / denominatorLower).nextUp,
                first: (
                    numeratorFirst * inverse
                        + numeratorUpper * inverseFirst
                ).nextUp,
                second: (
                    numeratorSecond * inverse
                        + 2.0 * numeratorFirst * inverseFirst
                        + numeratorUpper * inverseSecond
                ).nextUp
            )
            result = result?.merged(with: cell) ?? cell
            coordinateLower = coordinateCellUpper
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
                detail: "produced no finite positive mixed-root factor"
            )
        }
        return result
    }

    func doubleDoubleBounds(
        componentLower: Double,
        componentUpper: Double,
        requestedLower: Double,
        requestedUpper: Double,
        lowerValue: Double,
        lowerFirstDerivative: Double,
        lowerSecondDerivative: Double,
        upperValue: Double,
        upperFirstDerivative: Double,
        upperSecondDerivative: Double,
        firstDerivativeMagnitudeUpperBound: Double,
        secondDerivativeMagnitudeUpperBound: Double,
        fifthDerivativeMagnitudeUpperBound: Double,
        sixthDerivativeMagnitudeUpperBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        let span = componentUpper - componentLower
        guard span > tolerance.angle,
              requestedLower >= componentLower - tolerance.angle,
              requestedUpper <= componentUpper + tolerance.angle,
              requestedUpper > requestedLower,
              fifthDerivativeMagnitudeUpperBound.isFinite,
              sixthDerivativeMagnitudeUpperBound.isFinite else {
            throw failure(
                residual: span,
                tolerance: tolerance,
                label: label,
                detail: "lost its double-root component span"
            )
        }
        let endpointValueDelta = upperValue
            - lowerValue - lowerFirstDerivative * span
        let endpointSlopeDelta = upperFirstDerivative
            - lowerFirstDerivative
        let correctionCubic = (
            endpointSlopeDelta * span
                - 2.0 * endpointValueDelta
        ) / (span * span * span)
        let correctionQuadratic = (
            3.0 * endpointValueDelta
                - endpointSlopeDelta * span
        ) / (span * span)
        let correctedLowerSecond = lowerSecondDerivative
            - 2.0 * correctionQuadratic
        let correctedUpperSecond = upperSecondDerivative
            - 2.0 * correctionQuadratic
            - 6.0 * correctionCubic * span
        let spanSquared = span * span
        let lowerFactor = correctedLowerSecond * 0.5 / spanSquared
        let upperFactor = correctedUpperSecond * 0.5 / spanSquared
        let firstBound = (
            fifthDerivativeMagnitudeUpperBound / 120.0
        ).nextUp
        let secondBound = (
            sixthDerivativeMagnitudeUpperBound / 360.0
        ).nextUp
        guard lowerFactor > arithmeticEnvelope,
              upperFactor > arithmeticEnvelope,
              firstDerivativeMagnitudeUpperBound.isFinite,
              secondDerivativeMagnitudeUpperBound.isFinite,
              firstBound.isFinite,
              secondBound.isFinite else {
            throw failure(
                residual: min(lowerFactor, upperFactor),
                tolerance: tolerance,
                label: label,
                detail: "lost its positive two-double-root divided-difference factor"
            )
        }
        let lowerWidth = firstBound > Double.leastNonzeroMagnitude
            ? min(
                (span * 0.125).nextDown,
                (
                    lowerFactor / (firstBound * 4.0)
                ).nextDown
            )
            : (span * 0.125).nextDown
        let upperWidth = firstBound > Double.leastNonzeroMagnitude
            ? min(
                (span * 0.125).nextDown,
                (
                    upperFactor / (firstBound * 4.0)
                ).nextDown
            )
            : (span * 0.125).nextDown
        guard lowerWidth > 0.0, upperWidth > 0.0 else {
            throw failure(
                residual: min(lowerWidth, upperWidth),
                tolerance: tolerance,
                label: label,
                detail: "lost its two-double-root endpoint proof widths"
            )
        }
        var result: Bounds?
        if requestedLower < componentLower + lowerWidth {
            result = Bounds(
                lower: (
                    lowerFactor - firstBound * lowerWidth
                        - arithmeticEnvelope
                ).nextDown,
                upper: (
                    lowerFactor + firstBound * lowerWidth
                        + arithmeticEnvelope
                ).nextUp,
                first: firstBound,
                second: secondBound
            )
        }
        if requestedUpper > componentUpper - upperWidth {
            let upper = Bounds(
                lower: (
                    upperFactor - firstBound * upperWidth
                        - arithmeticEnvelope
                ).nextDown,
                upper: (
                    upperFactor + firstBound * upperWidth
                        + arithmeticEnvelope
                ).nextUp,
                first: firstBound,
                second: secondBound
            )
            result = result?.merged(with: upper) ?? upper
        }
        let correctionMagnitude = (
            abs(lowerValue)
                + abs(lowerFirstDerivative) * span
                + abs(correctionQuadratic) * span * span
                + abs(correctionCubic) * span * span * span
                + arithmeticEnvelope
        ).nextUp
        let correctionFirstMagnitude = (
            abs(lowerFirstDerivative)
                + 2.0 * abs(correctionQuadratic) * span
                + 3.0 * abs(correctionCubic) * span * span
        ).nextUp
        let correctionSecondMagnitude = (
            2.0 * abs(correctionQuadratic)
                + 6.0 * abs(correctionCubic) * span
        ).nextUp
        var cellLower = max(
            requestedLower,
            componentLower + lowerWidth
        )
        let interiorUpper = min(
            requestedUpper,
            componentUpper - upperWidth
        )
        var remainingCells = 4_096
        while cellLower < interiorUpper {
            guard remainingCells > 0 else {
                throw failure(
                    residual: interiorUpper - cellLower,
                    tolerance: tolerance,
                    label: label,
                    detail: "exceeded its two-double-root interior subdivision budget"
                )
            }
            remainingCells -= 1
            let lowerDistance = cellLower - componentLower
            let upperDistance = componentUpper - cellLower
            let step = max(
                min(lowerDistance, upperDistance) * 0.25,
                Double.ulpOfOne * max(span, 1.0) * 4_096.0
            )
            let cellUpper = min(cellLower + step, interiorUpper)
            let xLower = (cellLower - componentLower).nextDown
            let xUpper = (cellUpper - componentLower).nextUp
            let yLower = (componentUpper - cellUpper).nextDown
            let yUpper = (componentUpper - cellLower).nextUp
            let denominatorLower = lowerProduct(
                lowerProduct(xLower, xLower),
                lowerProduct(yLower, yLower)
            )
            let denominatorUpper = upperProduct(
                upperProduct(xUpper, xUpper),
                upperProduct(yUpper, yUpper)
            )
            let raw = try valueRange(cellLower, cellUpper)
            let numeratorLower = (
                raw.lower - correctionMagnitude
            ).nextDown
            let numeratorUpper = (
                raw.upper + correctionMagnitude
            ).nextUp
            guard denominatorLower > 0.0,
                  numeratorLower > 0.0 else {
                throw failure(
                    residual: min(denominatorLower, numeratorLower),
                    tolerance: tolerance,
                    label: label,
                    detail: "lost its positive two-double-root interior quotient"
                )
            }
            let denominatorFirst = (
                2.0 * xUpper * yUpper * span
            ).nextUp
            let denominatorSecond = (
                2.0 * yUpper * yUpper
                    + 8.0 * xUpper * yUpper
                    + 2.0 * xUpper * xUpper
            ).nextUp
            let denominatorSquaredLower = lowerProduct(
                denominatorLower,
                denominatorLower
            )
            let denominatorCubedLower = lowerProduct(
                denominatorSquaredLower,
                denominatorLower
            )
            let inverse = (1.0 / denominatorLower).nextUp
            let inverseFirst = (
                denominatorFirst / denominatorSquaredLower
            ).nextUp
            let inverseSecond = (
                2.0 * denominatorFirst * denominatorFirst
                    / denominatorCubedLower
                    + denominatorSecond / denominatorSquaredLower
            ).nextUp
            let numeratorFirst = upperSum(
                firstDerivativeMagnitudeUpperBound,
                correctionFirstMagnitude
            )
            let numeratorSecond = upperSum(
                secondDerivativeMagnitudeUpperBound,
                correctionSecondMagnitude
            )
            let cell = Bounds(
                lower: (numeratorLower / denominatorUpper).nextDown,
                upper: (numeratorUpper / denominatorLower).nextUp,
                first: (
                    numeratorFirst * inverse
                        + numeratorUpper * inverseFirst
                ).nextUp,
                second: (
                    numeratorSecond * inverse
                        + 2.0 * numeratorFirst * inverseFirst
                        + numeratorUpper * inverseSecond
                ).nextUp
            )
            result = result?.merged(with: cell) ?? cell
            cellLower = cellUpper
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
                detail: "produced no finite positive two-double-root factor"
            )
        }
        return result
    }

    private func doubleRootInteriorBounds(
        lower: Double,
        upper: Double,
        componentLower: Double,
        componentUpper: Double,
        rootAtLower: Bool,
        endpointValue: Double,
        endpointDerivative: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        arithmeticEnvelope: Double,
        valueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        var cellLower = lower
        var result: Bounds?
        var remainingCells = 2_048
        while cellLower < upper {
            guard remainingCells > 0 else {
                throw failure(
                    residual: upper - cellLower,
                    tolerance: tolerance,
                    label: label,
                    detail: "exceeded its double-root interior subdivision budget"
                )
            }
            remainingCells -= 1
            let endpointDistance = rootAtLower
                ? cellLower - componentLower
                : componentUpper - cellLower
            let step = max(
                abs(endpointDistance) * 0.25,
                Double.ulpOfOne
                    * max(componentUpper - componentLower, 1.0)
                    * 4_096.0
            )
            let cellUpper = min(cellLower + step, upper)
            let lowerDistance = rootAtLower
                ? cellLower - componentLower
                : componentUpper - cellUpper
            let upperDistance = rootAtLower
                ? cellUpper - componentLower
                : componentUpper - cellLower
            let denominatorLower = lowerDistance.nextDown
            let denominatorUpper = upperDistance.nextUp
            let raw = try valueRange(cellLower, cellUpper)
            let endpointCorrection = (
                abs(endpointValue)
                    + abs(endpointDerivative) * denominatorUpper
                    + arithmeticEnvelope
            ).nextUp
            let valueLower = (
                raw.lower - endpointCorrection
            ).nextDown
            let valueUpper = (
                raw.upper + endpointCorrection
            ).nextUp
            guard denominatorLower > 0.0,
                  denominatorUpper > 0.0,
                  valueLower > 0.0 else {
                throw failure(
                    residual: min(
                        denominatorLower,
                        denominatorUpper,
                        valueLower
                    ),
                    tolerance: tolerance,
                    label: label,
                    detail: "lost its positive double-root interior factor margin"
                )
            }
            let denominatorSquaredLower = lowerProduct(
                denominatorLower,
                denominatorLower
            )
            let denominatorSquaredUpper = upperProduct(
                denominatorUpper,
                denominatorUpper
            )
            let denominatorCubedLower = lowerProduct(
                denominatorSquaredLower,
                denominatorLower
            )
            let denominatorFourthLower = lowerProduct(
                denominatorSquaredLower,
                denominatorSquaredLower
            )
            let correctedFirst = upperSum(
                firstDerivativeBound,
                abs(endpointDerivative)
            )
            let cell = Bounds(
                lower: (valueLower / denominatorSquaredUpper).nextDown,
                upper: (valueUpper / denominatorSquaredLower).nextUp,
                first: upperSum(
                    (correctedFirst / denominatorSquaredLower).nextUp,
                    (
                        upperProduct(2.0, valueUpper)
                            / denominatorCubedLower
                    ).nextUp
                ),
                second: upperSum(
                    (secondDerivativeBound / denominatorSquaredLower).nextUp,
                    upperSum(
                        (
                            upperProduct(4.0, correctedFirst)
                                / denominatorCubedLower
                        ).nextUp,
                        (
                            upperProduct(6.0, valueUpper)
                                / denominatorFourthLower
                        ).nextUp
                    )
                )
            )
            result = result?.merged(with: cell) ?? cell
            cellLower = cellUpper
        }
        guard let result else {
            throw failure(
                residual: upper - lower,
                tolerance: tolerance,
                label: label,
                detail: "produced no double-root interior cells"
            )
        }
        return result
    }

    private func oneSidedInteriorBounds(
        lower: Double,
        upper: Double,
        componentLower: Double,
        componentUpper: Double,
        rootAtLower: Bool,
        endpointResidualMagnitude: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        arithmeticEnvelope: Double,
        orientedValueRange: (Double, Double) throws -> (
            lower: Double,
            upper: Double
        ),
        tolerance: ModelingTolerance,
        label: String
    ) throws -> Bounds {
        var cellLower = lower
        var result: Bounds?
        var remainingCells = 2_048
        while cellLower < upper {
            guard remainingCells > 0 else {
                throw failure(
                    residual: upper - cellLower,
                    tolerance: tolerance,
                    label: label,
                    detail: "exceeded its one-sided interior subdivision budget"
                )
            }
            remainingCells -= 1
            let endpointDistance = rootAtLower
                ? cellLower - componentLower
                : componentUpper - cellLower
            let step = max(
                abs(endpointDistance) * 0.25,
                Double.ulpOfOne
                    * max(componentUpper - componentLower, 1.0)
                    * 4_096.0
            )
            let cellUpper = min(cellLower + step, upper)
            let lowerDistance = rootAtLower
                ? cellLower - componentLower
                : componentUpper - cellUpper
            let upperDistance = rootAtLower
                ? cellUpper - componentLower
                : componentUpper - cellLower
            let denominatorLower = lowerDistance.nextDown
            let denominatorUpper = upperDistance.nextUp
            let raw = try orientedValueRange(cellLower, cellUpper)
            let valueLower = (
                raw.lower
                    - endpointResidualMagnitude
                    - arithmeticEnvelope
            ).nextDown
            let valueUpper = (
                raw.upper
                    + endpointResidualMagnitude
                    + arithmeticEnvelope
            ).nextUp
            guard denominatorLower > 0.0,
                  denominatorUpper > 0.0,
                  valueLower > 0.0 else {
                throw failure(
                    residual: min(
                        denominatorLower,
                        denominatorUpper,
                        valueLower
                    ),
                    tolerance: tolerance,
                    label: label,
                    detail: "lost its positive one-sided interior factor margin"
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
            let cell = Bounds(
                lower: (valueLower / denominatorUpper).nextDown,
                upper: (valueUpper / denominatorLower).nextUp,
                first: upperSum(
                    (firstDerivativeBound / denominatorLower).nextUp,
                    (valueUpper / denominatorSquared).nextUp
                ),
                second: upperSum(
                    (secondDerivativeBound / denominatorLower).nextUp,
                    upperSum(
                        (
                            upperProduct(2.0, firstDerivativeBound)
                                / denominatorSquared
                        ).nextUp,
                        (
                            upperProduct(2.0, valueUpper)
                                / denominatorCubed
                        ).nextUp
                    )
                )
            )
            result = result?.merged(with: cell) ?? cell
            cellLower = cellUpper
        }
        guard let result else {
            throw failure(
                residual: upper - lower,
                tolerance: tolerance,
                label: label,
                detail: "produced no one-sided interior cells"
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
