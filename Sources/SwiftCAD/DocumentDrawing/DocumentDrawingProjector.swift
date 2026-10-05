import CADCore
import CADGeometry
import CADIR
import CADKernel

public struct DocumentDrawingProjector: DocumentDrawingProjecting {
    private let projector: any BRepDrawingProjecting

    public init(projector: any BRepDrawingProjecting = BRepDrawingProjector()) {
        self.projector = projector
    }

    public func projectEdges(document: CADDocument, currentEvaluation: EvaluatedDocument,
                             onto frame: OrthographicProjectionFrame,
                             maximumProjectedUses: Int) throws -> BRepDrawingProjection {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "A geometric drawing requires the complete current source evaluation.")
        }
        return try projector.projectEdges(in: currentEvaluation, onto: frame,
                                           maximumProjectedUses: maximumProjectedUses)
    }
}
