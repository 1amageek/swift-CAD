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
        let curveSecondDerivative = try curveSecondDerivativeUpperBound(
            curve,
            tolerance: tolerance
        )
        let liftSecondDerivative = try liftSecondDerivativeUpperBound(
            surface: surface,
            parameterBounds: parameterBounds,
            tolerance: tolerance
        )
        let parameterRange = try ScalarInterval(
            lower: min(startCurveParameter, endCurveParameter),
            upper: max(startCurveParameter, endCurveParameter)
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
        var remainingCells = options.maximumCellCount
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Curve-surface correspondence validation exceeded its cell budget."
                )
            }
            remainingCells -= 1
            if try cellIsCertified(
                cell,
                curve: curve,
                surface: surface,
                parameterCurve: parameterCurve,
                curveSecondDerivativeUpperBound: curveSecondDerivative,
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
            guard lift.surface == surface,
                  expectedParameterCurve == parameterCurve else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A surface-lift edge changed its source surface or oriented pcurve."
                )
            }
            return true
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
            let scale = 2.0 * Double.pi
            guard curve == certified.intersection.curve,
                  abs(startCurveParameter - certified.startFraction * scale) <= tolerance.angle,
                  abs(endCurveParameter - certified.endFraction * scale) <= tolerance.angle else {
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
        case .line, .analytic, .bSpline, .implicit, .surfaceLift:
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
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A B-spline pcurve on an affine bilinear B-spline surface does not reproduce its exact 3D edge."
            )
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
        let lifted = try lift.differentialGeometry(
            atNormalizedFraction: middleFraction,
            tolerance: tolerance
        )
        let curveGeometry = try curve.differentialGeometry(
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
        return upperBound <= tolerance.distance
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
        case .analytic(.hyperbola), .analytic(.parabola), .analytic(.planeTorus),
             .implicit, .surfaceLift:
            throw unsupported(
                tolerance: tolerance,
                message: "The exact 3D curve requires a structural curve-surface certificate."
            )
        }
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

    private func unsupported(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
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
