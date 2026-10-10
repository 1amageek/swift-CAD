public protocol OriginalIssuedGraphResultResolving: Sendable {
    associatedtype IntersectionResult: Sendable
    /// Publishes a complete retained exact relation. Numeric representative arrays are not requested.
    func intersectionResult<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable, A: ExactScalarAdmission & ~Copyable>(
        exactRelations: borrowing OriginalIssuedGraphRelations<S,E,C,T,F,D>,
        limits: OriginalDomainIdentityLimits, geometryLimits: ExactGeometricRelationLimits,
        maximumPoints: Int, using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> IntersectionResult
}
