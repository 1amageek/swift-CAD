import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Requires immutable original patch admission and its authored native UV chart.
package protocol OriginalFaceTrimBoxContaining: Sendable {
    func classify(_ box: SurfaceParameterBox, inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox, inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> OriginalFaceTrimBoxClassification
    func classify(_ box: SurfaceParameterBox, inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> OriginalFaceTrimBoxClassification
    func containsStrictly(_ box: SurfaceParameterBox, inAdmitted patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> Bool
}

extension OriginalFaceTrimBoxContaining {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected finite-box provider must
    // forward the selected independent original caps and optional byte ledger;
    // its older geometry-only witness cannot establish that admission.
    func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "The finite-box provider has no selected original-cap witness.")
    }
}
