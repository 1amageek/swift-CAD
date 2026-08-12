import CADCore

public struct ProjectCurveFeature: Codable, Hashable, Sendable {
    public let source: CurveOutputReference
    public let planeOrigin: Point3D
    public let planeNormal: Vector3D
    /// Optional projection direction; nil projects along the plane normal.
    public let direction: Vector3D?

    public init(
        source: CurveOutputReference,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        direction: Vector3D? = nil
    ) {
        self.source = source
        self.planeOrigin = planeOrigin
        self.planeNormal = planeNormal
        self.direction = direction
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try source.validate()
        try planeOrigin.validate()
        try planeNormal.validate()
        guard planeNormal.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(planeNormal.length)
        }
        if let direction {
            try direction.validate()
            guard direction.length > tolerance.distance else {
                throw GeometryError.invalidVectorLength(direction.length)
            }
            guard abs(direction.dot(planeNormal))
                > tolerance.angle * direction.length * planeNormal.length else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Curve projection direction must not graze the target plane."
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case planeOrigin
        case planeNormal
        case direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.source, .planeOrigin, .planeNormal, .direction],
            in: decoder
        )
        source = try container.decode(CurveOutputReference.self, forKey: .source)
        planeOrigin = try container.decode(Point3D.self, forKey: .planeOrigin)
        planeNormal = try container.decode(Vector3D.self, forKey: .planeNormal)
        direction = try container.decodeIfPresent(Vector3D.self, forKey: .direction)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(planeOrigin, forKey: .planeOrigin)
        try container.encode(planeNormal, forKey: .planeNormal)
        try container.encodeIfPresent(direction, forKey: .direction)
    }
}
