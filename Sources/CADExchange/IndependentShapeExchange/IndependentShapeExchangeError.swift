import CADCore

public enum IndependentShapeExchangeError: Error, Equatable, Sendable {
    case invalidAssociation(String)
    case missingEntity(Int)
    case unsupportedSemantics(String)
    case metadataLoss(String)
    case resourceLimitExceeded(String)
}
