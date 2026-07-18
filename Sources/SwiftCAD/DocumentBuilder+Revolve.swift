import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func revolve(
        _ profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        named name: String? = nil
    ) throws -> FeatureID {
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .revolve(RevolveFeature(
                profile: profile,
                axis: axis,
                angle: angle,
                operation: .newBody
            ))
        )
        return featureID
    }
}
