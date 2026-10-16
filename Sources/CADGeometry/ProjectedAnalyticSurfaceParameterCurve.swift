import CADCore

public struct ProjectedAnalyticSurfaceParameterCurve: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(curve: curve, surface: surface, startParameter: startParameter, endParameter: endParameter, tolerance: tolerance, using: &execution)
    }


    public init(
        curve: Curve3D,
        surface: Surface3D,
        startParameter: Double,
        endParameter: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        self.curve = curve
        self.surface = surface
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.certificationTolerance = tolerance
        try validate(on: surface, tolerance: tolerance, using: &execution)
    }

    public func validate(
        on requestedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(on: requestedSurface, tolerance: tolerance, using: &execution)
    }


    public func validate(
        on requestedSurface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        try curve.validate(tolerance: tolerance, using: &execution)
        try surface.validate(tolerance: tolerance, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: requestedSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        guard requestedSurface == surface,
              startParameter.isFinite,
              endParameter.isFinite,
              abs(endParameter - startParameter) > tolerance.relative,
              Self.supports(curve, on: surface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A projected analytic pcurve requires a hyperbola or parabola on its exact plane or cone support, or an ellipse on its cylinder or cone, and a finite verification interval."
            )
        }
        try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
        for parameter in [
            startParameter,
            startParameter + (endParameter - startParameter) * 0.5,
            endParameter,
        ] {
            try execution.consumeWork(1)
            _ = try self.parameter(atCurveParameter: parameter, tolerance: tolerance, using: &execution)
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
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
        , using: &execution)
    }

    public func parameter(
        atCurveParameter parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try self.parameter(atCurveParameter: parameter, tolerance: tolerance, using: &execution)
    }


    public func parameter(
        atCurveParameter parameter: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        let point = try curve.point(at: parameter, tolerance: tolerance, using: &execution)
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
        guard Self.isAngular(surface) else {
            return SurfaceParameter(u: projection.u, v: projection.v)
        }
        // The angle continues from the interval's middle through eighths of the way, so an arc
        // turning most of the way round stays on one sheet of the angle.
        let middleParameter = startParameter + (endParameter - startParameter) * 0.5
        var reference = try surface.parameterProjection(
            of: try curve.point(at: middleParameter, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution).u
        for step in 1..<8 {
            try execution.consumeWork(1)
            let between = middleParameter + (parameter - middleParameter) * Double(step) / 8.0
            let angle = try surface.parameterProjection(
                of: try curve.point(at: between, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution).u
            reference = Self.unwrappedAngle(angle, nearest: reference)
        }
        return SurfaceParameter(
            u: Self.unwrappedAngle(projection.u, nearest: reference),
            v: projection.v
        )
    }

    /// Whether the curve projects onto the surface exactly: a hyperbola or parabola on its plane
    /// or cone, or an ellipse (a plane's oblique section) on its cylinder or cone.
    package static func supports(_ curve: Curve3D, on surface: Surface3D) -> Bool {
        switch (curve, surface) {
        case (.analytic(.hyperbola), .plane), (.analytic(.hyperbola), .analytic(.plane)), (.analytic(.hyperbola), .analytic(.cone)),
             (.analytic(.parabola), .plane), (.analytic(.parabola), .analytic(.plane)), (.analytic(.parabola), .analytic(.cone)),
             (.analytic(.ellipse), .cylinder), (.analytic(.ellipse), .analytic(.cylinder)), (.analytic(.ellipse), .analytic(.cone)):
            return true
        default:
            return false
        }
    }

    /// Whether the surface's u is an angle about an axis, unwrapped along the curve.
    private static func isAngular(_ surface: Surface3D) -> Bool {
        switch surface {
        case .cylinder, .analytic(.cylinder), .analytic(.cone): return true
        default: return false
        }
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveDifferential {
        try execution.consumeWork(1)
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
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point2D {
        try execution.consumeWork(1)
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
        , using: &execution)
        let spatialThird = try curve.parameterDerivativesThroughThirdOrder(
            at: parameter,
            tolerance: tolerance
        , using: &execution).thirdDerivative * (span * span * span)
        let surfaceDerivatives = try surface.parameterDerivativesThroughThirdOrder(
            u: lower.parameter.u,
            v: lower.parameter.v,
            tolerance: tolerance
        , using: &execution)
        return try SurfaceParameterThirdDerivativeSolver().solve(
            surface: surfaceDerivatives,
            firstParameterDerivative: lower.firstDerivative,
            secondParameterDerivative: lower.secondDerivative,
            spatialThirdDerivative: spatialThird,
            tolerance: tolerance,
            diagnosticContext: "Analytic projected pcurve", using: &execution
        )
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> ProjectedAnalyticSurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try reversed(tolerance: tolerance, using: &execution)
    }


    public func reversed(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ProjectedAnalyticSurfaceParameterCurve {
        try execution.consumeWork(1)
        return try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: endParameter,
            endParameter: startParameter,
            tolerance: tolerance
        , using: &execution)
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> ProjectedAnalyticSurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subcurve(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
    }


    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ProjectedAnalyticSurfaceParameterCurve {
        try execution.consumeWork(1)
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
        , using: &execution)
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> ProjectedAnalyticSurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trimmed(from: startParameter, to: endParameter, tolerance: tolerance, using: &execution)
    }


    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ProjectedAnalyticSurfaceParameterCurve {
        try execution.consumeWork(1)
        return try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: startParameter,
            endParameter: endParameter,
            tolerance: tolerance
        , using: &execution)
    }

    private func differential(
        atCurveParameter parameter: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveDifferential {
        try execution.consumeWork(1)
        let surfaceParameter = try self.parameter(
            atCurveParameter: parameter,
            tolerance: tolerance
        , using: &execution)
        let curveDifferential = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        , using: &execution)
        let surfaceDifferential = try surface.differentialGeometry(
            u: surfaceParameter.u,
            v: surfaceParameter.v,
            tolerance: tolerance
        , using: &execution)
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
            diagnosticContext: "Analytic projected pcurve", using: &execution
        )
        return SurfaceParameterCurveDifferential(
            parameter: surfaceParameter,
            firstDerivative: Point2D(x: derivativeU, y: derivativeV),
            secondDerivative: secondDerivative
        )
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case curve
        case surface
        case startParameter
        case endParameter
        case certificationTolerance
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
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
            tolerance: certificationTolerance, using: &execution
        )
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(on: surface, tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(surface, forKey: .surface)
        try container.encode(startParameter, forKey: .startParameter)
        try container.encode(endParameter, forKey: .endParameter)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
#endif

    private static func unwrappedAngle(_ angle: Double, nearest reference: Double) -> Double {
        let period = 2.0 * Double.pi
        return angle + period * ((reference - angle) / period).rounded()
    }
}

#if !hasFeature(Embedded)
extension ProjectedAnalyticSurfaceParameterCurve: Codable {}
#endif
