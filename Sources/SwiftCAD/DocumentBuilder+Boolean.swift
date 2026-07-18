import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func boolean(
        targets: [FeatureID],
        tool: FeatureID,
        operation: BooleanOperation,
        keepTools: Bool = false,
        named name: String? = nil
    ) throws -> FeatureID {
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .boolean(BooleanFeature(
                targets: targets.map(BooleanTargetReference.init(featureID:)),
                tool: BooleanToolReference(featureID: tool),
                operation: operation,
                keepTools: keepTools
            ))
        )
        return featureID
    }
}
