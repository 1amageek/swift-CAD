import CADCore

public struct SurfaceParameterProjection: Codable, Hashable, Sendable {
    public let u: Double
    public let v: Double
    public let point: Point3D
    public let residual: Double
    public let iterations: Int

    public init(
        u: Double,
        v: Double,
        point: Point3D,
        residual: Double,
        iterations: Int = 0
    ) throws {
        try point.validate()
        guard u.isFinite,
              v.isFinite,
              residual.isFinite,
              residual >= 0.0,
              iterations >= 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: nil,
                message: "Surface parameter projection values must be finite and non-negative."
            )
        }
        self.u = u
        self.v = v
        self.point = point
        self.residual = residual
        self.iterations = iterations
    }

    private enum CodingKeys: String, CodingKey {
        case u
        case v
        case point
        case residual
        case iterations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.u, .v, .point, .residual, .iterations],
            in: decoder
        )
        try self.init(
            u: container.decode(Double.self, forKey: .u),
            v: container.decode(Double.self, forKey: .v),
            point: container.decode(Point3D.self, forKey: .point),
            residual: container.decode(Double.self, forKey: .residual),
            iterations: container.decode(Int.self, forKey: .iterations)
        )
    }

    public func encode(to encoder: Encoder) throws {
        _ = try SurfaceParameterProjection(
            u: u,
            v: v,
            point: point,
            residual: residual,
            iterations: iterations
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(u, forKey: .u)
        try container.encode(v, forKey: .v)
        try container.encode(point, forKey: .point)
        try container.encode(residual, forKey: .residual)
        try container.encode(iterations, forKey: .iterations)
    }
}
