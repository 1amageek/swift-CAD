import CADCore
import Foundation

struct CurveParameterThirdOrderDerivatives: Sendable {
    let position: Point3D
    let firstDerivative: Vector3D
    let secondDerivative: Vector3D
    let thirdDerivative: Vector3D
}

extension Curve3D {
    func parameterDerivativesThroughThirdOrder(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterThirdOrderDerivatives {
        try validate(tolerance: tolerance)
        guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(parameter)
        }
        let lower = try differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let third: Vector3D
        switch self {
        case .line, .analytic(.line), .analytic(.parabola):
            third = .zero
        case .circle,
             .analytic(.circle),
             .analytic(.arc),
             .analytic(.ellipse):
            third = -lower.firstDerivative
        case .analytic(.hyperbola):
            third = lower.firstDerivative
        case let .analytic(.planeTorus(curve)):
            third = try curve.thirdDerivative(
                at: parameter,
                tolerance: tolerance
            )
        case let .implicit(curve):
            third = try curve.thirdDerivative(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .certifiedIntersection(curve):
            third = try curve.thirdDerivative(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            third = try curve.thirdDerivative(
                at: parameter,
                tolerance: tolerance
            )
        case let .surfaceLift(lift):
            third = try lift.thirdDerivative(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .rigidImage(image):
            third = image.transform.applying(to: try image.source
                .parameterDerivativesThroughThirdOrder(
                    at: parameter,
                    tolerance: tolerance
                ).thirdDerivative)
        case let .affineImage(image):
            third = image.transform.applying(to: try image.source
                .parameterDerivativesThroughThirdOrder(
                    at: parameter,
                    tolerance: tolerance
                ).thirdDerivative)
        }
        return CurveParameterThirdOrderDerivatives(
            position: lower.position,
            firstDerivative: lower.firstDerivative,
            secondDerivative: lower.secondDerivative,
            thirdDerivative: third
        )
    }

}

private extension CertifiedIntersectionCurve3D {
    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        switch self {
        case let .coneTorus(curve):
            return try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCone(curve):
            return try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCone(curve):
            return try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            return try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .parallelTorusTorus(curve):
            return try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
    }
}

private extension BSplineCurve3D {
    struct HomogeneousDerivative {
        let vector: Vector3D
        let weight: Double
    }

    func thirdDerivative(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let clamped = BSplineBasis.clampedParameter(
            parameter,
            knots: knots,
            degree: degree
        )
        let basis = (0...3).map { order in
            BSplineBasis.derivativeValues(
                parameter: clamped,
                degree: degree,
                derivativeOrder: order,
                knots: knots,
                count: controlPointCount
            )
        }
        let homogeneous = basis.map { values -> HomogeneousDerivative in
            var vector = Vector3D.zero
            var weight = 0.0
            for index in controlPoints.indices {
                let coefficient = values[index] * weights[index]
                vector = vector + Vector3D(
                    x: controlPoints[index].x,
                    y: controlPoints[index].y,
                    z: controlPoints[index].z
                ) * coefficient
                weight += values[index] * weights[index]
            }
            return HomogeneousDerivative(vector: vector, weight: weight)
        }
        guard homogeneous[0].weight.isFinite,
              homogeneous[0].weight > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: homogeneous[0].weight,
                tolerance: tolerance,
                message: "Rational B-spline third differentiation requires a positive finite weight."
            )
        }
        var euclidean: [Vector3D] = []
        for order in 0...3 {
            var numerator = homogeneous[order].vector
            if order > 0 {
                for weightOrder in 1...order {
                    numerator = numerator - euclidean[order - weightOrder]
                        * (Double(curveBinomial(order, weightOrder))
                            * homogeneous[weightOrder].weight)
                }
            }
            euclidean.append(numerator / homogeneous[0].weight)
        }
        guard euclidean[3].isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline third differentiation exceeded finite arithmetic."
            )
        }
        return euclidean[3]
    }
}

extension SurfaceLiftCurve3D {
    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        if let exactBSplineImage {
            return try exactBSplineImage.thirdDerivative(
                at: fraction,
                tolerance: tolerance
            )
        }
        if case let .certifiedAnalyticPair(curve) = parameterCurve {
            return try curve.modelSpaceThirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        let parameter = try parameterCurve.thirdOrderDifferential(
            atNormalizedFraction: fraction,
            on: surface,
            tolerance: tolerance
        )
        let surfaceDerivatives = try surface.parameterDerivativesThroughThirdOrder(
            atU: parameter.parameter.u,
            v: parameter.parameter.v,
            tolerance: tolerance
        )
        return SurfaceParameterThirdOrderChainRule.thirdDerivative(
            surface: surfaceDerivatives,
            firstParameterDerivative: parameter.firstDerivative,
            secondParameterDerivative: parameter.secondDerivative,
            thirdParameterDerivative: parameter.thirdDerivative
        )
    }
}

