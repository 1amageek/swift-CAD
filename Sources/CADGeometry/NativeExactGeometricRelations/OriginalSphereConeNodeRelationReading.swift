public protocol OriginalSphereConeNodeRelationReading: Sendable {
    var original:OriginalSphereConeNodePlaneRelation { get }
    var isEmpty:Bool { get }
    var hasPositiveDimensionalSolutions:Bool { get }
    var hasPositiveDimensionalImage:Bool { get }
}
extension OriginalSphereConeNodePlaneRelation: OriginalSphereConeNodeRelationReading {
    public var original:OriginalSphereConeNodePlaneRelation { self }
}
