import CADCore

public struct ProjectedAnalyticSurfaceParameterCurve: Codable, Hashable, Sendable {
    public let curve: Curve3D
    public let surface: Surface3D
    public let startParameter: Double
    public let endParameter: Double
    public let certificationTolerance: ModelingTolerance

    public init(
        curve: Curve3D,
        surface: Surface3D,
        startParameter: Double,
        endParameter: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.curve = curve
        self.surface = surface
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.certificationTolerance = tolerance
        try validate(on: surface, tolerance: tolerance)
    }

    public func validate(
        on requestedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        let hasSupportedCurve: Bool
        switch curve {
        case .analytic(.hyperbola), .analytic(.parabola):
            hasSupportedCurve = true
        case .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .rigidImage, .affineImage:
            hasSupportedCurve = false
        }
        let hasSupportedSurface: Bool
        switch surface {
        case .plane, .analytic(.plane), .analytic(.cone):
            hasSupportedSurface = true
        case .cylinder, .analytic, .bSpline, .procedural:
            hasSupportedSurface = false
        }
        guard requestedSurface == surface,
              startParameter.isFinite,
              endParameter.isFinite,
              abs(endParameter - startParameter) > tolerance.relative,
              hasSupportedCurve,
              hasSupportedSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A projected analytic pcurve requires a hyperbola or parabola on its exact plane or cone support and a finite verification interval."
            )
        }
        for parameter in [
            startParameter,
            startParameter + (endParameter - startParameter) * 0.5,
            endParameter,
        ] {
            _ = try self.parameter(atCurveParameter: parameter, tolerance: tolerance)
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let boundedFraction = min(max(fraction, 0.0), 1.0)
        return try parameter(
            atCurveParameter: startParameter
                + (endParameter - startParameter) * boundedFraction,
            tolerance: tolerance
        )
    }

    public func parameter(
        atCurveParameter parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        guard case .analytic(.cone) = surface else {
            return SurfaceParameter(u: projection.u, v: projection.v)
        }
        let middleParameter = startParameter + (endParameter - startParameter) * 0.5
        let middlePoint = try curve.point(at: middleParameter, tolerance: tolerance)
        let middleProjection = try surface.parameterProjection(
            of: middlePoint,
            tolerance: tolerance
        )
        return SurfaceParameter(
            u: Self.unwrappedAngle(projection.u, nearest: middleProjection.u),
            v: projection.v
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let span = endParameter - startParameter
        let boundedFraction = min(max(fraction, 0.0), 1.0)
        let parameter = startParameter + span * boundedFraction
        let result = try differential(
            atCurveParameter: parameter,
            tolerance: tolerance
        )
        return SurfaceParameterCurveDifferential(
            parameter: result.parameter,
            firstDerivative: Point2D(
                x: result.firstDerivative.x * span,
                y: result.firstDerivative.y * span
            ),
            secondDerivative: Point2D(
                x: result.secondDerivative.x * span * span,
                y: result.secondDerivative.y * span * span
            )
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let span = endParameter - startParameter
        let boundedFraction = min(max(fraction, 0.0), 1.0)
        let parameter = startParameter + span * boundedFraction
        let lower = try differential(
            atNormalizedFraction: boundedFraction,
            tolerance: tolerance
        )
        let spatialThird = try curve.parameterDerivativesThroughThirdOrder(
            at: parameter,
            tolerance: tolerance
        ).thirdDerivative * (span * span * span)
        let surfaceDerivatives = try surface.parameterDerivativesThroughThirdOrder(
            atU: lower.parameter.u,
            v: lower.parameter.v,
            tolerance: tolerance
        )
        return try SurfaceParameterThirdDerivativeSolver().solve(
            surface: surfaceDerivatives,
            firstParameterDerivative: lower.firstDerivative,
            secondParameterDerivative: lower.secondDerivative,
            spatialThirdDerivative: spatialThird,
            tolerance: tolerance,
            diagnosticContext: "Analytic projected pcurve"
        )
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> ProjectedAnalyticSurfaceParameterCurve {
        try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: endParameter,
            endParameter: startParameter,
            tolerance: tolerance
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> ProjectedAnalyticSurfaceParameterCurve {
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > tolerance.relative else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        let span = endParameter - startParameter
        return try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: startParameter + span * min(max(lower, 0.0), 1.0),
            endParameter: startParameter + span * min(max(upper, 0.0), 1.0),
            tolerance: tolerance
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> ProjectedAnalyticSurfaceParameterCurve {
        try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: startParameter,
            endParameter: endParameter,
            tolerance: tolerance
        )
    }

    private func differential(
        atCurveParameter parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        let surfaceParameter = try self.parameter(
            atCurveParameter: parameter,
            tolerance: tolerance
        )
        let curveDifferential = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let surfaceDifferential = try surface.differentialGeometry(
            atU: surfaceParameter.u,
            v: surfaceParameter.v,
            tolerance: tolerance
        )
        let tangentU = surfaceDifferential.tangentU
        let tangentV = surfaceDifferential.tangentV
        let metricUU = tangentU.dot(tangentU)
        let metricUV = tangentU.dot(tangentV)
        let metricVV = tangentV.dot(tangentV)
        let determinant = metricUU * metricVV - metricUV * metricUV
        let determinantFloor = max(
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 1_024.0
        ) * max(metricUU * metricVV, Double.leastNonzeroMagnitude)
        guard determinant.isFinite, determinant > determinantFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An analytic projected pcurve differential is singular."
            )
        }
        let spatialDerivative = curveDifferential.firstDerivative
        let rightU = tangentU.dot(spatialDerivative)
        let rightV = tangentV.dot(spatialDerivative)
        let derivativeU = (rightU * metricVV - rightV * metricUV) / determinant
        let derivativeV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructed = tangentU * derivativeU + tangentV * derivativeV
        let residual = (reconstructed - spatialDerivative).length
            / max(spatialDerivative.length, 1.0)
        guard residual <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "An analytic projected pcurve failed tangent reconstruction."
            )
        }
        let secondDerivative = try SurfaceParameterSecondDerivativeSolver().solve(
            surface: surfaceDifferential,
            firstParameterDerivative: Point2D(x: derivativeU, y: derivativeV),
            spatialSecondDerivative: curveDifferential.secondDerivative,
            tolerance: tolerance,
            diagnosticContext: "Analytic projected pcurve"
        )
        return SurfaceParameterCurveDifferential(
            parameter: surfaceParameter,
            firstDerivative: Point2D(x: derivativeU, y: derivativeV),
            secondDerivative: secondDerivative
        )
    }

    private enum CodingKeys: String, CodingKey {
        case curve
        case surface
        case startParameter
        case endParameter
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.curve, .surface, .startParameter, .endParameter, .certificationTolerance],
            in: decoder
        )
        let curve = try container.decode(Curve3D.self, forKey: .curve)
        let surface = try container.decode(Surface3D.self, forKey: .surface)
        let certificationTolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        try self.init(
            curve: curve,
            surface: surface,
            startParameter: container.decode(Double.self, forKey: .startParameter),
            endParameter: container.decode(Double.self, forKey: .endParameter),
            tolerance: certificationTolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(on: surface, tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(surface, forKey: .surface)
        try container.encode(startParameter, forKey: .startParameter)
        try container.encode(endParameter, forKey: .endParameter)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }

    private static func unwrappedAngle(_ angle: Double, nearest reference: Double) -> Double {
        let period = 2.0 * Double.pi
        return angle + period * ((reference - angle) / period).rounded()
    }
}
