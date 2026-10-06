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
        try sourceSnapshot.validateCurrent(evaluated)
    }

    public let spans: [BRepDrawingSilhouetteSpan]
    public let exactTrimmedSpans: [BRepDrawingExactSilhouetteSpan]
    public let trimPartitions: [BRepDrawingSilhouetteTrimPartition]
    /// Non-discrete original zero domains; consumers must process their actual face trims.
    public let coincidentFaceIDs: [FaceID]
    public let placement: BRepDrawingPlacement?
}
