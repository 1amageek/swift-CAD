import CADCore

/// Both original UV tuples and their exact source-owned XYZ definition.
public struct OriginalCoincidentConeMember: Sendable {
    public let relation: OriginalCoincidentConeRelation
    public let firstU: OriginalPhysicalAngleValue
    public let secondU: OriginalPhysicalAngleValue
    public let slant: OriginalPhysicalAngleValue
    public let isApex: Bool
    public let position: OriginalCoincidentConePosition
    public let proofDepth: ExactScalarDepth
    public var firstUV: (u:OriginalPhysicalAngleValue,v:OriginalPhysicalAngleValue) { (firstU,slant) }
    public var secondUV: (u:OriginalPhysicalAngleValue,v:OriginalPhysicalAngleValue) { (secondU,slant) }
    public var fiberDimension: Int { isApex ? relation.apexFiberDimension ?? 0:0 }
}
