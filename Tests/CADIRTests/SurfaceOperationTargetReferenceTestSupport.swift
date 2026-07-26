import CADCore
import CADIR

func surfaceOperationTargetReference(
    featureID: FeatureID
) -> SurfaceOperationTargetReference {
    SurfaceOperationTargetReference(
        featureID: featureID,
        face: StableSubshapeReference(
            subshapeID: SubshapeID(
                featureID: featureID,
                role: "face",
                ordinal: 0
            ),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
    )
}
