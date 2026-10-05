import CADCore

/// The parent's actual emitted original Body entity and coordinate unit.
public struct IndependentSTEPBodyBinding: Sendable {
    public let entityID: Int
    public let lengthUnit: LengthUnit
    public init(entityID: Int, lengthUnit: LengthUnit) throws {
        guard entityID > 0 else { throw IndependentShapeExchangeError.invalidAssociation("Original Body entity identity must be positive.") }
        self.entityID = entityID; self.lengthUnit = lengthUnit
    }
}
