import CADCore

/// Concrete requirements preserve Q(pi) and remain callable through Embedded existentials.
public protocol OriginalAngularPlaneRelationReading: Sendable {
    var original: OriginalAngularPlaneRelations<OriginalAnalyticCoordinateSnapshot,OriginalPlaneSnapshot> { get }
    var pairs: [ExactGeometricGraphRelation<OriginalPiScalarDomain>] { get }
    var exactPoints: [OriginalAngularPlaneExactPoint] { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
