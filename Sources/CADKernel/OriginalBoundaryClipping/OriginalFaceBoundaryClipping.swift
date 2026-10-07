import CADCore
import CADGeometry
import CADTopology

/// Original face-issued clipping of complete Native parameter relations.
public protocol OriginalFaceBoundaryClipping: Sendable {
    func clip(_ source: OriginalNativeBoundaryDomain.Source, to faceID: FaceID,
        in original: ValidatedBRepModel, selection: OriginalNativeBoundaryDomain.Selection,
        maximumDepth: Int, maximumCoefficientDepth: Int,
        usage: OriginalRelationUsage) throws -> OriginalFaceClippedParameters
}
