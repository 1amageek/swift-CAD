import CADCore
import CADIR
import CADModeling
import CADTopology

func surfaceOperationTarget(
    featureID: FeatureID,
    model: BRepModel,
    subshapes: SubshapeIndex
) throws -> SurfaceOperationTargetReference {
    let candidates = subshapes.entries.filter { entry in
        guard entry.key.featureID == featureID else {
            return false
        }
        if case .face = entry.value {
            return true
        }
        return false
    }
    guard candidates.count == 1,
          let candidate = candidates.first else {
        throw KernelError(
            phase: .validation,
            code: .ambiguousSelection,
            featureID: featureID,
            tolerance: .standard,
            message: "Surface operation test target requires exactly one indexed face."
        )
    }
    let face = StableSubshapeReference(
        subshapeID: candidate.key,
        geometrySignature: try SubshapeGeometrySignatureBuilder(
            model: model,
            tolerance: .standard
        ).signature(for: candidate.value)
    )
    return SurfaceOperationTargetReference(
        featureID: featureID,
        face: face
    )
}

func surfaceOperationTarget(
    featureID: FeatureID,
    fixture: PlanarSheetTestFixture
) throws -> SurfaceOperationTargetReference {
    try surfaceOperationTarget(
        featureID: featureID,
        model: fixture.brep,
        subshapes: fixture.subshapes
    )
}
