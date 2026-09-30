import CADCore
import CADTopology

public struct RevolveFeature: Codable, Hashable, Sendable {
    public var section: SectionReference
    public var axis: RevolveAxis
    public var angle: CADExpression
    public var operation: SolidOperation
    /// The bodies a Boolean revolve combines with, each moved to where it is placed first.
    public var targets: [BooleanTargetReference]
    /// Whether a Boolean revolve also keeps the revolved tool.
    public var keepTools: Bool
    public var resultKind: BodyKind
    /// A thin revolve's wall thickness: every loop of the section becomes a ring of it on the
    /// material's side, and each ring revolves into a solid wall.
    public var thickness: CADExpression?

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
                operation: SolidOperation = .newBody,
                targets: [BooleanTargetReference] = [],
                keepTools: Bool = false,
                resultKind: BodyKind,
                thickness: CADExpression? = nil) {
        self.section = section
        self.axis = axis
        self.angle = angle
        self.operation = operation
        self.targets = targets
        self.keepTools = keepTools
        self.resultKind = resultKind
        self.thickness = thickness
    }

    private enum CodingKeys: String, CodingKey {
        case section, axis, angle, operation, targets, keepTools, resultKind, thickness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.section, .axis, .angle, .operation, .targets, .keepTools, .resultKind, .thickness], in: decoder
        )
        section = try container.decode(SectionReference.self, forKey: .section)
        axis = try container.decode(RevolveAxis.self, forKey: .axis)
        angle = try container.decode(CADExpression.self, forKey: .angle)
        operation = try container.decode(SolidOperation.self, forKey: .operation)
        targets = try container.decodeIfPresent([BooleanTargetReference].self, forKey: .targets) ?? []
        keepTools = try container.decodeIfPresent(Bool.self, forKey: .keepTools) ?? false
        resultKind = try container.decode(BodyKind.self, forKey: .resultKind)
        thickness = try container.decodeIfPresent(CADExpression.self, forKey: .thickness)
        try validateSection()
    }

    public func encode(to encoder: Encoder) throws {
        try validateSection()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(axis, forKey: .axis)
        try container.encode(angle, forKey: .angle)
        try container.encode(operation, forKey: .operation)
        if !targets.isEmpty { try container.encode(targets, forKey: .targets) }
        if keepTools { try container.encode(keepTools, forKey: .keepTools) }
        try container.encode(resultKind, forKey: .resultKind)
        try container.encodeIfPresent(thickness, forKey: .thickness)
    }

    /// A curve revolves into a sheet, or into a solid when both its ends lie on the axis; which
    /// one holds is known only once the curve is evaluated, so a solid curve revolve is admitted
    /// here and checked by the evaluator.
    private func validateSection() throws {
        try section.validate()
        if thickness != nil {
            guard resultKind == .solid, section.isClosedRegion else {
                throw FeatureEvaluationError.invalidGraph("A thin revolve walls a closed section into a solid.")
            }
        }
        if operation == .newBody {
            guard targets.isEmpty, !keepTools else {
                throw FeatureEvaluationError.invalidGraph("New-body revolve cannot declare Boolean targets or Keep Tools.")
            }
        } else {
            guard resultKind == .solid, !targets.isEmpty,
                  Set(targets.map(\.featureID)).count == targets.count,
                  section.isFace || !targets.contains(where: { $0.featureID == section.featureID }) else {
                throw FeatureEvaluationError.invalidGraph("Boolean revolve requires solid output and unique targets distinct from its section.")
            }
            try targets.forEach { try $0.validate() }
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try validateSection()
        try axis.validate(tolerance: tolerance)
        try angle.validateLiteralQuantities()
        try thickness?.validateLiteralQuantities()
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
