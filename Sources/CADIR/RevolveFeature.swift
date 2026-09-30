import CADCore
import CADTopology

public struct RevolveFeature: Codable, Hashable, Sendable {
    public var section: SectionReference
    public var axis: RevolveAxis
    public var angle: CADExpression
    public var operation: SolidOperation
    public var resultKind: BodyKind

    public init(
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        operation: SolidOperation = .newBody,
        resultKind: BodyKind = .solid
    ) {
        self.init(section: .profile(profile), axis: axis, angle: angle,
                  operation: operation, resultKind: resultKind)
    }

    public init(section: SectionReference, axis: RevolveAxis,
                angle: CADExpression = .constant(.angle(360, unit: .degree)),
                operation: SolidOperation = .newBody, resultKind: BodyKind) {
        self.section = section
        self.axis = axis
        self.angle = angle
        self.operation = operation
        self.resultKind = resultKind
    }

    private enum CodingKeys: String, CodingKey {
        case section, axis, angle, operation, resultKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.section, .axis, .angle, .operation, .resultKind], in: decoder)
        section = try container.decode(SectionReference.self, forKey: .section)
        axis = try container.decode(RevolveAxis.self, forKey: .axis)
        angle = try container.decode(CADExpression.self, forKey: .angle)
        operation = try container.decode(SolidOperation.self, forKey: .operation)
        resultKind = try container.decode(BodyKind.self, forKey: .resultKind)
        try validateSection()
    }

    public func encode(to encoder: Encoder) throws {
        try validateSection()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(axis, forKey: .axis)
        try container.encode(angle, forKey: .angle)
        try container.encode(operation, forKey: .operation)
        try container.encode(resultKind, forKey: .resultKind)
    }

    private func validateSection() throws {
        try section.validate()
        // FIXME(INCOMPLETE_IMPLEMENTATION): a face section is refused. Production path:
        // RevolveFeature.validate for every revolve. Complete only when a planar face revolves
        // like a profile, verified by a revolved face's volume.
        if case .face = section {
            throw FeatureEvaluationError.invalidGraph("Revolve takes a profile or a curve section.")
        }
        guard resultKind == .sheet || section.isProfile else {
            throw FeatureEvaluationError.invalidGraph("A curve revolution requires sheet output.")
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try validateSection()
        try axis.validate(tolerance: tolerance)
        try angle.validateLiteralQuantities()
    }
}

public struct RevolveAxis: Codable, Hashable, Sendable {
    public var origin: Point3D
    public var direction: Vector3D

    public init(origin: Point3D, direction: Vector3D) {
        self.origin = origin
        self.direction = direction
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        _ = try direction.normalized(tolerance: tolerance.distance)
    }

    public func normalizedDirection(tolerance: ModelingTolerance) throws -> Vector3D {
        try direction.normalized(tolerance: tolerance.distance)
    }
}
