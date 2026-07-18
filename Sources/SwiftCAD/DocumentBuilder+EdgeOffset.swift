import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func edgeOffset(
        target targetFeatureID: FeatureID,
        edge: StableSubshapeReference,
        supportFace: StableSubshapeReference,
        distance: CADExpression,
        isSymmetric: Bool = false,
        named name: String? = nil
    ) throws -> FeatureID {
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .edgeOffset(EdgeOffsetFeature(
                target: EdgeOffsetTargetReference(featureID: targetFeatureID),
                edge: edge,
                supportFace: supportFace,
                distance: distance,
                isSymmetric: isSymmetric
            ))
        )
        return featureID
    }

    @discardableResult
    mutating func edgeOffset(
        target targetFeatureID: FeatureID,
        edge: StableSubshapeReference,
        supportFace: StableSubshapeReference,
        distance parameterID: ParameterID,
        isSymmetric: Bool = false,
        named name: String? = nil
    ) throws -> FeatureID {
        try edgeOffset(
            target: targetFeatureID,
            edge: edge,
            supportFace: supportFace,
            distance: .reference(parameterID),
            isSymmetric: isSymmetric,
            named: name
        )
    }
}
