/// Witness-table requirements expose the immutable source/DI contact owner.
public protocol OriginalCertifiedConeConeRelationReading: Sendable {
    var original: OriginalCertifiedConeConePlaneRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalCertifiedConeConePlaneRelation: OriginalCertifiedConeConeRelationReading {
    public var original: OriginalCertifiedConeConePlaneRelation { self }
}
