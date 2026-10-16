import CADCore
import CADGeometry
import CADIR

public struct BRepDrawingSilhouettes: Sendable {
    public let sourceDocument: CADDocument
    public let configuration: DocumentEvaluationConfiguration
    public let frame: OrthographicProjectionFrame
    public let contacts: [BRepDrawingSilhouetteContact]
    public let algebraicContacts: [BRepDrawingSilhouetteAlgebraicContact]
    public let atlasStations: [BRepDrawingSilhouetteAtlasStation]
    public let collapsedCurves: [BRepDrawingSilhouetteCollapsedCurve]
    public let singularStations: [BRepDrawingSilhouetteSingularStation]
    public let originalFaces: [BRepDrawingFaceSilhouette]
    internal let sourceSnapshot: BRepDrawingSourceSnapshot

    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try sourceSnapshot.validateCurrent(evaluated, using: &execution)
    }

    public let spans: [BRepDrawingSilhouetteSpan]
    public let exactTrimmedSpans: [BRepDrawingExactSilhouetteSpan]
    public let trimPartitions: [BRepDrawingSilhouetteTrimPartition]
    /// Non-discrete original zero domains; consumers must process their actual face trims.
    public let coincidentFaceIDs: [FaceID]
    public let placement: BRepDrawingPlacement?
}
