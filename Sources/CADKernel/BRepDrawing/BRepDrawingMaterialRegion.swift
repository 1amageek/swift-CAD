import CADCore
import CADIR
import CADModeling
import CADTopology

/// One connected material patch with original ordered outer and inner curves.
public struct BRepDrawingMaterialRegion: Sendable {
    public let bodyID: BodyID
    public let materialID: MaterialID?
    public let sourceFaceIDs: [FaceID]
    public let patch: BRepSewingFacePatch
    public let placement: BRepDrawingPlacement?
    internal let sectionIdentity: BRepDrawingSectionAuthority
    internal let sourceSnapshot: BRepDrawingSourceSnapshot

    init(bodyID: BodyID, materialID: MaterialID?, sourceFaceIDs: [FaceID], patch: BRepSewingFacePatch,
         sourceSnapshot: BRepDrawingSourceSnapshot, sectionIdentity: BRepDrawingSectionAuthority, placement: BRepDrawingPlacement? = nil) {
        self.bodyID = bodyID; self.materialID = materialID; self.sourceFaceIDs = sourceFaceIDs
        self.patch = patch; self.sourceSnapshot = sourceSnapshot; self.placement = placement; self.sectionIdentity = sectionIdentity
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        try sourceSnapshot.validateCurrent(evaluated)
    }
    public func validateCurrent(_ evaluated: EvaluatedDocument, for section: BRepDrawingSection) throws {
        try section.validateCurrent(evaluated)
        try sourceSnapshot.validateCurrent(evaluated)
        guard sectionIdentity === section.publicationIdentity, placement == section.placement else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: evaluated.configuration.tolerance,
                message: "Section publication mixes different source planes or authored occurrences.")
        }
    }
}
