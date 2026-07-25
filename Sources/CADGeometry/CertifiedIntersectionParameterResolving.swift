import CADCore

protocol CertifiedIntersectionParameterResolving: Sendable {
    func normalizedParameters(
        of point: Point3D,
        on curve: CertifiedIntersectionCurve3D,
        restrictedTo range: ScalarInterval?,
        tolerance: ModelingTolerance
    ) throws -> [Double]
}
