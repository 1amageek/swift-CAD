import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Requires immutable original patch admission and its authored native UV chart.
package protocol OriginalFaceTrimBoxContaining: Sendable {
    func classify(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox,
        in faceID: FaceID,
        validatedModel: ValidatedBRepModel,
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox,
        in faceID: FaceID,
        validatedModel: ValidatedBRepModel,
        maximumSubdivisionDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFaceTrimBoxClassification


    func containsStrictly(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> Bool
}

extension OriginalFaceTrimBoxContaining {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected finite-box provider must
    // implement its actual source/proof query under these independent limits.
    func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFaceTrimBoxClassification {
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "The finite-box provider has no direct original-cap witness.")
    }
}
