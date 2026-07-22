import CADCore
import CADGeometry
import Foundation

package struct SurfaceParameterCurveAreaIntegrator {
    private struct WorkItem {
        let patch: RationalBezierCurvePatch2D
        let requestedWidth: Double
        let depth: Int
    }

    private let maximumSubdivisionDepth = 40
    private let maximumCellCount = 131_072

    package init() {}

    package func bounds(
        for curve: SurfaceParameterCurve,
        uShift: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        try tolerance.validate()
        guard uShift.isFinite,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface-parameter area integration requires finite positive options."
            )
        }
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            let start = SurfaceParameter(
                u: origin.x + direction.x * startParameter + uShift,
                v: origin.y + direction.y * startParameter
            )
            let end = SurfaceParameter(
                u: origin.x + direction.x * endParameter + uShift,
                v: origin.y + direction.y * endParameter
            )
            return linearContribution(from: start, to: end)
        case let .constantU(u, vStart, vEnd):
            return productBounds(
                u + uShift,
                vEnd - vStart
            )
        case .constantV:
            return .zero
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return harmonicContribution(
                center: Point2D(x: center.x + uShift, y: center.y),
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            var result = SurfaceParameterAreaBounds.zero
            for index in 1..<points.count {
                result = result.adding(linearContribution(
                    from: SurfaceParameter(
                        u: points[index - 1].u + uShift,
                        v: points[index - 1].v
                    ),
                    to: SurfaceParameter(
                        u: points[index].u + uShift,
                        v: points[index].v
                    )
                ))
            }
            return result
        case let .bSpline(spline):
            return try bSplineBounds(
                for: spline,
                uShift: uShift,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .certifiedImplicit(certified):
            return try certifiedImplicitBounds(
                for: certified,
                uShift: uShift,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(certified):
            return try CertifiedAnalyticImplicitPcurveAreaIntegrator().bounds(
                for: certified,
                uShift: uShift,
                tolerance: tolerance
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return try SphericalGreatCirclePcurveAreaIntegrator().bounds(
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter,
                uShift: uShift,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(certified):
            return try CertifiedAnalyticPairPcurveAreaIntegrator().bounds(
                for: certified,
                uShift: uShift,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        case let .projectedAnalytic(projected):
            let bounds = try CertifiedAnalyticPcurveFluxIntegrator()
                .projectedParameterAreaBounds(
                    for: projected,
                    uShift: uShift,
                    requestedWidth: requestedWidth,
                    tolerance: tolerance
                )
            return SurfaceParameterAreaBounds(
                lower: bounds.lower,
                upper: bounds.upper
            )
        }
    }

    private func certifiedImplicitBounds(
        for curve: CertifiedImplicitSurfaceParameterCurve,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        try curve.intersection.validate(tolerance: tolerance)
        let selectedU: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstU
            : .secondU
        let selectedV: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstV
            : .secondV
        guard curve.intersection.cells.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified implicit pcurve area requires at least one graph cell."
            )
        }
        let ascendingStart = min(curve.startFraction, curve.endFraction)
        let ascendingEnd = max(curve.startFraction, curve.endFraction)
        let cellCount = curve.intersection.cells.count
        var result = SurfaceParameterAreaBounds.zero
        for (index, cell) in curve.intersection.cells.enumerated() {
            let freeCoordinate = cell.freeParameter
            let cellStart = Double(index) / Double(cellCount)
            let cellEnd = Double(index + 1) / Double(cellCount)
            let overlapStart = max(ascendingStart, cellStart)
            let overlapEnd = min(ascendingEnd, cellEnd)
            guard overlapEnd - overlapStart > tolerance.relative else {
                continue
            }
            let localStart = (overlapStart - cellStart) * Double(cellCount)
            let localEnd = (overlapEnd - cellStart) * Double(cellCount)
            let freeInterval = cell.parameterBox.interval(for: freeCoordinate)
            let freeDelta = graphFreeDeltaBounds(
                in: freeInterval,
                direction: cell.direction,
                from: localStart,
                to: localEnd
            )
            if freeCoordinate == selectedV {
                let uInterval = cell.parameterBox.interval(for: selectedU)
                result = result.adding(intervalProductBounds(
                    lower: (uInterval.lower + uShift).nextDown,
                    upper: (uInterval.upper + uShift).nextUp,
                    scalarLower: freeDelta.lower,
                    scalarUpper: freeDelta.upper
                ))
            } else if freeCoordinate == selectedU {
                let vInterval = cell.parameterBox.interval(for: selectedV)
                let startU = graphFreeValueBounds(
                    in: freeInterval,
                    direction: cell.direction,
                    at: localStart,
                    shift: uShift
                )
                let endU = graphFreeValueBounds(
                    in: freeInterval,
                    direction: cell.direction,
                    at: localEnd,
                    shift: uShift
                )
                let startV = graphDependentEndpointBounds(
                    in: cell,
                    coordinate: selectedV,
                    at: localStart
                )
                let endV = graphDependentEndpointBounds(
                    in: cell,
                    coordinate: selectedV,
                    at: localEnd
                )
                let startProduct = intervalProductBounds(
                    lower: startU.lower,
                    upper: startU.upper,
                    scalarLower: startV.lower,
                    scalarUpper: startV.upper
                )
                let endProduct = intervalProductBounds(
                    lower: endU.lower,
                    upper: endU.upper,
                    scalarLower: endV.lower,
                    scalarUpper: endV.upper
                )
                let vDu = intervalProductBounds(
                    lower: vInterval.lower,
                    upper: vInterval.upper,
                    scalarLower: freeDelta.lower,
                    scalarUpper: freeDelta.upper
                )
                result = result.adding(
                    subtracting(subtracting(endProduct, startProduct), vDu)
                )
            } else {
                let derivativeBounds = try cell.parameterDerivativeBounds(
                    firstSurface: curve.intersection.firstSurface,
                    secondSurface: curve.intersection.secondSurface,
                    tolerance: tolerance
                )
                let uInterval = cell.parameterBox.interval(for: selectedU)
                let vDerivative = derivativeBounds[selectedV.rawValue]
                let integrand = intervalProductBounds(
                    lower: (uInterval.lower + uShift).nextDown,
                    upper: (uInterval.upper + uShift).nextUp,
                    scalarLower: vDerivative.lower,
                    scalarUpper: vDerivative.upper
                )
                let fractionDelta = overlapEnd - overlapStart
                result = result.adding(intervalProductBounds(
                    lower: integrand.lower,
                    upper: integrand.upper,
                    scalarLower: fractionDelta.nextDown,
                    scalarUpper: fractionDelta.nextUp
                ))
            }
        }
        guard curve.startFraction <= curve.endFraction else {
            return SurfaceParameterAreaBounds(
                lower: (-result.upper).nextDown,
                upper: (-result.lower).nextUp
            )
        }
        return result
    }

    private func graphDependentEndpointBounds(
        in cell: CertifiedImplicitIntersectionGraphCell,
        coordinate: SurfaceIntersectionParameterCoordinate,
        at fraction: Double
    ) -> (lower: Double, upper: Double) {
        let endpointScale = max(abs(fraction), 1.0)
        let endpointTolerance = Double.ulpOfOne * endpointScale * 64.0
        let anchor: SurfaceIntersectionParameterPair?
        if abs(fraction) <= endpointTolerance {
            anchor = cell.startAnchor
        } else if abs(fraction - 1.0) <= endpointTolerance {
            anchor = cell.endAnchor
        } else {
            anchor = nil
        }
        guard let anchor else {
            let interval = cell.parameterBox.interval(for: coordinate)
            return (interval.lower, interval.upper)
        }
        let value = anchor.values[coordinate.rawValue]
        return (value.nextDown, value.nextUp)
    }

    private func graphFreeValueBounds(
        in interval: ScalarInterval,
        direction: CertifiedImplicitIntersectionDirection,
        at fraction: Double,
        shift: Double
    ) -> (lower: Double, upper: Double) {
        let directedFraction = direction == .forward ? fraction : 1.0 - fraction
        let widthLower = interval.width.nextDown
        let widthUpper = interval.width.nextUp
        let fractionLower = directedFraction.nextDown
        let fractionUpper = directedFraction.nextUp
        let products = [
            widthLower * fractionLower,
            widthLower * fractionUpper,
            widthUpper * fractionLower,
            widthUpper * fractionUpper,
        ]
        let productLower = (products.min() ?? -.infinity).nextDown
        let productUpper = (products.max() ?? .infinity).nextUp
        let unshiftedLower = (interval.lower + productLower).nextDown
        let unshiftedUpper = (interval.lower + productUpper).nextUp
        return (
            (unshiftedLower + shift).nextDown,
            (unshiftedUpper + shift).nextUp
        )
    }

    private func graphFreeDeltaBounds(
        in interval: ScalarInterval,
        direction: CertifiedImplicitIntersectionDirection,
        from startFraction: Double,
        to endFraction: Double
    ) -> (lower: Double, upper: Double) {
        let widthLower = interval.width.nextDown
        let widthUpper = interval.width.nextUp
        let fractionDelta = endFraction - startFraction
        let fractionLower = fractionDelta.nextDown
        let fractionUpper = fractionDelta.nextUp
        let products = [
            widthLower * fractionLower,
            widthLower * fractionUpper,
            widthUpper * fractionLower,
            widthUpper * fractionUpper,
        ]
        let positiveLower = (products.min() ?? -.infinity).nextDown
        let positiveUpper = (products.max() ?? .infinity).nextUp
        guard direction == .reversed else {
            return (positiveLower, positiveUpper)
        }
        return ((-positiveUpper).nextDown, (-positiveLower).nextUp)
    }

    private func intervalProductBounds(
        lower: Double,
        upper: Double,
        scalarLower: Double,
        scalarUpper: Double
    ) -> SurfaceParameterAreaBounds {
        let products = [
            lower * scalarLower,
            lower * scalarUpper,
            upper * scalarLower,
            upper * scalarUpper,
        ]
        return SurfaceParameterAreaBounds(
            lower: (products.min() ?? -.infinity).nextDown,
            upper: (products.max() ?? .infinity).nextUp
        )
    }

    private func subtracting(
        _ left: SurfaceParameterAreaBounds,
        _ right: SurfaceParameterAreaBounds
    ) -> SurfaceParameterAreaBounds {
        SurfaceParameterAreaBounds(
            lower: (left.lower - right.upper).nextDown,
            upper: (left.upper - right.lower).nextUp
        )
    }

    private func bSplineBounds(
        for curve: BSplineCurve2D,
        uShift: Double,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        let patches = try curve.rationalBezierPatches(tolerance: tolerance)
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "B-spline pcurve area integration produced no Bezier spans."
            )
        }
        let patchWidth = requestedWidth / Double(patches.count)
        var stack = patches.map {
            WorkItem(patch: $0, requestedWidth: patchWidth, depth: 0)
        }
        var result = SurfaceParameterAreaBounds.zero
        var remainingCells = maximumCellCount
        while let item = stack.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "B-spline pcurve area integration exceeded its cell budget."
                )
            }
            remainingCells -= 1
            let enclosure = try bezierContributionBounds(
                item.patch,
                uShift: uShift,
                tolerance: tolerance
            )
            if enclosure.width <= item.requestedWidth {
                result = result.adding(enclosure)
                continue
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: enclosure.width,
                    tolerance: tolerance,
                    message: "B-spline pcurve area integration exceeded its subdivision depth."
                )
            }
            let children = try item.patch.subdivided(tolerance: tolerance)
            let childWidth = item.requestedWidth * 0.5
            for child in children.reversed() {
                stack.append(WorkItem(
                    patch: child,
                    requestedWidth: childWidth,
                    depth: item.depth + 1
                ))
            }
        }
        return result
    }

    private func bezierContributionBounds(
        _ patch: RationalBezierCurvePatch2D,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        guard patch.degree >= 1,
              patch.controlPoints.count == patch.weights.count,
              patch.weights.allSatisfy({ $0.isFinite && $0 > Double.ulpOfOne }),
              let start = patch.controlPoints.first,
              let end = patch.controlPoints.last else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline pcurve area integration requires a positive-weight Bezier span."
            )
        }
        if patch.degree == 1 {
            return linearContribution(
                from: SurfaceParameter(u: start.x + uShift, v: start.y),
                to: SurfaceParameter(u: end.x + uShift, v: end.y)
            )
        }
        let startParameter = SurfaceParameter(
            u: start.x + uShift,
            v: start.y
        )
        let endParameter = SurfaceParameter(
            u: end.x + uShift,
            v: end.y
        )
        let deviationU = try chordDeviationUpperBound(
            patch,
            coordinate: \Point2D.x,
            tolerance: tolerance
        )
        let deviationV = try chordDeviationUpperBound(
            patch,
            coordinate: \Point2D.y,
            tolerance: tolerance
        )
        let variationV = try verticalVariationUpperBound(
            patch,
            tolerance: tolerance
        )
        let deltaU = end.x - start.x
        let deltaV = end.y - start.y
        let central = linearContribution(
            from: startParameter,
            to: endParameter
        )
        let error = (
            deviationU * (2.0 * abs(deltaV) + variationV)
                + abs(deltaU) * deviationV
        ).nextUp
        return SurfaceParameterAreaBounds(
            lower: (central.lower - error).nextDown,
            upper: (central.upper + error).nextUp
        )
    }

    private func chordDeviationUpperBound(
        _ patch: RationalBezierCurvePatch2D,
        coordinate: KeyPath<Point2D, Double>,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let first = patch.controlPoints.first,
              let last = patch.controlPoints.last,
              let minimumWeight = patch.weights.min(),
              minimumWeight > Double.ulpOfOne else {
            throw KernelError(
                phase: .topology,
                code: .singularSystem,
                tolerance: tolerance,
                message: "B-spline chord deviation encountered a singular rational denominator."
            )
        }
        let degree = patch.degree
        let denominator = Double(degree + 1)
        var maximumHomogeneousDeviation = 0.0
        for index in 0...(degree + 1) {
            let alpha = Double(index) / denominator
            var coefficient = 0.0
            if index <= degree {
                coefficient += (1.0 - alpha) * patch.weights[index]
                    * (patch.controlPoints[index][keyPath: coordinate]
                        - first[keyPath: coordinate])
            }
            if index > 0 {
                coefficient += alpha * patch.weights[index - 1]
                    * (patch.controlPoints[index - 1][keyPath: coordinate]
                        - last[keyPath: coordinate])
            }
            maximumHomogeneousDeviation = max(
                maximumHomogeneousDeviation,
                abs(coefficient).nextUp
            )
        }
        let result = (maximumHomogeneousDeviation / minimumWeight).nextUp
        guard result.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "B-spline chord deviation exceeded finite rational arithmetic."
            )
        }
        return result
    }

    private func verticalVariationUpperBound(
        _ patch: RationalBezierCurvePatch2D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let degree = Double(patch.degree)
        let homogeneousV = patch.controlPoints.indices.map {
            patch.controlPoints[$0].y * patch.weights[$0]
        }
        guard let minimumWeight = patch.weights.min(),
              let maximumWeight = patch.weights.max(),
              let maximumV = homogeneousV.map(abs).max(),
              minimumWeight > Double.ulpOfOne else {
            throw KernelError(
                phase: .topology,
                code: .singularSystem,
                tolerance: tolerance,
                message: "B-spline pcurve area integration encountered a singular rational denominator."
            )
        }
        var maximumVDifference = 0.0
        var maximumWeightDifference = 0.0
        for index in 1..<patch.controlPoints.count {
            maximumVDifference = max(
                maximumVDifference,
                abs(homogeneousV[index] - homogeneousV[index - 1])
            )
            maximumWeightDifference = max(
                maximumWeightDifference,
                abs(patch.weights[index] - patch.weights[index - 1])
            )
        }
        let numerator = (
            degree * maximumVDifference * maximumWeight
                + maximumV * degree * maximumWeightDifference
        ).nextUp
        let denominator = (minimumWeight * minimumWeight).nextDown
        guard numerator.isFinite,
              denominator.isFinite,
              denominator > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "B-spline pcurve area bounds exceeded finite rational arithmetic."
            )
        }
        return (numerator / denominator).nextUp
    }

    private func linearContribution(
        from start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> SurfaceParameterAreaBounds {
        productBounds(
            (start.u + end.u) * 0.5,
            end.v - start.v
        )
    }

    private func harmonicContribution(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double
    ) -> SurfaceParameterAreaBounds {
        func areaPrimitive(_ parameter: Double) -> Double {
            (center.x * cosine.y - center.y * cosine.x) * cos(parameter)
                + (center.x * sine.y - center.y * sine.x) * sin(parameter)
                + (cosine.x * sine.y - cosine.y * sine.x) * parameter
        }
        func parameter(_ value: Double) -> SurfaceParameter {
            SurfaceParameter(
                u: center.x + cosine.x * cos(value) + sine.x * sin(value),
                v: center.y + cosine.y * cos(value) + sine.y * sin(value)
            )
        }
        let start = parameter(startParameter)
        let end = parameter(endParameter)
        let orientedArea = 0.5 * (
            areaPrimitive(endParameter) - areaPrimitive(startParameter)
        )
        let endpointTerm = 0.5 * (end.u * end.v - start.u * start.v)
        let value = orientedArea + endpointTerm
        let scale = max(
            abs(value),
            abs(orientedArea),
            abs(endpointTerm),
            1.0
        )
        let roundoff = scale * Double.ulpOfOne * 1_024.0
        return SurfaceParameterAreaBounds(
            lower: (value - roundoff).nextDown,
            upper: (value + roundoff).nextUp
        )
    }

    private func productBounds(
        _ first: Double,
        _ second: Double
    ) -> SurfaceParameterAreaBounds {
        let value = first * second
        let scale = max(abs(value), Double.leastNormalMagnitude)
        let roundoff = scale * Double.ulpOfOne * 8.0
        return SurfaceParameterAreaBounds(
            lower: (value - roundoff).nextDown,
            upper: (value + roundoff).nextUp
        )
    }
}
