import CADCore

public struct SurfaceSurfaceCoincidence: Codable, Hashable, Sendable {
    public let residual: Double
    public let certificationTolerance: ModelingTolerance

    public init(residual: Double, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard residual.isFinite,
              residual >= 0.0,
              residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Coincident surfaces exceeded the requested tolerance."
            )
        }
        self.residual = residual
        certificationTolerance = tolerance
    }

    private enum CodingKeys: String, CodingKey {
        case residual
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.residual, .certificationTolerance],
            in: decoder
        )
        try self.init(
            residual: container.decode(Double.self, forKey: .residual),
            tolerance: container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
        )
    }

    public func encode(to encoder: Encoder) throws {
        _ = try SurfaceSurfaceCoincidence(
            residual: residual,
            tolerance: certificationTolerance
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(residual, forKey: .residual)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
