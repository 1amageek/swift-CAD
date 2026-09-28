import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func boolean(
        targets: [FeatureID],
        tools: [FeatureID],
        operation: BooleanOperation,
        keepTools: Bool = false,
        targetMaterial: BooleanMaterial = .default,
        toolMaterial: BooleanMaterial = .default,
        named name: String? = nil
    ) throws -> FeatureID {
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .boolean(BooleanFeature(
                targets: targets.map { BooleanTargetReference(featureID: $0) },
                tools: tools.map { BooleanToolReference(featureID: $0) },
                operation: operation,
                keepTools: keepTools,
                targetMaterial: targetMaterial,
                toolMaterial: toolMaterial
            ))
        )
        return featureID
    }

    /// A Boolean with one tool.
    @discardableResult
    mutating func boolean(
        targets: [FeatureID],
        tool: FeatureID,
        operation: BooleanOperation,
        keepTools: Bool = false,
        targetMaterial: BooleanMaterial = .default,
        toolMaterial: BooleanMaterial = .default,
        named name: String? = nil
    ) throws -> FeatureID {
        try boolean(
            targets: targets, tools: [tool], operation: operation, keepTools: keepTools,
            targetMaterial: targetMaterial, toolMaterial: toolMaterial, named: name
        )
    }
}
