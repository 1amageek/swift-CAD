import CADTopology

package protocol OriginalFiniteFaceContactClassifying: Sendable {
    func classify(firstFaceID: FaceID, secondFaceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFiniteFaceContactClassification
}
