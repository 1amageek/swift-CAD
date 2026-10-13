/// Witness-table operations retain the checked source role and both UV families.
public protocol OriginalCertifiedPairLiftRelationReading: Sendable {
    var original: OriginalCertifiedPairLiftPlaneRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalCertifiedPairLiftPlaneRelation: OriginalCertifiedPairLiftRelationReading {
    public var original: OriginalCertifiedPairLiftPlaneRelation { self }
}
