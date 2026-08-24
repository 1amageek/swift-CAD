import CADCore

package protocol SingleFaceSheetSurfaceOperationTargetValidating: Sendable {
    func validate(
        _ target: ResolvedSurfaceOperationTarget,
        operation: String,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws
}
