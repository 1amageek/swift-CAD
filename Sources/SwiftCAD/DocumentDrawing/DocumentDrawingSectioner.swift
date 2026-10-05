import CADCore
import CADGeometry
import CADIR
import CADKernel

public struct DocumentDrawingSectioner: DocumentDrawingSectioning {
    private let sectioner: any BRepDrawingSectioning

    public init(sectioner: any BRepDrawingSectioning = BRepDrawingSectioner()) {
        self.sectioner = sectioner
    }

    public func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                        on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "A geometric section requires the complete current source evaluation.")
        }
        return try sectioner.section(in: currentEvaluation, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents)
    }

    public func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                        bodyIDs: [BodyID], on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "A body-scoped section requires the complete current source evaluation.")
        }
        return try sectioner.section(bodyIDs: bodyIDs, in: currentEvaluation, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This public placed path forwards original affine
    // source composition; complete bounded originalImage/world-plane SSI remains required
    // before all-domain placed sections can be reported as completed.
    public func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                        placement: BRepDrawingPlacement, on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int,
                        maximumSourceEntities: Int, maximumPreparationWork: Int) throws -> BRepDrawingSection {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "A placed section requires the complete current source evaluation.")
        }
        return try sectioner.section(placement: placement, in: currentEvaluation, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents,
            maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This source facade forwards original local
    // cutting authority. Complete original-word SSI and lower aggregate callbacks
    // remain mandatory before full-domain section publication is complete.
    public func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                        bodyIDs: [BodyID], on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int, maximumPreparationWork: Int,
                        maximumPreparationBytes: Int, maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
                        maximumAlgebraicDepth: Int) throws -> BRepDrawingSection {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "An original placed cutting support requires the complete current source evaluation.")
        }
        return try sectioner.section(bodyIDs: bodyIDs, in: currentEvaluation, on: support,
            projectionFrame: projectionFrame, maximumSourceFaces: maximumSourceFaces,
            maximumComponents: maximumComponents, maximumPreparationWork: maximumPreparationWork,
            maximumPreparationBytes: maximumPreparationBytes, maximumSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Original body/cutting words are forwarded
    // without rounded substitutes. Complete SSI and aggregate lower bytes remain
    // mandatory before full-domain placed section source completion.
    public func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                        placement: BRepDrawingPlacement, on support: BRepDrawingCuttingSupport,
                        projectionFrame: OrthographicProjectionFrame, maximumSourceFaces: Int, maximumComponents: Int,
                        maximumSourceEntities: Int, maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Original placed section requires the complete current source evaluation.")
        }
        return try sectioner.section(placement: placement, in: currentEvaluation, on: support,
            projectionFrame: projectionFrame, maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents,
            maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork,
            maximumPreparationBytes: maximumPreparationBytes, maximumSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

}