private extension SurfaceParameterCurve {
    func thirdOrderDifferential(
        atNormalizedFraction fraction: Double,
        on supportSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveThirdOrderDifferential {
        let lower = try differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let third: Point2D
        switch self {
        case .affine, .constantU, .constantV, .polyline:
            third = Point2D(x: 0.0, y: 0.0)
        case let .harmonic(_, _, _, startParameter, endParameter):
            let span = endParameter - startParameter
            third = Point2D(
                x: -lower.firstDerivative.x * span * span,
                y: -lower.firstDerivative.y * span * span
            )
        case let .bSpline(curve):
            third = try curve.normalizedThirdDerivative(
                atFraction: fraction,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, _, _):
            return try base.thirdOrderDifferential(
                atNormalizedFraction: fraction,
                on: supportSurface,
                tolerance: tolerance
            )
        case let .certifiedImplicit(curve):
            let mapped = curve.startFraction
                + (curve.endFraction - curve.startFraction)
                    * min(max(fraction, 0.0), 1.0)
            let canonical = curve.intersection.isClosed && mapped > 1.0
                ? mapped - 1.0
                : mapped
            let source = try curve.intersection.differential(
                atNormalizedFraction: canonical,
                tolerance: tolerance
            )
            let derivative = curve.role == .first
                ? source.thirdParameterDerivatives.first
                : source.thirdParameterDerivatives.second
            let scale = curve.endFraction - curve.startFraction
            third = Point2D(
                x: derivative.u * scale * scale * scale,
                y: derivative.v * scale * scale * scale
            )
        case let .sphericalGreatCircle(cosine, sine, start, end):
            guard case let .analytic(.sphere(_, radius)) = supportSurface else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A spherical great-circle pcurve requires its spherical support surface."
                )
            }
            let span = end - start
            let angle = start + span * min(max(fraction, 0.0), 1.0)
            let radialFirst = (
                cosine * -sin(angle) + sine * cos(angle)
            ) * span
            let spatialThird = radialFirst * (-radius * span * span)
            let surface = try supportSurface.parameterDerivativesThroughThirdOrder(
                atU: lower.parameter.u,
                v: lower.parameter.v,
                tolerance: tolerance
            )
            third = try SurfaceParameterThirdDerivativeSolver().solve(
                surface: surface,
                firstParameterDerivative: lower.firstDerivative,
                secondParameterDerivative: lower.secondDerivative,
                spatialThirdDerivative: spatialThird,
                tolerance: tolerance,
                diagnosticContext: "Spherical great-circle pcurve"
            )
        case let .certifiedAnalyticImplicit(curve):
            third = try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .projectedAnalytic(curve):
            third = try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            third = try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(curve):
            return try curve.source.thirdOrderDifferential(
                atNormalizedFraction: fraction,
                on: curve.sourceSurface,
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(curve):
            third = try curve.thirdDerivative(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        return SurfaceParameterCurveThirdOrderDifferential(
            parameter: lower.parameter,
            firstDerivative: lower.firstDerivative,
            secondDerivative: lower.secondDerivative,
            thirdDerivative: third
        )
    }

}

private extension BSplineCurve2D {
    func normalizedThirdDerivative(
        atFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        guard case let .closed(lower, upper) = domain else {
            throw GeometryError.invalidDistance(fraction)
        }
        let span = upper - lower
        let parameter = lower + span * min(max(fraction, 0.0), 1.0)
        let embedded = BSplineCurve3D(
            degree: degree,
            knots: knots,
            controlPoints: controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: weights
        )
        let derivative = try embedded.thirdDerivative(
            at: parameter,
            tolerance: tolerance
        ) * (span * span * span)
        return Point2D(x: derivative.x, y: derivative.y)
    }
}

private func curveBinomial(_ n: Int, _ k: Int) -> Int {
    guard k >= 0, k <= n else { return 0 }
    if k == 0 || k == n { return 1 }
    if n == 2 { return 2 }
    if n == 3, k == 1 || k == 2 { return 3 }
    return 1
}
