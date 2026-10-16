import CADGeometry
import CADCore

public protocol BRepDrawingHatching: Sendable {
    func hatch(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
               spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
               maximumEventsPerRow: Int, maximumSegments: Int) throws -> [BRepDrawingHatchSegment]
    func hatch(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
               spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
               maximumEventsPerRow: Int, maximumSegments: Int, using execution: inout OriginalQueryExecution) throws -> [BRepDrawingHatchSegment]
    func hatch(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
               spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
               maximumEventsPerRow: Int, maximumSegments: Int,
               maximumPreparationWork: Int, maximumPreparationBytes: Int,
               maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
               maximumAlgebraicDepth: Int) throws -> BRepDrawingHatchResult
    func hatch(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
               spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
               maximumEventsPerRow: Int, maximumSegments: Int,
               maximumPreparationWork: Int, maximumPreparationBytes: Int,
               maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
               maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingHatchResult
}
