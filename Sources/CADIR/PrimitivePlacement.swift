import CADCore
import CADGeometry

public struct PrimitivePlacement: Hashable, Sendable {
    public let origin: Point3D
    public let axis: Vector3D
    public let referenceDirection: Vector3D

    public init(
        origin: Point3D,
        axis: Vector3D,
        referenceDirection: Vector3D
    ) {
        self.origin = origin
        self.axis = axis
        self.referenceDirection = referenceDirection
    }

    public static let identity = PrimitivePlacement(
        origin: .origin,
        axis: .unitZ,
        referenceDirection: .unitX
    )

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        try origin.validate()
        try axis.validateUnitLength(tolerance: tolerance)
        try referenceDirection.validateUnitLength(tolerance: tolerance)
        let orthogonalityResidual = abs(axis.dot(referenceDirection))
        guard orthogonalityResidual <= tolerance.angle else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: orthogonalityResidual,
                tolerance: tolerance,
                message: "Primitive placement axis and reference direction must be orthogonal unit vectors."
            )
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case origin
        case axis
        case referenceDirection
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.origin, .axis, .referenceDirection],
            in: decoder
        )
        origin = try container.decode(Point3D.self, forKey: .origin)
        axis = try container.decode(Vector3D.self, forKey: .axis)
        referenceDirection = try container.decode(
            Vector3D.self,
            forKey: .referenceDirection
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(axis, forKey: .axis)
        try container.encode(referenceDirection, forKey: .referenceDirection)
    }
#endif
}

#if !hasFeature(Embedded)
extension PrimitivePlacement: Codable {}
#endif
