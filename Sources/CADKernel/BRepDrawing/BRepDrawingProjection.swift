import CADCore
import CADGeometry
import CADIR

/// Edge geometry publication; visibility and section regions have distinct producers.
public struct BRepDrawingProjection: Sendable {
    public let sourceDocument: CADDocument
    public let configuration: DocumentEvaluationConfiguration
    public let frame: OrthographicProjectionFrame
    public let uses: [BRepDrawingProjectedUse]
    let sourceSnapshot: BRepDrawingSourceSnapshot

    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try sourceSnapshot.validateCurrent(evaluated, using: &execution)
    }
}
