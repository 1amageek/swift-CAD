import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func revolve(
        _ profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        operation: SolidOperation = .newBody,
        targets: [FeatureID] = [],
        keepTools: Bool = false,
        thickness: CADExpression? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        try revolve(section: .profile(profile), axis: axis, angle: angle, operation: operation,
                    targets: targets, keepTools: keepTools, resultKind: .solid, thickness: thickness, named: name)
    }

    /// Revolves any section (a profile, a curve, or a planar face) about `axis`, as a new body or
    /// combined with `targets`; a curve makes a solid only when it closes on its own or along the axis.
    @discardableResult
    mutating func revolve(
        section: SectionReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        operation: SolidOperation = .newBody,
        targets: [FeatureID] = [],
        keepTools: Bool = false,
        resultKind: BodyKind,
        thickness: CADExpression? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .revolve(RevolveFeature(
                section: section, axis: axis, angle: angle, operation: operation,
                targets: targets.map { BooleanTargetReference(featureID: $0) }, keepTools: keepTools,
                resultKind: resultKind, thickness: thickness
            ))
        )
        return featureID
    }
}
