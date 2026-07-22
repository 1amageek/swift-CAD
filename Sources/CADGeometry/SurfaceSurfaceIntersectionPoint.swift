import CADCore

public struct SurfaceSurfaceIntersectionPoint: Codable, Hashable, Sendable {
    public let point: Point3D
    public let firstSurfaceParameter: SurfaceParameterProjection
    public let secondSurfaceParameter: SurfaceParameterProjection
    public let residual: Double
    public let certificationTolerance: ModelingTolerance

    public init(
        point: Point3D,
        firstSurfaceParameter: SurfaceParameterProjection,
        secondSurfaceParameter: SurfaceParameterProjection,
        residual: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try point.validate()
        guard residual.isFinite,
              residual >= 0.0,
              residual <= tolerance.distance,
              firstSurfaceParameter.residual <= tolerance.distance,
              secondSurfaceParameter.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Surface-surface intersection point failed residual verification."
            )
        }
        self.point = point
        self.firstSurfaceParameter = firstSurfaceParameter
        self.secondSurfaceParameter = secondSurfaceParameter
        self.residual = residual
        certificationTolerance = tolerance
    }

    private enum CodingKeys: String, CodingKey {
        case point
        case firstSurfaceParameter
        case secondSurfaceParameter
        case residual
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .point,
                .firstSurfaceParameter,
                .secondSurfaceParameter,
                .residual,
                .certificationTolerance,
            ],
            in: decoder
        )
        try self.init(
            point: container.decode(Point3D.self, forKey: .point),
            firstSurfaceParameter: container.decode(
                SurfaceParameterProjection.self,
                forKey: .firstSurfaceParameter
            ),
            secondSurfaceParameter: container.decode(
                SurfaceParameterProjection.self,
                forKey: .secondSurfaceParameter
            ),
            residual: container.decode(Double.self, forKey: .residual),
            tolerance: container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
        )
    }

    public func encode(to encoder: Encoder) throws {
        _ = try SurfaceSurfaceIntersectionPoint(
            point: point,
            firstSurfaceParameter: firstSurfaceParameter,
            secondSurfaceParameter: secondSurfaceParameter,
            residual: residual,
            tolerance: certificationTolerance
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(point, forKey: .point)
        try container.encode(firstSurfaceParameter, forKey: .firstSurfaceParameter)
        try container.encode(secondSurfaceParameter, forKey: .secondSurfaceParameter)
        try container.encode(residual, forKey: .residual)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
