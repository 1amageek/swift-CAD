import Foundation
import CADCore

public struct DefaultCurveSurfaceCorrespondenceValidator: CurveSurfaceCorrespondenceValidating {
    private struct Node {
        let fraction: Double
        let curveParameter: Double
    }

    private struct Cell {
        let lower: Node
        let upper: Node
        let depth: Int
    }

    private struct ParameterDerivativeBounds {
        let firstU: Double
        let firstV: Double
        let secondU: Double
        let secondV: Double
        let vAbsolute: Double
        let breaks: [Double]
    }

    private struct HomogeneousCurveControl {
        static let zero = HomogeneousCurveControl(
            weightedPoint: .zero,
            weight: 0.0
        )

        let weightedPoint: Vector3D
        let weight: Double

        init(point: Point3D, weight: Double) {
            weightedPoint = Vector3D(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight
            )
            self.weight = weight
        }

        init(weightedPoint: Vector3D, weight: Double) {
            self.weightedPoint = weightedPoint
            self.weight = weight
        }

        func scaled(by scalar: Double) -> HomogeneousCurveControl {
            HomogeneousCurveControl(
                weightedPoint: weightedPoint * scalar,
                weight: weight * scalar
            )
        }

        func adding(_ other: HomogeneousCurveControl) -> HomogeneousCurveControl {
            HomogeneousCurveControl(
                weightedPoint: weightedPoint + other.weightedPoint,
                weight: weight + other.weight
            )
        }
    }

    public init() {}

