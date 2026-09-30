import CADCore
import CADIR

public extension DocumentBuilder {
    /// Offsets `edges` of `supportFace` over it (`EdgeOffsetFeature`).
    @discardableResult
    mutating func edgeOffset(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        supportFace: StableSubshapeReference,
        distance: CADExpression,
        isSymmetric: Bool = false,
        gapFill: OffsetGapFill = .round,
        named name: String? = nil
    ) throws -> FeatureID {
        let feature = EdgeOffsetFeature(
            target: PatternTargetReference(featureID: targetFeatureID),
            edges: edges,
            supportFace: supportFace,
            distance: distance,
            isSymmetric: isSymmetric,
            gapFill: gapFill
        )
        try feature.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .edgeOffset(feature))
        return featureID
    }

    /// Offsets the outlines of `faces` (`FaceLoopOffsetFeature`).
    @discardableResult
    mutating func faceLoopOffset(
        target targetFeatureID: FeatureID,
        faces: [StableSubshapeReference],
        distance: CADExpression,
        side: FaceLoopOffsetSide = .inward,
        gapFill: OffsetGapFill = .round,
        isIndividual: Bool = true,
        named name: String? = nil
    ) throws -> FeatureID {
        let feature = FaceLoopOffsetFeature(
            target: PatternTargetReference(featureID: targetFeatureID),
            faces: faces,
            distance: distance,
            side: side,
            gapFill: gapFill,
            isIndividual: isIndividual
        )
        try feature.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceLoopOffset(feature))
        return featureID
    }
}
