import CADIR
import CADKernel

public protocol DocumentDrawingHatching: Sendable {
    func hatch(_ section: BRepDrawingSection, document: CADDocument,
               currentEvaluation: EvaluatedDocument, spacing: Double,
               maximumRows: Int, maximumBoundaryCurves: Int,
               maximumEventsPerRow: Int, maximumSegments: Int) throws -> [BRepDrawingHatchSegment]
    func hatch(_ section: BRepDrawingSection, document: CADDocument,
               currentEvaluation: EvaluatedDocument, spacing: Double,
               maximumRows: Int, maximumBoundaryCurves: Int,
               maximumEventsPerRow: Int, maximumSegments: Int,
               maximumPreparationWork: Int, maximumPreparationBytes: Int,
               maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
               maximumAlgebraicDepth: Int) throws -> BRepDrawingHatchResult
}
