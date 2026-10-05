public enum IndependentShapeSourceError: Error, Equatable, Sendable {
    case invalidSource(String)
    case missingReference(String)
    case unprovedPlacement(IndependentShapeInstanceID)
    case unprovedFramePlacement(IndependentShapeFrameID)
    case unprovedAngularCoordinateLaw(IndependentShapeAngularUnitID)
    case cycle(IndependentShapeReference)
    case resourceLimitExceeded(String)
}
