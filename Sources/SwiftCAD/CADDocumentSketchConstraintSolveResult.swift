import CADCore
import CADIR
import CADKernel

public struct CADDocumentSketchConstraintSolveResult: Sendable {
    public let document: CADDocument
    public let featureID: FeatureID
    public let invalidatedFeatureIDs: [FeatureID]
    public let constraintResult: SketchConstraintSolveResult

    public init(
        document: CADDocument,
        featureID: FeatureID,
        invalidatedFeatureIDs: [FeatureID],
        constraintResult: SketchConstraintSolveResult
    ) {
        self.document = document
        self.featureID = featureID
        self.invalidatedFeatureIDs = invalidatedFeatureIDs
        self.constraintResult = constraintResult
    }
}
