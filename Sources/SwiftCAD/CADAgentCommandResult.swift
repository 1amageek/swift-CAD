import CADCore
import CADIR

public struct CADAgentCommandResult: Sendable {
    public var document: CADDocument
    public var addedFeatureID: FeatureID

    public init(document: CADDocument, addedFeatureID: FeatureID) {
        self.document = document
        self.addedFeatureID = addedFeatureID
    }
}
