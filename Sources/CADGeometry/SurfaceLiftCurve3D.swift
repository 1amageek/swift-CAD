import CADCore

/// The exact model-space lift of a face-local parameter curve.
public struct SurfaceLiftCurve3D: Codable, Hashable, Sendable {
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

    package init(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        exactBSplineImage: BSplineCurve3D
    ) {
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.exactBSplineImage = exactBSplineImage
        exactDerivativeCertificate = RationalBezierCurveDerivativeCertificate(
            curve: exactBSplineImage
        )
    }

    private enum CodingKeys: String, CodingKey {
        case surface
        case parameterCurve
    }

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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encode(parameterCurve, forKey: .parameterCurve)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        try parameterCurve.validate(on: surface, tolerance: tolerance)
        if let exactBSplineImage {
            try exactBSplineImage.validate(tolerance: tolerance)
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
    ) throws -> Point3D {
        try validateFraction(fraction, tolerance: tolerance)
        return try pointAssumingValid(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    package func pointAssumingValid(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try validateFractionAssumingValid(fraction, tolerance: tolerance)
        if let exactBSplineImage {
            return try exactBSplineImage.pointAssumingValid(
                at: fraction,
                tolerance: tolerance
            )
        }
        if case let .certifiedAnalyticPair(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            ).position
        }
        if case let .rigidImage(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            ).position
        }
        let parameter: SurfaceParameter
        if case let .bSpline(curve) = parameterCurve,
           case let .closed(lower, upper) = curve.domain {
            let curveParameter = lower + (upper - lower) * fraction
            let point = try curve.pointAssumingValid(
                at: curveParameter,
                tolerance: tolerance
            )
            parameter = SurfaceParameter(u: point.x, v: point.y)
        } else {
            parameter = try parameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        return try surface.pointAssumingValid(
            u: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        )
    }

    public func differentialGeometry(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try validateFraction(fraction, tolerance: tolerance)
        return try differentialGeometryAssumingValid(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    package func differentialGeometryAssumingValid(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        if let exactBSplineImage {
            let geometry = try exactBSplineImage.differentialGeometryAssumingValid(
                at: fraction,
                tolerance: tolerance
            )
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
            )
            return DifferentialGeometry(
                position: source.position,
                firstDerivative: source.firstDerivative,
                secondDerivative: source.secondDerivative
            )
        }
        if case let .rigidImage(curve) = parameterCurve {
            return try curve.modelSpaceDifferential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        let parameter: SurfaceParameterCurveDifferential
        if case let .bSpline(curve) = parameterCurve,
           case let .closed(lower, upper) = curve.domain {
            let span = upper - lower
            let curveParameter = lower + span * fraction
            let geometry = try curve.differentialGeometryAssumingValid(
                at: curveParameter,
                tolerance: tolerance
            )
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
            )
        }
        let geometry = try surface.parameterDerivativesAssumingValid(
            atU: parameter.parameter.u,
            v: parameter.parameter.v,
            tolerance: tolerance
        )
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
    ) throws {
        try validate(tolerance: tolerance)
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