    public func validate(
        curve: Curve3D,
        from startCurveParameter: Double,
        to endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance
    ) throws {
        try options.validate(tolerance: tolerance)
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        try parameterCurve.validate(on: surface, tolerance: tolerance)
        if case let .periodicTranslation(base, _, _) = parameterCurve {
            try validate(
                curve: curve,
                from: startCurveParameter,
                to: endCurveParameter,
                surface: surface,
                parameterCurve: base,
                options: options,
                tolerance: tolerance
            )
            return
        }
        guard startCurveParameter.isFinite,
              endCurveParameter.isFinite,
              abs(endCurveParameter - startCurveParameter) > tolerance.relative else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "Curve-surface correspondence requires a finite non-degenerate curve span."
            )
        }
        if try validateStructuralCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return
        }
        let parameterBounds = try derivativeBounds(
            for: parameterCurve,
            surface: surface,
            tolerance: tolerance
        )
        let parameterRange = try ScalarInterval(
            lower: min(startCurveParameter, endCurveParameter),
            upper: max(startCurveParameter, endCurveParameter)
        )
        let curveSecondDerivative = try curveSecondDerivativeUpperBound(
            curve,
            parameterRange: parameterRange,
            tolerance: tolerance
        )
        let liftSecondDerivative = try liftSecondDerivativeUpperBound(
            surface: surface,
            parameterBounds: parameterBounds,
            tolerance: tolerance
        )
        let projectionOptions = CurveParameterProjectionOptions(
            parameterRange: parameterRange
        )
        let initialFractions = ([0.0] + parameterBounds.breaks + [1.0])
            .filter { $0 >= 0.0 && $0 <= 1.0 }
            .sorted()
        var nodes: [Node] = []
        nodes.reserveCapacity(initialFractions.count)
        for (index, fraction) in initialFractions.enumerated() {
            if index == 0 {
                nodes.append(Node(
                    fraction: fraction,
                    curveParameter: startCurveParameter
                ))
            } else if index + 1 == initialFractions.count {
                nodes.append(Node(
                    fraction: fraction,
                    curveParameter: endCurveParameter
                ))
            } else {
                nodes.append(try projectedNode(
                    fraction: fraction,
                    candidateCurveParameter: startCurveParameter
                        + (endCurveParameter - startCurveParameter) * fraction,
                    curve: curve,
                    surface: surface,
                    parameterCurve: parameterCurve,
                    projectionOptions: projectionOptions,
                    tolerance: tolerance
                ))
            }
        }
        try validateMonotone(nodes, tolerance: tolerance)
        var stack: [Cell] = []
        for index in 1..<nodes.count {
            stack.append(Cell(lower: nodes[index - 1], upper: nodes[index], depth: 0))
        }
        // A curvature spike anywhere in the span inflates the global curve
        // bound for every cell; fixed dyadic windows refine the bound
        // locally with a bounded number of interval evaluations.
        let windowCount = 1024
        var windowBounds: [Int: Double] = [:]
        let windowLow = parameterRange.lower
        let windowSpan = parameterRange.upper - parameterRange.lower
        func localCurveSecondDerivativeBound(
            _ lower: Double,
            _ upper: Double
        ) throws -> Double {
            guard windowSpan > 0.0 else { return curveSecondDerivative }
            var lowIndex = Int(
                ((lower - windowLow) / windowSpan * Double(windowCount))
                    .rounded(.down)
            )
            var highIndex = Int(
                ((upper - windowLow) / windowSpan * Double(windowCount))
                    .rounded(.up)
            ) - 1
            lowIndex = max(0, min(windowCount - 1, lowIndex))
            highIndex = max(lowIndex, min(windowCount - 1, highIndex))
            var result = 0.0
            for index in lowIndex...highIndex {
                if let cached = windowBounds[index] {
                    result = max(result, cached)
                    continue
                }
                let bound = try self.curveSecondDerivativeUpperBound(
                    curve,
                    parameterRange: try ScalarInterval(
                        lower: windowLow + windowSpan * Double(index) / Double(windowCount),
                        upper: windowLow + windowSpan * Double(index + 1) / Double(windowCount)
                    ),
                    tolerance: tolerance
                )
                windowBounds[index] = bound
                result = max(result, bound)
            }
            return min(result, curveSecondDerivative)
        }
        var firstWindowBounds: [Int: Double?] = [:]
        func localCurveFirstDerivativeBound(
            _ lower: Double,
            _ upper: Double
        ) throws -> Double? {
            guard windowSpan > 0.0 else { return nil }
            var lowIndex = Int(
                ((lower - windowLow) / windowSpan * Double(windowCount))
                    .rounded(.down)
            )
            var highIndex = Int(
                ((upper - windowLow) / windowSpan * Double(windowCount))
                    .rounded(.up)
            ) - 1
            lowIndex = max(0, min(windowCount - 1, lowIndex))
            highIndex = max(lowIndex, min(windowCount - 1, highIndex))
            var result = 0.0
            for index in lowIndex...highIndex {
                let bound: Double?
                if let cached = firstWindowBounds[index] {
                    bound = cached
                } else {
                    bound = try self.curveFirstDerivativeUpperBound(
                        curve,
                        parameterRange: try ScalarInterval(
                            lower: windowLow + windowSpan * Double(index) / Double(windowCount),
                            upper: windowLow + windowSpan * Double(index + 1) / Double(windowCount)
                        ),
                        tolerance: tolerance
                    )
                    firstWindowBounds[index] = bound
                }
                guard let bound else { return nil }
                result = max(result, bound)
            }
            return result
        }
        var remainingCells = options.maximumCellCount
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                let lift = SurfaceLiftCurve3D(
                    surface: surface,
                    parameterCurve: parameterCurve
                )
                let middleFraction = (cell.lower.fraction + cell.upper.fraction) * 0.5
                let middleParameter = (
                    cell.lower.curveParameter + cell.upper.curveParameter
                ) * 0.5
                let liftedPosition = try lift.differentialGeometryAssumingValid(
                    atNormalizedFraction: middleFraction,
                    tolerance: tolerance
                ).position
                let curvePosition = try curve.differentialGeometryAssumingValid(
                    at: middleParameter,
                    tolerance: tolerance
                ).position
                let localBound = try self.curveSecondDerivativeUpperBound(
                    curve,
                    parameterRange: try ScalarInterval(
                        lower: min(cell.lower.curveParameter, cell.upper.curveParameter),
                        upper: max(cell.lower.curveParameter, cell.upper.curveParameter)
                    ),
                    tolerance: tolerance
                )
                let exhaustedLower = min(cell.lower.curveParameter, cell.upper.curveParameter)
                let exhaustedUpper = max(cell.lower.curveParameter, cell.upper.curveParameter)
                let windowFirst = try localCurveFirstDerivativeBound(
                    exhaustedLower,
                    exhaustedUpper
                )
                let cellFirst = exhaustedUpper > exhaustedLower
                    ? try self.curveFirstDerivativeUpperBound(
                        curve,
                        parameterRange: try ScalarInterval(
                            lower: exhaustedLower,
                            upper: exhaustedUpper
                        ),
                        tolerance: tolerance
                    )
                    : nil
                let liftedFirst = try lift.differentialGeometryAssumingValid(
                    atNormalizedFraction: middleFraction,
                    tolerance: tolerance
                ).firstDerivative
                let liftedFirstMagnitude = hypot(
                    hypot(liftedFirst.x, liftedFirst.y),
                    liftedFirst.z
                )
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Curve-surface correspondence validation exceeded its cell budget. Last cell fractions [\(cell.lower.fraction), \(cell.upper.fraction)] depth \(cell.depth) curve parameters [\(cell.lower.curveParameter), \(cell.upper.curveParameter)] midpoint deviation \((liftedPosition - curvePosition).length); curve second-derivative bound \(curveSecondDerivative), cell-local bound \(localBound), curve first-derivative window bound \(String(describing: windowFirst)), per-cell first bound \(String(describing: cellFirst)), lift first derivative at midpoint \(liftedFirstMagnitude), lift second-derivative bound \(liftSecondDerivative), parameter breaks \(parameterBounds.breaks.count)."
                )
            }
            remainingCells -= 1
            if try cellIsCertified(
                cell,
                curve: curve,
                surface: surface,
                parameterCurve: parameterCurve,
                curveSecondDerivativeUpperBound: curveSecondDerivative,
                localCurveSecondDerivativeBound: localCurveSecondDerivativeBound,
                localCurveFirstDerivativeBound: localCurveFirstDerivativeBound,
                liftSecondDerivativeUpperBound: liftSecondDerivative,
                tolerance: tolerance
            ) {
                continue
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Curve-surface correspondence validation exceeded its subdivision depth."
                )
            }
            let middleFraction = (cell.lower.fraction + cell.upper.fraction) * 0.5
            let middle = try projectedNode(
                fraction: middleFraction,
                candidateCurveParameter: (
                    cell.lower.curveParameter + cell.upper.curveParameter
                ) * 0.5,
                curve: curve,
                surface: surface,
                parameterCurve: parameterCurve,
                projectionOptions: projectionOptions,
                tolerance: tolerance
            )
            try validateMonotone(
                [cell.lower, middle, cell.upper],
                tolerance: tolerance
            )
            stack.append(Cell(lower: middle, upper: cell.upper, depth: cell.depth + 1))
            stack.append(Cell(lower: cell.lower, upper: middle, depth: cell.depth + 1))
        }
    }

    private func validateStructuralCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if case let .surfaceLift(lift) = curve {
            let lowerParameter = min(startCurveParameter, endCurveParameter)
            let upperParameter = max(startCurveParameter, endCurveParameter)
            guard try curve.parameterDomain.containsSpan(
                from: lowerParameter,
                to: upperParameter,
                tolerance: tolerance
            ) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A surface-lift edge trim is outside its normalized domain."
                )
            }
            let trimmed = try lift.parameterCurve.subcurve(
                fromNormalizedFraction: lowerParameter,
                toNormalizedFraction: upperParameter,
                tolerance: tolerance
            )
            let expectedParameterCurve = if startCurveParameter < endCurveParameter {
                trimmed
            } else {
                try trimmed.reversed(tolerance: tolerance)
            }
            if lift.surface == surface,
               expectedParameterCurve == parameterCurve {
                return true
            }
            if lift.surface == surface,
               case let .bSpline(expected) = expectedParameterCurve,
               case let .bSpline(actual) = parameterCurve,
               try bSplineCurvesHaveSameBasisAndBoundedControls(
                   embedded(expected),
                   embedded(actual),
                   tolerance: tolerance
               ) {
                return true
            }
        }
        switch parameterCurve {
        case let .certifiedImplicit(certified):
            guard curve == .implicit(certified.intersection),
                  abs(startCurveParameter - certified.startFraction) <= tolerance.relative,
                  abs(endCurveParameter - certified.endFraction) <= tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A certified implicit pcurve changed its source curve or trim."
                )
            }
            return true
        case let .certifiedAnalyticImplicit(certified):
            guard curve == .implicit(certified.intersection.implicitCurve),
                  abs(startCurveParameter - certified.startFraction) <= tolerance.relative,
                  abs(endCurveParameter - certified.endFraction) <= tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A certified analytic pcurve changed its source curve or trim."
                )
            }
            return true
        case let .certifiedAnalyticPair(certified):
            let certifiedCurve = certified.intersection.curve
            guard let expectedStart = sourceParameter(
                      forNormalizedFraction: certified.startFraction,
                      domain: certifiedCurve.parameterDomain
                  ),
                  let expectedEnd = sourceParameter(
                      forNormalizedFraction: certified.endFraction,
                      domain: certifiedCurve.parameterDomain
                  ),
                  curve == certifiedCurve,
                  abs(startCurveParameter - expectedStart) <= tolerance.angle,
                  abs(endCurveParameter - expectedEnd) <= tolerance.angle else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A certified analytic-pair pcurve changed its source curve or trim."
                )
            }
            return true
        case let .projectedAnalytic(projected):
            guard curve == projected.curve,
                  surface == projected.surface,
                  abs(startCurveParameter - projected.startParameter) <= tolerance.relative,
                  abs(endCurveParameter - projected.endParameter) <= tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "An analytic projected pcurve changed its source curve, surface, or trim."
                )
            }
            return true
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle, .polyline, .bSpline:
            break
        case .periodicTranslation:
            return false
        }
        if try validateSphericalGreatCircleCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return true
        }
        if try validateCylinderIsoparametricCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return true
        }
        if try validatePlanarHarmonicCircleCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return true
        }
        if try validateBSplineIsoparametricCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return true
        }
        if try validateBilinearBSplineAffineCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return true
        }
        if try validateAffineBilinearBSplinePcurveCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        ) {
            return true
        }
        return try validatePlanarBSplineCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance
        )
    }

    private func validateCylinderIsoparametricCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .cylinder(cylinder) = surface else { return false }
        switch parameterCurve {
        case let .constantU(u, vStart, vEnd):
            guard lineDefinition(curve) != nil else { return false }
            let startSurfacePoint = try surface.point(
                u: u,
                v: vStart,
                tolerance: tolerance
            )
            let endSurfacePoint = try surface.point(
                u: u,
                v: vEnd,
                tolerance: tolerance
            )
            let startCurvePoint = try curve.point(
                at: startCurveParameter,
                tolerance: tolerance
            )
            let endCurvePoint = try curve.point(
                at: endCurveParameter,
                tolerance: tolerance
            )
            let curveSpanVector = endCurvePoint - startCurvePoint
            let surfaceSpanVector = endSurfacePoint - startSurfacePoint
            guard startCurvePoint.isApproximatelyEqual(
                      to: startSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  endCurvePoint.isApproximatelyEqual(
                      to: endSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  (curveSpanVector - surfaceSpanVector).length
                      <= tolerance.distance,
                  abs(
                      curveSpanVector.cross(cylinder.axis).length
                  ) <= tolerance.distance * max(curveSpanVector.length, 1.0) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A constant-U cylindrical pcurve does not reproduce its exact linear generator."
                )
            }
            return true
        case let .constantV(v, uStart, uEnd):
            guard let circle = circleDefinition(curve) else { return false }
            let expectedCenter = cylinder.origin + cylinder.axis * v
            let normalAlignment = abs(circle.normal.dot(cylinder.axis))
            let curveSpan = endCurveParameter - startCurveParameter
            let parameterSpan = uEnd - uStart
            let middleCurveParameter = (startCurveParameter + endCurveParameter) * 0.5
            let middleSurfaceParameter = (uStart + uEnd) * 0.5
            let startCurvePoint = try curve.point(
                at: startCurveParameter,
                tolerance: tolerance
            )
            let middleCurvePoint = try curve.point(
                at: middleCurveParameter,
                tolerance: tolerance
            )
            let endCurvePoint = try curve.point(
                at: endCurveParameter,
                tolerance: tolerance
            )
            let startSurfacePoint = try surface.point(
                u: uStart,
                v: v,
                tolerance: tolerance
            )
            let middleSurfacePoint = try surface.point(
                u: middleSurfaceParameter,
                v: v,
                tolerance: tolerance
            )
            let endSurfacePoint = try surface.point(
                u: uEnd,
                v: v,
                tolerance: tolerance
            )
            let parameterTolerance = max(
                tolerance.angle,
                tolerance.relative * max(abs(curveSpan), abs(parameterSpan), 1.0)
            )
            guard circle.center.isApproximatelyEqual(
                      to: expectedCenter,
                      tolerance: tolerance.distance
                  ),
                  abs(circle.radius - cylinder.radius) <= tolerance.distance,
                  abs(normalAlignment - 1.0) <= tolerance.angle,
                  abs(abs(curveSpan) - abs(parameterSpan)) <= parameterTolerance,
                  startCurvePoint.isApproximatelyEqual(
                      to: startSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  middleCurvePoint.isApproximatelyEqual(
                      to: middleSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  endCurvePoint.isApproximatelyEqual(
                      to: endSurfacePoint,
                      tolerance: tolerance.distance
                  ) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A constant-V cylindrical pcurve does not reproduce its exact circular section."
                )
            }
            return true
        case .affine, .harmonic, .sphericalGreatCircle, .polyline, .bSpline,
             .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic:
            return false
        case .periodicTranslation:
            return false
        }
    }

    private func validatePlanarHarmonicCircleCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .plane(plane) = surface,
              let circle = circleDefinition(curve),
              case let .harmonic(
                  center,
                  cosine,
                  sine,
                  startParameter,
                  endParameter
              ) = parameterCurve else {
            return false
        }
        let basis = try circleOrthonormalBasis(
            plane.normal,
            tolerance: tolerance
        )
        let liftedCenter = plane.origin
            + basis.u * center.x
            + basis.v * center.y
        let liftedCosine = basis.u * cosine.x + basis.v * cosine.y
        let liftedSine = basis.u * sine.x + basis.v * sine.y
        let liftedCross = liftedCosine.cross(liftedSine)
        let liftedCrossLength = liftedCross.length
        let radialScale = liftedCosine.length * liftedSine.length
        let nondegenerateThreshold = max(
            tolerance.relative * radialScale,
            Double.ulpOfOne * radialScale * 64.0
        )
        guard liftedCrossLength > nondegenerateThreshold else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A planar harmonic pcurve has a degenerate lifted basis."
            )
        }
        let normalAlignment = abs(liftedCross.dot(circle.normal))
            / liftedCrossLength
        let curveSpan = endCurveParameter - startCurveParameter
        let harmonicSpan = endParameter - startParameter
        let startLiftedRadial = liftedCosine * cos(startParameter)
            + liftedSine * sin(startParameter)
        let startLiftedDerivative = (
            liftedCosine * -sin(startParameter)
                + liftedSine * cos(startParameter)
        ) * harmonicSpan
        let startCurveGeometry = try curve.differentialGeometry(
            at: startCurveParameter,
            tolerance: tolerance
        )
        let startCurveDerivative = startCurveGeometry.firstDerivative * curveSpan
        let derivativeScale = max(
            startLiftedDerivative.length,
            startCurveDerivative.length
        )
        let derivativeTolerance = max(
            tolerance.relative * derivativeScale,
            Double.ulpOfOne * derivativeScale * 64.0
        )
        let orthogonalityTolerance = max(
            tolerance.angle * radialScale,
            Double.ulpOfOne * radialScale * 64.0
        )
        guard liftedCenter.isApproximatelyEqual(
                  to: circle.center,
                  tolerance: tolerance.distance
              ),
              abs(liftedCosine.length - circle.radius) <= tolerance.distance,
              abs(liftedSine.length - circle.radius) <= tolerance.distance,
              abs(liftedCosine.dot(liftedSine))
                  <= orthogonalityTolerance,
              abs(normalAlignment - 1.0) <= tolerance.angle,
              abs(abs(harmonicSpan) - abs(curveSpan)) <= tolerance.angle,
              startCurveGeometry.position.isApproximatelyEqual(
                  to: liftedCenter + startLiftedRadial,
                  tolerance: tolerance.distance
              ),
              (startCurveDerivative - startLiftedDerivative).length
                  <= derivativeTolerance else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A planar harmonic pcurve does not reproduce its exact circular edge."
            )
        }
        return true
    }

    private func lineDefinition(
        _ curve: Curve3D
    ) -> (origin: Point3D, direction: Vector3D)? {
        switch curve {
        case let .line(line):
            return (line.origin, line.direction)
        case let .analytic(.line(origin, direction)):
            return (origin, direction)
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }

    private func circleDefinition(
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

    private func embedded(
        _ curve: BSplineCurve2D
    ) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: curve.weights
        )
    }

    private func sourceParameter(
        forNormalizedFraction fraction: Double,
        domain: ParameterDomain
    ) -> Double? {
        switch domain {
        case let .closed(lower, upper):
            return lower + (upper - lower) * fraction
        case let .periodic(period):
            return period * fraction
        case .unbounded:
            return nil
        }
    }

    private func validateSphericalGreatCircleCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .analytic(.sphere(center, radius)) = surface,
              case let .sphericalGreatCircle(
                  cosine,
                  sine,
                  startParameter,
                  endParameter
              ) = parameterCurve else {
            return false
        }
        let definition: (center: Point3D, normal: Vector3D, radius: Double)
        switch curve {
        case let .circle(value):
            definition = (value.center, value.normal, value.radius)
        case let .analytic(.circle(curveCenter, normal, curveRadius)),
             let .analytic(.arc(curveCenter, normal, curveRadius, _, _)):
            definition = (curveCenter, normal, curveRadius)
        case .line, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A spherical great-circle pcurve requires an exact circular edge."
            )
        }
        let parameterSpan = endParameter - startParameter
        let radial = cosine * cos(startParameter) + sine * sin(startParameter)
        let radialDerivative = (
            cosine * -sin(startParameter) + sine * cos(startParameter)
        ) * parameterSpan
        let liftedStart = center + radial * radius
        let liftedDerivative = radialDerivative * radius
        let curveStart = try curve.differentialGeometry(
            at: startCurveParameter,
            tolerance: tolerance
        )
        let curveSpan = endCurveParameter - startCurveParameter
        let curveDerivative = curveStart.firstDerivative * curveSpan
        let normal = try definition.normal.normalized(
            tolerance: tolerance.distance
        )
        let greatCircleNormal = try cosine.cross(sine).normalized(
            tolerance: tolerance.distance
        )
        let derivativeScale = max(
            max(liftedDerivative.length, curveDerivative.length),
            1.0
        )
        guard definition.center.isApproximatelyEqual(
                  to: center,
                  tolerance: tolerance.distance
              ),
              abs(definition.radius - radius) <= tolerance.distance,
              abs(abs(normal.dot(greatCircleNormal)) - 1.0) <= tolerance.angle,
              curveStart.position.isApproximatelyEqual(
                  to: liftedStart,
                  tolerance: tolerance.distance
              ),
              (curveDerivative - liftedDerivative).length
                  <= tolerance.relative * derivativeScale else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A spherical great-circle pcurve does not reproduce its circular 3D edge."
            )
        }
        return true
    }

    private func validateAffineBilinearBSplinePcurveCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .bSpline(surfaceValue) = surface,
              case let .bSpline(curveValue) = curve,
              case let .bSpline(parameterValue) = parameterCurve,
              surfaceValue.uDegree == 1,
              surfaceValue.vDegree == 1,
              surfaceValue.uControlPointCount == 2,
              surfaceValue.vControlPointCount == 2,
              isSingleBezierKnotVector(surfaceValue.uKnots, degree: 1),
              isSingleBezierKnotVector(surfaceValue.vKnots, degree: 1),
              case let .closed(uLower, uUpper) = surfaceValue.uDomain,
              case let .closed(vLower, vUpper) = surfaceValue.vDomain else {
            return false
        }
        let flatWeights = surfaceValue.weights.flatMap { $0 }
        guard let referenceWeight = flatWeights.first,
              referenceWeight.isFinite,
              referenceWeight > Double.ulpOfOne else {
            return false
        }
        let weightTolerance = max(
            tolerance.relative * abs(referenceWeight) * 16.0,
            Double.ulpOfOne * abs(referenceWeight) * 256.0
        )
        guard flatWeights.allSatisfy({
            abs($0 - referenceWeight) <= weightTolerance
        }) else {
            return false
        }
        let origin = surfaceValue.controlPoints[0][0]
        let uVector = (surfaceValue.controlPoints[0][1] - origin) / (uUpper - uLower)
        let vVector = (surfaceValue.controlPoints[1][0] - origin) / (vUpper - vLower)
        let expectedCorner = origin
            + uVector * (uUpper - uLower)
            + vVector * (vUpper - vLower)
        guard expectedCorner.isApproximatelyEqual(
            to: surfaceValue.controlPoints[1][1],
            tolerance: tolerance.distance
        ) else {
            return false
        }
        let lifted = BSplineCurve3D(
            degree: parameterValue.degree,
            knots: parameterValue.knots,
            controlPoints: parameterValue.controlPoints.map { point in
                origin
                    + uVector * (point.x - uLower)
                    + vVector * (point.y - vLower)
            },
            weights: parameterValue.weights
        )
        try lifted.validate(tolerance: tolerance)
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance
        )
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            lifted,
            tolerance: tolerance
        ) else {
            return false
        }
        return true
    }

    private func validateBilinearBSplineAffineCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .bSpline(surfaceValue) = surface,
              case let .bSpline(curveValue) = curve,
              case let .affine(
                  origin,
                  direction,
                  startParameter,
                  endParameter
              ) = parameterCurve,
              surfaceValue.uDegree == 1,
              surfaceValue.vDegree == 1,
              surfaceValue.uControlPointCount == 2,
              surfaceValue.vControlPointCount == 2,
              isSingleBezierKnotVector(surfaceValue.uKnots, degree: 1),
              isSingleBezierKnotVector(surfaceValue.vKnots, degree: 1) else {
            return false
        }
        let parameterSpan = endParameter - startParameter
        let start = Point2D(
            x: origin.x + direction.x * startParameter,
            y: origin.y + direction.y * startParameter
        )
        let end = Point2D(
            x: origin.x + direction.x * endParameter,
            y: origin.y + direction.y * endParameter
        )
        let middle = Point2D(
            x: origin.x + direction.x * (startParameter + parameterSpan * 0.5),
            y: origin.y + direction.y * (startParameter + parameterSpan * 0.5)
        )
        let startHomogeneous = try bilinearHomogeneousPoint(
            surfaceValue,
            u: start.x,
            v: start.y,
            tolerance: tolerance
        )
        let middleHomogeneous = try bilinearHomogeneousPoint(
            surfaceValue,
            u: middle.x,
            v: middle.y,
            tolerance: tolerance
        )
        let endHomogeneous = try bilinearHomogeneousPoint(
            surfaceValue,
            u: end.x,
            v: end.y,
            tolerance: tolerance
        )
        let middleControl = middleHomogeneous.scaled(by: 2.0)
            .subtracting(startHomogeneous.adding(endHomogeneous).scaled(by: 0.5))
        let homogeneousControls = [
            startHomogeneous,
            middleControl,
            endHomogeneous,
        ]
        guard homogeneousControls.allSatisfy({
            $0.weight.isFinite && $0.weight > Double.ulpOfOne
        }) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "An affine bilinear B-spline lift has a non-positive homogeneous weight."
            )
        }
        let lifted = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: homogeneousControls.map { $0.euclideanPoint },
            weights: homogeneousControls.map(\.weight)
        )
        try lifted.validate(tolerance: tolerance)
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance
        )
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            lifted,
            tolerance: tolerance
        ) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "An affine pcurve on a bilinear B-spline surface does not reproduce its exact 3D edge."
            )
        }
        return true
    }

    private func bilinearHomogeneousPoint(
        _ surface: BSplineSurface3D,
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> HomogeneousCoordinate {
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain,
              u >= uLower,
              u <= uUpper,
              v >= vLower,
              v <= vUpper else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "An affine bilinear B-spline pcurve leaves the surface domain."
            )
        }
        let normalizedU = (u - uLower) / (uUpper - uLower)
        let normalizedV = (v - vLower) / (vUpper - vLower)
        let lower = homogeneousCoordinate(
            point: surface.controlPoints[0][0],
            weight: surface.weights[0][0]
        ).interpolated(
            to: homogeneousCoordinate(
                point: surface.controlPoints[0][1],
                weight: surface.weights[0][1]
            ),
            parameter: normalizedU
        )
        let upper = homogeneousCoordinate(
            point: surface.controlPoints[1][0],
            weight: surface.weights[1][0]
        ).interpolated(
            to: homogeneousCoordinate(
                point: surface.controlPoints[1][1],
                weight: surface.weights[1][1]
            ),
            parameter: normalizedU
        )
        return lower.interpolated(to: upper, parameter: normalizedV)
    }

    private func homogeneousCoordinate(
        point: Point3D,
        weight: Double
    ) -> HomogeneousCoordinate {
        HomogeneousCoordinate(
            x: point.x * weight,
            y: point.y * weight,
            z: point.z * weight,
            weight: weight
        )
    }

    private func isSingleBezierKnotVector(
        _ knots: [Double],
        degree: Int
    ) -> Bool {
        guard knots.count == 2 * (degree + 1),
              let lower = knots.first,
              let upper = knots.last,
              upper > lower else {
            return false
        }
        return knots.prefix(degree + 1).allSatisfy { $0 == lower }
            && knots.suffix(degree + 1).allSatisfy { $0 == upper }
    }

    private func validateBSplineIsoparametricCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .bSpline(surfaceValue) = surface,
              case let .bSpline(curveValue) = curve else {
            return false
        }
        let boundary: BSplineCurve3D
        let parameterStart: Double
        let parameterEnd: Double
        switch parameterCurve {
        case let .constantU(u, vStart, vEnd):
            boundary = try surfaceValue.vIsoparametricCurve(
                atU: u,
                tolerance: tolerance
            )
            parameterStart = vStart
            parameterEnd = vEnd
        case let .constantV(v, uStart, uEnd):
            boundary = try surfaceValue.uIsoparametricCurve(
                atV: v,
                tolerance: tolerance
            )
            parameterStart = uStart
            parameterEnd = uEnd
        case .affine, .harmonic, .sphericalGreatCircle, .polyline, .bSpline,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            return false
        case .periodicTranslation:
            return false
        }
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance
        )
        let orientedBoundary = try trimmedAndOriented(
            boundary,
            from: parameterStart,
            to: parameterEnd,
            tolerance: tolerance
        )
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            orientedBoundary,
            tolerance: tolerance
        ) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A B-spline isoparametric edge does not match its exact surface boundary."
            )
        }
        return true
    }

    private func validatePlanarBSplineCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard isPlane(surface),
              case let .bSpline(curveValue) = curve,
              case let .bSpline(parameterValue) = parameterCurve else {
            return false
        }
        let lifted = BSplineCurve3D(
            degree: parameterValue.degree,
            knots: parameterValue.knots,
            controlPoints: try parameterValue.controlPoints.map { point in
                try surface.point(u: point.x, v: point.y, tolerance: tolerance)
            },
            weights: parameterValue.weights
        )
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance
        )
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            lifted,
            tolerance: tolerance
        ) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A planar B-spline pcurve does not lift to its exact 3D edge."
            )
        }
        return true
    }

    private func trimmedAndOriented(
        _ curve: BSplineCurve3D,
        from start: Double,
        to end: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        if start < end {
            return try curve.trimmed(
                from: start,
                to: end,
                tolerance: tolerance
            )
        }
        return try curve.trimmed(
            from: end,
            to: start,
            tolerance: tolerance
        ).reversed(tolerance: tolerance)
    }

    private func bSplineCurvesHaveSameBasisAndBoundedControls(
        _ lhs: BSplineCurve3D,
        _ rhs: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        var first = try normalizedCurve(lhs, tolerance: tolerance)
        var second = try normalizedCurve(rhs, tolerance: tolerance)
        if first.degree != second.degree {
            return try degreeElevatedBezierCurvesHaveBoundedControls(
                first,
                second,
                tolerance: tolerance
            )
        }
        let knotTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let interiorKnots = canonicalInteriorKnots(
            first.knots + second.knots,
            tolerance: knotTolerance
        )
        guard interiorKnots.count <= 4_096 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "B-spline correspondence exceeded its common-knot partition budget."
            )
        }
        for knot in interiorKnots {
            let targetMultiplicity = max(
                multiplicity(of: knot, in: first.knots, tolerance: knotTolerance),
                multiplicity(of: knot, in: second.knots, tolerance: knotTolerance)
            )
            while multiplicity(
                of: knot,
                in: first.knots,
                tolerance: knotTolerance
            ) < targetMultiplicity {
                first = try first.insertingKnot(knot, tolerance: tolerance)
            }
            while multiplicity(
                of: knot,
                in: second.knots,
                tolerance: knotTolerance
            ) < targetMultiplicity {
                second = try second.insertingKnot(knot, tolerance: tolerance)
            }
        }
        guard first.knots.count == second.knots.count,
              zip(first.knots, second.knots).allSatisfy({
                  abs($0 - $1) <= knotTolerance
              }),
              first.controlPoints.count == second.controlPoints.count else {
            return false
        }
        return homogeneousControlDistanceBound(first, second) <= tolerance.distance
    }

    private func degreeElevatedBezierCurvesHaveBoundedControls(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let knotTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let breakpoints = canonicalInteriorKnots(
            first.knots + second.knots,
            tolerance: knotTolerance
        )
        guard breakpoints.count <= 4_096 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "B-spline correspondence exceeded its degree-elevation partition budget."
            )
        }
        let partition = [0.0] + breakpoints + [1.0]
        let firstPatches = try bezierPatches(
            first,
            on: partition,
            tolerance: tolerance
        )
        let secondPatches = try bezierPatches(
            second,
            on: partition,
            tolerance: tolerance
        )
        guard firstPatches.count == secondPatches.count else {
            return false
        }
        let targetDegree = max(first.degree, second.degree)
        for index in firstPatches.indices {
            let firstControls = elevatedHomogeneousControls(
                firstPatches[index],
                toDegree: targetDegree
            )
            let secondControls = elevatedHomogeneousControls(
                secondPatches[index],
                toDegree: targetDegree
            )
            guard homogeneousControlDistanceBound(
                firstControls,
                secondControls
            ) <= tolerance.distance else {
                return false
            }
        }
        return true
    }

    private func bezierPatches(
        _ curve: BSplineCurve3D,
        on partition: [Double],
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch3D] {
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            tolerance: tolerance
        )
        var result: [RationalBezierCurvePatch3D] = []
        result.reserveCapacity(partition.count - 1)
        var sourceIndex = 0
        for index in 1..<partition.count {
            let lower = partition[index - 1]
            let upper = partition[index]
            while sourceIndex + 1 < sourcePatches.count,
                  sourcePatches[sourceIndex].upper <= lower {
                sourceIndex += 1
            }
            let source = sourcePatches[sourceIndex]
            guard lower >= source.lower,
                  upper <= source.upper else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "B-spline correspondence could not align its exact Bezier partitions."
                )
            }
            if lower == source.lower, upper == source.upper {
                result.append(source)
            } else {
                result.append(try source.trimmed(
                    from: lower,
                    to: upper,
                    tolerance: tolerance
                ))
            }
        }
        return result
    }

    private func elevatedHomogeneousControls(
        _ patch: RationalBezierCurvePatch3D,
        toDegree targetDegree: Int
    ) -> [HomogeneousCurveControl] {
        var result = patch.controlPoints.indices.map {
            HomogeneousCurveControl(
                point: patch.controlPoints[$0],
                weight: patch.weights[$0]
            )
        }
        while result.count - 1 < targetDegree {
            let nextDegree = result.count
            var elevated = Array(
                repeating: HomogeneousCurveControl.zero,
                count: result.count + 1
            )
            elevated[0] = result[0]
            elevated[elevated.count - 1] = result[result.count - 1]
            if result.count > 1 {
                for index in 1..<result.count {
                    let alpha = Double(index) / Double(nextDegree)
                    elevated[index] = result[index - 1].scaled(by: alpha)
                        .adding(result[index].scaled(by: 1.0 - alpha))
                }
            }
            result = elevated
        }
        return result
    }

    private func normalizedCurve(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        guard case let .closed(lower, upper) = curve.domain,
              upper > lower else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "B-spline correspondence requires a bounded nondegenerate domain."
            )
        }
        let span = upper - lower
        let normalized = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots.map { ($0 - lower) / span },
            controlPoints: curve.controlPoints,
            weights: curve.weights
        )
        try normalized.validate(tolerance: tolerance)
        return normalized
    }

    private func canonicalInteriorKnots(
        _ knots: [Double],
        tolerance: Double
    ) -> [Double] {
        var result: [Double] = []
        for knot in knots.sorted()
            where knot > tolerance && knot < 1.0 - tolerance {
            if let last = result.last, abs(last - knot) <= tolerance {
                continue
            }
            result.append(knot)
        }
        return result
    }

    private func multiplicity(
        of knot: Double,
        in knots: [Double],
        tolerance: Double
    ) -> Int {
        knots.reduce(0) { count, candidate in
            count + (abs(candidate - knot) <= tolerance ? 1 : 0)
        }
    }

    private func homogeneousControlDistanceBound(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D
    ) -> Double {
        homogeneousControlDistanceBound(
            first.controlPoints.indices.map {
                HomogeneousCurveControl(
                    point: first.controlPoints[$0],
                    weight: first.weights[$0]
                )
            },
            second.controlPoints.indices.map {
                HomogeneousCurveControl(
                    point: second.controlPoints[$0],
                    weight: second.weights[$0]
                )
            }
        )
    }

    private func homogeneousControlDistanceBound(
        _ first: [HomogeneousCurveControl],
        _ second: [HomogeneousCurveControl]
    ) -> Double {
        guard first.count == second.count,
              first.isEmpty == false,
              let firstScale = first.first?.weight,
              let secondScale = second.first?.weight,
              firstScale > 0.0,
              secondScale > 0.0 else {
            return .infinity
        }
        let firstWeights = first.map { $0.weight / firstScale }
        let secondWeights = second.map { $0.weight / secondScale }
        guard let minimumFirstWeight = firstWeights.min(),
              let minimumSecondWeight = secondWeights.min(),
              minimumFirstWeight > 0.0,
              minimumSecondWeight > 0.0 else {
            return .infinity
        }
        var maximumWeightedPointDifference = 0.0
        var maximumWeightDifference = 0.0
        var maximumSecondWeightedPointLength = 0.0
        for index in first.indices {
            let firstWeighted = first[index].weightedPoint / firstScale
            let secondWeighted = second[index].weightedPoint / secondScale
            maximumWeightedPointDifference = max(
                maximumWeightedPointDifference,
                (firstWeighted - secondWeighted).length.nextUp
            )
            maximumWeightDifference = max(
                maximumWeightDifference,
                abs(firstWeights[index] - secondWeights[index]).nextUp
            )
            maximumSecondWeightedPointLength = max(
                maximumSecondWeightedPointLength,
                secondWeighted.length.nextUp
            )
        }
        return (
            maximumWeightedPointDifference / minimumFirstWeight
                + maximumSecondWeightedPointLength * maximumWeightDifference
                    / (minimumFirstWeight * minimumSecondWeight)
        ).nextUp
    }

    private func cellIsCertified(
        _ cell: Cell,
        curve: Curve3D,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        curveSecondDerivativeUpperBound: Double,
        localCurveSecondDerivativeBound: (Double, Double) throws -> Double,
        localCurveFirstDerivativeBound: (Double, Double) throws -> Double?,
        liftSecondDerivativeUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let width = cell.upper.fraction - cell.lower.fraction
        guard width > 0.0 else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "Curve-surface correspondence subdivision collapsed."
            )
        }
        let middleFraction = (cell.lower.fraction + cell.upper.fraction) * 0.5
        let middleCurveParameter = (
            cell.lower.curveParameter + cell.upper.curveParameter
        ) * 0.5
        let lift = SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: parameterCurve
        )
        let lifted = try lift.differentialGeometryAssumingValid(
            atNormalizedFraction: middleFraction,
            tolerance: tolerance
        )
        let curveGeometry = try curve.differentialGeometryAssumingValid(
            at: middleCurveParameter,
            tolerance: tolerance
        )
        let parameterSlope = (
            cell.upper.curveParameter - cell.lower.curveParameter
        ) / width
        let residual = (lifted.position - curveGeometry.position).length
        let derivativeResidual = (
            lifted.firstDerivative - curveGeometry.firstDerivative * parameterSlope
        ).length
        let halfWidth = width * 0.5
        let secondDerivativeBound = upwardSum(
            liftSecondDerivativeUpperBound,
            upwardProduct(
                curveSecondDerivativeUpperBound,
                upwardProduct(abs(parameterSlope), abs(parameterSlope))
            )
        )
        let upperBound = upwardSum(
            residual,
            upwardSum(
                upwardProduct(derivativeResidual, halfWidth),
                upwardProduct(
                    0.5,
                    upwardProduct(
                        secondDerivativeBound,
                        upwardProduct(halfWidth, halfWidth)
                    )
                )
            )
        )
        if upperBound <= tolerance.distance {
            return true
        }
        // A curvature spike anywhere in the validated span inflates the
        // global curve bound for every cell, demanding deep subdivision
        // across the whole span; a windowed local bound certifies smooth
        // cells at their actual curvature, and cells inside a spike window
        // fall through to a per-cell bound so distance from the spike pays
        // off (a flat window bound would force the spike window's entire
        // subtree to uniform depth).
        func certifies(_ curveBound: Double) -> Bool {
            let bound = upwardSum(
                liftSecondDerivativeUpperBound,
                upwardProduct(
                    curveBound,
                    upwardProduct(abs(parameterSlope), abs(parameterSlope))
                )
            )
            let localUpperBound = upwardSum(
                residual,
                upwardSum(
                    upwardProduct(derivativeResidual, halfWidth),
                    upwardProduct(
                        0.5,
                        upwardProduct(
                            bound,
                            upwardProduct(halfWidth, halfWidth)
                        )
                    )
                )
            )
            return localUpperBound <= tolerance.distance
        }
        let cellLower = min(cell.lower.curveParameter, cell.upper.curveParameter)
        let cellUpper = max(cell.lower.curveParameter, cell.upper.curveParameter)
        let windowBound = try localCurveSecondDerivativeBound(cellLower, cellUpper)
        if windowBound < curveSecondDerivativeUpperBound, certifies(windowBound) {
            return true
        }
        // The curve's second-derivative certificate can saturate at a fixed
        // partition floor near a curvature spike; a Lipschitz argument over
        // the cell needs only finite first-derivative bounds and converges
        // linearly in the cell width.
        func lipschitzCertifies(_ curveFirst: Double) -> Bool {
            let liftFirstSupremum = upwardSum(
                hypot(
                    hypot(lifted.firstDerivative.x, lifted.firstDerivative.y),
                    lifted.firstDerivative.z
                ),
                upwardProduct(liftSecondDerivativeUpperBound, halfWidth)
            )
            let lipschitzUpperBound = upwardSum(
                residual,
                upwardProduct(
                    halfWidth,
                    upwardSum(
                        liftFirstSupremum,
                        upwardProduct(curveFirst, abs(parameterSlope))
                    )
                )
            )
            return lipschitzUpperBound <= tolerance.distance
        }
        if let windowFirst = try localCurveFirstDerivativeBound(
            cellLower,
            cellUpper
        ), lipschitzCertifies(windowFirst) {
            return true
        }
        guard cellUpper > cellLower else { return false }
        let cellRange = try ScalarInterval(lower: cellLower, upper: cellUpper)
        let cellBound = try self.curveSecondDerivativeUpperBound(
            curve,
            parameterRange: cellRange,
            tolerance: tolerance
        )
        if cellBound < windowBound, certifies(cellBound) {
            return true
        }
        // Window bounds smear a spike partition across the whole window; a
        // per-cell first-derivative query resolves down to the bounder's
        // expansion floor before concluding the spike is real.
        if let cellFirst = try self.curveFirstDerivativeUpperBound(
            curve,
            parameterRange: cellRange,
            tolerance: tolerance
        ), lipschitzCertifies(cellFirst) {
            return true
        }
        return false
    }

    private func projectedNode(
        fraction: Double,
        candidateCurveParameter: Double,
        curve: Curve3D,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        projectionOptions: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Node {
        let parameter = try parameterCurve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let point = try surface.point(
            u: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        )
        if candidateCurveParameter.isFinite,
           let parameterRange = projectionOptions.parameterRange,
           parameterRange.contains(candidateCurveParameter) {
            let candidatePoint = try curve.point(
                at: candidateCurveParameter,
                tolerance: tolerance
            )
            if (candidatePoint - point).length <= tolerance.distance {
                return Node(
                    fraction: fraction,
                    curveParameter: candidateCurveParameter
                )
            }
        }
        let projection: CurveParameterProjection
        do {
            projection = try curve.parameterProjection(
                of: point,
                options: projectionOptions,
                tolerance: tolerance
            )
        } catch let error as KernelError where
            error.code == .resourceLimitExceeded
                || error.code == .ambiguousSelection
                || error.code == .singularSystem {
            throw KernelError(
                phase: .topology,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "Curve-surface correspondence projection failed: \(error.message)"
            )
        } catch {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A pcurve point has no verified projection onto its exact 3D edge."
            )
        }
        guard projection.residual <= tolerance.distance else {
            throw correspondenceFailure(
                residual: projection.residual,
                tolerance: tolerance,
                message: "A pcurve point exceeds the 3D edge tolerance."
            )
        }
        return Node(fraction: fraction, curveParameter: projection.parameter)
    }

    private func validateMonotone(
        _ nodes: [Node],
        tolerance: ModelingTolerance
    ) throws {
        guard nodes.count >= 2 else { return }
        let direction = nodes[nodes.count - 1].curveParameter
            - nodes[0].curveParameter
        guard abs(direction) > tolerance.relative else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "Curve-surface correspondence has no oriented parameter span."
            )
        }
        for index in 1..<nodes.count {
            let step = nodes[index].curveParameter - nodes[index - 1].curveParameter
            let orientedStep = direction > 0.0 ? step : -step
            guard orientedStep >= -tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A face pcurve reverses direction along its 3D edge."
                )
            }
        }
    }

    private func derivativeBounds(
        for curve: SurfaceParameterCurve,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ParameterDerivativeBounds {
        switch curve {
        case let .affine(_, direction, start, end):
            let scale = abs(end - start)
            return ParameterDerivativeBounds(
                firstU: upwardProduct(abs(direction.x), scale),
                firstV: upwardProduct(abs(direction.y), scale),
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: try maximumAbsoluteV(curve, tolerance: tolerance),
                breaks: []
            )
        case let .constantU(_, vStart, vEnd):
            return ParameterDerivativeBounds(
                firstU: 0.0,
                firstV: abs(vEnd - vStart).nextUp,
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: max(abs(vStart), abs(vEnd)).nextUp,
                breaks: []
            )
        case let .constantV(v, uStart, uEnd):
            return ParameterDerivativeBounds(
                firstU: abs(uEnd - uStart).nextUp,
                firstV: 0.0,
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: abs(v).nextUp,
                breaks: []
            )
        case let .harmonic(_, cosine, sine, start, end):
            let scale = abs(end - start)
            let scaleSquared = upwardProduct(scale, scale)
            let uAmplitude = hypot(cosine.x, sine.x).nextUp
            let vAmplitude = hypot(cosine.y, sine.y).nextUp
            return ParameterDerivativeBounds(
                firstU: upwardProduct(scale, uAmplitude),
                firstV: upwardProduct(scale, vAmplitude),
                secondU: upwardProduct(scaleSquared, uAmplitude),
                secondV: upwardProduct(scaleSquared, vAmplitude),
                vAbsolute: try maximumAbsoluteV(curve, tolerance: tolerance),
                breaks: []
            )
        case let .polyline(points):
            var totalLength = 0.0
            var lengths: [Double] = []
            for index in 1..<points.count {
                let length = hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                )
                lengths.append(length)
                totalLength = upwardSum(totalLength, length)
            }
            guard totalLength > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(totalLength)
            }
            var accumulated = 0.0
            var breaks: [Double] = []
            for length in lengths.dropLast() {
                accumulated += length
                breaks.append(accumulated / totalLength)
            }
            return ParameterDerivativeBounds(
                firstU: totalLength,
                firstV: totalLength,
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: points.map { abs($0.v) }.max()?.nextUp ?? 0.0,
                breaks: breaks
            )
        case .sphericalGreatCircle:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A spherical great-circle pcurve failed its structural circular-edge proof."
            )
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(
                tolerance: tolerance
            )
            guard case let .closed(domainLower, domainUpper) = curve.domain,
                  patches.isEmpty == false else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "B-spline pcurve correspondence requires a bounded non-empty domain."
                )
            }
            let domainWidth = domainUpper - domainLower
            var firstU = 0.0
            var firstV = 0.0
            var secondU = 0.0
            var secondV = 0.0
            var vAbsolute = 0.0
            var breaks: [Double] = []
            for (index, patch) in patches.enumerated() {
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map(\.x),
                        patch.controlPoints.map(\.y),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                firstU = max(
                    firstU,
                    upwardProduct(bound.first[0], domainWidth)
                )
                firstV = max(
                    firstV,
                    upwardProduct(bound.first[1], domainWidth)
                )
                let domainWidthSquared = upwardProduct(
                    domainWidth,
                    domainWidth
                )
                secondU = max(
                    secondU,
                    upwardProduct(bound.second[0], domainWidthSquared)
                )
                secondV = max(
                    secondV,
                    upwardProduct(bound.second[1], domainWidthSquared)
                )
                vAbsolute = max(
                    vAbsolute,
                    patch.controlPoints.map { abs($0.y) }.max()?.nextUp ?? 0.0
                )
                if index + 1 < patches.count {
                    breaks.append((patch.upper - domainLower) / domainWidth)
                }
            }
            return ParameterDerivativeBounds(
                firstU: firstU,
                firstV: firstV,
                secondU: secondU,
                secondV: secondV,
                vAbsolute: vAbsolute,
                breaks: breaks
            )
        case .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A certified pcurve failed its structural source-curve match."
            )
        case let .periodicTranslation(base, _, vShift):
            let bounds = try derivativeBounds(
                for: base,
                surface: surface,
                tolerance: tolerance
            )
            return ParameterDerivativeBounds(
                firstU: bounds.firstU,
                firstV: bounds.firstV,
                secondU: bounds.secondU,
                secondV: bounds.secondV,
                vAbsolute: (bounds.vAbsolute + abs(vShift)).nextUp,
                breaks: bounds.breaks
            )
        }
    }

    private func maximumAbsoluteV(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let start = try curve.parameter(atNormalizedFraction: 0.0, tolerance: tolerance)
        let end = try curve.parameter(atNormalizedFraction: 1.0, tolerance: tolerance)
        switch curve {
        case let .harmonic(center, cosine, sine, _, _):
            let amplitude = hypot(cosine.y, sine.y).nextUp
            return max(
                abs(center.y - amplitude),
                abs(center.y + amplitude)
            ).nextUp
        default:
            return max(abs(start.v), abs(end.v)).nextUp
        }
    }

    private func liftSecondDerivativeUpperBound(
        surface: Surface3D,
        parameterBounds: ParameterDerivativeBounds,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let uFirst = parameterBounds.firstU
        let vFirst = parameterBounds.firstV
        let uSecond = parameterBounds.secondU
        let vSecond = parameterBounds.secondV
        switch surface {
        case .plane, .analytic(.plane):
            return hypot(uSecond, vSecond).nextUp
        case let .cylinder(cylinder):
            return cylinderSecondDerivativeBound(
                radius: cylinder.radius,
                uFirst: uFirst,
                uSecond: uSecond,
                vSecond: vSecond
            )
        case let .analytic(.cylinder(_, _, radius)):
            return cylinderSecondDerivativeBound(
                radius: radius,
                uFirst: uFirst,
                uSecond: uSecond,
                vSecond: vSecond
            )
        case let .analytic(.cone(_, _, halfAngle)):
            let sine = abs(sin(halfAngle)).nextUp
            return upwardSum(
                upwardProduct(
                    upwardProduct(parameterBounds.vAbsolute, sine),
                    upwardProduct(uFirst, uFirst)
                ),
                upwardSum(
                    upwardProduct(
                        2.0,
                        upwardProduct(sine, upwardProduct(uFirst, vFirst))
                    ),
                    upwardSum(
                        upwardProduct(
                            upwardProduct(parameterBounds.vAbsolute, sine),
                            uSecond
                        ),
                        vSecond
                    )
                )
            )
        case let .analytic(.sphere(_, radius)):
            return upwardProduct(
                radius,
                upwardSum(
                    upwardSum(
                        upwardProduct(uFirst, uFirst),
                        upwardProduct(2.0, upwardProduct(uFirst, vFirst))
                    ),
                    upwardSum(
                        upwardProduct(vFirst, vFirst),
                        upwardSum(uSecond, vSecond)
                    )
                )
            )
        case let .analytic(.torus(_, _, majorRadius, minorRadius)):
            return upwardSum(
                upwardProduct(
                    majorRadius + minorRadius,
                    upwardSum(upwardProduct(uFirst, uFirst), uSecond)
                ),
                upwardProduct(
                    minorRadius,
                    upwardSum(
                        upwardProduct(2.0, upwardProduct(uFirst, vFirst)),
                        upwardSum(upwardProduct(vFirst, vFirst), vSecond)
                    )
                )
            )
        case let .bSpline(surface):
            let surfaceBounds = try CubicSurfaceResidualCertifier
                .SurfaceDerivativeBounds(
                    surface: surface,
                    tolerance: tolerance
                )
            let result = upwardSum(
                upwardSum(
                    upwardProduct(
                        surfaceBounds.secondUU,
                        upwardProduct(uFirst, uFirst)
                    ),
                    upwardProduct(
                        2.0,
                        upwardProduct(
                            surfaceBounds.secondUV,
                            upwardProduct(uFirst, vFirst)
                        )
                    )
                ),
                upwardSum(
                    upwardProduct(
                        surfaceBounds.secondVV,
                        upwardProduct(vFirst, vFirst)
                    ),
                    upwardSum(
                        upwardProduct(surfaceBounds.tangentU, uSecond),
                        upwardProduct(surfaceBounds.tangentV, vSecond)
                    )
                )
            )
            guard result.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "B-spline surface-lift derivative certification exceeded finite arithmetic."
                )
            }
            return result
        }
    }

    private func cylinderSecondDerivativeBound(
        radius: Double,
        uFirst: Double,
        uSecond: Double,
        vSecond: Double
    ) -> Double {
        upwardSum(
            upwardProduct(
                radius,
                upwardSum(upwardProduct(uFirst, uFirst), uSecond)
            ),
            vSecond
        )
    }

    private func curveSecondDerivativeUpperBound(
        _ curve: Curve3D,
        parameterRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double {
        switch curve {
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
            let maximumAbsoluteParameter = max(
                abs(parameterRange.lower),
                abs(parameterRange.upper)
            )
            let hyperbolicCosine = cosh(maximumAbsoluteParameter)
            let hyperbolicSine = sinh(maximumAbsoluteParameter)
            let bound = hypot(
                curve.transverseRadius * hyperbolicCosine,
                curve.conjugateRadius * hyperbolicSine
            )
            guard bound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Hyperbola correspondence derivative certification exceeded finite arithmetic."
                )
            }
            return bound.nextUp
        case let .analytic(.parabola(curve)):
            return (1.0 / (2.0 * curve.focalLength)).nextUp
        case let .bSpline(curve):
            let patches = try BSplineCurveBezierDecomposer().curvePatches(
                curve: curve,
                tolerance: tolerance
            )
            guard patches.isEmpty == false else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "B-spline curve correspondence requires a non-empty Bezier decomposition."
                )
            }
            var maximum = 0.0
            for patch in patches {
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
            guard let bound = try SurfaceLiftDifferentialBounder()
                .secondDerivativeMagnitude(
                    lift: lift,
                    interval: parameterRange,
                    tolerance: tolerance
                ) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "Surface-lift correspondence could not certify a finite second-derivative bound."
                )
            }
            return bound
        case .analytic(.planeTorus), .implicit, .certifiedIntersection:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "The exact 3D curve does not match a required structural curve-surface certificate."
            )
        }
    }

    // A first-derivative (Lipschitz) bound certifies cells whose
    // second-derivative certificate saturates; only surface-lift curves
    // need it, other curve kinds certify through the Taylor remainder.
    private func curveFirstDerivativeUpperBound(
        _ curve: Curve3D,
        parameterRange: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard case let .surfaceLift(lift) = curve else { return nil }
        return try SurfaceLiftDifferentialBounder().firstDerivativeMagnitude(
            lift: lift,
            interval: parameterRange,
            tolerance: tolerance
        )
    }

    private func isPlane(_ surface: Surface3D) -> Bool {
        switch surface {
        case .plane, .analytic(.plane):
            return true
        case .cylinder, .analytic, .bSpline:
            return false
        }
    }

    private func upwardSum(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs + rhs).nextUp
    }

    private func upwardProduct(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs * rhs).nextUp
    }

    private func correspondenceFailure(
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private func resourceFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }

    private struct HomogeneousCoordinate {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        var euclideanPoint: Point3D {
            Point3D(
                x: x / weight,
                y: y / weight,
                z: z / weight
            )
        }

        func adding(_ other: Self) -> Self {
            Self(
                x: x + other.x,
                y: y + other.y,
                z: z + other.z,
                weight: weight + other.weight
            )
        }

        func subtracting(_ other: Self) -> Self {
            Self(
                x: x - other.x,
                y: y - other.y,
                z: z - other.z,
                weight: weight - other.weight
            )
        }

        func scaled(by scale: Double) -> Self {
            Self(
                x: x * scale,
                y: y * scale,
                z: z * scale,
                weight: weight * scale
            )
        }

        func interpolated(to other: Self, parameter: Double) -> Self {
            scaled(by: 1.0 - parameter).adding(other.scaled(by: parameter))
        }
    }
}
