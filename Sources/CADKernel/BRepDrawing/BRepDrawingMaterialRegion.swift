import CADGeometry
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try sourceSnapshot.validateCurrent(evaluated, using: &execution)
    }
    public func validateCurrent(_ evaluated: EvaluatedDocument, for section: BRepDrawingSection) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, for: section, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, for section: BRepDrawingSection, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try section.validateCurrent(evaluated, using: &execution)
        try sourceSnapshot.validateCurrent(evaluated, using: &execution)
        guard sectionIdentity === section.publicationIdentity, try BRepDrawingPlacementComparison.equal(placement, section.placement, using: &execution) else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: evaluated.configuration.tolerance,
                message: "Section publication mixes different source planes or authored occurrences.")
        }
    }
}
