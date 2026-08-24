import CADCore

package struct DefaultSingleFaceSheetSurfaceOperationTargetValidator:
    SingleFaceSheetSurfaceOperationTargetValidating
{
    package init() {}

    package func validate(
        _ target: ResolvedSurfaceOperationTarget,
        operation: String,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        guard target.body.kind == .sheet,
              target.body.shellIDs == [target.shellID],
              target.shell.faceIDs == [target.faceID] else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "\(operation) requires the selected face to be the only face of a single-shell sheet body."
            )
        }
    }
}
