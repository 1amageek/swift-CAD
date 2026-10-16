import CADCore
import CADGeometry
import CADTopology

package protocol OriginalFiniteFaceContactClassifying: Sendable {
    func classify(firstFaceID: FaceID, secondFaceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalFiniteFaceContactClassification
}
