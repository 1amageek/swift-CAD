import CADCore

public protocol OriginalPolylinePcurveFamilyPreparing: Sendable {
    func prepare<A: ExactScalarAdmission & ~Copyable>(_ originals: borrowing [SurfaceParameterCurve],
        maximumCurves: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPreparedPolylinePcurves
}
