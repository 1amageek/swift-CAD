import CADCore

/// Exact authored apex and the complete selected original parameter pair.
public struct OriginalCommonApexConeMember: Sendable {
    public let relation: OriginalCommonApexConeRelation
    public let firstU: ExactRationalCoefficient
    public let secondU: ExactRationalCoefficient
    public let zero: ExactRationalCoefficient
    public let proofDepth: ExactScalarDepth
    public var firstUV: (u: ExactRationalCoefficient, v: ExactRationalCoefficient) { (firstU,zero) }
    public var secondUV: (u: ExactRationalCoefficient, v: ExactRationalCoefficient) { (secondU,zero) }
    public var position: (x: ExactRationalCoefficient, y: ExactRationalCoefficient, z: ExactRationalCoefficient) { relation.source.original.position }
}
