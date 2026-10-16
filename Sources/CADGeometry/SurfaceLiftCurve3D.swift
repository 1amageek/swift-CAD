import CADCore

/// The exact model-space lift of a face-local parameter curve.
public struct SurfaceLiftCurve3D: Hashable, Sendable {
    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public let surface: Surface3D
    public let parameterCurve: SurfaceParameterCurve
    package let exactBSplineImage: BSplineCurve3D?
    package let exactDerivativeCertificate: RationalBezierCurveDerivativeCertificate?

    public init(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve
    ) {
        self.surface = surface
        self.parameterCurve = parameterCurve
        exactBSplineImage = nil
        exactDerivativeCertificate = nil
    }

    package init(surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        exactBSplineImage: BSplineCurve3D) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(surface: surface, parameterCurve: parameterCurve,
            exactBSplineImage: exactBSplineImage, using: &execution)
    }

    package init(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        exactBSplineImage: BSplineCurve3D, using execution: inout OriginalQueryExecution
    ) throws {
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.exactBSplineImage = exactBSplineImage
        exactDerivativeCertificate = try RationalBezierCurveDerivativeCertificate(
            curve: exactBSplineImage, using: &execution
        )
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case surface
        case parameterCurve
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.surface, .parameterCurve],
            in: decoder
        )
        surface = try container.decode(Surface3D.self, forKey: .surface)
        parameterCurve = try container.decode(
            SurfaceParameterCurve.self,
            forKey: .parameterCurve
        )
        exactBSplineImage = nil
        exactDerivativeCertificate = nil
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encode(parameterCurve, forKey: .parameterCurve)
    }
#endif

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    package func pointAssumingValid(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try pointAssumingValid(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometry(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    package func differentialGeometryAssumingValid(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometryAssumingValid(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
        try parameterCurve.validate(on: surface, tolerance: tolerance, using: &execution)
        if let exactBSplineImage {
            try exactBSplineImage.validate(tolerance: tolerance, using: &execution)
            guard case let .closed(lower, upper) = exactBSplineImage.domain,
                  abs(lower) <= tolerance.relative,
                  abs(upper - 1.0) <= tolerance.relative else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "An exact surface-lift B-spline image must use the normalized closed domain."
                )
            }
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        try validateFraction(fraction, tolerance: tolerance, using: &execution)
        return try pointAssumingValid(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
    }

    package func pointAssumingValid(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        try validateFractionAssumingValid(fraction, tolerance: tolerance)
        if let exactBSplineImage {
            return try exactBSplineImage.pointAssumingValid(
                at: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        if case let .certifiedAnalyticPair(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution).position
        }
        if case let .originalAffineWord(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution).position
        }
        if case let .originalImage(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution).position
        }
        if case let .rigidImage(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution).position
        }
        let parameter: SurfaceParameter
        if case let .bSpline(curve) = parameterCurve,
           case let .closed(lower, upper) = curve.domain {
            let curveParameter = lower + (upper - lower) * fraction
            let point = try curve.pointAssumingValid(
                at: curveParameter,
                tolerance: tolerance
            , using: &execution)
            parameter = SurfaceParameter(u: point.x, v: point.y)
        } else {
            parameter = try parameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        return try surface.pointAssumingValid(
            u: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        , using: &execution)
    }

    public func differentialGeometry(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        try validateFraction(fraction, tolerance: tolerance, using: &execution)
        return try differentialGeometryAssumingValid(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
    }

    package func differentialGeometryAssumingValid(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        if let exactBSplineImage {
            let geometry = try exactBSplineImage.differentialGeometryAssumingValid(
                at: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        }
        if case let .certifiedAnalyticPair(curve) = parameterCurve {
            let source = try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: source.position,
                firstDerivative: source.firstDerivative,
                secondDerivative: source.secondDerivative
            )
        }
        if case let .originalAffineWord(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        }
        if case let .originalImage(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        }
        if case let .rigidImage(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        let parameter: SurfaceParameterCurveDifferential
        if case let .bSpline(curve) = parameterCurve,
           case let .closed(lower, upper) = curve.domain {
            let span = upper - lower
            let curveParameter = lower + span * fraction
            let geometry = try curve.differentialGeometryAssumingValid(
                at: curveParameter,
                tolerance: tolerance
            , using: &execution)
            parameter = SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: geometry.position.x,
                    v: geometry.position.y
                ),
                firstDerivative: Point2D(
                    x: geometry.firstDerivative.x * span,
                    y: geometry.firstDerivative.y * span
                ),
                secondDerivative: Point2D(
                    x: geometry.secondDerivative.x * span * span,
                    y: geometry.secondDerivative.y * span * span
                )
            )
        } else {
            parameter = try parameterCurve.differentialGeometry(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        let geometry = try surface.parameterDerivativesAssumingValid(
            u: parameter.parameter.u,
            v: parameter.parameter.v,
            tolerance: tolerance
        , using: &execution)
        let firstU = parameter.firstDerivative.x
        let firstV = parameter.firstDerivative.y
        let secondU = parameter.secondDerivative.x
        let secondV = parameter.secondDerivative.y
        let firstDerivative = geometry.tangentU * firstU
            + geometry.tangentV * firstV
        let secondDerivative = geometry.secondDerivativeUU * (firstU * firstU)
            + geometry.secondDerivativeUV * (2.0 * firstU * firstV)
            + geometry.secondDerivativeVV * (firstV * firstV)
            + geometry.tangentU * secondU
            + geometry.tangentV * secondV
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    private func validateFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        try validateFractionAssumingValid(fraction, tolerance: tolerance)
    }

    private func validateFractionAssumingValid(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.surface == rhs.surface
            && lhs.parameterCurve == rhs.parameterCurve
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(surface)
        hasher.combine(parameterCurve)
    }
}

#if !hasFeature(Embedded)
extension SurfaceLiftCurve3D: Codable {}
#endif
