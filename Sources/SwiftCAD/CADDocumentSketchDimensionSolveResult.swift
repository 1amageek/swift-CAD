import CADCore
import CADIR

public struct CADDocumentSketchDimensionSolveResult: Sendable {
    public var document: CADDocument
    public var featureID: FeatureID
    public var invalidatedFeatureIDs: [FeatureID]
    public var sketchResult: SketchDimensionSolveResult

    public init(
        document: CADDocument,
        featureID: FeatureID,
        invalidatedFeatureIDs: [FeatureID],
        sketchResult: SketchDimensionSolveResult
    ) {
        self.document = document
        self.featureID = featureID
        self.invalidatedFeatureIDs = invalidatedFeatureIDs
        self.sketchResult = sketchResult
    }
}
