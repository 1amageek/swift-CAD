import CADCore
import CADIR
import CADKernel

public struct DocumentDrawingHatcher: DocumentDrawingHatching {
    private let hatcher: any BRepDrawingHatching

    public init(hatcher: any BRepDrawingHatching = BRepDrawingHatcher()) {
        self.hatcher = hatcher
    }

    public func hatch(_ section: BRepDrawingSection, document: CADDocument,
                      currentEvaluation: EvaluatedDocument, spacing: Double,
                      maximumRows: Int, maximumBoundaryCurves: Int,
                      maximumEventsPerRow: Int, maximumSegments: Int) throws -> [BRepDrawingHatchSegment] {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document, section.sourceDocument == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Original section hatching requires the complete current source evaluation.")
        }
        return try hatcher.hatch(section, in: currentEvaluation, spacing: spacing,
            maximumRows: maximumRows, maximumBoundaryCurves: maximumBoundaryCurves,
            maximumEventsPerRow: maximumEventsPerRow, maximumSegments: maximumSegments)
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): The original-chart hatch producer is
    // wired here; complete lower aggregate callbacks remain a Kernel dependency.
    public func hatch(_ section: BRepDrawingSection, document: CADDocument,
                      currentEvaluation: EvaluatedDocument, spacing: Double,
                      maximumRows: Int, maximumBoundaryCurves: Int,
                      maximumEventsPerRow: Int, maximumSegments: Int,
                      maximumPreparationWork: Int, maximumPreparationBytes: Int,
                      maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
                      maximumAlgebraicDepth: Int) throws -> BRepDrawingHatchResult {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard currentEvaluation.document == document, section.sourceDocument == document else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: currentEvaluation.configuration.tolerance,
                message: "Original cutting-chart hatch requires the complete current source evaluation.")
        }
        return try hatcher.hatch(section, in: currentEvaluation, spacing: spacing, maximumRows: maximumRows,
            maximumBoundaryCurves: maximumBoundaryCurves, maximumEventsPerRow: maximumEventsPerRow,
            maximumSegments: maximumSegments, maximumPreparationWork: maximumPreparationWork,
            maximumPreparationBytes: maximumPreparationBytes, maximumSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

}
