/// Witness-table access to the complete original pair and all UV families.
public protocol OriginalCommonApexConeRelationReading: Sendable {
    var original: OriginalCommonApexConeRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalCommonApexConeRelation: OriginalCommonApexConeRelationReading {
    public var original: OriginalCommonApexConeRelation { self }
}
