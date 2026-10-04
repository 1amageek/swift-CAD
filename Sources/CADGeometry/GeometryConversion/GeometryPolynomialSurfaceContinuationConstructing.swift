/// Authors a native-knot candidate and certifies its complete original continued law.
public protocol GeometryPolynomialSurfaceContinuationConstructing: Sendable {
    func constructContinuationCandidate(
        preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
        uDegree: Int, vDegree: Int,
        maximumSpanCount: Int, maximumControlPointCountPerAxis: Int
    ) throws -> CertifiedPolynomialSurfaceContinuationCandidate
}
