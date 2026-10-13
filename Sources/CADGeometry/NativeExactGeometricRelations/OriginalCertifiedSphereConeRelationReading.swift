/// Witness-table requirements retain exact mixed coordinates on Embedded.
public protocol OriginalCertifiedSphereConeRelationReading: Sendable {
    var original: OriginalCertifiedSphereConePlaneRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalCertifiedSphereConePlaneRelation: OriginalCertifiedSphereConeRelationReading {
    public var original: OriginalCertifiedSphereConePlaneRelation { self }
}
