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

    public init(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve
    ) {
        self.surface = surface
        self.parameterCurve = parameterCurve
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
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try validateFraction(fraction, tolerance: tolerance)
        let parameter = try parameterCurve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        return try surface.point(
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
        if case let .certifiedAnalyticPair(curve) = parameterCurve,
           let source = try curve
            .modelSpaceDifferentialAtCertifiedSupportChartSingularity(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            ) {
            return DifferentialGeometry(
                position: source.position,
                firstDerivative: source.firstDerivative,
                secondDerivative: source.secondDerivative
            )
        }
        let parameter = try parameterCurve.differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let geometry = try surface.differentialGeometry(
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
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
    }
}
